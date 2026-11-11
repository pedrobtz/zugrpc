# Assurance

How this package meets `.claude/shared/assurance.md`. CI checks this
file (r-actions `assurance.yml`), so keep the headings and table
columns as they are.

- **Statuses:** a cell is a fact, `gap #<issue>` or `n/a: <reason>`.
- **Paths:** test files are under `tests/testthat/`.
- **Live:** `test-live.R` and `test-spark.R` run only in `live.yaml`,
  against grpc-go's interop server at v1.67.1, `tools/test-server`
  (the same grpc-go) and Spark Connect 4.2.1.

## Kinds

`untrusted-input` `spec` `lifecycle` `emits`

## Required checks

`Where` names the workflow file under `.github/workflows/` that runs the
check. Add `(own)` when that workflow is the package's own rather than a
call to r-actions.

| Check      | Status | Where |
| ---------- | ------ | ----- |
| fuzz       | gap #59 |       |
| fuzz-reach | gap #60 |       |

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
| `grpc-timeout`, as the server read it                       | gap #61                                                                                                                   | gap #61                                               |
| Request headers under a hostile session                     | gap #62                                                                                                                   | gap #62                                               |
| Metadata, encoding (ASCII and `-bin` base64)                | RFC 4648 §10 vectors; round trip of every byte at every length mod 3; grpc-go live echoes initial and `-bin` trailing metadata | test-metadata.R, test-call.R, test-live.R          |
| Metadata, decoding                                         | recorded and live grpc-go echoes; padded and unpadded base64 give the same bytes                                          | test-metadata.R, test-call.R, test-live.R            |
| Metadata, a repeated header against one comma-joined value  | gap #63                                                                                                                   | gap #63                                               |
| Call status (`grpc-status`, Trailers-Only, HTTP fallback)   | recorded grpc-go responses for codes 1 to 16; every code live; HTTP map from the specification's table                   | test-call.R, test-status.R, test-stream.R, test-live.R |
| Call status, unary against stream on the same response      | gap #64                                                                                                                   | gap #64                                               |
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
| `zugrpc_channel` (two zuhttp clients on one pool, and the registry of open responses) | test-channel.R, test-stream.R, test-live.R: close twice, call after close, close with open streams, readRDS() then call                    | gap #65 | test-stream.R: an interrupt inside zuhttp leaves the channel usable; it holds no native state of its own    | test-channel.R, test-stream.R: its pool is never the caller's client's or another channel's; only grpc_close() resets it (spy)   |
| `zugrpc_stream` (a pulled zuhttp response)                  | test-stream.R, test-live.R: read past the end, cancel twice, cancel then read, close then read, deadline then read, failure then read, interrupt then read; after readRDS(): gap #66 | gap #65 | test-stream.R: a failure while opening aborts and unregisters; a dropped stream's finaliser aborts it    | test-stream.R: the channel's registry holds the response; cancel, close, failure or the finaliser aborts it once (spy) |
| `google.rpc` descriptor pool, cached for the session         | n/a: built once from the bundled file and only read after                                                                                                | n/a: read-only, so a child's copy is the parent's | n/a: assigned only after zuproto returns it                                              | n/a: the package namespace holds it for the session                                                                   |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

<!-- markdownlint-disable MD013 -->
| Limit                                                      | Unit                                                                                     | Straddled by                                         |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `max_message`                                              | message bytes, prefix excluded; on unary calls zuhttp's `max_body` is `max_message + 5`, whole-body bytes | gap #67                                |
| `max_message` argument, 0 to 4294967295                    | bytes                                                                                    | gap #68                                               |
| request message, at most 4294967295                        | message bytes                                                                            | gap #69                                               |
| `grpc-timeout`, eight digits per unit                      | digits of the TimeoutValue                                                               | gap #70                                               |
| `grpc-timeout` cap, `99999999H`                            | hours                                                                                    | gap #70                                               |
| local request timeout floor, 1 ms                          | seconds                                                                                  | gap #71                                               |
| `grpc-status`, at most nine digits                         | digits                                                                                   | gap #72                                               |
| status codes 0 to 16                                       | code                                                                                     | test-status.R: every code 0 to 16, then 17 is UNKNOWN |
| stream read size, 64 KiB to 16 MiB                         | wire bytes per read                                                                      | gap #73                                               |
| non-gRPC body kept in the condition, 1 KiB                 | body bytes                                                                               | gap #74                                               |
<!-- markdownlint-enable MD013 -->
