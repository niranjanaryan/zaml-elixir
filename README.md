# 🚀 zaml

A **fast YAML 1.2 parser for Elixir**, powered by a Zig NIF that wraps
[libyaml](https://pyyaml.org/wiki/LibYAML). Heavily inspired by
[`kubkon/zig-yaml`](https://github.com/kubkon/zig-yaml) and the original
Python prototype that lives in this same repository (see
[Python prototype](#python-prototype) below).

```elixir
iex> Zaml.load("foo: 1\nbar: [a, b, 3.14]\n")
%{"bar" => ["a", "b", 3.14], "foo" => 1}

iex> Zaml.load("""
...> name: zaml
...> tags: [yaml, elixir, nif, zig]
...> ratio: 3.14
...> flag: true
...> empty: ~
...> """)
%{"name" => "zaml", "tags" => ["yaml", "elixir", "nif", "zig"],
  "ratio" => 3.14, "flag" => true, "empty" => nil}
```

## Why?

The most popular Elixir YAML libraries — [`yaml_elixir`](https://hex.pm/packages/yaml_elixir)
and its underlying [`yamerl`](https://hex.pm/packages/yamerl) — are
pure-Erlang ports. They're correct but slow. The existing native
option on Hex is [`fast_yaml`](https://hex.pm/packages/fast_yaml)
(processone), which is the obvious thing to compare against because it
also wraps `libyaml`.

`Zaml` is `fast_yaml` but with a thinner event-to-term bridge: the
libyaml event stream is consumed in Zig and turned into Erlang terms
in a single pass, building maps directly instead of going through
intermediate proplists. That gives a **~3× speedup over `fast_yaml`**
on both flat and nested mappings, and **35–48× over the pure-Erlang
parsers**. See [benchmarks](#benchmarks) below.

The newer [`glazer`](https://hex.pm/packages/glazer) NIF is the one
library that can beat `Zaml` — it's faster on nested data (~1.35×) and
slower on a single flat 1M-key map (~1.8×). It gets there with a
hand-rolled C++ YAML parser built with profile-guided optimisation,
whereas `Zaml` deliberately stays on top of battle-tested `libyaml`.

The toolchain is also notably lighter: `Zaml` is built with the
single `zig` CLI invocation you see in the `Makefile`, with no
`./configure`, no `rebar3` port-compiler, and no autoconf.

## Benchmarks

Two fixtures, both parsed to native Erlang terms, on an Apple M3 Pro.
Full report at [`benchmark/RESULTS.md`](benchmark/RESULTS.md).

### 1M-line flat mapping (16 MB)

| Parser                              | Avg (s) | Relative |
| ----------------------------------- | -------:| --------:|
| **Zaml (NIF, libyaml + Zig)**       | **0.85**| **1.00×**|
| `glazer 1.1.6` (C++ NIF, PGO)       |  1.54   |   1.81×  |
| `fast_yaml 1.0.40` (rebar3 NIF)     |  2.60   |   3.06×  |
| `yamerl 0.10.0` (pure Erlang)       | 28.94   |  34.0×   |
| `yaml_elixir 2.12.2` (yamerl)       | 30.71   |  36.0×   |

### 100k-key nested mapping (15 MB)

| Parser                              | Avg (s) | Relative |
| ----------------------------------- | -------:| --------:|
| **Zaml (NIF, libyaml + Zig)**       | **0.51**| **1.00×**|
| `glazer 1.1.6` (C++ NIF, PGO)       |  0.38   |   0.74×  |
| `fast_yaml 1.0.40` (rebar3 NIF)     |  1.71   |   3.36×  |
| `yamerl 0.10.0` (pure Erlang)       | 23.48   |  46.2×   |
| `yaml_elixir 2.12.2` (yamerl)       | 24.25   |  47.7×   |

Both `Zaml` and `fast_yaml` wrap the same `libyaml` C parser, so the
~3× gap there is purely the event→term bridge. `glazer` is a
different design (a hand-rolled C++ parser, not libyaml): it wins on
nested data and loses on the wide flat map, so there's no single
"fastest" library across shapes.

## Installation

Add `zaml` to your `mix.exs`:

```elixir
def deps do
  [
    {:zaml, "~> 0.1.0"}
  ]
end
```

### Build prerequisites

The NIF is built at compile time from source. You need:

- **Zig 0.16+** (`brew install zig`, `apt install zig`, `asdf install zig latest`, …)
- **libyaml** development headers
  - macOS: `brew install libyaml`
  - Debian/Ubuntu: `apt install libyaml-dev`
  - Alpine: `apk add yaml-dev`
  - Fedora: `dnf install libyaml-devel`
- An Erlang/OTP installation (any reasonably recent version, 24+)

The compiler auto-detects `libyaml` via `pkg-config` first, then falls
back to well-known locations. Override with `YAML_INCLUDE_DIR` and
`YAML_LIB_DIR` env vars or `make` variables if it lives somewhere
unusual.

```bash
mix deps.get
mix compile   # builds the NIF via elixir_make / Makefile
```

## Usage

```elixir
Zaml.load(yaml_string) :: term
```

Returns the corresponding Elixir term for the **first YAML document** in
the input. Scalar type detection follows the YAML 1.2 *core* schema:

| YAML scalar         | Elixir term       |
| ------------------- | ----------------- |
| `42`, `-3`, `+1_000` | integer (`42`, `-3`, `1000`) |
| `3.14`, `1.0e-3`     | float (`3.14`, `0.001`) |
| `true`, `yes`, `on`  | atom `true` (or `:true` quoted) |
| `false`, `no`, `off` | atom `false` |
| `null`, `~`, empty   | atom `nil` |
| everything else      | binary (string)  |
| `!!str 42`           | binary `"42"` (explicit tag respected) |
| `!!int "42"`         | integer `42` (explicit tag respected) |

Sequences become lists, mappings become maps with binary keys.

Returns `:error` for non-binary input, `:parse_error` for malformed
YAML, and `:nil` for an empty document.

### Anchor / alias example

```elixir
iex> Zaml.load("""
...> defaults: &d {a: 1, b: 2}
...> prod:    *d
...> """)
%{"defaults" => %{"a" => 1, "b" => 2}, "prod" => %{"a" => 1, "b" => 2}}
```

> **Note:** YAML merge keys (`<<: *alias`) are not yet supported.

### Using the alternatives

For reference, here's how the same parse is done with each library the
benchmarks compare against:

```elixir
# zaml — returns the first document as a term
Zaml.load(yaml)

# fast_yaml — returns {:ok, [doc]}; :maps gives maps instead of proplists
:fast_yaml.decode(yaml, [:sane_scalars, :maps])

# glazer — hand-rolled C++ NIF; use_nil maps null -> nil (default is :null)
:glazer_yaml.decode(yaml, [:use_nil])
# ...or the Elixir wrapper:
Glazer.YAML.decode!(yaml)

# yaml_elixir — the most widely used wrapper, over pure-Erlang yamerl
YamlElixir.read_from_string(yaml)   # => {:ok, term}

# yamerl directly (raw records; yaml_elixir adds the Elixir mapper)
:yamerl_constr.string(yaml, detailed_constr: true, str_node_as_binary: true)
```

Two other libraries in the space aren't in the parse benchmarks:
[`ymlr`](https://hex.pm/packages/ymlr) is an **encoder** (`Ymlr.document!/1`),
not a parser, and [`yamleam`](https://hex.pm/packages/yamleam) is a
pure-Gleam parser, so it isn't reachable as a plain Mix dependency.

## Running tests

```bash
mix test
```

The test suite covers basic scalars, nested maps and lists, explicit
tags, anchors, empty input, and parse-error handling.

## Running benchmarks

The repo ships a Mix task that compares the Elixir NIF against
`fast_yaml`, `glazer`, `yaml_elixir`, and `yamerl` on the same fixture
(any parser whose dependency isn't installed is skipped).

```bash
# 1. Build the Elixir NIF + the benchmark deps
#    (glazer needs a C++23 compiler and rebar3; `brew install rebar3`)
mix deps.get
mix compile

# 2. Generate the 100k-key nested fixture
python3 benchmark/gen_big_yaml.py 100000 benchmark/big.yml

# 3. Generate the 1M-line flat fixture
python3 -c "
import yaml
yaml.dump({f'a{i}': f'b{i+1}' for i in range(1_000_000)},
          Dumper=yaml.CSafeDumper, default_flow_style=False,
          open('benchmark/big_1m.yml', 'w'))
"

# 4. Run the head-to-head
mix zaml_nif.bench benchmark/big.yml        # Zaml parse ~0.5 s (all parsers run)
mix zaml_nif.bench benchmark/big_1m.yml     # Zaml parse ~0.9 s (all parsers run)
```

A separate cross-language script (`benchmark/run_benchmark.py`) also
compares against PyYAML and ruamel.yaml if you want the Python
numbers.

## Project layout

```
.
├── lib/
│   ├── zaml.ex                      # public Elixir API
│   └── mix/tasks/
│       ├── zaml_nif.build.ex        # manual NIF build (`mix zaml_nif.build`)
│       └── zaml_nif.bench.ex        # `mix zaml_nif.bench` benchmark task
├── native/
│   └── zaml_nif.zig                 # the NIF (uses libyaml via @cImport)
├── priv/                            # compiled zaml.so lands here
├── test/                            # ExUnit tests
├── benchmark/
│   ├── benchmark.exs                # Elixir side
│   ├── run_benchmark.py             # Python driver
│   ├── gen_big_yaml.py              # fixture generator
│   ├── big.yml                      # generated 100k-key fixture
│   └── RESULTS.md                   # last benchmark run
├── Makefile                         # `make` builds the NIF directly
└── mix.exs
```

## Limitations / status

- YAML merge keys (`<<: *alias`) are not yet expanded.
- Multi-document input returns only the first document.
- Not yet battle-tested on very large or adversarial input. If you find
  a crash, please open an issue with the input.

## Credits

- [`kubkon/zig-yaml`](https://github.com/kubkon/zig-yaml) — the original
  pure-Zig YAML parser this project took inspiration from (and that
  still powers the Python prototype in this repo).
- [`yaml/libyaml`](https://github.com/yaml/libyaml) — the production
  YAML 1.1 parser that the Elixir NIF wraps.

---

## Python prototype

The original proof-of-concept — a `pip install`-able Python C extension
built in pure Zig by importing `Python.h` directly — still lives in
this repository. It demonstrates that you can build a CPython extension
module using only the Zig toolchain, with no `clang` or `setuptools`
workarounds. It was the subject of a [PyCon DE 2022 talk][talk] on
*Speeding Up Python with Zig*.

[talk]: https://2022.pycon.de/program/DFWSQR/

### Building the Python prototype

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
python test.py
```

**Note:** the Python prototype pins Zig 0.10.0. Newer Zig versions have
dropped fields from `struct _object` that the original `zamlmodule.zig`
references, so the prototype needs the older toolchain to build. Use the
Elixir NIF (above) for current Zig versions.

### Python benchmark

```bash
cd benchmark
python benchmark.py
```

The original prototype was benchmarked on a 2.3 GHz Quad-Core Intel
Core i7 as follows:

```text
zaml took 0.89 seconds
PyYAML CSafeLoader took 13.36 seconds
ruamel took 38.86 seconds
PyYAML SafeLoader took 81.78 seconds
```

The prototype is intentionally minimal (top-level `dict[str, str]`
only); it was meant to validate the toolchain story, not to compete
with full YAML libraries.

### Cross-platform notes (Python prototype)

- **Linux:** tested via Docker (`fedora` base image, `zig` and
  `python3-devel` from dnf).
- **Windows:** tested with Parallels.
- **macOS:** developed on macOS; no cross-host testing documented.
