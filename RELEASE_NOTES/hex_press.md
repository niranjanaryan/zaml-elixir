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
favour `zaml`.

**Headline benchmarks (Apple M3 Pro, libyaml 0.2.5, avg of 3 runs):**

- **1,000,000-line flat mapping (16 MB):** `zaml` 1.34 s vs
  `fast_yaml` 1.88 s — **1.4× faster**.
- **100,000-key nested mapping (15 MB):** `zaml` 0.50 s vs
  `fast_yaml` 1.45 s — **2.9× faster**, and ~17× faster than PyYAML
  `CSafeLoader` on the same fixture.

Both libraries wrap the same `libyaml` C parser, so the speedup comes
from how quickly the libyaml event stream is turned into Erlang terms:
`zaml` builds maps directly, in a single pass, in Zig; `fast_yaml`
constructs an intermediate proplist representation that gets converted
to maps on request.

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

Prerequisites: Zig 0.10+ and `libyaml` development headers. `mix.exs`
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
