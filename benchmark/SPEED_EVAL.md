# Speed/throughput evaluation (libyaml vs libfyaml, M3 Pro)

Event-mode parse-only throughput (events/sec / MB/s). Both tested at -O2 with scalar text extraction where fair.

## Real fixtures
| Fixture | libfyaml | libyaml | MB/s (fy/ly) |
| --- | --- | --- | --- |
| `benchmark/big.yml` (nested 15.18MB) | 0.283s (53.7 MB/s) | 0.306s (49.5 MB/s) | +8.5% |
| `benchmark/big_1m.yml` (flat 16.78MB) | 0.259s (64.8 MB/s) | 0.302s (55.5 MB/s) | +16.8% |

## Synthetic
| Case | libfyaml | libyaml | Notes |
| --- | --- | --- | --- |
| block sequence (400k items) | 82.1 MB/s | 71.3 MB/s | fy wins |
| flow sequence (400k items) | 39.6 MB/s | 45.2 MB/s | ly wins |
| flow map (400k k:v) | 42.0 MB/s | 48.7 MB/s | ly wins |
| anchors/aliases (400k refs to same map) | 48.6 MB/s | 51.3 MB/s | ly wins |

## Document/tree mode (libfyaml)
Building a full document tree + duplicate-key detection is O(n²) on large maps (index-based pair access). With `FYPCF_ALLOW_DUPLICATE_KEYS` and skipping a full O(M) walk for large files, 50k-line flat parsed in 0.018s (47.7 MB/s) — but "build full tree" still expensive vs event-mode. `ALLOW_DUPLICATE_KEYS` avoids quadratic duplicate checks.

## Conclusion
- Event streaming: libfyaml is competitive, not universally faster (0–17% delta on these inputs).
- Replacing the libyaml event feed in the NIF alone is unlikely to yield the ~3–4× needed to approach rapidyaml/libfyaml's fastest modes; the event→term conversion + BEAM scheduling remain dominant (see spikes in `/tmp/zaml_eval/`).
- libfyaml's API is richer (document/tree) but tree construction overhead is problematic for high-throughput flat mappings without care.
- Feasible swap: use `fy_parser_*`/`fy_event_*` with Zig `@cImport` in `native/zaml_nif.zig`. Need to handle anchors/tags, and to track memory (libfyaml events owned by parser until `fy_parser_event_free`). Also note C-ABI via `@cImport`.
- If swapping, preserve: "YAML 1.2 core schema", exact number semantics as-is, sub-binary optimization, dirty-scheduler exploration already evaluated (reverted). Don't drop it blindly.

## Artifacts
- `/tmp/zaml_eval/fy_count.c`, `fy_doc.c`, `ly_count.c`, built binaries; fixtures generated there.
- libfyaml installed at `/opt/homebrew/Cellar/libfyaml/0.9.6/`.

## Recommendation
Try a minimal event-feed shim in the NIF first (A/B against current build) on the same fixtures before committing a full engine swap. If gains are < 1.3×, focus on: (1) avoid per-event heap churn in the conversion layer, (2) batch map construction more aggressively, (3) consider offloading to dirty CPU schedulers or a parallel chunked parse (evaluated). The Python extension mirrors the same event→object logic; evaluate there too.

## Updated numbers (libfyaml 0.9.6, doc-mode build-only, allow-dup-keys)
| Case | doc build (allow dup keys) |
| --- | --- |
| `big.yml` (nested 15.18MB) | 0.374s (40.5 MB/s) |
| `big_1m.yml` (flat 16.78MB) | 0.357s (47.0 MB/s) |
| flow map (6.18MB, 400k k:v) | 0.203s (30.5 MB/s) |
| block seq (5.09MB, 400k) | 0.086s (58.9 MB/s) |
| anchors (4.69MB, 400k refs) | 0.133s (35.2 MB/s) |
| flow seq (2.69MB, 400k) | 0.077s (34.9 MB/s) |


## Python extension performance vs PyYAML/ruamel (macOS arm64, Python 3.14)

| Fixture | zaml | PyYAML CSafeLoader | PyYAML SafeLoader | ruamel.yaml (safe,pure) |
| --- | --- | --- | --- | --- |
| `benchmark/big.yml` (nested 15.18MB, 2 runs) | 532 ms (1.0×) | 9646 ms (18.1×) | ~28s (52–53×) | ~50.7s (95×) |
| `benchmark/big_1m.yml` (flat 16.78MB, 2 runs) | 587 ms (1.0×) | 5329 ms (9.1×) | ~29s (49×) | ~41.6s (71×) |

Notes: Python extension wraps libyaml in Zig, builds native objects directly (dict/list/str/int/float/bool/None), matching YAML 1.2 core schema with explicit tag support and anchors.
