---
title: "Average score in Grafana"
date: 2022-07-03 00:00:00 -0000
tags:
  - data
  - monitoring
---

As someone who was trained in mathematics, I was filled with embarrassment when I saw a time series panel using
the query below in one of our Grafana dashboard. Averaging over averages might be a common mistake at high school,
but completely unacceptable in a data science team.

```shell
avg(
rate(application_score_sum[$__rate_interval])
/
rate(application_score_count[$__rate_interval])
)
```

Aim of the panel is to track the quantiles and the average score of a ML (machine learning) model.
The ML model that returns a score [0,1] and auto-scales within kubernetes with a range
between 2 and 5 pods. Prometheus is exposed directly from the application via a
[Summary](https://prometheus.io/docs/concepts/metric_types/#summary) and the aim is to track the scores to
alert for any major score drift as an earning warning for (potential) problem in other services (such as
feature building).

[Official documentation mentions that summary are not aggregatable](https://prometheus.io/docs/practices/histograms/#quantiles)
on the quantiles, and this applies to average as well under broad conditions.  In this scenario where
we want to calculate the average score, taking the *average (over pods) of averages score* almost guarantee a
wrong value due to the uneven distribution of requests. In fact, this is a weighted average with weights determined
by the number of requests going through each pod. From the query (as formatted), it is obvious that we are
first calculating the average score on a pod level before taking the average of the pods.

The solution is very simply, in that we can do the average manually; sum up the nominator and denominator first,
across the pods, before the division.

```shell
sum(rate(application_score_sum[$__rate_interval]))
/
sum(rate(application_score_count[$__rate_interval]))
```

For those who are slightly bothered by `rate` because the function does a division operation over time,
I hear your concern, but note that the two intervals (in nominator and denominator) used in `rate` are identical.
If the two intervals are different, well you have a bigger problem so *shrug*.

However, there is most definition some benefit to changing from `rate` to an `increase`: having the peace of mind,
lowering the mental calculation/confusion when people look at the query the next time, the translation between
the maths (in formula) to the query is verbatim.

```shell
sum(increase(application_score_sum[$__rate_interval]))
/
sum(increase(application_score_count[$__rate_interval]))
```

One minor note is that when you use the `increase` then it may be beneficial to also allow a custom interval
variable such that you have more control over the length of time window used in the moving average
calculation. Namely, if your concern is something say "massive shift in average score over a 5 minutes period" then
a custom interval (of 5m) provides such information directly.
