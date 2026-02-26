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

> **Inline-lambda limitation (all targets)**: when a plain (non-coroutine)
> function is called from an **inline lambda** coroutine body
> (`node -> { yield(); thrower(); }`) *after* a suspension point, the
> resulting native call frame has no source position (it appears as
> `LocalFunction(N) at ?:1:0`).  The continuation-chain frames that follow
> are still correct.  This does not affect named `@:coroutine` functions,
> which always show the call site accurately.

### js (Node.js)

Identical stack shape to eval in all observed cases.  LocalFunction IDs
differ (they are sequential integers and vary between targets/builds) — use
`Skip` or `AnyLine` if the exact integer matters.

### hl (HashLink)

Generally matches eval, with one documented quirk that affects **all** test
cases: the position of the **first (innermost) coroutine frame** is
OS-dependent.

- **Linux HL**: the exact throw line is reported (matching eval).
- **Windows and macOS HL**: the coroutine *definition* line is reported
  instead (probable JIT-related frame-omission, same root cause as cpp).

Because the line can be either the definition or the throw position depending
on the OS, all tests use `AnyLine` for the innermost HL frame rather than
asserting a specific line number.

The `toprecursion` test has an additional quirk: the innermost sync-bridge
frame (`Top.hx:throwing`) may be absent on Windows/macOS HL, so it uses
`Skip` past that region.

### cpp

The only target where the first (innermost) coroutine frame consistently
reports the **coroutine function definition line** instead of the exact throw
or suspension line.  All subsequent frames (call sites further up the chain)
are reported accurately.

| Test case    | First-frame line (eval) | First-frame line (cpp) |
|--------------|------------------------|------------------------|
| foobarbaz    | 6 (throw)              | 5 (definition)         |
| directthrow  | 7 (throw)              | 6 (definition)         |
| asyncscope   | 11 (throw)             | 9 (definition)         |
| catchrethrow | 6 (throw)              | 5 (definition)         |

The pattern is: cpp's top frame is 1–2 lines earlier than eval's, landing on
the `@:coroutine function foo() {` opening brace rather than the actual
throw.  This is a known limitation; use `#if cpp … #else … #end` guards in
assertions.

Sync-bridge frames (`Top.hx`) are fully present on cpp, as on eval.

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
| First frame = definition line, not throw line | cpp (always), hl (Windows/macOS — use `AnyLine`) |
| Sync-bridge frames absent                    | js, python, neko, php (before first suspension point only; eval and cpp always expose them) |
| Rethrow appends to stack instead of replacing | all targets              |
| `scope.async()` exceptions propagate to parent `CoroRun.run()` | all targets |
| Inline-lambda coroutine body has no source pos after yield (`?:1:0`) | all targets (compiler limitation) |

## Test cases

| Case           | What it tests                                                     |
|----------------|-------------------------------------------------------------------|
| `foobarbaz`    | 3-deep coroutine chain after `yield()`; full chain including intermediate call sites |
| `toprecursion` | Complex chain: sync → coro → recursive coro → sync bridge → throw |
| `directthrow`  | Throw in a coroutine that never suspends (no `yield()`)          |
| `catchrethrow` | Catching an exception in a coroutine and rethrowing it           |
| `asyncscope`   | Exception thrown from a `scope.async()` child coroutine          |
