# Gen Z social post — `zaml` 0.2.0

**Platforms:** Bluesky / X (Twitter) / LinkedIn short-form
**Tone:** direct, no-nonsense, slightly irreverent — the "another YAML
lib? yes, and it's faster" energy.

---

## Bluesky

built a yaml parser in zig that wraps libyaml. it's ~3x faster than
fast_yaml on the same underlying C parser, and now anchors/aliases
actually work.

0.2.0 out: https://hex.pm/packages/zaml

the trick: maps get built in one shot instead of pair-by-pair, and
string scalars are zero-copy sub-binaries of the input. no intermediate
proplists, no re-copies.

1M-line flat: 0.84s. fast_yaml: 2.54s. yamerl: 30s.

repo: https://github.com/niranjanaryan/zaml-elixir

## X (Twitter)

just shipped zaml 0.2.0 — a Zig NIF YAML parser for Elixir.

the 0.2.0 headline: single-shot map construction + zero-copy scalar
sub-binaries. 1M-line flat parse in 0.84s vs 2.54s for fast_yaml
(same libyaml underneath) and 30s for yamerl.

anchors & aliases now actually resolve (they were returning
:parse_error before).

https://hex.pm/packages/zaml

## LinkedIn (longer)

announcing zaml 0.2.0 — a Zig NIF YAML 1.2 parser for Elixir that
wraps libyaml and ships with two performance wins over the existing
native option on Hex:

1. **Single-shot map construction.** Maps are built with one
   `enif_make_map_from_arrays` call instead of a per-pair
   `enif_make_map_put`, eliminating the O(n²) rehashing that dominated
   wide maps. This is most of the gain over `fast_yaml` on the flat
   1M-key fixture.

2. **Zero-copy scalar sub-binaries.** String scalars are returned as
   sub-binaries of the input rather than copied into freshly allocated
   binaries. The path is bounds-checked with a copy fallback, so it
   stays correct across libyaml versions that may write quoted/block
   scalars into their own buffer.

Headline numbers (Apple M3 Pro, avg of 5 runs):

| Parser | 1M-line flat | 100k-key nested |
|---|---:|---:|
| zaml 0.2.0 | 0.84 s | 0.53 s |
| fast_yaml 1.0.40 | 2.54 s | 1.86 s |
| yamerl 0.10.0 | 30.27 s | 23.88 s |

This release also fixes anchors and aliases end-to-end — `&name` /
`*name` now resolve, with anchor names copied into a parse-scoped arena
because libyaml frees its event buffer after each event.

Build needs Zig 0.16+ and libyaml dev headers; `mix.exs` auto-detects
Homebrew/Linux locations and injects the right CFLAGS/CPPFLAGS/LDFLAGS
for rebar3-compiled deps.

https://hex.pm/packages/zaml