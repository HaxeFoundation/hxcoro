# hxcoro

A coroutine library for [Haxe](https://haxe.org/), providing asynchronous calls, generators, structured concurrency, and more — across all major Haxe targets.

## Hello World

```haxe
import hxcoro.Coro.*;
import hxcoro.CoroRun;

class Main {
    @:coroutine static function greet():Void {
        trace("Hello…");
        delay(500); // suspend for 500 ms
        trace("…World!");
    }

    static function main() {
        CoroRun.run(_ -> greet());
    }
}
```

## Capabilities

- **Asynchronous clals** — write asynchronous code in a straightforward sequential style using `@:coroutine` methods.
- **Structured concurrency** — manage lightweight groups of child tasks with well-defined lifetimes and cancellation semantics.
- **Generators** — produce lazy sequences with `HaxeGenerator`, `Es6Generator`, `CsGenerator`, and the async variant `AsyncGenerator`.
- **Cancellation** — first-class `CancellationException` support throughout, with `suspendCancellable` for registering cleanup callbacks.
- **Dispatchers & schedulers** — pluggable execution model; ships with `TrampolineDispatcher`, `ThreadPoolDispatcher`, and (on C++) `LuvDispatcher`.
- **Cross-target** — works on JS, HL, C++, JVM, Python, PHP, Neko, and Eval.
- **JS Promise integration** — `CoroRun.promise` wraps a coroutine as a `js.lib.Promise`; `CoroRun.await` suspends on an existing Promise.

## Running the Tests

Tests live in the `tests/` directory. Each supported target has its own build file:

```bash
haxe --cwd tests build-eval.hxml    # Eval (fastest, no extra tools needed)
haxe --cwd tests build-js.hxml      # JavaScript (requires Node.js)
haxe --cwd tests build-hl.hxml      # HashLink
haxe --cwd tests build-cpp.hxml     # C++
haxe --cwd tests build-jvm.hxml     # JVM
haxe --cwd tests build-python.hxml  # Python
haxe --cwd tests build-php.hxml     # PHP
haxe --cwd tests build-neko.hxml    # Neko
```
