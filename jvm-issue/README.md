# JVM static method-reference deduplication bug

> **Status: Fixed in Haxe `coro-ExceptionHandler-rework_f22c52b`.**
> Running `haxe build.hxml` against that build (or any later build that
> includes the fix) produces the correct output.  This directory is kept as a
> standalone reproducer for the original bug.

This is a minimal reproducer for a bug in the Haxe JVM backend where static
method references with the **same simple class name and method name but
different packages** are all collapsed into a single shared closure class,
causing every reference to call the *last* method that was processed.

## How to run

```
haxe build.hxml
```

## Expected output

```
a: Running A
b: Running B
c: Running C
```

## Actual output on JVM

```
a: Running C
b: Running C
c: Running C
```

## Root cause

`Main.hx` creates three method references:

```haxe
{name: "a", run: a.Test.run},
{name: "b", run: b.Test.run},
{name: "c", run: c.Test.run},
```

The JVM backend generates a closure class for each static method reference.
The class name is derived from the **simple** (unqualified) class name and
method name only, ignoring the package.  All three references therefore get
the same generated class name: `_Main.Main_Fields_$Test_run`.

Since a JVM class can only be defined once, the last definition wins.  The
class ends up hardwired to call `c.Test.run`:

```java
// Compiled from "src/Main.hx"
public final class _Main.Main_Fields_$Test_run extends haxe.jvm.Function {
  public static final _Main.Main_Fields_$Test_run run;   // single shared instance

  public void invoke() {
    c.Test.run();   // always c, regardless of which package was intended
  }
  …
}
```

All three array entries use `getstatic _Main/Main_Fields_$Test_run.run`, which
returns the same shared instance, so calling any of them invokes `c.Test.run`.

## Impact in callstack-tests

`callstack-tests/src/CaseMacro.hx` generates an array of
`{name, run: <pkg>.Test.run}` entries — exactly the pattern shown above.
When there are multiple test-case packages that all have a class named `Test`
with a `run()` method, only the last discovered one is actually called on JVM.
The other test cases silently "pass" by running the wrong code.
