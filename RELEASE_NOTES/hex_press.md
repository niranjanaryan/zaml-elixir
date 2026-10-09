# Hex.pm press release — `zaml` 0.2.0

**Title:** zaml 0.2.0 — YAML parsing for Elixir, but fast ⚡

**Summary (one sentence):**
A tiny Zig NIF that wraps the same `libyaml` C library PyYAML uses, exposing
a single `Zaml.load/1` that returns native Erlang terms in one pass.

**Body:**

[`zaml`](https://hex.pm/packages/zaml) 0.2.0 is out. it's a YAML 1.2 parser
for Elixir built as a Zig NIF around
[libyaml](https://pyyaml.org/wiki/LibYaml), and it is *fast*. we're talking
~3× `fast_yaml` and ~36–46× the pure-Erlang crew. receipts below 🧾

**why another YAML lib?**
[`yamerl`](https://hex.pm/packages/yamerl) and its wrapper
[`yaml_elixir`](https://hex.pm/packages/yaml_elixir) are pure-Erlang,
correct, and slow at scale. the existing native option,
[`fast_yaml`](https://hex.pm/packages/fast_yaml), also wraps libyaml — so
that's the real head-to-head. we also benchmark the newer hand-rolled C++
NIF [`glazer`](https://hex.pm/packages/glazer), which wins on nested data
but trails `zaml` on a wide flat map.

**headline benchmarks (Apple M3 Pro, avg of 5 runs):**

| Parser | 1M-line flat (16 MB) | 100k-key nested (15 MB) |
|---|---:|---:|
| **`zaml` 0.2.0** | **0.84 s** | **0.53 s** |
| `glazer` 1.1.6 (C++ NIF, PGO) | 1.73 s | 0.41 s |
| `fast_yaml` 1.0.40 (rebar3 NIF) | 2.54 s | 1.86 s |
| `yamerl` 0.10.0 (pure Erlang) | 30.27 s | 23.88 s |
| `yaml_elixir` 2.12.2 (yamerl) | 30.95 s | 24.40 s |

so `zaml` is ~3–3.5× faster than `fast_yaml` and ~36–46× faster than the
pure-Erlang parsers. both `zaml` and `fast_yaml` wrap the same `libyaml`, so
the gap is the bridge: `zaml` builds maps directly, in a single Zig pass;
`fast_yaml` builds an intermediate proplist and converts it on request.

**what's new in 0.2.0:**

- **single-shot map construction.** one `enif_make_map_from_arrays` per map
  instead of a per-pair `enif_make_map_put`, killing the O(n²) rehashing on
  wide maps. this is the bulk of the flat-file gain.
- **zero-copy scalar sub-binaries.** string scalars come back as
  sub-binaries of the input instead of fresh allocations. the path is
  bounds-checked with a copy fallback, so it stays correct across libyaml
  versions.
- **anchors & aliases.** `&name` / `*name` now work end-to-end. anchor names
  are copied into a parse-scoped arena because libyaml frees its event
  buffer after each event. before, any anchored document returned
  `:parse_error`.

**features:**

- `Zaml.load/1` → native Elixir term (maps, lists, integers, floats,
  booleans, `:nil`).
- YAML 1.2 core-schema scalar resolution (`true`/`false`/`null`, int and
  float inference from plain scalars).
- respects explicit `!!str`/`!!int`/`!!float`/`!!bool`/`!!null` tags.
- anchors & aliases (`&name` / `*name`).
- `:parse_error` for malformed input, `:nil` for an empty doc.
- `mix zaml_nif.bench PATH` head-to-head bench vs `fast_yaml`, `glazer`,
  `yaml_elixir`, and `yamerl`.

**build & install:**

```elixir
def deps do
  [{:zaml, "~> 0.2.0"}]
end
```

prereqs: Zig 0.16+ and `libyaml` dev headers. `mix.exs` auto-detects
Homebrew/Linux locations and injects the right `CFLAGS`/`CPPFLAGS` for
rebar3-compiled deps.

```bash
mix deps.get
mix compile   # builds the NIF automatically
mix test
```

**caveats (no cap):**

- YAML merge keys (`<<: *alias`) aren't expanded yet.
- multi-document input returns only the first document.

**links:**

- Hex: https://hex.pm/packages/zaml
- Docs: https://hexdocs.pm/zaml
- Repo: https://github.com/niranjanaryan/zaml-elixir
- Benchmarks: see `benchmark/RESULTS.md` in the repo.

thanks to the `fast_yaml` and `yamerl` authors for paving the way, and to
the Zig project for making the toolchain story tractable. 🫡
