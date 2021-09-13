---
layout: post
title:  "What is the correct number"
date:   2021-09-13 00:00:00 -0000
categories: data programming
---

Today I have been reminded about one of the most famous quotes: 

> Lies, damn lies, and statistics.

This entry is a rant because one of the most weird situation happened today.  A senior dev spotted a
mistake in one part of an algorithm while adding a feature along with some test cases.  Basically the
mistake boils down to something like this

```python
max_y = 0
for xi in x:
    y = compute(xi)
max_y = max(y, max_y)
```

such that only the last element in the list is used.  This mistake was spotted and fixed immediately
with consensus from all other engineers.  It only impacted a limited number of scenarios (less than 1%),
and we have all missed this[^1].
We shipped the fix within the week and has lived in production for a couple of months.

Today, a product manager asked us to roll back to the previous version because the new one
can give a different result in some situations (rather obviously).  The sole reason of the roll back was
that the numbers look a bit off.  There is no question around "what is the desired outcome",
"what is the requirement", or even the definition of "correct".  Simply the numbers are different &mdash;
regardless if the numbers make sense or not &mdash; was enough of a motivation to not accept the fact
that mistakes were made in the past.

This is the second time in my career, at different companies, where I have had to revert an algorithm back
to a state where it is clearly incorrect. An equally sad realization was that I clearly don't have the
moral compass in the right direction (to quit on the spot).

I can't even tell at this point whether there is anything based on numbers, be it CRM/BI/DS/ML/AI,
is correct at all in this world.  Maybe the click&ndash;through rate are wrong, or the conversion
rate is wrong, or your credit score is wrong, or just maybe the revenues reports by companies are wrong[^2].
It would appear that for a lot of people, having a number that "look right" is more important than being
right.  There is no desire to find out about the root cause or how to improve the system; just hack some
numbers together because why not.  The number is correct as long as it serves a purpose.

[^1]: Everyone has made the wrong python indentation before so this was almost a non&ndash;event for the engineering team.
[^2]: Okay this is almost a guarantee as most companies spends a fortune on accountants to massage their numbers.
