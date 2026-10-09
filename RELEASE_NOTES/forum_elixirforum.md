# Elixir Forum post — `zaml` 0.2.0: a fast YAML parser for Elixir

**Category:** Libraries & Frameworks → Announcements
**Title:** zaml 0.2.0 — fast YAML parser for Elixir (Zig NIF + libyaml)

---

Hi everyone,

I'd like to announce `zaml` 0.2.0, a YAML 1.2 parser for Elixir
that's noticeably faster than the existing options on Hex. It's
released as a Zig NIF that wraps the same `libyaml` C library used by
PyYAML, with the libyaml event stream → Erlang term conversion done in
Zig in a single pass.

**The pitch:**

```elixir
iex> Zaml.load("foo: 1\nbar: [a, b, 3.14]\n")
%{"bar" => ["a", "b", 3.14], "foo" => 1}
```

**Why a new one?** The two main YAML libs on Hex,
[`yamerl`](https://hex.pm/packages/yamerl) /
[`yaml_elixir`](https://hex.pm/packages/yaml_elixir), are pure-Erlang
and correct but slow on real workloads. The existing native option,
[`fast_yaml`](https://hex.pm/packages/fast_yaml) (processone), also
wraps libyaml — and is the obvious benchmark target. `zaml` ships the
same libyaml parser, but the event-to-term bridge is thinner, and the
benchmarks show a real speedup over it.

The newer [`glazer`](https://hex.pm/packages/glazer) NIF deserves a
mention: it's a *hand-rolled* C++ YAML parser (not libyaml) built with
profile-guided optimisation, and it's the one library that can beat
`zaml` — on nested data. On a single flat 1M-key map it's slower than
`zaml`. I've benchmarked it rather than pretending it doesn't exist.

**Headline numbers** (Apple M3 Pro, avg of 5 runs, `mix zaml_nif.bench`):

| Parser | 1M-line flat (16 MB) | 100k-key nested (15 MB) |
|---|---:|---:|
| **`zaml` 0.2.0** (Zig NIF + libyaml) | **0.84 s** | **0.53 s** |
| `glazer` 1.1.6 (C++ NIF, PGO) | 1.73 s | 0.41 s |
| `fast_yaml` 1.0.40 (rebar3 NIF) | 2.54 s | 1.86 s |
| `yamerl` 0.10.0 (pure Erlang) | 30.27 s | 23.88 s |
| `yaml_elixir` 2.12.2 (yamerl) | 30.95 s | 24.40 s |

So: `zaml` is **~3–3.5× faster than `fast_yaml`** and **~36–46×
faster than the pure-Erlang parsers** on both fixtures. `glazer` is
~1.3× faster than `zaml` on the nested fixture and ~2.1× slower on the
flat one — there's no single fastest library across shapes.

**What's new in 0.2.0:**

- **Single-shot map construction.** Maps are built with one
  `enif_make_map_from_arrays` call per map instead of a per-pair
  `enif_make_map_put`, removing the O(n²) rehashing that dominated wide
  maps. This is most of the gain over `fast_yaml` on the flat fixture.
- **Zero-copy scalar sub-binaries.** String scalars are returned as
  sub-binaries of the input rather than copied into freshly allocated
  binaries. The path is bounds-checked, with a copy fallback for scalars
  that some libyaml versions write into their own buffer, so it stays
  correct across libyaml versions.
- **Anchors and aliases now work end-to-end.** `&name` / `*name` were
  accepted by the parser but never resolved, so any document using an
  anchor returned `:parse_error`. Anchor names are now copied into a
  parse-scoped arena (libyaml frees the event buffer after each event)
  and aliases resolve to the aliased term.

The full report (with min/max, reproduce steps, and caveats) is in
`benchmark/RESULTS.md` in the repo. You can reproduce the head-to-head
with one command:

```bash
mix deps.get
mix compile
mix zaml_nif.bench benchmark/big.yml        # compares every installed parser
```

(The 100k nested fixture is generated with
`python3 benchmark/gen_big_yaml.py 100000 benchmark/big.yml`.)

**What it does:**

- `Zaml.load/1` — returns maps/lists/ints/floats/bools/`:nil`.
- YAML 1.2 *core* schema scalar resolution (`true`/`false`/`null`,
  int/float inference from plain scalars).
- Respects explicit `!!str`/`!!int`/`!!float`/`!!bool`/`!!null` tags.
- Anchors and aliases (`&name` / `*name`).
- Returns `:parse_error` for malformed YAML, `:nil` for an empty doc.

**What's not yet done:**

- Merge keys (`<<: *alias`).
- Multi-document input (returns the first document only).

**Installation & build:**

```elixir
def deps do
  [{:zaml, "~> 0.2.0"}]
end
```

Build needs Zig 0.16+ and `libyaml` dev headers. The `mix.exs` shipped
with the package auto-detects Homebrew/`/usr/local`/`/usr` libyaml
locations and exports `CFLAGS`/`CPPFLAGS`/`LDFLAGS` for rebar3, so on a
standard macOS or Debian/Ubuntu dev machine you only need:

```bash
brew install zig libyaml          # macOS
# Debian/Ubuntu: apt install libyaml-dev, and install Zig 0.16+
# from https://ziglang.org/download (or your distro's package).

mix deps.get
mix compile
```

The NIF is built automatically during `mix compile` through
`elixir_make` and a single `make` invocation; no `rebar3
port_compiler`, no `configure` script.

**Origin:** this started as a side experiment in porting the original
`zaml` Python prototype (a pure-Zig Python extension that was the
subject of a [PyCon DE 2022 talk](https://2022.pycon.de/program/DFWSQR/))
to the BEAM. The Python prototype still lives in the same repo for
historical reference; the NIF here is the actively maintained Elixir
binding.

**Links:**

- Hex: https://hex.pm/packages/zaml
- Source: https://github.com/niranjanaryan/zaml-elixir
- README, benchmark suite, and full benchmark results are in the repo.

Happy to answer questions or take bug reports here or in the issue
tracker. The package is at 0.2.0 — I'd love feedback on the API shape
before locking in a 1.0.
