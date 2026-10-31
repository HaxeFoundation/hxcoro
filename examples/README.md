# Examples

Code that builds on hxcoro but isn't part of its API. The examples aren't on the hxcoro class path, so you can't import them as a library: copy and adapt them instead.

The [wiki](https://github.com/HaxeFoundation/hxcoro/wiki) explains the API with short snippets. The examples here are larger pieces of code that use it.

| Example | Description |
| --- | --- |
| [generators](generators/) | Synchronous generators in Haxe, ES6 and C# style, and an asynchronous generator |

## Layout

Each example lives in its own directory with a `README.md`, its code in `src/` and its tests, if it has any, in `test/`. Run an example's tests from the repository root:

```bash
haxe --cwd examples/<name> build-<target>.hxml
```

CI runs every `examples/*/build-<target>.hxml` for the targets of its test matrix. An example that only works on some targets, or that needs external dependencies, should only provide build files for the targets CI can run, and use differently named build files for the rest. Its `README.md` explains how to build it.
