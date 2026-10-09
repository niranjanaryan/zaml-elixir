# Elixir Forum post (catchy cut) — `zaml` 0.2.0

**Category:** Libraries & Frameworks → Announcements
**Title:** zaml 0.2.0 — a YAML parser for Elixir that actually goes fast ⚡

---

yaml parsing, but fast ⚡

`zaml` 0.2.0 is out. it's a tiny Zig NIF over `libyaml` (the same C parser
PyYAML uses), and it turns the libyaml event stream straight into Erlang
terms in a single pass. no intermediate proplists, no second walk, no
allocation drama. it just goes.

**the vibe check:**

```elixir
iex> Zaml.load("foo: 1\nbar: [a, b, 3.14]\n")
%{"bar" => ["a", "b", 3.14], "foo" => 1}
```

- **~3–3.5× faster than `fast_yaml`** on both shapes
- **~36–46× faster than the pure-Erlang parsers**
- 1,000,000-line flat file in **0.84 s**, 100,000-key nested file in **0.53 s**

no cap, receipts below 🧾

**the receipts** (Apple M3 Pro, avg of 5 runs, `mix zaml_nif.bench`):

| Parser | 1M-line flat (16 MB) | 100k-key nested (15 MB) |
|---|---:|---:|
| **`zaml` 0.2.0** (Zig NIF + libyaml) | **0.84 s** | **0.53 s** |
| `glazer` 1.1.6 (C++ NIF, PGO) | 1.73 s | 0.41 s |
| `fast_yaml` 1.0.40 (rebar3 NIF) | 2.54 s | 1.86 s |
| `yamerl` 0.10.0 (pure Erlang) | 30.27 s | 23.88 s |
| `yaml_elixir` 2.12.2 (yamerl) | 30.95 s | 24.40 s |

**the why:** `zaml` and `fast_yaml` wrap the *same* `libyaml`. so the gap
isn't the parser — it's the bridge. `fast_yaml` builds a proplist and
converts it to a map later; `zaml` builds the map directly, in Zig, in one
pass. that's the whole trick, and it's most of the speedup on nested data.

**the honesty:** not gonna glaze, but `glazer` is genuinely goated on nested
data — it's ~1.3× ahead there. on a single wide flat map, though, `zaml`
wins by ~2.1×. no single library takes both shapes, and i'd rather say that
out loud than cherry-pick. 🫡

**what's new in 0.2.0:**

- **single-shot map construction.** one `enif_make_map_from_arrays` per map
  instead of a per-pair `enif_make_map_put`, which kills the O(n²) rehashing
  on wide maps. this is most of the flat-file glow-up.
- **zero-copy scalar sub-binaries.** string scalars are returned as
  sub-binaries of the input instead of fresh allocations. the path is
  bounds-checked with a copy fallback, so it stays correct across libyaml
  versions.
- **anchors & aliases actually work now.** `&name` / `*name` used to just
  return `:parse_error` 💀. now they resolve — anchor names get copied into a
  parse-scoped arena because libyaml frees its event buffer after every event.

**what it does:**

- `Zaml.load/1` → maps, lists, ints, floats, bools, `:nil`
- YAML 1.2 *core* schema scalar resolution, plus explicit
  `!!str`/`!!int`/`!!float`/`!!bool`/`!!null` tags
- anchors & aliases (`&name` / `*name`)
- `:parse_error` for malformed input, `:nil` for an empty document

**not done yet (being real):**

- merge keys (`<<: *alias`)
- multi-document input (returns the first document only)

**install:**

```elixir
def deps do
  [{:zaml, "~> 0.2.0"}]
end
```

needs Zig 0.16+ and `libyaml` headers, then it builds itself:

```bash
brew install zig libyaml          # macOS
# Debian/Ubuntu: apt install libyaml-dev, and Zig 0.16+
# from https://ziglang.org/download (or your distro).

mix deps.get
mix compile
```

the NIF compiles automatically during `mix compile` through `elixir_make`
and one `make` invocation — no `rebar3 port_compiler`, no `configure`.

**run the head-to-head yourself:**

```bash
mix deps.get
mix compile
mix zaml_nif.bench benchmark/big.yml   # runs every installed parser
```

(the 100k nested fixture: `python3 benchmark/gen_big_yaml.py 100000 benchmark/big.yml`.)

**links:**

- Hex: https://hex.pm/packages/zaml
- Docs: https://hexdocs.pm/zaml
- Source: https://github.com/niranjanaryan/zaml-elixir
- Full numbers, reproduce steps, caveats: `benchmark/RESULTS.md`

that's the post. `zaml` is at 0.2.0 — i'd love feedback on the API shape
before locking in a 1.0. got a YAML file that breaks it? open an issue with
the input attached. 🙏
