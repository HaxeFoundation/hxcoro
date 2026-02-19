# Copilot Instructions for hxcoro

## Repository Overview

hxcoro is a coroutine library for Haxe that provides generators, async generators, and coroutine primitives. The library supports multiple Haxe compilation targets including JavaScript, C++, HashLink, JVM, Python, PHP, Neko, Eval, and C#.

**Project Type:** Haxe library
**Language:** Haxe
**License:** GPL (see haxelib.json)
**Repository Size:** Small to medium-sized library focused on coroutine implementation

## Build and Test Instructions

### Prerequisites

Nightly Haxe, Neko, and haxelib are **pre-installed** in the agent environment via `.github/workflows/copilot-setup-steps.yml`, so you do not need to install them manually. The `utest` library and `hxcoro` dev library are also pre-configured.

For target-specific builds:
- **HashLink (hl):** Requires HashLink runtime (the CI uses nightly version as specified in the workflow)
- **C++ (cpp):** Requires hxcpp library and hxcpp_luv_io
- **JVM (jvm):** Requires hxjava library

### Environment Setup

The haxelib setup is handled automatically. You can verify with:

```bash
haxe -version
haxelib list
```

For target-specific dependencies:

**C++ target:**
```bash
haxelib git hxcpp https://github.com/HaxeFoundation/hxcpp.git
haxe --cwd .haxelib/hxcpp/git/tools/hxcpp compile.hxml
haxelib git hxcpp_luv_io https://github.com/Aidan63/hxcpp_luv_io
```

**JVM target:**
```bash
haxelib install hxjava
```

### Running Tests

Tests are located in the `tests/` directory. To run tests for a specific target:

```bash
haxe --cwd tests build-<target>.hxml
```

Where `<target>` is one of: `eval`, `js`, `hl`, `hlc`, `cpp`, `jvm`, `php`, `python`, `neko`, `lua`

