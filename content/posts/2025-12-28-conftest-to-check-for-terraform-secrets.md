---
title:  "Conftest to check for Terraform secrets"
date:   2025-12-28
tags:
  - programming
  - terraform
  - testing
  - documentation
---

This is a documentation entry that explains the detection of sensitive data in Terraform using Conftest.
Previously it was explained
[how to use ephemeral resource]( {{< ref "2025-08-13-ephemeral-password-for-rds-in-terraform" >}} )
to interact with sensitive information. However, what happens if we started using Terraform way back in the day
and wish to scrub the state with the introduction of ephemeral reads.
To start the process we need to first detect all the issues.

We go through how to use [Conftest](https://www.conftest.dev/), based on
[OPA](https://www.openpolicyagent.org/), to detect issues, specifically on the known fields such as password
that contains sensitive data.
Note that OPA can only be used against the json and requires a Terraform plan be performed first, whereas Conftest
can (additionally) run on raw `*.tf` files and provides a more friendly local development experience. 
In short, we simply need to detect whether the `password` argument is being used in the
`aws_db_instance` as follows.

```rego deny_secrets.rego
package main # deny_secrets.rego

has_field(obj, field) if {
	_ = obj[field]
}

deny contains msg if {
    some name
    some rds in input.resource.aws_db_instance[name]
    has_field(rds, "password")
    msg = sprintf("Password for RDS instance `%v` is being set.", [name])
}
```

The policy above can be placed in a `policy` folder in the source root or a remote storage,
see the official documentation for details.
To only run a single policy we invoke `conftest test *.tf -p policy/deny_secrets.rego`, and this will throw an error in the CI/CD pipeline.
We can move this detection to the left by running the test locally, ideally in the form of a [pre-commit hook](https://www.conftest.dev/pre_commit/).

One blessing and a curse we can see from above is that it will only look for the `aws_db_instance` resource.
If we wish to check for the `master_password` field in `aws_rds_cluster` resource we will need another policy.
From a remediation standpoint this is probably for the best since we can work incrementally with a small blast radius.

To expand our scope further to go beyond RDS, we can look for secretsmanager resources directly.
For example, we know that `aws_secretsmanager_secret_version` can be problematic,

```terraform
resource "aws_secretsmanager_secret_version" "second" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = "foobarbaz"
}
```

and that can be blocked in a similar way as we did for the RDS resource,
e.g. a policy that looks for the exact `secret_string` field.

```
deny contains msg if {
	some name
	some secret in input.resource.aws_secretsmanager_secret_version[name]
	has_field(secret, "secret_string")
	msg = sprintf("Secretmanager `%v` is using secret_string and not secret_string_wo.", [name])
}
```

However, it is not necessary to create `aws_secretsmanager_secret_version` in Terraform in order to use it.
We can create the secret without the version via Terraform and then manually populated the data before reading it,
leading to a scenario where there is no `resource.aws_secretsmanager_secret_version`.
However, the read using `data.aws_secretsmanager_secret_version` is equally problematic if we inspect the Terraform state and also require remediation. 

As we only need to look at the type of `data` being read, it is possible to make it more generic and
scan for multiple types simultaneously.
Below we have a set of two containing `aws_secretsmanager_secret_version` and `aws_ssm_parameter`
which can be expanded as required.
The policy loops through all the data types from the input, and then progress through the logic if the type is found in the pre-defined set.
Since we are looking for multiple types, the error message is more verbose compare to before and states the type of object in addition to the name.

```
# Targeted data types that contains sensitive information
target_data_types := {"aws_secretsmanager_secret_version", "aws_ssm_parameter"}

deny contains msg if {
    some aws_data, name
	some d in input.data[aws_data][name]
	aws_data in target_data_types
	msg = sprintf("`%v` from data.`%v` is not allowed as it contains sensitive data.", [name, aws_data])
}
```

Last point to note is that we can change the `deny` keyword to `warn` to make the test non-blocking.
Running it in a pipeline will yield a `WARN` message which is probably a better starting point
even when given advanced warning.

```shell
WARN - main.tf - main - `rds` from data.`aws_secretsmanager_secret_version` is not allowed as it contains sensitive data
# echo $? = 0 
```
