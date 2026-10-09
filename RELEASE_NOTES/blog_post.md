# zaml 0.2.0 — a fast YAML parser for Elixir, and what I learned wiring libyaml to the BEAM via Zig

*Announcing `zaml` 0.2.0, a Zig NIF for fast YAML 1.2 parsing in Elixir. Repo at https://github.com/niranjanaryan/zaml-elixir, package on Hex at https://hex.pm/packages/zaml.*

## TL;DR

`zaml` is a Zig NIF that wraps the same `libyaml` C library used by
PyYAML. It exposes a single `Zaml.load/1` function that returns native
Erlang terms. On an Apple M3 Pro, it parses:

- a 1,000,000-line flat YAML file in **0.84 s** (vs. 1.73 s for
  `glazer` and 2.54 s for `fast_yaml`), and
- a 100,000-key nested YAML file in **0.53 s** (vs. 0.41 s for
  `glazer` and 1.86 s for `fast_yaml`).

The pure-Erlang parsers everyone ships today — `yamerl` / `yaml_elixir`
— take **23–31 s** on the same fixtures.

This post is the story of how I built it, the trade-offs I made, and
why a thin Zig shim over a battle-tested C parser is still worth
writing in 2026.

## Why yet another YAML library

There are already two well-loved YAML libraries on Hex:
[`yamerl`](https://hex.pm/packages/yamerl) and its Elixir wrapper
[`yaml_elixir`](https://hex.pm/packages/yaml_elixir). Both are pure
Erlang ports of the yamerl parser, which is correct and supports the
full spec. They're just slow on real workloads — the cost of building
every value through BEAM dispatches adds up at the million-line scale.

The existing native option on Hex is
[`fast_yaml`](https://hex.pm/packages/fast_yaml), a thin rebar3 NIF
that wraps libyaml. It's what most production Elixir apps reach for
when `yaml_elixir` is too slow.

So really, the question is: *why not just use `fast_yaml`?* The honest
answer is that I started this as a porting exercise — I had a pure-Zig
Python extension in the same repo and wanted to see what the
equivalent would look like on the BEAM. Once I had a working NIF that
parsed the same fixture, it turned out to be a few-times faster than
`fast_yaml` on nested data, so I cleaned it up and shipped it.

## How it's built

### The architecture

`zaml` is a Zig NIF. The shape is:

```
 ┌─────────────┐    binary    ┌─────────────────┐    events    ┌────────────────────┐
 │  Zaml.load  │ ───────────► │   libyaml       │ ───────────► │  Zig event loop    │
 │  (Elixir)   │              │   (C)           │              │  → Erlang terms    │
 └─────────────┘              └─────────────────┘              └────────────────────┘
```

`libyaml` is a streaming event-based parser: you feed it bytes, and
it gives you back a stream of `STREAM_START`, `DOCUMENT_START`,
`SEQUENCE_START`, `MAPPING_START`, `SCALAR`, etc. events. Building
the final term tree is the consumer's job.

`fast_yaml` consumes that stream in C and emits a proplist
representation, which the caller can then flatten into a map if they
pass `:maps`. `zaml` consumes the stream in Zig and emits a map
directly. That's the entire difference, and it accounts for most of
the speedup on nested data: no intermediate proplist, no second
pass to walk it.

### The toolchain

Zig has a single CLI that compiles C, Zig, and arbitrary combinations
into a shared library. The whole build is one line in the `Makefile`:

```make
zig build-lib -O ReleaseFast -dynamic -fallow-shlib-undefined \
    -femit-bin=priv/zaml.so \
    -I $ERTS_INCLUDE_DIR \
    $YAML_CFLAGS $YAML_LIBS \
    -Mroot=native/zaml_nif.zig
```

Two non-obvious things:

1. **The libyaml C headers** come in via `@cImport({ @cInclude("yaml.h"); })`.
   Zig translates them to native calls; you never write a C wrapper.
2. **The Erlang NIF entry** is a small Zig struct literal:

   ```zig
   var nif_entry = erl_nif.ErlNifEntry{
       .major = erl_nif.ERL_NIF_MAJOR_VERSION,
       .minor = erl_nif.ERL_NIF_MINOR_VERSION,
       .name = "Elixir.Zaml",  // important: the leading "Elixir." is required
       .num_of_funcs = nif_funcs.len,
       .funcs = &nif_funcs,
       .vm_variant = erl_nif.ERL_NIF_VM_VARIANT,
       ...
   };
   export fn nif_init() callconv(.c) [*c]erl_nif.ErlNifEntry {
       return &nif_entry;
   }
   ```

   The `ERL_NIF_INIT` C macro you'd find in any NIF tutorial
   just expands to something like this; writing it in Zig by hand
   means you can use a single toolchain (Zig) and never touch clang.

### Auto-discovery of libyaml

The build has to know where `libyaml` lives. On Homebrew it's at
`/opt/homebrew/{include,lib}`. On Debian/Ubuntu it's in `/usr`. The
`mix.exs` walks a list of well-known prefixes and exports the right
`CFLAGS`/`CPPFLAGS`/`LDFLAGS` *before* `mix deps.get` runs, so even
rebar3-compiled deps (like `fast_yaml` in the bench task) can find
it. The user doesn't have to set any env vars on a normal dev box.

```elixir
# top of mix.exs
yaml_inc = System.get_env("YAML_INCLUDE_DIR") ||
  Enum.find_value(["/opt/homebrew/include", "/usr/local/include", "/usr/include"],
                  fn p -> if File.exists?(Path.join(p, "yaml.h")), do: p end)
if yaml_inc do
  System.put_env("CFLAGS", "-I#{yaml_inc}")
  System.put_env("CPPFLAGS", "-I#{yaml_inc}")
end
```

## Benchmarks

The full table lives in `benchmark/RESULTS.md` in the repo. The
short version:

| Parser | 1M-line flat | 100k-key nested |
|---|---|---|
| `zaml` 0.2.0 (Zig NIF + libyaml) | **0.84 s** | **0.53 s** |
| `glazer` 1.1.6 (C++ NIF, PGO) | 1.73 s | 0.41 s |
| `fast_yaml` 1.0.40 | 2.54 s (3.03×) | 1.86 s (3.50×) |
| `yamerl` 0.10.0 (pure Erlang) | 30.27 s (36.1×) | 23.88 s (45.0×) |
| `yaml_elixir` 2.12.2 | 30.95 s (36.9×) | 24.40 s (45.9×) |

`zaml` is ~3–3.5× faster than `fast_yaml` across shapes — the
proplist-to-map conversion in `fast_yaml` is the dominant cost — and
~36–46× faster than the pure-Erlang parsers. The one library that
edges it out is `glazer`, a hand-rolled C++ YAML parser (not libyaml)
built with profile-guided optimisation: it wins on the deeply nested
fixture (~1.3×) and loses on the single wide 1M-key map (~2.1×). I'd
rather publish that than cherry-pick a shape.

The benchmark fixtures are committed as generators; the actual 16 MB
YAML file is `.gitignore`d. You can re-create the 1M-line fixture
with:

```bash
python3 -c "
import yaml
yaml.dump({f'a{i}': f'b{i+1}' for i in range(1_000_000)},
          Dumper=yaml.CSafeDumper, default_flow_style=False,
          stream=open('benchmark/big_1m.yml', 'w'))
"
```

…and then run `mix zaml_nif.bench benchmark/big_1m.yml`.

## What I learned

A few things I didn't expect going in:

1. **The Z-array → C-array story in Zig 0.16 is awkward.** The
   `enif_get_string`/`enif_make_string` API takes a C-style
   `char *buf, size_t len`, not an Erlang binary. You end up calling
   `enif_inspect_binary` to get a pointer + length out of the
   binary, then pass that to libyaml. Reversing the direction needs
   `enif_make_new_binary` plus a memcpy. None of this is hard, but
   it's the kind of thing that takes an afternoon to get right the
   first time.

2. **Naming matters.** The NIF's `ErlNifEntry.name` field is the
   module name in Erlang's atom notation: `Elixir.Zaml` for an
   `Elixir`-namespaced module. I spent a while debugging a
   `"Library module name 'zaml' does not match calling module
   'Elixir.Zaml'"` error before figuring that out. The C macro
   `ERL_NIF_INIT(zaml, ...)` does this stringification for you; the
   Zig version doesn't.

3. **`callconv(.C)` is now `callconv(.c)` in Zig 0.16.** Trivial, but
   it took me a few minutes to find because the error message is
   "no member named 'C' in 'CallingConvention'".

4. **rebar3-compiled deps need help finding C libraries.** `fast_yaml`
   ships a rebar.config that doesn't auto-discover Homebrew's
   `libyaml`. The trick was to inject `CFLAGS`/`CPPFLAGS`/`LDFLAGS`
   into the parent `mix` process *before* `mix deps.get` spawns
   rebar3. `System.put_env` from inside `mix.exs` works because
   `mix.exs` runs in the parent Elixir VM, and rebar3 inherits the
   env.

5. **Benchmarks should compare to the thing your users will pick,
   not the thing you think is the right answer.** The interesting
   comparison isn't `zaml` vs `yamerl` (everyone knows C is faster
   than Erlang); it's `zaml` vs `fast_yaml` (both wrap the same C
   library) and vs `glazer` (the newer hand-rolled NIF). The `fast_yaml`
   result is a real, defensible ~3× improvement on the same underlying
   parser; `glazer` beats `zaml` on nested data and loses on flat maps,
   and that's worth saying out loud rather than hiding.

## What's next

`zaml` is at 0.2.0. The obvious next steps:

- **YAML merge keys (`<<: *alias`).** libyaml gives me a
  `MAPPING_START` event followed by a `SCALAR` whose value is `<<`.
  I need to look up the alias and merge its contents in. A few
  dozen lines of Zig.
- **Multi-document input.** libyaml gives me `DOCUMENT_START` /
  `DOCUMENT_END` events; I just need to return a list of documents
  instead of only the first. This is a one-line change in the API
  contract, so I'd like feedback on whether to break the signature
  now (0.3.0) or wait.
- **An emitter.** libyaml has an emitter API too, and writing a
  `Zaml.dump/1` would round out the package. Lower priority since
  most callers only need to read YAML.

If you have a YAML file that breaks `zaml`, please open an issue
with the input attached. The CI matrix covers `mix test` on a
single Erlang/OTP version right now; I'd like to expand it to cover
Linux + multiple OTP versions before 1.0.

## Try it

```elixir
# mix.exs
def deps do
  [{:zaml, "~> 0.2.0"}]
end
```

```bash
mix deps.get
mix compile
iex> Zaml.load("foo: 1\nbar: [a, b, 3.14]\n")
%{"bar" => ["a", "b", 3.14], "foo" => 1}
```

Links: [Hex.pm](https://hex.pm/packages/zaml) ·
[GitHub](https://github.com/niranjanaryan/zaml-elixir) ·
[CHANGELOG](https://github.com/niranjanaryan/zaml-elixir/blob/main/CHANGELOG.md) ·
[Benchmarks](https://github.com/niranjanaryan/zaml-elixir/blob/main/benchmark/RESULTS.md)

— *Niranjan Aryan*
