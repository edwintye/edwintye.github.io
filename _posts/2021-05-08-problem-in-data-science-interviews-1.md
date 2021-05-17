---
layout: post
title:  "Problem in data science interviews - Part 1"
date:   2021-05-08 00:00:00 -0000
categories: posts
---
Over a social event where me and some friends from my PhD days met up, we spent a lot of time talking
about recruitment, in both direction where we are the interviewer and the interviewee.  During the
course of our discussion, it was evident that the interview processes do not marry up to the corresponding
job roles.  I will comment on a few of the issues which I have repeatedly observed in data science interviews &mdash;
Part 1, programming exercises.

### Interview types

There is no doubt that interviews in tech is a serious problem; I have heard stories where front end engineers
were asked to do a sorting algorithm on a whiteboard where surely time can be better spent on other aspects of the job.
A data science interview usually involves a combination of:
- General background interview
- HR/competence type questions
- Interviewing with a future colleague from the business side
- Presentation
- Technical interviews
- Whiteboard exercises such as case study
- Some sort of programming task involving Python/R and/or SQL

Obviously components such as the HR/competence interview is now baked into every interview process
and there is no hope of skipping for most people.  The ones I want to focus on are those that the hiring managers
can influence such as the programming task, which irate me the most and will be the first point of discussion.  

A programming task can be classified broadly into two types:

1. Take home exercise where the candidate should spend no more than X hours on it,

2. In person with a strict time limit.

### Problem with take home exercise

When it is a take home exercise, the difficulty is how much time you should spend.  The reality is such that
some candidates will spend more time than others depending on their schedule, and it can be extremely hard to
differentiate time spent vs expertise. When we allow the quality to be skewed by the time spent, the implicit bias
is placed on those who "really want the job".  Arguably we all want to hire those who are willing to put in more
effort, however, that penalizes candidates who are doing part-time study or have dependents; a take home test
should not be a proxy to assessing privilege where job applications can be the highest priority in a person's life. 

A take home task without a follow up session on the code also makes it hard to judge on the thought process
which leads up to the final state which was submitted.  From that perspective, the second option that where
a test done in person &mdash; or over a video conference with the remote hiring &mdash; provides
a guaranteed feedback cycle.  The feedback process is important because code (unlike presentation) will
mostly likely be used by other people, and a certain level of consensus/compromise must be made with colleagues.
Now that leads to the next point where we often see code written by data scientist goes into production and expects:
- their code is of a production level as if they are software engineers,
- or the code works while going through the happy path and no one wants to touch it.

### Data scientists are not software engineers

For one reason or another data scientists' work often end up in production.  A natural path is something like this:
the business wants a POC, then a set of scripts for the POC becomes the MVP, and then in production without
tidy up or even basic error/exception handling.  Obviously the simplest solution is to not let POC, often
in jupyter notebooks, becomes more than a POC and do a rewrite but we all know what real life is like.
 
If we are treating data scientists as software engineers, then the approach
to test programming knowledge should be exactly the same as software engineers!  The design of the interview
should not be leaned towards the knowledge of a framework like Tensorflow or Spark, but rather in the remit
of programming practices and principles.  Some topics will obviously be better suited than others; knowledge
on CI/CD will always be welcomed in any organization, while understanding distributed system is most
probably not necessary. 

Let's assume that we do in fact want the data scientists to put code into production, or at least be part of
the process.  A
[pair programming](https://en.wikipedia.org/wiki/Pair_programming) like setting where an engineer guides the
candidate through a series of programming task would be ideal, or at least have an additional session where
the code will be reviewed between the interviewers and candidate.
I must stress that again that code will live until deleted, so communication skills is effectively a
core part of programming skills, be it verbal or written (documentation). Even if the candidate is so awesome that
deployment to production is a daily exercise, a deployment *does not equal* integration with the rest of the system. 
Synchronization is necessary even for siloed teams at integration time.

Personally the most common issue I have seen is scaling workload.  
One of the worst solutions is to simply buy a bigger machine in terms of cpu/ram/storage rather than
tackle the problem itself, i.e. analyze the bottleneck and understanding the root cause.  For some who has seen
their AWS/GCP/Azure bills have lived to tell the tales of how it would be more cost effective to hire a
data engineer.  Fortunately, most of the cloud provider toolings has scaling in mind so quite often
it is a matter of ensure that all the infrastructure is in place.

Finally, data exploration is probably one of the most fun and annoying aspect of analytics.  Knowledge of SQL is
extremely useful, but a test should be driven by the type of data to be analysed.  If the
majority of the data sits in a traditional data warehouse then knowing the difference between a
[fact](https://en.wikipedia.org/wiki/Fact_table) and [dim](https://en.wikipedia.org/wiki/Dimension_(data_warehouse))
table is highly desirable.  However if the main source of data has already been transformed to the normalized form
and sitting in columnar file storage, then the understanding of how `SELECT *` is a lot more costly (money and/or 
computation resources) than careful columns and dates selection.
