# SDL

Runs hxcoro coroutines on SDL's main thread, based on Aidan's [SDL_Hxcoro](https://github.com/Aidan63/SDL_Hxcoro) sample from #53. C++ only.

- `SdlDispatcher` pushes each dispatched object as an SDL user event, so coroutines resume on the thread that polls SDL's event queue. The object is kept alive with `cpp.marshal.RootHandle` while only SDL references it.
- The main loop drives a `RealTimeScheduler` once per frame, polls events and draws.
- Input reaches the coroutines through a `Channel`, filled from the event loop with `tryWrite`.
- Each click starts a task that animates a box with `delay`, limited by `timeout`. Escape cancels all box tasks.
- Space counts primes on a `ThreadPoolDispatcher` and shows the result in the window title.
- Closing the window cancels the root task, and the main loop runs until all tasks have finished.

## Building

Download the SDL3 development package (`SDL3-devel-<version>-VC.zip` on Windows), then build with:

```bash
haxe --cwd examples/sdl build.hxml -D SDL_DIST_DIR=<path to the extracted package>
```

This needs an hxcpp version that has `cpp.marshal.RootHandle`. Only tested on Windows with SDL 3.4.0.

## Status

Work in progress. The background work of the Space key doesn't behave as intended yet, because of two hxcoro issues:

1. `node.with(background).async(...).await()` can run the child on the awaiting thread, because `await` starts the task inline if the pool hasn't picked it up yet. The main loop then freezes while counting.
2. The code after `await()` continues on the thread that completed the child, not on the awaiting coroutine's dispatcher, so the title is set from a pool thread.
