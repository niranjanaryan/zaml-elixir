# `zaml` 0.2.0 — social & forum copy (all channels)

One source of truth for every channel. Numbers are the canonical
5-run averages from `benchmark/RESULTS.md`. Trim emojis/slang to taste
per audience; **do not change the numbers or links**.

Links:
- Hex: https://hex.pm/packages/zaml
- Docs: https://hexdocs.pm/zaml
- Repo: https://github.com/niranjanaryan/zaml-elixir
- Benchmarks: https://github.com/niranjanaryan/zaml-elixir/blob/main/benchmark/RESULTS.md

---

## LinkedIn (long-form, polished-catchy)

yaml parsing in Elixir, but fast ⚡

I shipped `zaml` 0.2.0 — a YAML parser for Elixir built as a tiny Zig NIF
over the same `libyaml` C library PyYAML uses. It turns the libyaml event
stream straight into Erlang terms in a single pass: no intermediate
proplists, no second walk.

The numbers (Apple M3 Pro, avg of 5 runs):

⚡ 1,000,000-line flat map: **0.84 s** — ~3.0× faster than `fast_yaml`,
   ~36× faster than pure-Erlang `yamerl`
⚡ 100,000-key nested map: **0.53 s** — ~3.5× / ~45×

Same underlying C parser as `fast_yaml` — so the win isn't the parser, it's
the bridge. `zaml` builds Erlang maps directly in Zig, in one pass.

What's new in 0.2.0:
- **Single-shot map construction** — one `enif_make_map_from_arrays` per
  map instead of per-pair `enif_make_map_put`, killing O(n²) rehashing on
  wide maps.
- **Zero-copy scalar sub-binaries** — string scalars are returned as
  sub-binaries of the input, bounds-checked with a copy fallback.
- **Anchors & aliases** (`&name` / `*name`) now resolve end-to-end.

I also keep the benchmark honest: `glazer` is ~1.3× faster than `zaml` on
nested data and ~2.1× slower on a wide flat map. No single library wins
across shapes.

Hex: https://hex.pm/packages/zaml
Docs: https://hexdocs.pm/zaml
Repo: https://github.com/niranjanaryan/zaml-elixir

#Elixir #Erlang #BEAM #YAML #Zig #OpenSource #Performance

---

## X / Twitter (thread)

1/
yaml parsing, but fast ⚡

`zaml` 0.2.0 is out — a Zig NIF over libyaml for Elixir.

~3× faster than fast_yaml on the *same* C parser, ~36–46× faster than the
pure-Erlang parsers.

🧵

2/
the receipts (Apple M3 Pro, avg of 5):

1M-line flat: 0.84s vs 2.54s fast_yaml vs 30.9s yaml_elixir
100k-key nested: 0.53s vs 1.86s vs 24.4s

3/
why is it fast? both wrap the same libyaml. fast_yaml builds a proplist
then converts; zaml builds Erlang maps directly in Zig, one pass. the
bridge is the speedup.

4/
what's new in 0.2.0:
• single-shot map construction (no more O(n²) rehashing)
• zero-copy scalar sub-binaries
• anchors & aliases actually work now (&name / *name)

5/
being honest: glazer (hand-rolled C++, PGO) is ~1.3× faster on nested data.
zaml takes the wide flat map by ~2.1×. different shapes, different winners.

6/
add `{:zaml, "~> 0.2.0"}`. needs Zig 0.16+ + libyaml headers; NIF builds on
`mix compile`.

hex → https://hex.pm/packages/zaml
docs → https://hexdocs.pm/zaml
repo → https://github.com/niranjanaryan/zaml-elixir

---

## Bluesky (short)

built a yaml parser in zig that wraps libyaml. it's ~3× faster than
fast_yaml on the same underlying C parser, and 0.2.0 makes anchors/aliases
actually work.

1M-line flat: 0.84s. fast_yaml: 2.54s. yamerl: 30s.

the trick: maps built in one shot instead of pair-by-pair, and string
scalars are zero-copy sub-binaries of the input.

https://hex.pm/packages/zaml

---

## Mastodon (short + tags)

`zaml` 0.2.0 — YAML parsing for Elixir that goes fast ⚡

A Zig NIF over libyaml: ~3× `fast_yaml`, ~36–46× the pure-Erlang parsers.
1M-line flat file in 0.84 s. Anchors & aliases now work.

https://hex.pm/packages/zaml

#Elixir #Erlang #BEAM #YAML #Zig #OpenSource

---

## Reddit — r/elixir

**Title:** zaml 0.2.0 — a YAML parser for Elixir (Zig NIF over libyaml), ~3× fast_yaml, ~36–46× pure-Erlang

