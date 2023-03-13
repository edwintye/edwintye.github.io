---
title:  "Respecting request termination in FastAPI"
date: 2021-10-29
tags:
  - programming
  - python
---

After using golang for a while before switching back to python, one of the first issues that
really frustrates me is the widespread use of "fire and forget" pattern.  Namely, the server keeps
processing the api request even when it has been terminated, e.g. request timed out or cancelled.
For sure there are cases when this is desirable, especially from the client side if you don't need
an ack. The issue here is when the requests require the servers to run some resource heavy process,
and the system performance is tied to the number of concurrent requests.  Our aim is to respect the
termination signal and stop all computation accordingly.

Let's assume that we have a cpu intensive process for one of the endpoints, which can be represented
as the example below with the cpu heavy part replaced by a sleep.  In the event that a client hits the
endpoint `/no-context` (code block below) with a timeout less than the sleep (at 3 seconds) then:
1. The client does not get a response.
2. Server keeps sleeping until the end.
3. Server response with a 200 and thinks it has done a great job.
4. If response is cached then client can get the response in a repeated request, else, go back to step 1. 

```python
from typing import Optional, Union, Dict

import asyncio
from fastapi import FastAPI, HTTPException, Request
from fastapi.logger import logger

app = FastAPI()

async def cpu_heavy() -> bool:
    try:
        await asyncio.sleep(3)
        logger.info("cpu_heavy success")
        return True
    except asyncio.CancelledError as e:
        logger.error("Canceled")
        return False

@app.get("/no-context")
async def get_sleep(request: Request) -> Union[Optional[Dict], HTTPException]:
    res = await cpu_heavy()
    return {"msg": "Slept beautifully", "success": res}
```

In the worst case scenario, the client comes back and fire the same request again and we redo
the whole computation once more because we don't have a cache.  As the client never receives a response,
the same request keeps coming back until our server crashes.  Obviously, there are numerous mechanisms to
resolve this issue: recognize that this client has failed to complete many requests and temporarily
block them, implement a cache, scale up to decrease response time, etc. One option here is to simply
stop the computation when the request stops.

FastAPI has a `Request` object that we can use to help with deciding the state of the request.  Even
though the request object does not have full set of context awareness like the one in golang, there is a
`is_disconnected()` method which returns `True` when the request is dropped.  All we have to do is to
wrap the method inside a while condition such that a change of status sends an "alert".

```python
async def client_disconnected(request: Request) -> bool:
    disconnected = False
    while not disconnected:
        disconnected = await request.is_disconnected()
    return True
```

Next, we need a way to have the "alert" pushed to the request handler.  Probably the simplest way is to
execute both the main function `cpu_heavy` and this newly created function `client_disconnected` simultaneously
and see which completes first.  Thankfully we don't need to work out the details because `asyncio.wait`
already provides this feature out of the box.  The only job we have is to handle the two difference scenarios:
* The client disconnected.
* Computation finished and respond appropriately.

```python
@app.get("/with-context")
async def get_sleep_with_cancel(request: Request) -> Union[Optional[Dict], HTTPException]:
    t1 = asyncio.create_task(client_disconnected(request))
    t2 = asyncio.create_task(cpu_heavy())
    done, pending = await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED)
    logger.error(f"Number of done elements: {len(done)}")
    for t in done:
        if t == t1:
            logger.info(f"Cancelling the cpu heavy process")
            c = t2.cancel()
            raise HTTPException(status_code=503, detail={"msg": "Disconnected so you won't see this", "cancelled": c})
        else:
            return {"msg": "Slept beautifully without Cancel", "success": t2.result()}
```

One of the decision paths &mdash; neither task finished &mdash; is not handled above because one (and only one)
of the tasks *will always be done*.  The `HTTPException` will also never reach the client. However,
the response should be logged/traced by the application/gateway for diagnosis and improvement.

If we want to be extra safe, we can always add a timeout to the execution of the tasks. Having a timeout
ensures that we always cancel the cpu intensive task in the event that the client
never disconnects[^1]!

```python
done, pending = await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED, timeout=10000)
```

Curious reader may think why isn't everyone doing this already given the simplicity and the low effort
requirement.  Well, the caveat here is that we have assumed that the function `cpu_heavy`
can be cancelled. Depending on what and how the resource intensive process runs, `Task.cancel()` may do
absolutely nothing.  For example, the task may be a coroutine that is built on top of a synchronous action,
which does a heavy maths calculation delegated to a C library.  You first issue to resolve is probably to check
if the C library recognizes any signal to cancel in the first instance.  The underlying runtime mechanism
determines the setup required for proper cancellation, with the nuclear option of spinning off in a
subprocess then force a kill.  If you are running such functions, then good luck, and have fun.


[^1]: If your gateway does not have a timeout you need to speak to some people.  But it is *never* too safe to have a timeout in the server.
