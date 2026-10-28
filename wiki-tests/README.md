# wiki-tests

Compiles and runs the Haxe examples of the
[hxcoro wiki](https://github.com/HaxeFoundation/hxcoro/wiki) against the hxcoro
sources in this repository, so that API changes which break the documentation
are noticed. CI runs this on every push and pull request, and whenever the wiki
is edited.

## Running

```
git clone https://github.com/HaxeFoundation/hxcoro.wiki.git ../hxcoro.wiki
haxe --cwd wiki-tests --run WikiTests ../../hxcoro.wiki
```

The path to the wiki checkout is relative to the `wiki-tests` directory. Each
example is written to `bin/<page>-<line>/source/Main.hx` and run on eval with
`-cp source`, so traces look like `source/Main.hx:12: ...`, matching the
`haxe -lib hxcoro -cp source --run Main` command used in the wiki. Examples that
don't finish within 30 seconds fail.

## How code blocks are tested

Every `haxe` code block that contains a `function main` is compiled and run, and
must exit successfully. Other code blocks are ignored unless a directive says
otherwise. A `haxe` block without `function main` fails unless it has a
directive, so that new fragments aren't silently left untested.

Directives are HTML comments, which GitHub doesn't render, placed on the line
directly before a code block:

````
<!-- test: output -->
```
source/Main.hx:6: 1
```
````

Several directives can be combined in one comment, e.g.
`<!-- test: id=twice patch=nonblocking -->`.

| Directive | Meaning |
|-----------|---------|
| `skip` | Don't test this block. |
| `output` | This plain block is the expected output of the previous example. Blank lines are ignored. |
| `output=nopos` | Like `output`, but positions such as `source/Main.hx:12: ` are removed from the actual output first. |
| `error="text"` | Compiling this example must fail with an error containing `text`. |
| `prelude` | Prepend this block to all following examples on the page. `import` and `using` declarations are moved to the top. |
| `module=Name` | Save this block as `Name.hx` next to all following examples on the page. |
| `id=name` | Remember this example under `name` for `patch`. |
| `patch=name` | Run the example `name` with this block's module-level functions replacing the ones of the same name, e.g. a different `main`. |

Line numbers in expected output only match the page if the example is run as
shown, so use `output=nopos` for examples that use `prelude` or `patch`.
