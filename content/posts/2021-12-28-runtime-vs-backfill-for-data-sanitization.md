---
title: "Runtime vs backfill for data transformation"
date: 2021-12-28
tags:
  - data
  - process
  - programming
---

Machine learning typically, if not always, require some data preprocessing.  Data filtering and cleaning to
ensure data quality can happen during runtime or prebuilt via an engineering layer. Either can be performed
via say a
[scikit-learn pipeline](https://scikit-learn.org/stable/modules/generated/sklearn.pipeline.Pipeline.html)
with a transformer or the typical Spark ETL pipeline for complex logics. Quite often there is a choice
between the two (runtime or prebuilt), or even a combination, when moving an ML solution from POC to production.
Often the choices are driven by what we "can do" given the availability and familiarity of various tech.
In other cases, the decision comes down to "just ship it". What we don't usually do is calculate the long
term operational cost would be, mostly due to the inability of gauging longevity of the ML solution.

Let's ignore how decisions come into play, and here we just focus on the difference and cost between
having the features generated runtime vs prebuilt, and the associated cost of using prebuilt features
due to data backfilling.

## Scenario

Imagine we are back to the start of the covid-19 pandemic and we have to quickly score the similarity of names
and phone number from raw data against known official records so that contact tracing can be done
accurately[^1]. The correctness of the raw names and numbers changes through time as technology improves:
  1. At the start people just write it down on paper and then manually entered into a database.
  2. Then we move from manual entry to scan and convert text straight into the database.
  3. People start submitting info via electronic forms.
  4. Introduction of QR codes and forms automatically filled by smartphones.

The source of error changes, from the first stage where it can be due to bad handwriting to the last stage
where it can be the way we use the official record that causes the mismatch and low score. For example,
I have a Spanish friend where his bank uses the middle name of his passport as last name, and that is
perfectly valid as that is a family name[^2]!  


## Initial solution

Right at the beginning when we try to solve the problem, we will probably do something like the code block
below in python; a pipeline model that transforms the data right before final classifier.  

```python
from pandas import DataFrame
from typing import Iterable
from sklearn.pipeline import Pipeline
from sklearn.base import BaseEstimator, TransformerMixin

# our class that does the transformation
class CleanNameNumber(BaseEstimator, TransformerMixin):

    def __init__(self, columns: Iterable[str]):
        self._columns = [c.lower() for c in columns]

    def fit(self, X, y=None):
        return self

    def transform(self, X, y=None):
        if isinstance(X, DataFrame):
            # pandas dataframe are sensitive
            X.columns = X.columns.str.lower()
            X["raw_name"] = clean_name(X["raw_name"]) # some random clean_name function not shown here
            X["raw_number"] = clean_number(X["raw_number"]) # a clean_number function also not here
            X["official_name"] = clean_name(X["official_name"])
            X["official_number"] = clean_number(X["official_number"])
        return X

# our model consist of the data transformation and the classifier
model = Pipeline([('data_cleaning', CleanNameNumber()), ('clf', clf)])
```

The code block above represents the **runtime solution** where `X` is a dataframe that is obtained
from the database which our data are stored.  The main benefit here is that we can change the data cleaning
functions quickly as we learn more about problem. Obviously there is a cost to pay, in that we are doing all
the transformation each time we score.  Cleaning the data each and every time may make sense may make
sense for the raw, but probably a waste of computer power and time for the official records.

Improving the performance of our solution is quite simply to do some, if not all, of the data cleaning as
soon as possible. Consider the current data flow below, and our aim is to move the data transformation
block into the database/data lake territory. More concretely, we just execute the `clean_name` and
`clean_number` functions at an earlier point before the data touches the model.

![runtime-solution](/images/2021-12-23-rutnime-solution.png)

## Moving data transformation to the left

First opportunity of data transformation is to do it after the raw data has been stored, which we can
just assume it's an ODS without loss of generality.  Similarly, we can also transform the official records
if we desire so e.g. we may want to convert everything to be in the form of international phone number,
say changing a 0 to +44 for the UK.

Now we have improved the speed which the model scores, but created an issue when we wish to update
our functions `clean_name` and `clean_number`.  We will have to backfill and run the new functions
pass all the original data that we wish to use which has already been processed before. This is because
**data cleaning is not a reversible process** for the most part. If we strip the title of a name, i.e.
the name Edwin Tye can be derived from both Dr Edwin Tye and Mr Edwin Tye.

For sure, the alternative here to perform the transformation during runtime leads to a lot of repeats and
probably worse, but the total cost calculation (in terms of compute time) is not that obvious.
In the scenario where we don't already possess an automated backfill ability &mdash; using the likes of
[Airflow](https://github.com/apache/airflow),
[Dagster](https://github.com/dagster-io/dagster),
[Luigi](https://github.com/spotify/luigi) &mdash;
then the backfill cost is almost certainly too high if performed more than once.

Assume that we can backfill on demand, let's consider some of the differences between the two types of data:
raw and official records[^3].


|              | Raw data                                | Official record           | 
|--------------|-----------------------------------------|---------------------------|
| Quality      | Improves over time                      | Static                    |
| Size         | Changes depending on restrictions       | Slowly changing dimension |
| Valid period | Subject to contact tracing requirements | Always                    |

Looking at the table above, it is fair to conclude that the cost (time and complexity) of backfill
is also inheritly different for the two types of data.  For a dataset that has an expiration date like
the raw data here, a backfill job will process data that is subject to deletion as soon as the job finishes.
At the same time, the data cleaning logic may be moving very fast when the data quality is low. We certainly
don't want to be in a situation where the time required for data transformation over the dataset is on the
same magnitude as the iteration of code. 

The size of the data changes the cost calculation, in terms of total size as well as percentage that is new.
We can assume that all the new data can be transformed using the new logic without issue, so if the
new data proportion is significant, there simply isn't much to backfill (comparatively). Coupled with a short
retention period, something like 1 month for covid-19 contact tracing, we may even reach the decision to simply
accept to only backfill *on demand*.  More concretely, we store an identifier in the transformed data such as
`logic_version=X` to allow the pipeline to determine if it is out-of-date when fetching.  In the event it is
out-of-date, the pipeline can simply do the transformation on the original data and update/overwrite the
transformed data with the latest. Depending on the hit rate (percentage of data used within its lifetime) 
this may be more cost effective than a full backfill. In general, a batch job is going to be way more efficient
than updating individual records but if only 1% of the data ever get a hit the batch job will never be worth it.
Furthermore, to allow concurrent scoring we will **never lock** the transformed data for read and the same
record may receive multiple identical updates/overwrites if those records have been requested by multiple
pipelines simultaneously.

A combined solution that leverages pre-built batch jobs and runtime calculation may look something like
below, which evidently require a lot of coordination and infrastructure to make work.

![combined-solution](/images/2021-12-23-combined-solution.png)

## Best method?

There is no single way to ensure that we have minimized cost/compute time because there are many competing factors
and some outside our control.  Hence, it is extremely hard (if not impossible) to make the correct decision right
from onset.  In the scenario used here, we may start off with 20 data scientists and engineers going through
the raw data + official records to uplift the data quality, and suddenly reached a stage where the quality is
deemed good enough and moved everyone to another priority task.  So we may never reach a stage where time can be
spent on analysing the usage pattern and converge to a suitable architecture.  For those who wish or think they
can make the correct decision without going through many iterations on a new problem, I sincerely wish them luck.

---

[^1]: I made this up on the spot just for demonstration purposes so may not make that much sense.

[^2]: Understanding how non-English names works has definitely made me way more aware of custom norms when
      doing feature engineering.

[^3]: The two points "Size" and "Valid period" are correlated for the raw data, and not true for the official
      record.
