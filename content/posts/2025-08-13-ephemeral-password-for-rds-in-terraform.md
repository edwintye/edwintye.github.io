---
title:  "Ephemeral password for RDS in Terraform"
date:   2025-08-13
tags:
  - programming
  - terraform
  - documentation
---

This is a documentation entry that explains the creation of ephemeral password in secrets manager for RDS.
Ephemeral resources is a new (and widely anticipated) feature introduced in Terraform `1.10`.
An ephemeral resource is not stored in either the plan or the state, which in conjunction with write only resource
allows a completely secret free Terraform state without weird hacks like `null_resource` and etc.

AWS RDS requires a master password and the Terraform provider allows a few different ways to set it.
Obviously, setting username/password as below is less than ideal, especially when RDS has the functionality
to manage the password for you via `manage_master_user_password`.
However, there is a catch; `manage_master_user_password` cannot be used with blue green deployment
simultaneously (at the time of writing).
So we are left to setting the username and password ourselves.

```terraform
resource "aws_db_instance" "mysql" {
  allocated_storage   = 10
  db_name             = "mydb"
  engine              = "mysql"
  engine_version      = "8.0.34"
  instance_class      = "db.t3.micro"
  username            = "foo"
  password             = "foobarbaz"
  # manage_master_user_password = true # cannot be used with blue green
  parameter_group_name = "mysql8.0"
  blue_green_update {
    enabled = true
  }
}
```

Fortunately, we can now set the password directly in Terraform without worrying about the security implication.
First we generate a password with an ephemeral random password generator say `aws_secretsmanager_random_password`
or `random_password`,
then set it directly in the secret manager via the write only argument `secret_string_wo`.
Information injected into `secret_string_wo` is not stored in the state, instead `secret_string_wo_version`
tracks the secret version and should be incremented accordingly when a password rotation is desired. 


```terraform
ephemeral "aws_secretsmanager_random_password" "rds" {
  exclude_punctuation = true
}

resource "aws_secretsmanager_secret" "rds" {
  name = "rds"
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string_wo = jsonencode(
    {
      # username = "foo", # commonly exposed to make the secret easier to use
      password = ephemeral.aws_secretsmanager_random_password.rds.random_password
    }
  )
  secret_string_wo_version = 1
}
```

We can then retrieve the secret via an ephemeral read which again will not be stored in the state
unlike the `data` equivalent of `aws_secretsmanager_secret_version`.

```terraform
ephemeral "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id
}
```

Finally, the RDS resource can be updated to use its own write only argument as well to stop the
secrets be persisted to the state.
We are using the version of the secret directly here to ensure that the RDS and secret manager resources
are in lock step.

```terraform
resource "aws_db_instance" "mysql" {
  # ...
  password_wo         = jsondecode(ephemeral.aws_secretsmanager_secret_version.rds.secret_string).password
  password_wo_version = aws_secretsmanager_secret_version.rds.secret_string_wo_version
  # ...
}
```

If we combine all the logic above into a module, allowing the override of the password version (for rotation)
would be a minimum requirement.

```terraform
variable "password_version" {
  type    = number
  default = 1
}
```
