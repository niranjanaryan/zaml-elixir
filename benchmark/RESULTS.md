# YAML Parser Benchmarks — `zaml` vs the Elixir ecosystem

These benchmarks measure how long it takes to parse a single YAML
document from a binary to native Erlang terms. The field:

| Library | Version | Engine |
| --- | --- | --- |
| **`zaml`** (this repo) | 0.2.0 | Zig NIF over `libyaml` |
| [`fast_yaml`](https://hex.pm/packages/fast_yaml) | 1.0.40 | rebar3 NIF over `libyaml` |
| [`glazer`](https://hex.pm/packages/glazer) | 1.1.6 | C++ NIF, hand-rolled recursive-descent parser, PGO build |
| [`yaml_elixir`](https://hex.pm/packages/yaml_elixir) | 2.12.2 | pure-Erlang `yamerl` + Elixir mapper |
| [`yamerl`](https://hex.pm/packages/yamerl) | 0.10.0 | pure-Erlang parser (raw, no mapper) |

Two of these — `zaml` and `fast_yaml` — wrap the *same* underlying
`libyaml` C library, so the head-to-head there isolates the
event-stream → Erlang-term bridge. `glazer` is a different design: a
self-contained, hand-rolled C++ parser (not libyaml), built with
profile-guided optimisation and `-march=native`. The pure-Erlang
options are included as the "what most apps ship today" baseline.

> **TL;DR.** `zaml` is ~3× faster than `fast_yaml` on the flat map and
> ~3.5× on the nested one, and ~36–46× faster than the pure-Erlang
> parsers. The hand-rolled `glazer` NIF is faster than `zaml` on nested
> data (~1.3×) but slower on the 1M-key flat map (~2.1×); no single
> library wins both. `zaml`'s advantage is doing this on top of
> battle-tested `libyaml` rather than a bespoke YAML parser.

## 1M-line flat mapping

**Input:** `benchmark/big_1m.yml` — 1 000 000 keys (`aN: bN+1`), 16.0 MB,
1 000 000 lines.

| Parser | Avg (s) | Min (s) | Max (s) | Relative |
| --- | ---: | ---: | ---: | ---: |
| **Zaml (NIF, libyaml + Zig)** | **0.84** | 0.82 | 0.87 | **1.00×** |
| `glazer 1.1.6` (C++ NIF, PGO) | 1.73 | 1.64 | 1.79 | 2.06× |
| `fast_yaml 1.0.40` (rebar3 NIF) | 2.54 | 2.48 | 2.62 | 3.03× |
| `yamerl 0.10.0` (raw, pure Erlang) | 30.27 | 29.40 | 31.24 | 36.1× |
| `yaml_elixir 2.12.2` (yamerl + mapper) | 30.95 | 29.99 | 32.52 | 36.9× |

On a single, very wide map, Zaml is the fastest: ~2.1× ahead of
`glazer` and ~3.0× ahead of `fast_yaml`.

## 100k-key nested mapping

**Input:** `benchmark/big.yml` — 100 000 top-level keys each containing
a nested map (strings, integers, floats, booleans, a list, and a
nested map), 15.2 MB, ~1.1 M lines.

| Parser | Avg (s) | Min (s) | Max (s) | Relative |
| --- | ---: | ---: | ---: | ---: |
| **Zaml (NIF, libyaml + Zig)** | **0.53** | 0.52 | 0.58 | **1.00×** |
| `glazer 1.1.6` (C++ NIF, PGO) | 0.41 | 0.38 | 0.49 | 0.77× |
| `fast_yaml 1.0.40` (rebar3 NIF) | 1.86 | 1.74 | 1.96 | 3.50× |
| `yamerl 0.10.0` (raw, pure Erlang) | 23.88 | 23.16 | 24.49 | 45.0× |
| `yaml_elixir 2.12.2` (yamerl + mapper) | 24.40 | 24.07 | 24.84 | 45.9× |

On deeply nested data, `glazer`'s hand-rolled parser pulls ahead
(~1.3× over Zaml), while Zaml still beats `fast_yaml` by ~3.5× and
the pure-Erlang parsers by ~45–46×. The `yaml_elixir`/`yamerl` gap is
almost entirely the pure-Erlang parse itself — the Elixir mapper adds
only a few percent on top.

## Reading the numbers

- **Zaml vs `fast_yaml`** — both wrap libyaml; the difference is that
  Zaml builds maps directly from the event stream while `fast_yaml`
  constructs proplists and converts to maps on request. That's why the
  gap is larger on nested data (more proplist nodes to rewrite).
- **Zaml vs `glazer`** — different tools. `glazer` is a bespoke
  recursive-descent parser compiled with PGO and `-march=native`; it's
  faster on nested maps but slower on a single 1M-entry flat map. Zaml
  gets its speed from a thin Zig shim over libyaml, so it inherits
  libyaml's spec coverage and battle-testing.
- **Zaml vs pure Erlang** — a C parser plus a single-pass Zig bridge is
  ~36–46× faster than building every node through BEAM dispatches.

## Hardware

- Apple M3 Pro (arm64), macOS Darwin 25.6.0
- Erlang/OTP 29, Elixir 1.20.2
- libyaml 0.2.5 (Homebrew), Zig 0.16.0
- Apple clang 21 (for glazer's C++23 NIF, PGO build)
- rebar3 3.27.1 (to build `glazer` and `fast_yaml`)

## How to reproduce

```bash
# 1. Install deps and build everything. mix.exs auto-detects libyaml
#    on common paths (Homebrew, /usr/local, /usr) and injects
#    CFLAGS/CPPFLAGS/LDFLAGS so rebar3-compiled deps find it.
mix deps.get
mix compile

# 2. Generate the 100k nested fixture
python3 benchmark/gen_big_yaml.py 100000 benchmark/big.yml

# 3. Generate the 1M flat fixture
python3 -c "
import yaml
yaml.dump({f'a{i}': f'b{i+1}' for i in range(1_000_000)},
          Dumper=yaml.CSafeDumper, default_flow_style=False,
          open('benchmark/big_1m.yml', 'w'))
"

# 4. Run the head-to-head
mix zaml_nif.bench benchmark/big.yml        # Zaml parse ~0.5 s (all parsers run)
mix zaml_nif.bench benchmark/big_1m.yml     # Zaml parse ~0.8 s (all parsers run)
```

`mix zaml_nif.bench` runs the file through every available parser
(any whose dep isn't installed is skipped), once as a warm-up and then
5 timed runs each, reporting average/min/max in seconds. A
`:erlang.garbage_collect/0` is forced before each timed run so that
freeing a previous parser's 1M-entry map isn't charged to the next.

## Caveats

- Numbers are wall-clock for the parse call only — `mix run` startup
  is excluded.
- The pure-Erlang numbers are ~30 s per parse, so run-to-run variance
  is correspondingly larger in absolute terms; the ranking is stable.
- `fast_yaml` defaults to returning proplists; we request
  `[:sane_scalars, :maps]` so its output is comparable to Zaml's
  (Erlang maps). The proplists form is slightly faster but isn't
  directly comparable.
- `yamerl` is measured raw (`detailed_constr`, `str_node_as_binary`);
  `yaml_elixir` measures `read_from_string/1`, i.e. yamerl plus the
  Elixir map mapper.
- `glazer`'s YAML decoder is hand-rolled and caps nesting at 256
  levels; it is not a libyaml-compatible implementation. Its build here
  used `-march=native` on this M3 Pro.
- The 1M-line fixture uses a flat `key: value` shape (1 string value
  per key); the 100k-key fixture has the full nested structure. Use
  whichever matches your real workload when extrapolating.