**Body:**

hey r/elixir — I built `zaml`, a YAML parser for Elixir as a Zig NIF over
the same libyaml C library PyYAML uses. 0.2.0 is out today.

I kept seeing libyaml-vs-pure-Erlang benchmarks that compared across
different parsers, so I tried to isolate the bridge instead. Here's the
head-to-head (Apple M3 Pro, avg of 5 runs, all via `mix zaml_nif.bench`):

| Parser | 1M-line flat (16 MB) | 100k-key nested (15 MB) |
|---|---:|---:|
| zaml 0.2.0 (Zig NIF) | **0.84 s** | **0.53 s** |
| glazer 1.1.6 (C++ NIF, PGO) | 1.73 s | 0.41 s |
| fast_yaml 1.0.40 (rebar3 NIF) | 2.54 s | 1.86 s |
| yamerl 0.10.0 (pure Erlang) | 30.27 s | 23.88 s |
| yaml_elixir 2.12.2 (yamerl) | 30.95 s | 24.40 s |

zaml and fast_yaml wrap the same libyaml, so the gap is the bridge: fast_yaml
builds a proplist and converts to a map later; zaml builds the map directly
in Zig, one pass.

Being upfront: glazer is genuinely faster on nested data (~1.3×) and slower
on the wide flat map (~2.1×). No single library wins both shapes.

0.2.0 changes:
- single-shot map construction (one `enif_make_map_from_arrays`) — kills
  O(n²) rehashing on wide maps
- zero-copy scalar sub-binaries (bounds-checked, copy fallback)
- anchors & aliases now work

Not done yet: merge keys (`<<`) and multi-doc (first doc only).

Code + reproduce steps: https://github.com/niranjanaryan/zaml-elixir
Full numbers: https://github.com/niranjanaryan/zaml-elixir/blob/main/benchmark/RESULTS.md

Would love feedback on the API before a 1.0. Bug reports with the YAML
that broke it are the most useful thing you can send.

---

## Hacker News (Show HN)

**Title (66 chars):** Show HN: Zaml – fast YAML parser for Elixir (Zig NIF over libyaml)

**First comment (author):**

`zaml` is a YAML parser for Elixir. It's a Zig NIF wrapping libyaml, with
the event → Erlang term conversion done in Zig in a single pass. There's a
single `Zaml.load/1` entry point returning native terms.

The interesting bit for HN is probably the head-to-head: `fast_yaml` also
wraps libyaml, so I benchmarked both against hand-rolled and pure-Erlang
alternatives. zaml is ~3× fast_yaml and ~36–46× the pure-Erlang parsers on
my fixtures. `glazer` (hand-rolled C++ with PGO) is faster on nested data
(~1.3×) and slower on a wide flat map (~2.1×).

0.2.0 added single-shot map construction, zero-copy scalar sub-binaries,
and working anchors/aliases (the last one previously returned a parse
error).

Reproduce: `mix zaml_nif.bench benchmark/big.yml`. Table + caveats in
benchmark/RESULTS.md. Happy to answer questions about the Zig/BEAM
boundary or the benchmark methodology.

---

## Erlang Forums (professional)

Cross-posted from the Elixir Forum announcement: `zaml` 0.2.0 is a YAML
parser for Elixir implemented as a Zig NIF over libyaml, exposing
`Zaml.load/1` → Erlang terms in a single pass. It benchmarks at ~3×
`fast_yaml` and ~36–46× the pure-Erlang parsers (`yamerl` / `yaml_elixir`)
on flat and nested fixtures, with `glazer` faster on nested data and slower
on wide flat maps.

0.2.0 adds single-shot map construction, zero-copy scalar sub-binaries, and
anchors/aliases. Build needs Zig 0.16+ and libyaml dev headers.

Hex: https://hex.pm/packages/zaml
Docs: https://hexdocs.pm/zaml

---

## Dev.to (cross-post blurb)

Republishing the long-form writeup: "zaml 0.2.0 — YAML parsing for Elixir,
but fast ⚡ (and what I learned wiring libyaml to the BEAM via Zig)."

Covers: why another YAML lib, the Zig↔BEAM boundary, single-pass map
construction, zero-copy sub-binaries, anchors, and the full benchmark with
methodology and caveats. Canonical copy lives in the repo
(`RELEASE_NOTES/blog_post.md`); set the canonical URL to the HexDocs/blog
original.

---

## Discord / Slack / IRC (one-liner)

`zaml` 0.2.0 — a fast YAML parser for Elixir (Zig NIF over libyaml). ~3×
fast_yaml, ~36–46× the pure-Erlang parsers, anchors now work. Hex:
https://hex.pm/packages/zaml