**Note:** The CI primarily tests: `eval`, `js`, `hl`, `cpp`, `jvm`, `php`, `python`, `neko`. Other targets like `lua` and `hlc` have build files but may not be regularly tested in CI. The `cs` (C#) target is still in development and should be ignored for now.

**Example:**
```bash
haxe --cwd tests build-eval.hxml  # For eval target
haxe --cwd tests build-js.hxml    # For JavaScript target
```

For debugging mode, add `-debug` flag:
```bash
haxe --cwd tests -debug build-eval.hxml
```

For HXB (Haxe Binary) compilation testing:
```bash
haxe --cwd tests build-<target>.hxml --hxb bin/test.hxb
haxe --cwd tests build-<target>.hxml --hxb-lib bin/test.hxb
```

**C++ Target Specific:** According to the CI workflow, when testing the C++ target, skip the debug mode build (the `-debug` flag variation) and proceed directly with the standard build.

### CI Pipeline

The repository uses GitHub Actions for CI (`.github/workflows/main.yml`). The CI:
- Runs on push and pull requests
- Tests on macOS, Ubuntu, and Windows
- Tests all supported Haxe targets (eval, js, hl, cpp, jvm, php, python, neko)
- Uses concurrency control to cancel in-progress runs when new commits are pushed

**Important:** PHP target is excluded on macOS runners.

## Project Layout and Architecture

### Directory Structure

```
/
├── .github/
│   └── workflows/
│       └── main.yml          # CI configuration
├── src/
│   ├── haxe/                 # Haxe standard library extensions (if any)
│   └── hxcoro/               # Main library code
│       ├── Coro.hx           # Core coroutine utilities and suspend functions
│       ├── CoroRun.hx        # Coroutine execution utilities
│       ├── generators/       # Generator implementations
│       │   ├── Generator.hx         # Synchronous generator (restricted suspension)
│       │   ├── AsyncGenerator.hx    # Asynchronous generator
│       │   ├── YieldingGenerator.hx # Yielding interface
│       │   └── ...          # API-style variants (Es6Generator, CsGenerator, HaxeGenerator)
│       ├── dispatchers/      # Execution dispatchers
│       │   ├── SelfDispatcher.hx
│       │   ├── TrampolineDispatcher.hx
│       │   ├── ThreadPoolDispatcher.hx
│       │   └── LuvDispatcher.cpp.hx  # C++ specific (libuv)
│       ├── schedulers/       # Scheduling strategies
│       ├── continuations/    # Continuation implementations
│       │   ├── CancellingContinuation.hx
│       │   ├── TimeoutContinuation.hx
│       │   └── RacingContinuation.hx
│       ├── concurrent/       # Concurrency primitives
│       │   ├── CoroLatch.hx
│       │   ├── Tls.hx        # Thread-local storage
│       │   └── BackOff.hx    # Used in busy-loops (e.g., CAS loops) to avoid GC deadlocks
│       ├── task/             # Task abstractions
│       ├── exceptions/       # Exception types
│       └── ...
├── tests/
│   ├── build-base.hxml       # Base build configuration
│   ├── build-<target>.hxml   # Target-specific configs (eval, js, cpp, etc.)
│   └── src/                  # Test source files
│       ├── generators/       # Generator tests
│       ├── concurrent/       # Concurrency tests
│       └── ...
├── haxelib.json              # Haxelib package metadata
└── .gitignore
```

### Key Architectural Concepts

1. **Coroutines:** The primary focus of this library. Use the `@:coroutine` metadata on methods. The `Coro` class provides key primitives:
   - `suspend()`: Basic suspension point
   - `suspendCancellable()`: Cancellable suspension with cleanup
   - `delay()`: Async delay primitive

2. **Generators:** A use-case for coroutines that support yielding values. Two main types:
   - `Generator<T, R>`: Synchronous generator requiring Kotlin-style restricted suspension
   - `AsyncGenerator<T, R>`: Asynchronous generator
   - Additional API-style variants (Es6Generator, CsGenerator, HaxeGenerator) provide different interfaces but work on any target

3. **Dispatchers:** Control coroutine execution context. Available dispatchers include:
   - `SelfDispatcher`: Synchronous execution
   - `TrampolineDispatcher`: Trampoline scheduling
   - `ThreadPoolDispatcher`: Multi-threaded execution
   - `LuvDispatcher`: libuv-based (C++ only)

4. **Target-Specific Code:** Some files have target-specific extensions (e.g., `.cpp.hx` for C++ only).

### Configuration Files

- **haxelib.json:** Package metadata, sets class path to `src`
- **build-base.hxml:** Common build settings for all tests (includes utest, main class, etc.)
- **build-<target>.hxml:** Include base config and add target-specific flags

### Dependencies

- **utest:** Testing framework (from GitHub: `haxe-utest/utest`)
- **haxe.coro:** Core coroutine support (built into Haxe standard library)
- **Target-specific:**
  - C++: hxcpp, hxcpp_luv_io
  - JVM: hxjava

## Code Style and Conventions

1. Use Haxe package naming: lowercase with dots (e.g., `hxcoro.generators`)
2. Use `@:coroutine` metadata for coroutine methods
3. Use `@:coroutine.nothrow` for coroutines that don't throw exceptions
4. Generator classes typically extend `SuspensionResult` and implement `IContinuation`
5. Use target-specific conditional compilation when needed
6. Follow existing patterns for suspend/resume mechanics

## Important Notes for Coding Agents

1. **Trust these instructions:** Only search for additional information if these instructions are incomplete or incorrect.

2. **Never skip haxelib setup:** ALWAYS run `haxelib newrepo` and install dependencies before building or testing.

3. **Target-specific considerations:** 
   - C++ builds require additional setup time for hxcpp compilation
   - Some targets may not be available on all platforms (e.g., PHP on macOS)
   - Use conditional compilation for target-specific code

4. **Test execution:** Tests must be run from the `tests/` directory using `--cwd tests` flag.

5. **Build artifacts:** The `.hxb` files and binaries generated during testing should not be committed.

6. **Coroutine semantics:** When modifying coroutine-related code, ensure proper handling of:
   - Suspension and resumption
   - Cancellation propagation
   - Exception handling in async contexts
   - Context management

7. **Common pitfalls:**
   - Forgetting to set up haxelib repository before running tests
   - Running tests without proper target-specific dependencies
   - Not using `--cwd tests` when building tests
   - Assuming all targets work the same way (they have subtle differences)
