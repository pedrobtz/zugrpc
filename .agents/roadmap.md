# zugrpc: roadmap

Status: draft 2026-11-03. Implements [design.md](design.md).
Target: v0.1.0, the first CRAN release.
Tracking: [v0.1.0 (#1)](https://github.com/pedrobtz/zugrpc/issues/1), with one
sub-issue per stage;
[CRAN-submission (#11)](https://github.com/pedrobtz/zugrpc/issues/11).

The stages follow the design's own plan, moved here from its §13. Stages 0 to
5 keep the design's numbers. The design's Stage 6 (Full CI, README, release
preparation) becomes Stages 6 to 8, and the README moves to Stage 5. The
descriptor set moves from Stage 0 to Stage 3, the stage that first uses it.

## Stages

| Stage | Title | CI | Issue | Pull request | Done |
| --- | --- | --- | --- | --- | --- |
| 0 | [Package identity](#stage-0--package-identity) | quick | [#2](https://github.com/pedrobtz/zugrpc/issues/2) | [#13](https://github.com/pedrobtz/zugrpc/pull/13) | 2026-11-03 |
| 1 | [Framing](#stage-1--framing) | quick | [#3](https://github.com/pedrobtz/zugrpc/issues/3) | | |
| 2 | [Unary calls on recorded responses](#stage-2--unary-calls-on-recorded-responses) | quick | [#4](https://github.com/pedrobtz/zugrpc/issues/4) | | |
| 3 | [Status details and conditions](#stage-3--status-details-and-conditions) | quick | [#5](https://github.com/pedrobtz/zugrpc/issues/5) | | |
| 4 | [Live HTTP/2 and streaming](#stage-4--live-http2-and-streaming) | full | [#6](https://github.com/pedrobtz/zugrpc/issues/6) | | |
| 5 | [Spark, keepalive and performance](#stage-5--spark-keepalive-and-performance) | quick | [#7](https://github.com/pedrobtz/zugrpc/issues/7) | | |
| 6 | [Full CI](#stage-6--full-ci) | full | [#8](https://github.com/pedrobtz/zugrpc/issues/8) | | |
| 7 | [v0.1.0 readiness](#stage-7--v010-readiness) | full | [#9](https://github.com/pedrobtz/zugrpc/issues/9) | | |
| 8 | [Review](#stage-8--review) | full | [#10](https://github.com/pedrobtz/zugrpc/issues/10) | | |

## Stage 0 — Package identity

**Issue.** [#2](https://github.com/pedrobtz/zugrpc/issues/2), sub-issue of [v0.1.0](https://github.com/pedrobtz/zugrpc/issues/1).

**CI.** `quick`.

**Goal.** The empty package has its real identity and CI, and checks clean.

**Work.**

- `DESCRIPTION`: real Title and Description, `Authors@R` with `cre`, `aut`
  and `cph`, `Depends: R (>= 4.1)`, `Language: en-GB`, MIT licence,
  `Version: 0.0.0.9000`. `Imports` stay empty until a stage uses them.
- `.Rbuildignore` with every entry `CLAUDE.md`'s "Working with skills" lists.
- `R-CMD-check` caller with the `{"os": "windows-latest", "r": "devel"}`
  runner row.
- `CLAUDE.md` (written by `pkg-init`, 2026-11-03).

**Exit criteria.**

- `R CMD check` passes on the quick r-actions profile with 0 errors, 0
  warnings and 0 notes.
- Every check of the quick profile on the pull request finishes in under
  five minutes; what was tuned, if anything, is recorded here.
- The `R-CMD-check` caller lists the Windows R-devel runner.

**Design.** [§3](design.md#3-position-in-the-zu-family), [§12](design.md#12-build-and-cran).

## Stage 1 — Framing

**Issue.** [#3](https://github.com/pedrobtz/zugrpc/issues/3), sub-issue of [v0.1.0](https://github.com/pedrobtz/zugrpc/issues/1).

**CI.** `quick`.

**Goal.** Every pure function of the wire protocol exists and is tested
against byte-exact fixtures, with no network and no dependency on `zuhttp`.

**Work.**

- `R/frame.R`: message prefix encode and split, gRPC request headers,
  metadata validation and `-bin` base64, `grpc-timeout`, `grpc-message`
  percent-decoding.
- `R/status.R`: the code table, `grpc_status_codes()`, the HTTP-status
  fallback map.
- Tests for each, as the design's framing fixtures list.

**Exit criteria.**

- Every framing and status fixture of design §10 passes on the quick profile.
- A message split across chunk boundaries at every offset reassembles
  byte-for-byte.
- `grpc_status_codes()` is exported and documented and returns 17 rows.

**Design.** [§4](design.md#4-architecture) item 1,
[§6.2](design.md#62-request-and-response-framing) to
[§6.5](design.md#65-status-and-status-details) (the parts that need no I/O),
[§10](design.md#10-testing).

## Stage 2 — Unary calls on recorded responses

**Issue.** [#4](https://github.com/pedrobtz/zugrpc/issues/4), sub-issue of [v0.1.0](https://github.com/pedrobtz/zugrpc/issues/1).

**CI.** `quick`.

**Goal.** `grpc_channel()` and `grpc_call()` work end to end against
recorded responses replayed through `zuhttp`'s mock transport.

**Work.**

- `grpc_channel()`, `grpc_close()`, the channel's `print()` method.
- `grpc_call()`: request building, memory sink, response through the framing
  layer, Trailers-Only, HTTP-status fallback, content-type check.
- `zuhttp` in `Imports`, with `Remotes:` while it is not on CRAN.
- Recorded unary responses from the Go server, in a fixture format this
  stage chooses, and the hostile inputs of design §10 that a unary call can
  meet.

**Exit criteria.**

- Recorded unary, Trailers-Only and every-status-code responses give the
  result or condition design §6.2 to §6.5 prescribes, on the quick profile.
- Two messages on a unary call, a declared length above `max_message`, a
  compressed flag with no encoding and `text/html` with status 200 each raise
  their stated class.

**Design.** [§4](design.md#4-architecture) item 3,
[§5](design.md#5-public-r-api-v010-shape),
[§6.1](design.md#61-channels) to [§6.4](design.md#64-metadata),
[§10](design.md#10-testing).

## Stage 3 — Status details and conditions

**Issue.** [#5](https://github.com/pedrobtz/zugrpc/issues/5), sub-issue of [v0.1.0](https://github.com/pedrobtz/zugrpc/issues/1).

**CI.** `quick`.

**Goal.** A failed call raises the full condition hierarchy, with
`google.rpc.Status` and its `ErrorInfo` decoded.

**Work.**

- `tools/gen-descriptors.sh` and `inst/descriptors/google-rpc.binpb` from
  pinned googleapis protos, with its SHA-256; `inst/COPYRIGHTS` with the
  Apache-2.0 notice.
- `zuproto` in `Imports`, with `Remotes:` while it is not on CRAN.
- `grpc-status-details-bin` decoding, `Any` unpacking for the ten
  `error_details.proto` types, and the condition constructors.

**Exit criteria.**

- A recorded Spark-style `Status` with `ErrorInfo` yields
  `zugrpc_error_status` whose `details` holds `reason`, `domain` and
  `metadata`.
- Every class in design §9's table is raised by at least one test, and each
  status carries its `zugrpc_error_<code>` class.
- A details trailer that is not base64, or not a `Status`, gives a warning
  and keeps the status.

**Design.** [§6.5](design.md#65-status-and-status-details),
[§9](design.md#9-errors), [§12](design.md#12-build-and-cran).

## Stage 4 — Live HTTP/2 and streaming

**Issue.** [#6](https://github.com/pedrobtz/zugrpc/issues/6), sub-issue of [v0.1.0](https://github.com/pedrobtz/zugrpc/issues/1).

**CI.** `full — first real HTTP/2 through zuhttp: TLS with ALPN h2 on every
platform leg, and stream lifetimes with the pool.`

**Goal.** zugrpc talks to a real gRPC server over h2c and TLS, streams with
back pressure, and honours deadlines, cancellation and interrupts.

**Work.**

- `grpc_stream()` and the `zugrpc_stream` iterator on `zuhttp`'s pull body.
- Deadlines, `$cancel()`, interrupts, the finaliser, `grpc_close()` with open
  streams.
- The live-server tests behind `ZUGRPC_TEST_SERVER`, against `grpc-go`'s
  interop server built from a pinned tag.
- `Remotes:` on the `zuhttp` branch that carries HTTP/2.

**Exit criteria.**

- Every behaviour of design §6.6 passes against the live interop server on
  the Ubuntu legs, and against recorded responses everywhere.
- A server that sends headers and then stalls raises `DEADLINE_EXCEEDED` at
  the deadline; `$cancel()` returns within 100 ms.
- TLS with ALPN `h2` works on all three platforms, and an `http/1.1`
  negotiation raises `zugrpc_error_transport`.
- The lifetime tests of design §10 pass: dropped stream, close with open
  streams, interrupt, channel after `readRDS()`.

**Design.** [§4](design.md#4-architecture),
[§6.1](design.md#61-channels), [§6.3](design.md#63-messages-and-limits),
[§6.6](design.md#66-deadlines-cancellation-and-interrupts),
[§7.2](design.md#72-the-request-item-by-item), [§10](design.md#10-testing).

## Stage 5 — Spark, keepalive and performance

**Issue.** [#7](https://github.com/pedrobtz/zugrpc/issues/7), sub-issue of [v0.1.0](https://github.com/pedrobtz/zugrpc/issues/1).

**CI.** `quick`.

**Goal.** zugrpc carries a real Spark Connect workload, and its performance
is measured and published.

**Work.**

- The `apache/spark` 4.2.1 test: one `ExecutePlan` that streams and ends
  `OK`, one invalid plan with Spark's `ErrorInfo`.
- Keepalive settings passed through the channel.
- Benchmarks for design §11's four targets, and an article recording them.
- `README.Rmd`, written with `pkg-readme`; the Get started article made
  runnable.

**Exit criteria.**

- The Spark test passes on the Ubuntu legs, and its error carries
  `errorClass` and `sqlState` in `details`.
- The performance article reports a measurement for each §11 target.
- The Get started article evaluates its chunks and builds on pkgdown.

**Design.** [§6.1](design.md#61-channels), [§6.5](design.md#65-status-and-status-details),
[§11](design.md#11-performance-targets), [§14](design.md#14-acceptance-criteria-for-v010).

## Stage 6 — Full CI

**Issue.** [#8](https://github.com/pedrobtz/zugrpc/issues/8), sub-issue of [v0.1.0](https://github.com/pedrobtz/zugrpc/issues/1).

**CI.** `full`, always.

**Goal.** The full r-actions profile is green on the code Stages 1 to 5
merged. No new features.

**Work.**

- Run the full profile (`full-ci` label) and fix what it finds: every
  platform leg, the containers, `nosuggests`, `nold`, cran-special and any
  failures recorded on this stage's issue.

**Exit criteria.**

- A full-profile run is green on the pull request and on its merge commit.

**Design.** [§14](design.md#14-acceptance-criteria-for-v010).

## Stage 7 — v0.1.0 readiness

**Issue.** [#9](https://github.com/pedrobtz/zugrpc/issues/9), sub-issue of [v0.1.0](https://github.com/pedrobtz/zugrpc/issues/1).

**CI.** `full`, always.

**Goal.** The package is a release candidate that installs from CRAN
dependencies only.

**Work.**

- `Version: 0.1.0` and the matching `NEWS.md` heading.
- `Remotes:` removed, with `Imports` floors on the CRAN versions of `zuhttp`
  (the HTTP/2 minor) and `zuproto` (0.1.0).
- `cran-comments.md` listing the r-actions CI legs as test environments.
- `urlchecker::url_check()` and `spelling::spell_check_package()` clean.

**Exit criteria.**

- `DESCRIPTION` has no `Remotes:`, and its floors are versions on CRAN.
- A full-profile run is green on the merge commit.

**Design.** [§12](design.md#12-build-and-cran),
[§14](design.md#14-acceptance-criteria-for-v010).

## Stage 8 — Review

**Issue.** [#10](https://github.com/pedrobtz/zugrpc/issues/10), sub-issue of [v0.1.0](https://github.com/pedrobtz/zugrpc/issues/1).

**CI.** `full`, always.

**Goal.** The release candidate is reviewed and every blocking finding is
fixed. No new features. Only submission is left when it closes.

**Work.**

1. `pkg-critical-review` (code, tests and style). Blocking and required
   findings become sub-issues of this stage's issue, each fixed in a pull
   request that closes it.
2. `pkg-cran-review`, after those fixes, with every FAIL and WARN resolved.

**Exit criteria.**

- Every blocking and required review issue is closed.
- The `pkg-cran-review` table is clean.
- `NEWS.md` reflects any user-visible fix.
- A full-profile run is green on the default branch, whose head becomes the
  release commit.

**Design.** [§14](design.md#14-acceptance-criteria-for-v010).

## After 0.1.0

- [§16](design.md#16-later-versions-in-the-order-they-are-expected): gzip,
  client and bidirectional streaming, retries, server reflection, Connect and
  gRPC-Web. Each needs a later `zuhttp` or `zukomp` feature, or is not needed
  by `zuspark`.

## Blocking open questions

- [§17](design.md#17-open-questions) Q1 blocks Stage 4 and Stage 7: which
  `zuhttp` minor carries HTTP/2, and when it reaches CRAN (D3).
- [§17](design.md#17-open-questions) Q2 blocks Stage 4: pull or callback for
  the streaming body. A callback turns `grpc_stream()` into `each =` (D6).
- [§17](design.md#17-open-questions) Q3 should be settled before Stage 4:
  whether `$next_message()` takes its own timeout.
- [§17](design.md#17-open-questions) Q4 should be settled before Stage 2:
  whether `grpc_channel()` accepts a caller's `zu_client()`.
- [§10](design.md#10-testing) blocks Stage 2: replaying recorded responses
  needs `zuhttp`'s mock transport to carry trailers, and
  `zu_resp_trailers()` (§7.2, item 2). Stages 0 and 1 need nothing from
  `zuhttp`.
- [§10](design.md#10-testing) blocks Stage 4: the live tests run a gRPC
  server in Docker, but `r-cmd-check.yml` has no input for a service
  container. Either r-actions gains one, or the design records a caller
  workflow for the live tests. Not yet in the design's open questions.
