# Changelog

All notable changes to `zaml` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Performance.** Maps are now built with a single
  [`enif_make_map_from_arrays`](https://www.erlang.org/doc/man/erl_nif.html)
  call per map instead of a per-pair `enif_make_map_put`, eliminating the
  O(n^2) rehashing on wide maps. String scalars are now returned as
  sub-binaries of the input (`enif_make_sub_binary`) rather than copied
  into freshly allocated binaries, so the parse no longer re-copies every
  string value. Combined these take the 100k-key nested benchmark from
  ~0.65 s to ~0.53 s and the 1M-key flat benchmark from ~0.85 s to ~0.63 s,
  widening the lead over `fast_yaml` to ~3.5–4.6×.

  The sub-binary path is guarded: we only sub-binary when the scalar
  pointer provably lies inside the input buffer, falling back to a copy
  otherwise, so the change stays correct across libyaml versions that may
  write quoted/block/folded scalars into their own buffer.

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
- NIF is compiled at `mix compile` via [`elixir_make`](https://hex.pm/packages/elixir_make)
  and the project `Makefile` (also invokable as Mix task `ZamlNif.Build`).
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
