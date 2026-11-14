# SDL3 (C++)

Runs hxcoro coroutines on SDL's main thread, based on Aidan's [SDL_Hxcoro](https://github.com/Aidan63/SDL_Hxcoro) sample from #53. It uses SDL3 through hxcpp's marshalling externs, so it only works on the C++ target.

- `SdlDispatcher` pushes each dispatched object as an SDL user event, so coroutines resume on the thread that polls SDL's event queue. The object is kept alive with `cpp.marshal.RootHandle` while only SDL references it.
- The main loop drives a `RealTimeScheduler` once per frame, polls events and draws.
- Input reaches the coroutines through a `Channel`, filled from the event loop with `tryWrite`.
- Each click starts a task that animates a box, limited by `timeout`. It waits for each frame with `FrameClock.awaitFrame`, which the main loop resumes once per frame, like `yield return null` in Unity. Escape cancels all box tasks.
- Space counts primes on a `ThreadPoolDispatcher` and shows the result in the window title.
- Closing the window cancels the root task, and the main loop runs until all tasks have finished. If the root task failed instead, its exception is rethrown afterwards, so that errors in coroutines don't end the app silently.

## Building

Download the SDL3 development package (`SDL3-devel-<version>-VC.zip` on Windows), then build with:

```bash
haxe --cwd examples/sdl3-cpp build.hxml -D SDL_DIST_DIR=<path to the extracted package>
```

This needs an hxcpp version that has `cpp.marshal.RootHandle`. Only tested on Windows with SDL 3.4.0.

## Threads

All coroutines of the example run on the main thread, except the prime counting. `node.with(background).async(...)` starts that task on the thread pool, because a task always starts on the dispatcher of its context. `await()` then suspends through `Coro.suspend`, which resumes the awaiting coroutine through its own dispatcher, so the code after `await()` runs on the main thread again and can update the title without synchronization.

This is the usual way to handle a UI thread. The main thread owns the window and the state that is drawn, and it must never block. So coroutines run there by default, expensive work is moved to a thread pool explicitly, and its result is handed back. Other ecosystems do the same:

| Ecosystem | Main-thread dispatcher | Background | Switching |
| --- | --- | --- | --- |
| Kotlin (Android, Swing, JavaFX) | `Dispatchers.Main` | `Dispatchers.Default` | `withContext(Dispatchers.Default) { ... }` |
| C# (WPF, WinForms) | the UI `SynchronizationContext` | thread pool | `await Task.Run(...)` |
| Swift | `@MainActor` | global executor | `await` on a non-isolated function |
| Unity (UniTask) | main-thread `SynchronizationContext` | thread pool | `SwitchToThreadPool()` / `SwitchToMainThread()` |

The main-thread dispatchers of these frameworks also post to the platform's event queue, just like `SdlDispatcher` posts SDL user events.

Running the box animations on the main thread doesn't contradict the "never block" rule. Each animation step only does a few calculations before it suspends again. What matters is the work between two suspension points, not how much code runs on the thread in total. The animations also have to run there, because the main loop reads the boxes while drawing. If a step became expensive, it would be split like the prime counting: compute on the pool, apply the result on the main thread.

Some simplifications compared with production code:

- `SdlDispatcher` pushes one SDL event per dispatched object. SDL's event queue has a fixed size, so under heavy load `pushEvent` can fail. A more robust dispatcher keeps its own thread-safe queue and only pushes an event to wake up the main thread. SDL 3.2 and later also offer `SDL_RunOnMainThread`.
- The thread pool shares the scheduler that the main loop drives, so a `delay` on the pool only ends when the main loop runs, once per frame. Usually the pool would have its own timers.
- One coroutine per box is fine for a few boxes. Games with thousands of entities usually update them in a single loop instead.
