# YAML 1.2 Parser Benchmarks — `zaml` NIF vs `fast_yaml`

These benchmarks measure how long it takes to parse a single YAML
document from a binary to native Erlang terms, comparing the Elixir
`zaml` NIF (this repo) against [`fast_yaml`](https://hex.pm/packages/fast_yaml)
(processone, the existing libyaml wrapper on Hex).

The head-to-head is the important one: **both libraries wrap the same
underlying `libyaml` C parser**, so any difference is in how quickly
they convert libyaml's event stream into Erlang terms.

## 1M-line flat mapping

**Input:** `benchmark/big_1m.yml` — 1 000 000 keys (`aN: bN+1`), 16.0 MB,
1 000 000 lines.

| Parser                              | Avg (s) | Min (s) | Max (s) | Relative |
| ----------------------------------- | -------:| -------:| -------:| --------:|
| **Zaml (NIF, libyaml + Zig)**       | **1.34**|  1.24   |  1.53   | **1.00x**|
| `fast_yaml 1.0.40` (rebar3 NIF)     |  1.88   |  1.77   |  1.97   |   1.40x  |

Zaml parses the 1M-line document in **~1.34 seconds**, about **1.4×
faster** than `fast_yaml`, even though both go through the same
libyaml.

## 100k-key nested mapping

**Input:** `benchmark/big.yml` — 100 000 top-level keys each containing
a nested map (strings, integers, floats, booleans, a list, and a
nested map), 15.2 MB, ~1.1 M lines.

| Parser                              | Avg (s) | Min (s) | Max (s) | Relative |
| ----------------------------------- | -------:| -------:| -------:| --------:|
| **Zaml (NIF, libyaml + Zig)**       | **0.50**|  0.48   |  0.53   | **1.00x**|
| `fast_yaml 1.0.40` (rebar3 NIF)     |  1.45   |  1.17   |  2.01   |   2.91x  |
| PyYAML `CSafeLoader` (libyaml)      |  8.49   |  8.20   |  8.79   |  17.05x  |
| PyYAML `SafeLoader` (pure Python)   | 33.11   | 32.32   | 33.55   |  66.46x  |
| ruamel.yaml (`safe`, pure Python)   | 48.39   | 47.12   | 49.62   |  97.11x  |

The gap widens to **2.91×** on nested data — Zaml's single-pass term
construction avoids the per-node `proplists` ↔ `maps` conversion that
`fast_yaml` does (it returns proplists by default, and converting to
maps adds overhead that Zaml never pays because it builds maps
directly).

## Hardware

- Apple M3 Pro (arm64), macOS Darwin 25.6.0
- Erlang/OTP 29, Elixir 1.20.2
- libyaml 0.2.5 (Homebrew), Zig 0.16.0

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
mix zaml_nif.bench benchmark/big.yml        # ~0.5 s
mix zaml_nif.bench benchmark/big_1m.yml     # ~1.3 s
```

The `ZamlNif.Bench` Mix task runs the chosen YAML through `Zaml.load/1` and
`:fast_yaml.decode/2` three times each and reports average, min, and
max in seconds (or milliseconds for runs under 1 s).

## Caveats

- Numbers are wall-clock for the parse call only — `mix run` startup
  is excluded.
- `fast_yaml` defaults to returning proplists; we request `[:sane_scalars,
  :maps]` so its output is comparable to Zaml's (Erlang maps). The
  proplists form is slightly faster but isn't directly comparable.
- Run-to-run variance on this M3 Pro is small (≤ 5%) for Zaml but
  occasionally higher for `fast_yaml` because of the proplists→maps
  pass.
- The 1M-line fixture uses a flat `key: value` shape (1 string value
  per key); the 100k-key fixture has the full nested structure. Use
  whichever matches your real workload when extrapolating.
