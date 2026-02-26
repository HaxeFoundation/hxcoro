# callstack-tests

Mini-framework for asserting the shape of exception call stacks in hxcoro
coroutines.  Unlike the main `tests/` suite (which uses `utest`), this
directory has a self-contained runner so that individual cases can pin the
exact stack frames they care about.

## Running

```
haxe --cwd callstack-tests build-<target>.hxml
```

Supported targets: `eval`, `js`, `hl`, `cpp`, `jvm`, `php`, `python`, `neko`.

## Adding a test case

1. Create a new directory under `cases/`, e.g. `cases/mycasename/`.
2. Add Haxe source files for the scenario (they live in the `mycasename`
   package because the `cases/` directory is on the class-path).
3. Add a `Test.hx` file in that directory with a `public static function
   run():Void` that throws an `haxe.Exception` (or a subclass) on failure
   and returns normally on success.
4. The `CaseMacro.discoverCases()` macro finds every `cases/*/Test.hx` at
   compile time and wires it into the runner automatically.

Use the `Inspector` class to assert the shape of `e.stack.asArray()`.

## Target-specific stack-trace quirks

The sections below summarise what each compilation target actually does with
coroutine exception stacks, based on the test cases in this suite.  Use this
as a reference when writing new `#if target` branches.

### eval (reference)

The eval interpreter produces the most complete and accurate stacks.

- The innermost frame reports the **exact throw line** inside the coroutine.
- Every coroutine call site in the chain gets its own frame, including
  intermediate coroutine-to-coroutine calls that do not themselves throw
  (e.g. `foo → bar → baz`: all three functions appear in the stack).
- Each coroutine entry lambda (`_ -> someFn()`) appears as a `LocalFunction`
  frame followed immediately by a `Method(…, coro)` frame at the same line.
- Sync bridge frames (plain functions called from **named** `@:coroutine`
  functions) are fully included when they are on the native call stack at throw
  time.
- `throw e` (rethrowing a caught exception) **appends** the rethrow location
  and its continuation chain to the existing stack rather than replacing it,
  producing a doubled call path in the stack array.
- The `task.await()` call site does **not** appear as a stack frame when a
  child task's exception propagates through it; the child task's exception
  stack is attached directly to the continuation chain.

### js (Node.js)

Identical stack shape to eval in all observed cases.  LocalFunction IDs
differ (they are sequential integers and vary between targets/builds) — use
`Skip` or `AnyLine` if the exact integer matters.

### hl (HashLink)

Generally matches eval, with one documented quirk that affects all test
cases: the position of the **first (innermost) coroutine frame** is
OS-dependent.

- **Linux HL**: the exact throw line is reported (matching eval).
- **Windows and macOS HL**: the coroutine *definition* line is reported
  instead (probable JIT-related frame-omission).

Because the line can be either the definition or the throw position depending
on the OS, all tests use `AnyLine` for the innermost HL frame rather than
asserting a specific line number.

The `toprecursion` test has an additional quirk: the innermost sync-bridge
frame (`Top.hx:throwing`) may be absent on Windows/macOS HL, so it uses
`Skip` past that region.

Plain (non-`@:coroutine`) functions called from inside a coroutine lambda use
`OptionalLine` for their frame, since that frame may also be absent on
Windows/macOS HL (same JIT root cause as above).

### cpp

Produces the same stack shape as eval: the innermost frame reports the
**exact throw line** (as of Haxe commit e63e9897, which fixed the `HXDLIN`
annotation in generated coroutine state machines).

Sync-bridge frames (`Top.hx`) are fully present, as on eval.

### jvm

Stack shape matches eval: exact throw lines, sync-bridge frames present,
full intermediate coroutine call chain reconstructed.

### python

Identical stack shape to eval.  The only cosmetic difference is that
`trace()` output goes to stderr, so `Sys.println()` is used in probes.

### neko

Identical stack shape to eval.

### php

Identical stack shape to eval.

## Summary table

| Quirk                                        | Targets affected         |
|----------------------------------------------|--------------------------|
| First frame = definition line, not throw line | hl (Windows/macOS — use `AnyLine`) |
| Sync-bridge frames absent                    | js, python, neko, php (before first suspension point only; eval and cpp always expose them) |
| Rethrow appends to stack instead of replacing | all targets              |
| `scope.async()` exceptions propagate to parent `CoroRun.run()` | all targets |
| `task.await()` call site absent from stack   | all targets (child exception attached directly) |
| `supervisor()` contributes a `hxcoro/Coro.hx` frame | all targets (use `Skip` to navigate past it) |
| `CancellationException` from `cancel()` has no user-code frames | all targets (coroStack is empty; raw runtime frames only) |

## Test cases

| Case             | What it tests                                                     |
|------------------|-------------------------------------------------------------------|
| `foobarbaz`      | 3-deep coroutine chain after `yield()`; full chain including intermediate call sites |
| `toprecursion`   | Complex chain: sync → coro → recursive coro → sync bridge → throw |
| `directthrow`    | Throw in a coroutine that never suspends (no `yield()`)          |
| `catchrethrow`   | Catching an exception in a coroutine and rethrowing it           |
| `asyncscope`     | Exception thrown from a `scope.async()` child coroutine          |
| `nestedplainthrow` | Plain (non-`@:coroutine`) function called from deeply-nested `node.async()` lambdas |
| `awaittask`      | Child task throws; parent explicitly awaits it with `task.await()` |
| `supervisortask` | Child task throws inside a `supervisor()` scope; parent awaits child |
