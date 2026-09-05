# Changelog

All notable changes to `zaml` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-05

### Added

- **Elixir NIF**: a Zig NIF wrapping [libyaml](https://pyyaml.org/wiki/LibYaml) for
  fast YAML 1.2 parsing in Elixir.
  - `Zaml.load/1` parses a YAML binary and returns the corresponding Elixir term
    (maps, lists, integers, floats, booleans, `:nil`).
  - YAML 1.2 *core* schema scalar resolution for ints, floats, bools, and null.
  - Respects explicit `!!str` / `!!int` / `!!float` / `!!bool` / `!!null` tags.
  - Anchors and aliases (`&name` / `*name`).
  - Returns `:error` for non-binary input, `:parse_error` for malformed YAML,
    and `:nil` for an empty document.
- `mix zaml_nif.build` Mix task that auto-builds the NIF during `mix compile`
  and `mix test` (idempotent, dependency-aware).
- `mix zaml_nif.bench PATH` Mix task for head-to-head benchmarking against
  `fast_yaml`.
- `Makefile` driving the `zig build-lib` invocation directly, with
  `pkg-config`/Homebrew/`/usr` libyaml auto-detection.
- `mix.exs` auto-detects `libyaml` on common paths and exports
  `CFLAGS`/`CPPFLAGS`/`LDFLAGS` so rebar3-compiled deps (e.g. `fast_yaml` in
  the bench task) find it.
- ExUnit test suite covering basic scalars, nested maps and lists, explicit
  tags, anchors, empty input, and parse-error handling.
- Cross-language benchmark suite (`benchmark/`) comparing the NIF against
  `fast_yaml`, PyYAML, and `ruamel.yaml`.
- `benchmark/RESULTS.md` with the measured numbers on a 1M-line flat mapping
  and a 100k-key nested mapping.

### Notes

- Merge keys (`<<: *alias`) are not yet expanded.
- Multi-document input returns only the first document.

[0.1.0]: https://github.com/kubkon/zig-yaml/releases/tag/v0.1.0
