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
intermediate proplists. That gives a **~1.35× speedup on a 1M-line
flat mapping** and a **~3× speedup on nested mappings**. See
[benchmarks](#benchmarks) below.

The toolchain is also notably lighter: `Zaml` is built with the
single `zig` CLI invocation you see in the `Makefile`, with no
`./configure`, no `rebar3` port-compiler, and no autoconf.

## Benchmarks

Two fixtures, both parsed to native Erlang terms, on an Apple M3 Pro.
Full report at [`benchmark/RESULTS.md`](benchmark/RESULTS.md).

### 1M-line flat mapping (16 MB)

| Parser                              | Avg (s) | Relative |
| ----------------------------------- | -------:| --------:|
| **Zaml (NIF, libyaml + Zig)**       | **1.34**| **1.00x**|
| `fast_yaml 1.0.40` (rebar3 NIF)     |  1.88   |   1.40x  |

Both wrap the same `libyaml` C parser; the speedup comes from how
quickly the event stream is turned into Erlang terms in a single pass.

### 100k-key nested mapping (15 MB)

| Parser                              | Avg (s) | Relative |
| ----------------------------------- | -------:| --------:|
| **Zaml (NIF, libyaml + Zig)**       | **0.50**| **1.00x**|
| `fast_yaml 1.0.40` (rebar3 NIF)     |  1.45   |   2.91x  |
| PyYAML `CSafeLoader` (libyaml)      |  8.49   |  17.05x  |
| PyYAML `SafeLoader` (pure Python)   | 33.11   |  66.46x  |
| ruamel.yaml (`safe`, pure Python)   | 48.39   |  97.11x  |

The gap widens to **2.91×** on nested data: Zaml builds Erlang maps
directly from the event stream, while `fast_yaml` constructs
proplists first and then converts to maps on request.

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

- **Zig 0.10+** (`brew install zig`, `apt install zig`, `asdf install zig latest`, …)
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
mix compile   # automatically builds the NIF via `mix zaml_nif.build`
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

## Running tests

```bash
mix test
```

The test suite covers basic scalars, nested maps and lists, explicit
tags, anchors, empty input, and parse-error handling.

## Running benchmarks

The repo ships a Mix task that compares the Elixir NIF against
`fast_yaml` (the existing libyaml wrapper on Hex) on the same fixture.

```bash
# 1. Build the Elixir NIF + the fast_yaml dep
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
mix zaml_nif.bench benchmark/big.yml        # ~0.5 s
mix zaml_nif.bench benchmark/big_1m.yml     # ~1.3 s
```

A separate cross-language script (`benchmark/run_benchmark.py`) also
compares against PyYAML and ruamel.yaml if you want the Python
numbers.

## Project layout

```
.
├── lib/
│   ├── zaml.ex                      # public Elixir API
│   └── mix/tasks/zaml_nif.build.ex  # compile-time NIF build task
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
