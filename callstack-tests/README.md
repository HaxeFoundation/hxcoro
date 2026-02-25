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
- Every coroutine call site in the chain gets its own frame.
- Each coroutine entry lambda (`_ -> someFn()`) appears as a `LocalFunction`
  frame followed immediately by a `Method(…, coro)` frame at the same line.
- Sync bridge frames (plain functions called from coroutines) are fully
  included when they are on the native call stack at throw time; eval does
  not see reconstructed frames before the first suspension point differently
  from after it.
- `throw e` (rethrowing a caught exception) **appends** the rethrow location
  and its continuation chain to the existing stack rather than replacing it,
  producing a doubled call path in the stack array.

### js (Node.js)

Identical stack shape to eval in all observed cases.  LocalFunction IDs
differ (they are sequential integers and vary between targets/builds) — use
`Skip` or `AnyLine` if the exact integer matters.

### hl (HashLink)

Generally matches eval, with one documented quirk:

- **foobarbaz (`baz` coroutine)**: the position of the first (innermost) frame
  varies by OS and HashLink version.  On Linux the throw line is reported;
  on Windows and macOS the coroutine *definition* line may be reported
  instead (probable JIT-related frame-omission).  The `foobarbaz` test uses
  `AnyLine` for this frame to tolerate both values.
- **toprecursion**: the innermost sync-bridge frame (`Top.hx:throwing`) may
  be absent on Windows/macOS HL.  The test uses `Skip` to skip past the
  uncertain top frames and assert from the first reliably-present frame.
- All other cases tested (`directthrow`, `asyncscope`, `catchrethrow`) report
  the exact throw line, matching eval.

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

> ⚠️ **Known framework limitation on JVM**
>
> The Haxe JVM backend deduplicates static-method-reference closures.
> `CaseMacro` generates expressions like `directthrow.Test.run`,
> `toprecursion.Test.run`, etc., but the JVM code generator emits a *single*
> shared closure class for all of them, leaving every entry pointing to the
> *last* discovered `Test.run` (currently `foobarbaz.Test.run`).  As a
> result, the `directthrow`, `asyncscope`, and `catchrethrow` test cases are
> **not actually executed on JVM** — they silently pass by running
> `foobarbaz.Test.run` instead.
>
> This is a limitation to keep in mind when interpreting JVM test results.

When JVM tests do run correctly (e.g. `toprecursion` and `foobarbaz`, which
happen to share behavior with the last-in-list case), the stack shape matches
eval: exact throw lines, sync-bridge frames present.

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
| First frame = definition line, not throw line | cpp (always), hl (sometimes, OS-dependent) |
| Sync-bridge frames absent                    | js, python, neko, php (before first suspension point only; eval and cpp always expose them) |
| Rethrow appends to stack instead of replacing | all targets              |
| `scope.async()` exceptions propagate to parent `CoroRun.run()` | all targets |
| Method-reference deduplication (framework bug) | jvm                   |

## Test cases

| Case           | What it tests                                                     |
|----------------|-------------------------------------------------------------------|
| `foobarbaz`    | Basic throw through a 3-deep coroutine chain after `yield()`     |
| `toprecursion` | Complex chain: sync → coro → recursive coro → sync bridge → throw |
| `directthrow`  | Throw in a coroutine that never suspends (no `yield()`)          |
| `catchrethrow` | Catching an exception in a coroutine and rethrowing it           |
| `asyncscope`   | Exception thrown from a `scope.async()` child coroutine          |
