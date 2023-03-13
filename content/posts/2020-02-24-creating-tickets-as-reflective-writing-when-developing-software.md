---
title: "Creating tickets as reflective writing when developing software"
date: 2020-02-24
tags:
  - process
  - team
---

A lot of developers seem to despise tickets, a written up piece of work tracked in some issue tracking tool.
Some of the most common complains are: not informative, no context, unclear solution/requirement, or even
unclear goal. While quite often that is true, the aforementioned issues also signify the maturity level of
the development team as well as the product owner (PO). For example, a ticket should not be created without
the oversight of the PO because the PO is the closest contact with customers/stakeholders. A lack of background
information is usually due to insufficient tagging and organization, as context should be obtainable through the
board, epic it belongs to, and the linked tickets.

![ticket-types](/assets/2020-02-24-ticket-types.png)

### What is the real problem here?

Think of a time when a ticket has been created without a reason; such an event should never occur. Now think
of a time when a ticket is created based on a completely new idea, blue sky thinking without prior information;
a scenario very unlikely but certainly happens. The fact is that the majority of the tickets are based on some
existing work, which themselves should have been described in their own tickets! Therefore there is no reason
for anything be it a feature, bug, improvement, to not be linked in some way, probably all way back to the *seed*
ticket with that blue sky idea.

One of the powers of issue tracking is that it acts as a knowledge repository as time progress. Quite often
the people who find such knowledge repository useful are not long-serving members, but those who just starting
work in the company or even team. Indeed, I have seen teams who are into domain driven design who uses one board
for one product, and separate the individual parts into epics. Each epic is then represented effectively as a seed
ticket with the statement of work/contract/api spec stated, naturally ensuring that subsequent works
have a clear target.

### But that is just documentation...

So how is all linked to reflective writing I hear you ask. Reflective writing is a practice where the
experience and outcome of the events get documented, and then reflected upon in order to allow better
actions in the future. To some people, that just sounds like having a retrospective with one participant,
and would hate such an idea. To others, that is what they are doing constantly: refractoring, trying something
new; the aspiration should always be fast and short feedback cycle, and this sort of mini-retro is another
mechanism to achieve that. Given that we know that hindsight is wonderful, surely the learning from the time
spent working on an issue is an invaluable experience that should be shared. One of the best ways to persist
such learning is to write them down, where writing will consolidate thoughts and enforces structure.

Our aim to have comprehensive documentation in the form of tickets as a mechanism to increase transparency.
Everyone in the company should be able to see what has been written, and can gauge with state of the product
themselves. By removing ambiguity, it tries to eliminate the emotional fear due to unknowns; a rapid release
cycle demonstrates progress, and an up-to-date board/backlog is simply another way to achieve the same idea
in the written form of natural languages rather than code.

### Visibility is good yet there must be some price to pay

What changes to the normal workflow will be required? I mean, there must be time dedicated to essentially not
doing work right? Such a view is biased because it is predicated on the assumption that all work completed is
flawless and cannot be improved, rarely true in the face of deadlines and the world of small increments. To
demonstrate, a ticket that is created after analyzing the work completed may look something like this

> There is a known future performance and stability issue as the database connection is created
> each time due to a lack of time for refinement in feature/ABC-123. Some of the known solutions include
>changing from creating new connection to using a connection pool in <some random place>, and make use
>of transactions without auto-commit in<another random place>. The difficulty is that we lack the guarantee
>of thread safety for the database object because the current design is to initialize the object once and
>passed onto the various functions as an argument.

The motivation behind this ticket is rather obvious; a sacrifice was made to use the simplest solution
with the least number lines of code so that it would just work. Here, the potential problem is not being
hidden, but rather, made aware such that it is visible to those interested. At the same time, this ticket acts
not only as documentation but also as a candidate solution once the problem surfaces. Note that the information
contained in the ticket is aimed to cut down the amount of time required in the future to both the think
and implement phase.

Clearly there is a trade-off here in that we could have just started solving the problem rather than
writing it down. If you are in a startup or a solo developer then the benefits of clear instructions
or learnings will not be the same as a team of 10 with members dipping in and out due to holiday, sickness,
reassignment, etc. Taking the time to pause and reflect is certainly better suited to long-lived teams with
stability, where communication takes priority.

### Let’s start write better tickets!

How would we encourage such practice? To start, allow the developers walk through their train of thought
regularly. The most obvious time slot is the daily standup, where we would ditch the
**"What have you done?" + "What are you going to do?"** type framework to
**"How do I plan to solve this problem?" + "What I did to solve the problem"**. More concretely,

- Anyone who has finished a ticket should share the learnings and discuss what can be done better or left to do, if any.
- Write the follow up tickets either together during a standup, or pin it up to be finished later.
- Review these new tickets with relevant parties, including those outside the immediate team if required.
- Remaining time should be used to talk about the current proposed solution for all the items in progress.
- Write down the proposed solution and realign with team

The biggest struggle with such a new routine is the appearance of “pointing the spotlights at stuff not done well”.
PO needs to start by providing comfort to developers that in reality perfection does not exist. Surfacing issues
at the start rather than discovered at a later stage also allow the PO to be fully prepared, especially when it
is known ahead of time! Imagine the scenarios a few months down the line, where the discussion is now centered
around “We need to change the priority and stop neglecting these issues” rather than
“Why did that not work this way to begin with”. The latter will most likely force all parties to be
confrontational and/or defensive, an unnecessary step when in the end the **exact same work** will be carried out.

When all the developers have had a go with “I think doing X instead of Y would have been way better,
but none of us knew”, then the team mentality will become more pragmatic because they can empathize
with each other’s choice. Using the wrong library/framework/design is indeed painful, and we have all
been there before. So let’s start by explaining the developer journey to everyone where the increased
transparency is by design aiming to shift an emotional conversation to a logical one.
