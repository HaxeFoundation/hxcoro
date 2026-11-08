# AGENTS.md

Guidance for coding agents working in the hxcoro repository.

## Repository Overview

hxcoro is a coroutine library for Haxe. It provides asynchronous calls, structured concurrency (scopes, supervisors, tasks, cancellation, timeouts), channels, pipelines and concurrency primitives. It is built on the compiler's `haxe.coro` support, so it requires a **nightly Haxe** build.

- **Language:** Haxe (nightly)
- **License:** MIT (see `haxelib.json`)
- **Supported targets:** eval, js, hl, cpp, jvm, python, php, neko, lua. `hlc` has a build file but is not tested in CI. The `cs` (C#) target is still in development and should be ignored.

## Environment Setup

Tests compile with `--library hxcoro`, so the repository must be registered as a dev library in a local haxelib repo. Check the current state first:

```bash
haxe -version
haxelib list
```

If `hxcoro` (and the dependencies for your target) are missing, set them up from the repository root:

```bash
haxelib newrepo                    # creates a local .haxelib/ (git-ignored)
haxelib dev hxcoro .
haxelib install hxjava             # jvm only
haxelib git hxcpp https://github.com/HaxeFoundation/hxcpp.git           # cpp only
haxe --cwd .haxelib/hxcpp/git/tools/hxcpp compile.hxml                  # cpp only
haxelib git hxcpp_luv_io https://github.com/Aidan63/hxcpp_luv_io        # cpp only
```

Runtime requirements per target: Node.js (js), HashLink nightly (hl), Java (jvm), Python 3 (python), PHP (php), Neko (neko), Lua 5.4 (lua; builds use `-D lua-vanilla`, so no luarocks packages are needed), and a C++ toolchain (cpp).

GitHub Copilot's environment is prepared by `.github/workflows/copilot-setup-steps.yml`, which installs Haxe, Neko, HashLink and the haxelib dependencies above.

## Running Tests

There are four test-like suites, each with one `build-<target>.hxml` per target, plus the tests of each example. Always run them from the repository root with `--cwd`:

```bash
haxe --cwd tests build-<target>.hxml             # main test suite
haxe --cwd callstack-tests build-<target>.hxml   # exception call-stack shape tests
haxe --cwd thread-tests build-<target>.hxml      # tests that use real threads (threaded targets only)
haxe --cwd benchmarks build-<target>.hxml        # benchmarks (not run in CI)
haxe --cwd examples/<name> build-<target>.hxml   # tests of one example
```

`eval` is the easiest target to test and needs no external tools, so start there. C++ builds are slow, especially the first one.

The code examples of the [wiki](https://github.com/HaxeFoundation/hxcoro/wiki) are tested on eval with a checkout of the wiki repository. When changing public API, run this and update the wiki if examples break:

```bash
git clone https://github.com/HaxeFoundation/hxcoro.wiki.git ../hxcoro.wiki
haxe --cwd wiki-tests --run WikiTests ../../hxcoro.wiki
```

### Variations used by CI

```bash
haxe --cwd tests -debug -D coro.stack-traces build-<target>.hxml   # debug build with coroutine stack traces (skipped for cpp)
haxe --cwd tests build-<target>.hxml --hxb bin/test.hxb       # release build + HXB output
haxe --cwd tests build-<target>.hxml --hxb-lib bin/test.hxb   # build against the HXB
```

On sys targets, the test runner reads the `HXCORO_DISPATCHER` environment variable to pick a dispatcher. Use `trampoline`, or `threadpool` on threaded targets. Anything else uses the default dispatcher:

```bash
HXCORO_DISPATCHER=threadpool haxe --cwd tests build-eval.hxml
```

### CI Pipeline

`.github/workflows/main.yml` runs on push and pull request, on Ubuntu, macOS and Windows, for every target listed above. It excludes PHP on macOS and Lua on Windows. For each target it runs the main tests (debug, release+HXB and HXB-lib builds, plus extra dispatcher runs on eval, cpp, hl, jvm and python), then the callstack tests, on threaded targets the thread tests, and every `examples/*/build-<target>.hxml`. `.github/workflows/wiki.yml` runs the wiki examples on push, pull request and wiki edits.

## Project Layout

```
src/
├── haxe/                  # Additions to the haxe std package (CoroIntrinsics, ds.VecDeque)
└── hxcoro/
    ├── Coro.hx            # Core suspend functions: suspend, suspendCancellable, delay, yield, scope, supervisor, timeout
    ├── CoroRun.hx         # Entry points for running coroutines (run, with, JS promise integration)
    ├── run/               # Run/setup helpers (Setup, ContextRun, LoopRun)
    ├── task/              # Task tree: CoroTask, AbstractTask, cancellation, TaskKind
    ├── dispatchers/       # TrampolineDispatcher, ThreadPoolDispatcher, LuvDispatcher (.cpp.hx / .eval.hx)
    ├── schedulers/        # Real-time, virtual-time, thread-aware, Haxe timer and libuv schedulers
    ├── continuations/     # Cancelling, racing, timeout, stack-frame continuations
    ├── concurrent/        # CoroMutex, CoroSemaphore, CoroLatch, CoroBarrier, AtomicState, BackOff
    ├── ds/                # Data structures, channels/ and pipelines/
    ├── elements/          # Context elements (CoroName, NonCancellable, DefaultCallStackHandler)
    ├── debug/             # Task lifecycle tracing, only with -D hxcoro.trace_tasks
    ├── thread/            # Thread pool and work-stealing queue
    ├── exceptions/        # TimeoutException, etc.
    └── util/
tests/                     # Main test suite (atest)
├── build-base.hxml        # Shared config; every build-<target>.hxml includes it
└── src/                   # Main.hx registers cases; one subdirectory per area
callstack-tests/           # Asserts exception stack shapes; see callstack-tests/README.md
thread-tests/              # Tests that create threads or pools directly, for eval, hl, cpp, jvm, python and neko
wiki-tests/                # Compiles and runs the wiki's code examples; see wiki-tests/README.md
benchmarks/                # Benchmark suite; results go to benchmarks/results/ (git-ignored)
examples/                  # Usage examples that aren't API, e.g. generators; see examples/README.md
libs/atest/                # In-repo test framework used by tests/
```

Files with a target suffix such as `Foo.cpp.hx` or `Foo.eval.hx` are only used on that target.

## Key Concepts

1. **Coroutines** are functions marked with `@:coroutine`. They can call other coroutines and suspend functions from `hxcoro.Coro`.
2. **Structured concurrency:** coroutines run inside a task tree. `CoroRun.run(node -> ...)` starts a root task. `node.async(...)` and `node.lazy(...)` create child tasks. `scope`, `supervisor` and `timeout` create nested scopes with defined lifetimes. Cancellation propagates through the tree as `CancellationException`.
3. **Dispatchers and schedulers** decide where and when continuations resume. `hxcoro.run.Setup` contains factory helpers such as `createTrampoline` and `createThreadPool`.
4. **Task tree semantics** follow Kotlin coroutines where hxcoro doesn't say otherwise; when behaviour is in doubt, check what Kotlin does. The invariants that are easy to break when touching `hxcoro.task`:
   - A cancelled child never affects its parent. A failing `Concurrent` child reports to its parent right away, before it completes, so the parent can cancel its other children while the child winds down. A parent awaiting that child is cancelled first and catches a `FailureCancellationException` from `await`.
   - The cancellation cause is created once per failure or cancellation and shared with the children and the cancellation callbacks.
   - `NonCancellable` applies to the task created with it and is not inherited.
   - A task in a final state refuses new children; a child of a cancelling parent is cancelled with the parent's cause before it starts. A task is dispatched once, however often its start is requested.

## Code Style and Conventions

- Indent with tabs and follow the style of the surrounding code.
- Library code compiles with `--macro nullSafety("hxcoro")`, so new code under `src/hxcoro` must be null-safe. Null safety is turned off for php and python builds. This only applies to the `hxcoro` package. The test suites and benchmarks enable it to check the library, but their own code, like the examples, isn't checked, so write it in plain Haxe without local copies of nullable fields or similar workarounds.
- Use `@:coroutine` for coroutine functions. Express outcome hints through metadata parameters, for example `@:coroutine(outcome = { noThrow: true })`.
- Stack-trace bookkeeping (`?startPos:haxe.PosInfos` parameters and similar) is gated on `#if coro.stack_traces`, not `#if debug`.
- Use conditional compilation (`#if target.threaded`, `#if cpp`, `#if lua_vanilla`, ...) or target-suffixed files for target-specific code. `-D lua-vanilla` has no `Sys.sleep` or `Sys.time`.
- Busy loops such as CAS retry loops should use `hxcoro.concurrent.BackOff`. This avoids GC deadlocks on some targets.
- A spin lock that is folded into an atomic value, so that the value is unavailable while the lock is held, uses `hxcoro.concurrent.LockableAtomic` rather than a hand-written CAS loop with a sentinel.
- Doc comments are brief and say what a function does and what it throws. Don't list use cases, and don't refer to other API functions from a doc comment. How something works internally goes into line comments at the code, not into the doc comment.

### Writing Tests

- Test classes extend `atest.Test`. Test methods are named `testXxx`, and assertions use `Assert`.
- Use `run(node -> { ... })` to execute coroutine code inside a test. It is imported for all tests by `tests/src/import.hx`, comes from `tests/src/TestRun.hx`, and honours the `HXCORO_DISPATCHER` selection.
- Classes in the `tests/src/` subdirectories (`concurrent`, `ds`, `structured`, ...) are discovered automatically through `atest.Macros.addCases`. Top-level test classes must be registered by hand in `tests/src/Main.hx`.
- Never rely on `delay` timing with a real-time scheduler, such as the one `run` uses. A slow CI machine can take longer than any delay. `delay` is fine with a `VirtualTimeScheduler`, for example through `VirtualRun.run` or `Setup.createVirtualTrampoline`. Otherwise, synchronize with latches or barriers, use `yield()` to suspend, and use `awaitCancellation()` from `tests/src/TestRun.hx` to wait until the task is cancelled.
- A task that is cancelled before it starts never runs its body. To have tasks reach a certain point before cancelling them, let them arrive at a `CoroLatch` first and wait for it.
- Tests that create threads, thread pools or thread-aware schedulers themselves go to `thread-tests/src/cases/`, where they are discovered automatically. Give every wait a deadline, so that a bug fails the test instead of hanging the run.
- For callstack tests, add `callstack-tests/cases/<name>/Test.hx`. It is discovered automatically. See `callstack-tests/README.md` for the per-target stack quirks.
- Before pushing a fix with a regression test, check that the test fails without the fix (stash `src/`, run the suite, unstash).
- `tests/src/review/` and `thread-tests/src/review/` hold tests for known bugs from the 1.0 review, each documented in the test's doc comment. They are expected to fail and only run with `-D hxcoro-known-failures`, in a CI job that doesn't fail the workflow. When fixing one of these bugs, move its test out of the `review` package into the regular suite.

### Debugging

With `-D hxcoro.trace_tasks`, the task classes report every lifecycle call to the `hxcoro.debug.TaskTrace` element of their context, and `hxcoro.debug.SequenceDiagram` renders a recording as a Mermaid sequence diagram. Put `new TaskTrace(event -> events.push(event))` into the root context to trace everything, or into `node.with(...)` to trace one subtree. `examples/task-trace/diagrams.md` shows the common lifecycles; its test regenerates it, so commit the new version after changing the task classes.

## Notes for Agents

- When you change coroutine machinery, think about suspension and resumption, cancellation propagation, exceptions crossing async boundaries, context handling and thread safety on threaded targets.
- Targets differ in subtle ways, especially in threading, stack traces and timers. Run eval first, then at least one threaded target (cpp, jvm or hl) and js for anything concurrency-related.
- Code that shows how to use hxcoro but shouldn't become API belongs in `examples/`, not `src/`.
- Don't commit build output: `bin/`, `dump/`, `.hxb` files, `.haxelib/` and `benchmarks/results/`.
- Keep unrelated changes in separate pull requests. Pull requests are squash-merged, so a branch stacked on another pull request keeps that one's commits after the merge; rebuild it on master then, so that the pull request shows only its own commits.
