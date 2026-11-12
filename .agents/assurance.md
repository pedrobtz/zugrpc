# Assurance

How this package meets `.claude/shared/assurance.md`. CI checks this
file (r-actions `assurance.yml`), so keep the headings and table
columns as they are.

- **Statuses:** a cell is a fact, `gap #<issue>` or `n/a: <reason>`.
- **Paths:** test files are under `tests/testthat/`.
- **Live:** `test-live.R` and `test-spark.R` run only in `live.yaml`,
  against grpc-go's interop server at v1.67.1, `tools/test-server`
  (the same grpc-go) and Spark Connect 4.2.1.
- **Fuzzing:** `fuzz.yaml` runs `tools/fuzz/fuzz.R`, whose six targets
  each check an oracle, and `tools/fuzz/reach.R`, which holds each parser's
  covr reach to a floor. r-actions' `fuzz.yml` is libFuzzer over C, which
  zugrpc does not have (D1).

## Kinds

`untrusted-input` `spec` `lifecycle` `emits`

## Required checks

`Where` names the workflow file under `.github/workflows/` that runs the
check. Add `(own)` when that workflow is the package's own rather than a
call to r-actions.

| Check      | Status | Where           |
| ---------- | ------ | --------------- |
| fuzz       | done   | fuzz.yaml (own) |
| fuzz-reach | done   | fuzz.yaml (own) |

## Boundaries

One row per boundary the package crosses. An oracle knows the answer:

- a conformance suite or test vectors;
- a reference implementation;
- a round trip;
- equivalent inputs compared;
- the bytes the other side received.

"No crash" is not an oracle.

<!-- markdownlint-disable MD013 -->
| Boundary                                                   | Oracle                                                                                                                   | Carried by                                           |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| Length-prefixed message, decoding, unary                   | responses recorded from grpc-go v1.67.1, replayed; grpc-go live                                                          | test-call.R, test-live.R                             |
| Length-prefixed message, decoding, stream                  | recorded grpc-go streams; one body split at every offset gives the same messages; grpc-go and Spark Connect 4.2.1 live   | test-stream.R, test-frame.R, test-live.R, test-spark.R |
| Length-prefixed message, encoding                          | request bodies built by hand in tools/record-fixtures.R, compared byte for byte; grpc-go live returns the payload sizes asked for | test-frame.R, test-call.R, test-stream.R, test-live.R |
| Request headers (`te`, `content-type`, `user-agent`)        | grpc-go accepts them live; the specification's literal values asserted on the request zuhttp was given                                         | test-call.R, test-live.R                             |
| `grpc-timeout`, encoding                                   | values worked by hand from PROTOCOL-HTTP2.md's TimeoutValue and TimeoutUnit, at every unit and each eight-digit edge     | test-timeout.R                                       |
| `grpc-timeout`, as the server read it | tools/test-server's Deadline method returns grpc-go's own decoding; within one unit step, at every unit | test-live.R |
| Request headers under a hostile session | the same requests built under `OutDec`, `scipen`, `digits`, C collation and ctype, and another time zone equal the default | test-call.R |
| Metadata, encoding (ASCII and `-bin` base64)                | RFC 4648 §10 vectors; round trip of every byte at every length mod 3; grpc-go live echoes initial and `-bin` trailing metadata | test-metadata.R, test-call.R, test-live.R          |
| Metadata, decoding                                         | recorded and live grpc-go echoes; padded and unpadded base64 give the same bytes                                          | test-metadata.R, test-call.R, test-live.R            |
| Metadata, a repeated header against one comma-joined value | a repeated received field and a comma-joined one give the same lists, through a call and a stream | test-metadata.R |
| Call status (`grpc-status`, Trailers-Only, HTTP fallback)   | recorded grpc-go responses for codes 1 to 16; every code live; HTTP map from the specification's table                   | test-call.R, test-status.R, test-stream.R, test-live.R |
| Call status, unary against stream on the same response | hand-built responses and every recorded grpc-go unary fixture end the same way on both paths | test-stream.R |
| `grpc-message`, percent-decoding                            | grpc-go encodes `café 100%`, recorded and live                                                                            | test-status.R, test-call.R, test-live.R              |
| `google.rpc.Status` details, decoding                       | trailers recorded from tools/test-server, written by grpc-go's status package; the same live                             | test-details.R, test-live.R                          |
| Bundled `google.rpc` descriptor set                         | SHA-256 recorded when tools/gen-descriptors.sh built it                                                                  | test-details.R                                       |
<!-- markdownlint-enable MD013 -->

