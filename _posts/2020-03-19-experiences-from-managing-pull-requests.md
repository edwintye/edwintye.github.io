---
layout: post
title:  "Experiences from managing Pull Requests"
date:   2020-03-19 00:00:00 -0000
categories: posts
---

![new-pull-request](/assets/2020-03-19-new-pull-request.png)

One of the ongoing conversations I have at work is whether we need Pull Request (PR) and how to improve the
current process given that PR is mandated for all our repositories. Here, I talk about how we previously and
currently manage PRs, the journey which has taken us to this point thus far, and the learnings from it. We
have learned by experimenting via a change in the PR process, and lessons include: the need for a team to
converge on both style and design quickly and constantly, which can be facilitated via pairing/show and
tell/shadowing between members, as well as the need to eliminate trust deficit, by being open to change
and allowing the team to drive it while accepting that things may be broken along the way (including master branch!)

### Background

I work at a company with a global operation where teams are not necessarily co-located. Some of the teams
are distributed across multiple time zones, leading to a lack of natural overlap during the team members’
standard working hours. To complicate matters, being part of a matrix like organization means engineers can
be in multiple teams across both vertical and horizontal streams, representing the products and functional
(such as application, platform, etc) teams respectively.

To further set the scene, it is important to note that we cannot do trunk based development due to policy
rather than unwillingness. Contrast this with my previous job where trunk based development is allowed and I
have personally pushed to master many times, I am a big opponent to the enforcement of PR and fight for
change continuously.

### The rise of PR

Most software engineers will be familiar with Git branching models, such as Git flow or GitHub flow. Such
systems work reasonably well as evident through the number of successful open source projects. Therefore,
it is natural to assume that the same process will also work well within a company. Considering that the
usual issues with bad open source project: the lack of owners and slow turnover, is not as prominent with
full time staff manning the repos, it is unsurprising that Git branching models should work. Indeed,
nearly all the problems we have experienced are down to execution rather than theoretical.

Our teams consist of anywhere between 4–8 people, and had a minimum required approval of 3 people for each
repo when I first started. It goes without saying, getting 3 thumbs up for a team of 4 proved to be almost impossible
and PRs would sit hanging for days if not weeks when people go on leave. Even for larger teams,
there were significant delays as the reviewers wait for each other hoping that they can skip the painful
process of code review. As you might have guessed, this process which can drag on for weeks which in turn
leads to developers making the PR bigger and bigger, forming a vicious cycle as the pain of code review
increases with the size of the PR. As the unavoidable process was sufficiently painful for everyone
to attempt a new process, we need to understand if changes were affecting things in a positive or negative way.

### Tracking our progress

Measuring KPIs around PR is a relatively simple affair given that every action on the git server is recorded.
Some of the KPIs we are particularly concerned about include:

- number of PR raised
- length of time before PR merged
- number of comments
- number of commits after starting the PR
- number of new files
- number of new lines
- number of issues closed with the PR

Without a doubt, some of the KPIs mentioned is very useful in describing the team dynamics and maturity;
the length of time before a PR is merged should be low to improve integration in the master branch, and the number
of comments decreases as the team mature and converge to a particular style of programming.

On the other hand, it is very easy to misuse KPIs because the number of new lines is not equivalent to progress.
If there is a PR which delete 10% of the codebase and everything still functions the same, everyone in the team
would rejoice! Similarly, new files created from refractoring is very different to adding new functionality.
This is where a second source of information such as static code analysis and test coverage provides the context.
For us, each PR is analyzed during CI and results made visible in the PR itself. From this perspective,
PRs are a useful mechanism that allows us to enforce certain quality control &mdash; probably reflecting
the motivation behind the policy of mandating PR for us and many companies out there.

### Here come the changes

Equipped with both the incentive and observability, the first change was to decrease the number of
approval from 3 to 2. Although this doesn’t sound like a massive change, the shift in dynamics in the different
repo was immediately evident. A universal drop in the time to merge with some repos dropping all the way to below
one day. The main reason for this change is that it is easy to form a clique of 3 in a team, but
a clique of 4 was a stretch given the size of our teams.

To further increase velocity, the minimum approval requirement was changed to 1 for smaller teams. Contra to
initial expectation, there was essentially no difference when measuring average the time to merge.
What jumped out straight away was the increase in variation, with some PR being approved and merged
almost immediately whereas some took an unexpectedly long time. Thinking back on my personal experience,
the answer was obvious. I occasionally pair program with others and raising a PR was purely formalities, we already
reached an agreement while pairing. Now we have an explanation for one end of the spectrum, what
about the PRs which took much longer than expected?

This is a rather complicated issue and so let’s explore the implication of lowering the requirement of
accepting a PR from the reviewers point of view. Providing the thumbs up means that the feature branch
will be merged unless someone explicitly stops that from happening. First, this creates responsibility
because of “what if this is breaks something when merged into master”; junior developers will be put off by
this pressure with the fear that they cannot fix the issue and/or get the blame. Secondly, the hidden pressure
due to the lack of safety net offered by requiring a second approval. More concretely,
in the system where 2 approval is required allows:

- the first reviewer to think &mdash; *"The other reviewer will spot something if I have missed it"*,
- while the second reviewer has some breathing room because &mdash; "It has been approved already so I don’t need to be super diligent"*.

Personally, I have no doubt that the shift in dynamics we have seen when adjusting the system is simply
reflecting the problem in both organization and team culture. A team should **own** the code as a team,
and people forming cliques to fast track PRs defeats that purpose. More concretely, benefits by enforcing PR
such as: transparency, knowledge transfer, quality + style control, co-ownership, etc, are all bypassed
when PRs are always fast tracked. Developers having second thoughts about doing code review again
indicates a dysfunctional team, because they should always be able to find the time to review PR and 
t is the whole team’s problem when the master branch fails a build. The fear of merging a PR because it may break
master should be corrected by improving the CI pipeline with contributions from everyone involved.

In a nutshell, the teams lack the mentality of being a "team. The company structure makes this easy, i.e. when 
a team is distributed in general but some members are colocated, then inevitably the level of trust varies
due to the number of contact hours and types of contacts between team members. Junior developers and those
not familiar with the codebase reluctant to do code review shows that our culture does not encourage growth
or practice open communication. What we have observed is an underlying problem, where the enforcement of PRs
and changing the rule of the game surfaced the fundamental behavior problems.

### Current state of affairs

One brave developer decided to set up a video conference after seeing his PR hanging for an extended duration.
After the hour long debate, most participants agreed that it was productive despite the heated nature.
That particular PR only merged after another 3 sessions, however, it did lead to other developer follow suit.

We now have demand meetings for all those who develops or makes use of the repo/service. This acts as an
open forum to discuss any issues which fails to resolve within a short thread (of comments) or
raise up issues that is of wider concern. The desire is that every participant had spent some time
looking through the changes, and indeed everyone should at some point should host a session to
walk everyone through their PR so that they can be on both side of the process.

There is without a doubt an administrative overhead by letting developers set up meetings on-demand,
when compared to a recurring event. The upside is that our speed is not bounded by the frequency of meetings,
and introduced yet another ceremonial events which pollute the calendar. For mature teams that are
very good at cutting ceremonial events short, there could definitely be benefits to fixed and regular
PR review sessions. Considering that quite often a PR is directly linked to an issue/ticket, one idea
is to embed code reviews into our daily standups. The routine would then be changed from talking about
what has been done, to demonstrate what has been done and it is something we would love to trial at some point.
