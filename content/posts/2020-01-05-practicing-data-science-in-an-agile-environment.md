---
title: "Practicing data science in an agile environment"
date: 2020-01-05
tags:
  - team
---

Working as a data scientist, I am faced with the question of "how to hit the next target" almost every day.
Most companies require iterations and improvements frequently to stay competitive, while at the same time have
limited resources usually in the form of technical support. This is especially true in cross-functional teams,
where a data scientists are dropped into a team consisting of data engineer, network engineer, platform, backend… etc,
and is expected to essentially perform magic.

For most data scientist, their background is mostly likely academia. An environment where the work is
expected to be hard and requires a long time. The research environment is also setup such that a failure can be
a success; a negative result which rules out a train of thought is extremely useful for the future. Additionally,
if we see how long it takes for someone to complete their PhD, anywhere from 3 to 7 years, then it is obvious
a mindset change is required when stepping into the corporate world where the timeline becomes months if not weeks.

In order for a company to move in a certain timeline, they usually follow some sort of agile implementation
such as scrum (which we will use as an example without loss of generality). Let's pretend here that we are
talking about the proper version rather than [dark scrum](https://ronjeffries.com/articles/016-09ff/defense/)
to simplify the conversation. First of all, companies and managers usually don't explain why they are using
scrum in the first place. Second of all, they enforce the culture of the scrum onto the data scientists, who
now feels the pressure to work in the same way as a software engineer.

Root cause of the problem with scrum (or indeed) agile is that they were developed in the domain of
software engineering. Their goal was to delivery quickly and fail fast, and most tasks have visible
improvements. On the other hand, a data scientist spending weeks to create and test different features can
easily yield zero improvements. I have seen how practices like daily standup &mdash; which effectively forces
a data scientists to inform everyone of the null progress &mdash; becomes a mechanism that demotivates
or add pressure to data scientists.

As data science almost never progress in a linear manner, the purpose of using scrum is rather unclear,
at least on an individual level. On a team level, it still makes perfect sense; scrum provides a good
framework for the team to communicate with each other. Life just gets harder when the communication
appears to be going one way, due to the nature of the work, where a data scientist requires a different timeline.

Within a cross functional team, if a data scientist is struggling with say getting the right data or packaging
the code up, then someone should step in and provide help. A data scientist should have no issue in saying
something like "still stuck on trying to write the correct SQL" in the daily scrum, because it can be complicated
in a corporate environment when you have never heard of concepts like dimension and fact table before. We should
all remember that the main skill of a data scientist is building mathematical models suitable for the problem in
hand. The rest of the team should be educated about this and understand that "I have made no progress" or
silence does not mean a day was wasted. In fact, informing your team that "Working on the same issue,
not stuck, and don't need help yet" offers great comfort; your team realize that you are keeping track
and your message will change if you desire some form of support.

In the scenario where the scrum team sits horizontally (aka functional teams), namely a team that consists
of only data scientists, then scrum shouldn't be used in the same manner. Without a doubt, the principles are
still very much applicable. Time-boxing in particular is an extremely good way to ensure that the data
scientists do not wander off and try every crazy idea (s)he can think of because "it's fun". I am not
advocating an environment where fun is eliminated, but rather, it should be controlled. The goal of scrum may
remain the same, however the purpose of a sprint should change; progress is measured by the understanding of
the problem and knowledge gained, and the end of a sprint signifies a consolidation of knowledge.

If you are 1.) a manager or 2.) a data scientist who feels that scrum has simply become a
mechanism to apply pressure and/or micromanage, then it is a problem. More concretely, the time
scale have not been adjusted to reflect the complexity of work. Or, the team is doing work they weren't
designed to do, such as using data scientists as a data engineer or in the extreme case as a platform developer.

A successful scrum team should be motivated, and the most successful story I know of motivating data
scientists is Kaggle. By having short term projects with clear deadline and goals, they have whipped up
a crowd who is willing to work in their free time just to prove themselves. There is nothing stopping
companies to implement the same mindset internally: set a problem, provide a dataset, give the staff a
pre-allocated time, and set regular check points from start to finish.

The last two items are the easiest to achieve given that stakeholders usually love timelines and check points
can be implemented as part of A/B testing. Problem usually lies in the pre-requisite of starting with a
workable dataset. Unfortunately, there is no silver bullet because either there is support from the data
engineering team, or be prepared to let the data scientists spend time in data preparation.
