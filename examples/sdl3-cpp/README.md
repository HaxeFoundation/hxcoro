# SDL3 (C++)

Runs hxcoro coroutines on SDL's main thread, based on Aidan's [SDL_Hxcoro](https://github.com/Aidan63/SDL_Hxcoro) sample from #53. It uses SDL3 through hxcpp's marshalling externs, so it only works on the C++ target.

- `SdlDispatcher` pushes each dispatched object as an SDL user event, so coroutines resume on the thread that polls SDL's event queue. The object is kept alive with `cpp.marshal.RootHandle` while only SDL references it.
- The main loop drives a `RealTimeScheduler` once per frame, polls events and draws.
- Input reaches the coroutines through a `Channel`, filled from the event loop with `tryWrite`.
- Each click starts a task that animates a box with `delay`, limited by `timeout`. Escape cancels all box tasks.
- Space counts primes on a `ThreadPoolDispatcher` and shows the result in the window title.
- Closing the window cancels the root task, and the main loop runs until all tasks have finished.

## Building

Download the SDL3 development package (`SDL3-devel-<version>-VC.zip` on Windows), then build with:

```bash
haxe --cwd examples/sdl3-cpp build.hxml -D SDL_DIST_DIR=<path to the extracted package>
```

This needs an hxcpp version that has `cpp.marshal.RootHandle`. Only tested on Windows with SDL 3.4.0.

## Status

Work in progress, based on #203. The background work of the Space key relies on tasks starting on their own dispatcher, which #203 ensures. Without it, `node.with(background).async(...).await()` could start the child on the awaiting thread, and the main loop froze while counting.

The code after `await()` continues on the main thread, because `await` suspends through `Coro.suspend`, which resumes on the awaiting coroutine's dispatcher.
