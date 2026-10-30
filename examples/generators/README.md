# Generators

Generators produce values lazily by suspending a coroutine at each `yield`.

- `HaxeGenerator`, `Es6Generator` and `CsGenerator` are synchronous generators with Haxe-, JavaScript- and C#-style yield APIs. They are built on `Generator`, which uses restricted suspension: the generator function can only suspend by yielding, and runs on the thread that iterates the generator.
- `AsyncGenerator` allows arbitrary suspension, so the generator function can call any coroutine, for example `delay`. Its `hasNext` is a coroutine, so it has to be iterated from a coroutine.
- `Yield` and `YieldingGenerator` let a coroutine yield to any of these generators, for example to yield recursively.

```haxe
final gen = HaxeGenerator.create(yield -> {
	yield(1);
	yield(2);
	yield(3);
});
trace([for (v in gen) v]); // [1, 2, 3]
```

See [test/TestGenerator.hx](test/TestGenerator.hx) and [test/TestAsyncGenerator.hx](test/TestAsyncGenerator.hx) for more examples.