## Objects

One row per object that outlives the call that made it. "Sequences" is
the test of its out-of-order use (abort then read, use after end, use
after free). The guard columns name the test, or say why the guard
cannot apply.

<!-- markdownlint-disable MD013 -->
| Object                                                      | Sequences                                                                                                                                                 | Fork   | Unwind                                                                                                     | Owner                                                                                                                  |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `zugrpc_channel` (two zuhttp clients on one pool, and the registry of open responses) | test-channel.R, test-stream.R, test-live.R: close twice, call after close, close with open streams, readRDS() then call                    | test-live.R: a forked child calls on its own connection; the parent's calls are untouched | test-stream.R: an interrupt inside zuhttp leaves the channel usable; it holds no native state of its own    | test-channel.R, test-stream.R: its pool is never the caller's client's or another channel's; only grpc_close() resets it (spy)   |
| `zugrpc_stream` (a pulled zuhttp response)                  | test-stream.R, test-live.R: read past the end, cancel twice, cancel then read, close then read, deadline then read, failure then read, interrupt then read; after readRDS(), the same error on every read (test-live.R) | test-live.R: a forked child cannot read the parent's stream, which reads on to OK | test-stream.R: a failure while opening aborts and unregisters; a dropped stream's finaliser aborts it    | test-stream.R: the channel's registry holds the response; cancel, close, failure or the finaliser aborts it once (spy) |
| `google.rpc` descriptor pool, cached for the session         | n/a: built once from the bundled file and only read after                                                                                                | n/a: read-only, so a child's copy is the parent's | n/a: assigned only after zuproto returns it                                              | n/a: the package namespace holds it for the session                                                                   |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

<!-- markdownlint-disable MD013 -->
| Limit                                                      | Unit                                                                                     | Straddled by                                         |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `max_message` | message bytes, prefix excluded; on unary calls zuhttp's `max_body` is `max_message + 5`, whole-body bytes | test-frame.R, test-call.R, test-stream.R; live in test-live.R, unary and stream, and `max_message = 0` |
| `max_message` argument, 0 to 4294967295 | bytes | test-channel.R: 0, 1, 4294967294, 4294967295, and the values refused around them |
| request message, at most 4294967295 | message bytes | test-frame.R: `frame_prefix()` at 4294967294, 4294967295 and 4294967296 |
| `grpc-timeout`, eight digits per unit | digits of the TimeoutValue | test-timeout.R: all five unit edges at limit - 1, limit and limit + 1 |
| `grpc-timeout` cap, `99999999H` | hours | test-timeout.R: 99999998H, then the cap less a second, exactly and a second over |
| local request timeout floor, 1 ms | seconds | test-call.R: 0.9, 1 and 1.1 ms |
| `grpc-status`, at most nine digits | digits | test-call.R: nine and ten digits, with sign, space and exponent |
| status codes 0 to 16                                       | code                                                                                     | test-status.R: every code 0 to 16, then 17 is UNKNOWN |
| stream read size, 64 KiB to 16 MiB | wire bytes per read | test-stream.R: 64 KiB - 1, 16 MiB - 1, 16 MiB, 16 MiB + 1 |
| non-gRPC body kept in the condition, 1 KiB | body bytes | test-call.R and test-stream.R: 1023, 1024 and 1025 bytes |
<!-- markdownlint-enable MD013 -->
