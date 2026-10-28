# callstack-tests

Mini-framework for asserting the shape of exception call stacks in hxcoro
coroutines. Unlike the main `tests/` suite (which uses `atest`), this
directory has a self-contained runner so that individual cases can pin the
exact stack frames they care about.

Coroutine stack-frame tracking is only compiled in with
`-D coro.stack-traces`, which `build-base.hxml` sets together with `-debug`.

## Running

```
haxe --cwd callstack-tests build-<target>.hxml
```

Supported targets: `eval`, `js`, `hl`, `cpp`, `jvm`, `php`, `python`, `neko`,
`lua`. CI runs this suite on every OS/target combination in
`.github/workflows/main.yml`. As in the main matrix, PHP doesn't run on macOS
and Lua doesn't run on Windows.

## Adding a test case

1. Create a new directory under `cases/`, e.g. `cases/mycasename/`.
2. Add Haxe source files for the scenario. They live in the `mycasename`
   package because `cases/` is on the class path.
3. Add a `Test.hx` file in that directory with a
   `public static function run():Void` that throws a `haxe.Exception` (or a
   subclass) on failure and returns normally on success.
4. The `CaseMacro.discoverCases()` macro finds every `cases/*/Test.hx` at
   compile time and wires it into the runner automatically.
5. Add the case to the [table below](#test-cases).

Line numbers in the expectations refer to the scenario sources, so editing
those files usually means updating `Test.hx` too.

## Inspector

Use the `Inspector` class to assert the shape of `e.stack.asArray()`.
`inspect()` walks the stack from the innermost frame outwards. It returns
`null` on success or an `InspectorFailure` that includes a dump of the whole
stack. Frames after the last directive are ignored.

| Directive          | Meaning                                                                  |
|--------------------|--------------------------------------------------------------------------|
| `File(file)`       | Set the expected file (suffix match) for the following directives.       |
| `Line(n)`          | The next frame is in the current file at line `n`.                       |
| `AnyLine`          | The next frame is in the current file, at any line.                      |
| `OptionalLine(n)`  | Consume the next frame only if it is in the current file at line `n`.    |
| `Skip(file)`       | Skip frames until a method or local-function frame in `file`, then make it the current file. |

## Stack shape on all targets

These behaviours are asserted for every target. eval is the reference
implementation.

- The innermost frame is the **exact throw line**, followed by every
  coroutine call site in the chain. Intermediate coroutines that don't throw
  themselves are included (`foobarbaz`, `directthrow`, `asyncscope`).
- A task's entry lambda appears **twice at the same line**: once as the
  lambda frame and once as the coroutine frame of the
  `node.async()`/`CoroRun.run()` call site that created it.
- **Rethrowing** a caught exception (`throw e`) appends the rethrow location
  and its continuation chain to the existing stack instead of replacing it,
  so the call path appears twice (`catchrethrow`).
- A child task's chain links back to where the child was **created**
  (`node.async()`), not to where the parent is **waiting**. The
  `task.await()` call site doesn't appear (`awaittask`, `cancellation`).
- **Lazy tasks** record their position at the first explicit `start()`,
  `await()` or `awaitContinuation()` call, not at `node.lazy()`
  (`lazytask`, `awaitcontinuation`). This is transitive: if lazy `task2`
  awaits lazy `task1`, both the `task1.await()` site inside `task2` and the
  `task2.start()` site appear. Because `start()` isn't a coroutine, it takes
  an optional `?caller:ICoroNode` parameter (only with `-D coro.stack-traces`).
  Pass `node`, as in `task1.start(node)`, to keep the chain intact.
- A lazy task that starts **implicitly**, when its parent's lambda returns,
  keeps the `node.lazy()` call site. A later `await()` from a sibling doesn't
  overwrite it (`implicitlazy`).
- `scope()` and `supervisor()` contribute their **call-site frame**
  (`scopetask`, `supervisortask`).
- `timeout()` throws a `TimeoutException` created inside hxcoro. Its stack
  starts with a `hxcoro/Coro.hx` frame whose line varies by target, so match
  it with `AnyLine`. That frame is followed by the `timeout()` call site, the
  `node.async()` call site and the outer entry lambda (`timeout`).
- When a child throws and its siblings are cancelled, each sibling's
  `CancellationException` carries the **original thrower's stack**, not its
  own suspension point. JS is the exception (`siblingcancellation`).

## Target differences

The cases with target-specific expectations (`nestedplainthrow`,
`toprecursion`) split the targets into two groups with
`#if (eval || cpp || jvm || hl)`.

### Full native stack: eval, cpp, jvm, hl

- Plain (non-`@:coroutine`) functions on the native call stack at throw time
  get their own frames: the throw site inside the plain function and its call
  site in the coroutine. This includes sync-bridge frames, such as a plain
  function that calls `CoroRun.run()` from inside a coroutine.
- The innermost coroutine frame is patched to its actual call position.

### Coroutine chain only: js, neko, python, php, lua

- Frames of plain functions are missing. Only the reconstructed coroutine
  chain is visible. In `nestedplainthrow` the innermost lambda therefore
  appears twice (native frame plus coroutine-chain frame), with no
  `thrower()` frames.
- In `toprecursion`, the first coroutine frame of each chain segment shows
  the function's **definition line** rather than its call line. The sync
  bridge frames (`Top.hx`, `syncFun1`) are absent.

### Other per-target notes

- **js:** `Exception.stack` can't be assigned, so the sibling stack
  propagation in `AbstractTask.cancelChildren` is disabled. Sibling
  `CancellationException`s only contain internal JS frames, so assertions on
  them need `#if !js`.
- **python:** `trace()` writes to stderr. Use `Sys.println()` for debugging
  output.
- **lua:** builds use `-D lua-vanilla`, which has no `Sys.sleep`/`Sys.time`.

## Summary table

| Behaviour                                                     | Targets                          |
|---------------------------------------------------------------|----------------------------------|
| Plain-function and sync-bridge frames present                 | eval, cpp, jvm, hl               |
| First coroutine frame shows definition line, not call line    | js, neko, python, php, lua       |
| Rethrow appends to the stack instead of replacing it          | all                              |
| `task.await()` call site absent (creation site shown instead) | all                              |
| Lazy task position = first explicit `start()`/`await()`       | all                              |
| Implicitly started lazy task position = `node.lazy()` site    | all                              |
| `scope()` / `supervisor()` call-site frame present            | all                              |
| `TimeoutException` starts with an internal `Coro.hx` frame    | all                              |
| Sibling `CancellationException` mirrors the original stack    | all except js                    |

## Test cases

| Case                  | What it tests                                                                 |
|-----------------------|-------------------------------------------------------------------------------|
| `foobarbaz`           | 3-deep coroutine chain after `yield()`, directly and inside nested `async` scopes |
| `toprecursion`        | sync → coro → recursive coro → sync bridge → throw                            |
| `directthrow`         | Throw in a coroutine that never suspends                                      |
| `catchrethrow`        | Catching an exception in a coroutine and rethrowing it                        |
| `asyncscope`          | Exception thrown from a `scope.async()` child coroutine                       |
| `nestedplainthrow`    | Plain function called from deeply nested `node.async()` lambdas               |
| `lazytask`            | Lazy task with `start()`, `await()`, and transitive await and start chains    |
| `implicitlazy`        | Lazy task started implicitly by its parent, with and without a sibling awaiting it |
| `awaitcontinuation`   | Calling `awaitContinuation()` directly records the lazy task's position       |
| `supervisortask`      | Child throws inside a `supervisor()` scope; parent awaits the child           |
| `scopetask`           | Child throws inside a `scope()` call; scope call-site frame visible           |
| `awaittask`           | Child throws; parent explicitly awaits it with `task.await()`                 |
| `cancellation`        | Child throws; exception propagates through scope cancellation without an explicit await |
| `siblingcancellation` | Sibling's `CancellationException` carries the original thrower's stack        |
| `timeout`             | Loop cancelled by `timeout()`; `TimeoutException` stack shows the call site and task chain |
