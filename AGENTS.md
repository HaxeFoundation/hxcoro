# AGENTS.md

Guidance for coding agents working in the hxcoro repository.

## Repository Overview

hxcoro is a coroutine library for Haxe. It provides asynchronous calls, structured concurrency (scopes, supervisors, tasks, cancellation, timeouts), generators, channels, pipelines and concurrency primitives. It is built on the compiler's `haxe.coro` support, so it requires a **nightly Haxe** build.

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

There are three test-like suites, each with one `build-<target>.hxml` per target. Always run them from the repository root with `--cwd`:

```bash
haxe --cwd tests build-<target>.hxml             # main test suite
haxe --cwd callstack-tests build-<target>.hxml   # exception call-stack shape tests
haxe --cwd benchmarks build-<target>.hxml        # benchmarks (not run in CI)
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

`.github/workflows/main.yml` runs on push and pull request, on Ubuntu, macOS and Windows, for every target listed above. It excludes PHP on macOS and Lua on Windows. For each target it runs the main tests (debug, release+HXB and HXB-lib builds, plus extra dispatcher runs on eval, cpp, hl, jvm and python) and then the callstack tests. `.github/workflows/wiki.yml` runs the wiki examples on push, pull request and wiki edits.

## Project Layout

```
src/
├── haxe/                  # Additions to the haxe std package (CoroIntrinsics, ds.VecDeque)
└── hxcoro/
    ├── Coro.hx            # Core suspend functions: suspend, suspendCancellable, delay, yield, scope, supervisor, timeout
    ├── CoroRun.hx         # Entry points for running coroutines (run, with, JS promise integration)
    ├── run/               # Run/setup helpers (Setup, ContextRun, LoopRun)
    ├── task/              # Task tree: CoroTask, AbstractTask, cancellation, node strategies (child/scope/supervisor)
    ├── dispatchers/       # TrampolineDispatcher, ThreadPoolDispatcher, LuvDispatcher (.cpp.hx / .eval.hx)
    ├── schedulers/        # Real-time, virtual-time, thread-aware, Haxe timer and libuv schedulers
    ├── continuations/     # Cancelling, racing, timeout, stack-frame continuations
    ├── concurrent/        # CoroMutex, CoroSemaphore, CoroLatch, CoroBarrier, AtomicState, BackOff
    ├── ds/                # Data structures, channels/ and pipelines/
    ├── generators/        # Generator, AsyncGenerator, and the Es6/Cs/Haxe API-style variants
    ├── elements/          # Context elements (CoroName, NonCancellable, DefaultExceptionHandler)
    ├── thread/            # Thread pool and work-stealing queue
    ├── exceptions/        # TimeoutException, etc.
    └── util/
tests/                     # Main test suite (atest)
├── build-base.hxml        # Shared config; every build-<target>.hxml includes it
└── src/                   # Main.hx registers cases; one subdirectory per area
callstack-tests/           # Asserts exception stack shapes; see callstack-tests/README.md
wiki-tests/                # Compiles and runs the wiki's code examples; see wiki-tests/README.md
benchmarks/                # Benchmark suite; results go to benchmarks/results/ (git-ignored)
libs/atest/                # In-repo test framework used by tests/
```

Files with a target suffix such as `Foo.cpp.hx` or `Foo.eval.hx` are only used on that target.

## Key Concepts

1. **Coroutines** are functions marked with `@:coroutine`. They can call other coroutines and suspend functions from `hxcoro.Coro`.
2. **Structured concurrency:** coroutines run inside a task tree. `CoroRun.run(node -> ...)` starts a root task. `node.async(...)` and `node.lazy(...)` create child tasks. `scope`, `supervisor` and `timeout` create nested scopes with defined lifetimes. Cancellation propagates through the tree as `CancellationException`.
3. **Dispatchers and schedulers** decide where and when continuations resume. `hxcoro.run.Setup` contains factory helpers such as `createTrampoline` and `createThreadPool`.
4. **Generators** are a coroutine use case for yielding values. `Generator<T, R>` uses Kotlin-style restricted suspension, and `AsyncGenerator<T>` allows arbitrary suspension. Both extend `SuspensionResult` and implement `IContinuation`.

## Code Style and Conventions

- Indent with tabs and follow the style of the surrounding code.
- Library code compiles with `--macro nullSafety("hxcoro")`, so new code under `src/hxcoro` must be null-safe. Null safety is turned off for php and python builds.
- Use `@:coroutine` for coroutine functions. Express outcome hints through metadata parameters, for example `@:coroutine(outcome = { noThrow: true })`.
- Stack-trace bookkeeping (`?startPos:haxe.PosInfos` parameters and similar) is gated on `#if coro.stack_traces`, not `#if debug`.
- Use conditional compilation (`#if target.threaded`, `#if cpp`, `#if lua_vanilla`, ...) or target-suffixed files for target-specific code. `-D lua-vanilla` has no `Sys.sleep` or `Sys.time`.
- Busy loops such as CAS retry loops should use `hxcoro.concurrent.BackOff`. This avoids GC deadlocks on some targets.

### Writing Tests

- Test classes extend `atest.Test` (or `BaseCase` for generator helpers). Test methods are named `testXxx`, and assertions use `Assert`.
- Use `run(node -> { ... })` to execute coroutine code inside a test. It is imported for all tests by `tests/src/import.hx`, comes from `tests/src/TestRun.hx`, and honours the `HXCORO_DISPATCHER` selection.
- Classes in the `tests/src/` subdirectories (`concurrent`, `ds`, `structured`, ...) are discovered automatically through `atest.Macros.addCases`. Top-level test classes must be registered by hand in `tests/src/Main.hx`.
- For callstack tests, add `callstack-tests/cases/<name>/Test.hx`. It is discovered automatically. See `callstack-tests/README.md` for the per-target stack quirks.

## Notes for Agents

- When you change coroutine machinery, think about suspension and resumption, cancellation propagation, exceptions crossing async boundaries, context handling and thread safety on threaded targets.
- Targets differ in subtle ways, especially in threading, stack traces and timers. Run eval first, then at least one threaded target (cpp, jvm or hl) and js for anything concurrency-related.
- Don't commit build output: `bin/`, `dump/`, `.hxb` files, `.haxelib/` and `benchmarks/results/`.
