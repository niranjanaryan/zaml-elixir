# Hex.pm press release — `zaml` 0.1.0

**Title:** zaml 0.1.0 — a fast YAML parser for Elixir, powered by libyaml + Zig

**Summary (one sentence):**
A Zig NIF that wraps the same `libyaml` C library used by PyYAML, exposing
a single `Zaml.load/1` function that returns native Erlang terms in a
single pass.

**Body:**

We're pleased to announce the first release of [`zaml`](https://hex.pm/packages/zaml),
a YAML 1.2 parser for Elixir built as a Zig NIF around
[libyaml](https://pyyaml.org/wiki/LibYaml).

**Why another YAML library?**
[`yamerl`](https://hex.pm/packages/yamerl) and its Elixir wrapper
[`yaml_elixir`](https://hex.pm/packages/yaml_elixir) are pure-Erlang
and correct, but slow. The existing native option on Hex,
[`fast_yaml`](https://hex.pm/packages/fast_yaml), also wraps libyaml —
and is the obvious thing to compare against. We do, and the numbers
favour `zaml`. We also benchmark the newer hand-rolled C++ NIF
[`glazer`](https://hex.pm/packages/glazer), which beats `zaml` on
nested data but trails it on a wide flat map.

**Headline benchmarks (Apple M3 Pro, avg of 5 runs):**

| Parser | 1M-line flat (16 MB) | 100k-key nested (15 MB) |
|---|---:|---:|
| **`zaml` 0.1.0** | **0.84 s** | **0.53 s** |
| `glazer` 1.1.6 (C++ NIF, PGO) | 1.73 s | 0.41 s |
| `fast_yaml` 1.0.40 (rebar3 NIF) | 2.54 s | 1.86 s |
| `yamerl` 0.10.0 (pure Erlang) | 30.27 s | 23.88 s |
| `yaml_elixir` 2.12.2 (yamerl) | 30.95 s | 24.40 s |

`zaml` is ~3–3.5× faster than `fast_yaml` and ~36–46× faster than the
pure-Erlang parsers. Both `zaml` and `fast_yaml` wrap the same
`libyaml` C parser, so that speedup comes from how quickly the libyaml
event stream is turned into Erlang terms: `zaml` builds maps directly,
in a single pass, in Zig; `fast_yaml` constructs an intermediate
proplist representation that gets converted to maps on request.

**Features in 0.1.0:**

- `Zaml.load/1` → native Elixir term (maps, lists, integers, floats,
  booleans, `:nil`).
- YAML 1.2 core-schema scalar resolution (`true`/`false`/`null`, int
  and float inference from plain scalars).
- Respects explicit `!!str`/`!!int`/`!!float`/`!!bool`/`!!null` tags.
- Anchors and aliases (`&name` / `*name`).
- Returns `:parse_error` for malformed input.
- `mix zaml_nif.bench PATH` head-to-head benchmark against `fast_yaml`.

**Build & install:**

```elixir
def deps do
  [{:zaml, "~> 0.1.0"}]
end
```

Prerequisites: Zig 0.16+ and `libyaml` development headers. `mix.exs`
auto-detects Homebrew/Linux locations and injects the right
`CFLAGS`/`CPPFLAGS` for rebar3-compiled deps.

```bash
mix deps.get
mix compile   # builds the NIF automatically
mix test
```

**Caveats:**

- YAML merge keys (`<<: *alias`) are not yet expanded.
- Multi-document input returns only the first document.

**Links:**

- Hex: https://hex.pm/packages/zaml
- Repo: https://github.com/niranjanaryan/zaml-elixir
- Benchmarks: see `benchmark/RESULTS.md` in the repo.

Thanks to the `fast_yaml` and `yamerl` authors for paving the way, and
to the Zig project for making the toolchain story tractable.
