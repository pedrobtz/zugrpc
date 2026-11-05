# RFC 0069: `zugrpc`, a gRPC client on zuhttp's HTTP/2

Adopted from [RFC 0069](https://github.com/pedrobtz/packages/blob/cde89a11e54efb58857d19b2fbc148ad141cf6e7/rfcs/not-started/0069-zugrpc-grpc-client-on-zuhttp-http2.md)
on 2026-11-03. This file is the single source of truth for the design; the
RFC is now a pointer here.

- **Status:** Proposed. Merging this file adopts the design as the starting
  point for the package's own `.agents/design.md`; each decision in
  section 15 stays the maintainer's until the package repository records
  it. D1, which puts HTTP/2 into `zuhttp` and makes `zugrpc` a pure R
  protocol layer, is the one most worth a second look: it makes this
  package small and its release date `zuhttp`'s.
- **Date:** 2026-11-03.
- **Packages:** `zugrpc` (not yet created; crandb returns `not_found` and
  there is no `pedrobtz/zugrpc` repository, both checked on 2026-11-03).
  Pure R: no `src/`, no `LinkingTo`. `Imports: zuhttp (>= the minor that
  carries HTTP/2), zuproto`. `Suggests: testthat (>= 3.2.0), withr`.
  Ships a descriptor set built from googleapis' `google/rpc`
  (Apache-2.0) under `inst/descriptors/`. MIT.
- **Source:** the discussion of 2026-11-03 that agreed this design and
  RFC 0070 (`zuspark`), and the maintainer's decision later that day to
  vendor nghttp2 in `zuhttp` rather than here; zuproto's and zuhttp's
  design documents and zuhttp's roadmap, cited by section below;
  `rfcs/more-candidates.md` §5; nghttp2 at tag `v1.71.0`, downloaded
  and read (§7.1); the gRPC, googleapis and Spark sources of §19;
  crandb and `tools::CRAN_package_db()` for §1.2. Nothing has been
  built.

## 1. What zugrpc is

`zugrpc` speaks the gRPC wire protocol over HTTP/2 requests that
`zuhttp` makes. A call names a method such as
`/spark.connect.SparkConnectService/ExecutePlan`, sends one encoded
request message, and returns either one response message with its
headers and trailers (unary) or an iterator that yields response
messages as they arrive (server streaming). The caller encodes and
decodes messages with `zuproto`; `zugrpc` never looks inside them
except to decode `google.rpc.Status` when a call fails.

> **A protocol, not a transport: the five-byte prefix, the gRPC
> headers, trailers and status, in R, on top of zuhttp's HTTP/2.**

### 1.1 What zugrpc is not

- Not a protobuf library. zuproto's design §2 lists "a gRPC client"
  under *Never*, "that is a transport, not a format"; this RFC is the
  layer above zuproto, with no descriptor pool and no generated stubs.
- Not an HTTP client and not an HTTP/2 implementation. Every socket,
  TLS handshake, frame and HPACK table is `zuhttp`'s (§7). `zugrpc`
  has no C code at all (D1).
- Not a server. No listening socket, no service registration.
- Not gRPC-Web or Connect. Both are HTTP/1.1-compatible variants
  (§6.7); Spark Connect speaks neither, and v0.1.0 follows Spark.

### 1.2 Where it sits among CRAN packages

Checked on crandb and `tools::CRAN_package_db()` (25,626 packages) on
2026-11-03. The names `zugrpc`, `grpc`, `GRPC` and `grpcr` are
`not_found`. One package mentions gRPC in its title or description.

- **`rgrpc`** 0.1.2 (2026-10-02, Apache-2.0, cornball.ai) is an
  asynchronous client and server runtime over gRPC's C++ `GenericStub`
  and `AsyncGenericService`, with `RProtoBuf` supplying the bytes. It
  links the system gRPC C++ and protobuf libraries through `pkg-config
  grpc++ protobuf` ("bundled with Rtools 4.3 and later" on Windows) and
  "without them the package installs as a stub whose functions error".
  CRAN's macOS flavours show that stub (a 2-second install), so a CRAN
  binary user on macOS gets no working function. It is the right
  choice for someone with gRPC C++ installed who also needs a server.
- **`curl`** 8.1.0 and **`httr2`** 1.3.0 reach HTTP/2 through libcurl
  (`curl_options()` lists `http_version`; value 5 is prior knowledge),
  but the R package appends every header-callback chunk to one buffer
  (`src/handle.c`, `CURLOPT_HEADERFUNCTION` set to `append_buffer`),
  no accessor separates trailers from headers, and a streaming
  response cannot be cancelled with `RST_STREAM` from R.
- **`arrow`** 26.0.0 exports `flight_connect()` and friends, which are
  `reticulate` calls into `pyarrow.flight` (`r/R/flight.R`); the R
  package carries no Flight or gRPC native code.
- Nothing else. No package binds nghttp2, nghttp3 or an HTTP/2 client.

So the opening is narrow and real: a gRPC client whose CRAN binary
works on every platform, with no system gRPC, protobuf or libcurl, that
exposes trailers, deadlines, cancellation and streaming to R.

### 1.3 The admission test

Of `base-layer-candidates.md` §2's four tests: a specification with
references passes (`PROTOCOL-HTTP2.md`, `statuscodes.md`, and the Go,
Java and C-core implementations behind every Spark client); vendorable
code is moot, since the package is R on top of `zuhttp`; a weakness in
base R passes (no HTTP/2, no gRPC). The consumer test passes once,
honestly: `zuspark` (RFC 0070) needs exactly this and nothing else in
the family provides it. The prospects beyond it are a client for any
gRPC or Connect API, and zuproto's design §2, which lists "gRPC server
reflection as a descriptor source" as later work that `zugrpc` would
make possible.

## 2. Scope

**In v0.1.0:**

- A channel: a `zuhttp` client configured for HTTP/2, cleartext with
  prior knowledge (h2c) for local servers or TLS with ALPN `h2` (§6.1).
- Unary and server-streaming calls with the gRPC framing of §6.2:
  length-prefixed messages, `content-type: application/grpc+proto`,
  `te: trailers`, `grpc-timeout`, `grpc-encoding: identity`.
- Metadata in both directions, ASCII and `-bin` (§6.4).
- Status from trailers and Trailers-Only responses, `grpc-message`
  percent-decoding, and `grpc-status-details-bin` decoded to
  `google.rpc.Status` with its `ErrorInfo` details (§6.5, §9).
- Deadlines, cancellation and interrupts (§6.6).
- A pull iterator for streaming responses, so `zuspark` can read Arrow
  batches as they arrive without holding the whole response.
- `zugrpc_info()`: the `zuhttp` version, whether it offers HTTP/2, and
  the TLS backend it reports. *Added in Stage 4 (2026-11-05), which no
  stage listed it in.*

**Later, in the order expected** (§16): `grpc-encoding: gzip` through
`zukomp`; client-streaming and bidirectional calls once `zuhttp` has
streaming request bodies; retries from `RetryInfo`; server reflection
for zuproto; Connect and gRPC-Web over HTTP/1.1.

## 3. Position in the `zu*` family

| | zugrpc |
| --- | --- |
| Role | protocol, on a transport |
| R prefix | `grpc_` |
| Info function | `zugrpc_info()` |
| Root condition class | `zugrpc_error` |
| Public C prefix | none; no C code (D1) |
| From C | no |
| Hides symbols | not applicable |
| Vendored code | none; `google/rpc` descriptors in `inst/` |
| `Depends: R` | 4.1 (R2) |
| Language | en-GB (R2) |

**Relationships:**

- **`zuspark`** (RFC 0070): the consumer this package exists for.
  `ExecutePlan` and `ReattachExecute` are server-streaming,
  `AnalyzePlan`, `Config`, `FetchErrorDetails` and the rest are unary,
  and `AddArtifacts` is client-streaming, which is why §16 lists it
  first among the later call types.
- **`zuhttp`** (started; 0.1.0 "ready to submit" on 2026-10-30, not on
  CRAN): the transport, in `Imports`. Its design §60 keeps HTTP/2 out
  and §30.3 lists multiplexing as "not planned"; §7 is the request to
  change that after 1.0.
- **`zuproto`** (RFC 0010, started): `Imports`, from R (D4), to decode
  `google.rpc.Status` through `proto_pool()`, `proto_decode()` and
  `proto_unpack_any()` against the bundled descriptors. zuproto's §10
  calls "gRPC's 5-byte prefix" a later option; `zugrpc` owns it.
- **`zukomp`** (0.1.0 on CRAN): `grpc-encoding: gzip`, later (§16).
- **`zumail`** (`more-candidates.md` §5) and **`zusocks`** (RFC 0033)
  wanted a TLS stream out of `zuhttp`; the HTTP/2 work of §7 does not
  serve them, and this RFC does not claim it does.

## 4. Architecture

Three R files, each one job, and nothing below them but `zuhttp`.

1. **Framing** (`R/frame.R`): pure functions over raw vectors. Encode a
   message as flag, four-byte big-endian length and bytes; split a
   buffer into complete messages and a remainder; build and parse the
   gRPC headers of §6.2; base64 for `-bin` metadata; the `grpc-timeout`
   value; percent-decoding of `grpc-message`. No I/O, so every
   behaviour is tested against fixtures on every platform.
2. **Status** (`R/status.R`): the code table, the HTTP-status fallback
   map, `google.rpc.Status` decoding through zuproto, and the
   condition constructors of §9.
3. **Calls** (`R/call.R`, `R/stream.R`): `grpc_call()` builds a
   `zu_request()`, performs it on the channel's client with a memory
   sink, and hands body, headers and trailers to the framing layer.
   `grpc_stream()` performs it with `zuhttp`'s pull-based body (§7.2,
   item 3) and wraps it in an iterator that splits messages out of the
   chunks it pulls, asking for more only when no complete message is
   buffered, which is what gives the server back pressure.

A channel is an environment of class `zugrpc_channel` holding a
`zu_client()`, the authority, channel headers and keepalive settings;
it survives `saveRDS()` because `zuhttp` rebuilds native resources
lazily (§29.3). A stream is an environment of class `zugrpc_stream`
holding the open response and its buffer.

## 5. Public R API (v0.1.0 shape)

```r
# channels
ch <- grpc_channel("http://localhost:15002")      # h2c, prior knowledge
ch <- grpc_channel("https://spark.example.org:443",
                   tls = zuhttp::zu_tls(ca_file = NULL),
                   headers = c(authorization = "Bearer ..."),
                   keepalive = grpc_keepalive(time = 60, timeout = 20),
                   max_message = 128 * 1024^2)
grpc_close(ch)

# unary
res <- grpc_call(ch, "/spark.connect.SparkConnectService/AnalyzePlan",
                 request = req_bytes,        # raw, from proto_encode()
                 metadata = c("x-user-agent" = "zuspark"),
                 deadline = 30)              # seconds, or a POSIXct
res$message      # raw: one response message
res$headers      # named list, initial metadata
res$trailers     # named list, trailing metadata
res$status       # "OK"

# server streaming
st <- grpc_stream(ch, "/spark.connect.SparkConnectService/ExecutePlan",
                  request = req_bytes, deadline = 600)
st$headers()                 # blocks until initial metadata arrives
while (!is.null(m <- st$next_message())) proto_decode(m, type, pool)
st$trailers(); st$status()   # available once next_message() is NULL
st$cancel()                  # aborts the request; idempotent

# diagnostics
zugrpc_info()
grpc_status_codes()          # the 17 codes as a data frame
```

`print()` on a channel shows the authority, h2c or TLS with the
negotiated protocol, and the number of open streams. `$next_message()`
returns `NULL` at end of stream and raises on a non-OK status.

*Decided 2026-11-05 (Stage 2):* `grpc_call()` returns a plain list, not an
S3 object, since its four fields need no accessors. `headers` and
`trailers` are named lists, not character vectors, because a `-bin` value
is raw in R (§6.4). They hold metadata only: `content-type`, `te`, the
pseudo-headers and every `grpc-` field are left out. Keepalive is Stage 5's
and is not yet an argument.

## 6. Semantics

### 6.1 Channels

`grpc_channel()` parses the URL for scheme, host and port and builds a
`zu_client()` with HTTP/2 required: `http://` is cleartext with prior
knowledge, `https://` negotiates ALPN `h2`. A connection whose
negotiated protocol is anything else is `zugrpc_error_transport`,
since gRPC has no HTTP/1.1 fallback. Connection reuse, window sizes,
SETTINGS, PING and GOAWAY are `zuhttp`'s (§7.2); the channel passes
`keepalive` through, with defaults of 60 seconds between PINGs and 20
to answer, as in Spark's Python client. A GOAWAY fails in-flight calls
with `UNAVAILABLE`; the next call opens a new connection.

*Decided 2026-11-05 (Stage 5):* `keepalive` takes `grpc_keepalive(time,
timeout)`, whose defaults are 60 and 20 seconds, and `NULL` turns it off.
It becomes zuhttp's `zu_pool(keepalive_time, keepalive_timeout)` (its
§65.6). The other pool settings of a caller's client are kept, and a
client with no pool is left as it is.

*Decided 2026-11-05 (Stage 2):* `grpc_channel()` takes `client =`, a
`zu_client()` the caller built (Q4). The channel derives its own client
from it with `zu_client_update()`, setting `http2 = "required"`,
`check = FALSE`, its user agent and `max_body = max_message + 5`, since
zuhttp's default of 16 MiB is below the 128 MiB message limit. Proxies, TLS
pins, middleware and transports come from zuhttp unchanged, which is also
how the recorded-response tests inject `zu_mock_transport()`. The URL must
be a bare origin, `http://host:port` or `https://host:port`. `grpc_close()`
resets the client's pool and marks the channel closed; a call on a closed
channel is `zugrpc_error_argument`.

*Decided 2026-11-05 (Review, #27):* the channel's client always gets a
pool of its own, even when its pool settings equal the caller's, so
`grpc_close()` never clears the caller's connections or another
channel's. The stream client shares the channel's pool.

### 6.2 Request and response framing

From `PROTOCOL-HTTP2.md`. The request is `POST` to the method path
with `te: trailers`, `content-type: application/grpc+proto`,
`user-agent: zugrpc/<ver> zuhttp/<ver>`, `grpc-timeout` when a deadline
is set, `grpc-accept-encoding: identity` in v0.1.0, then the caller's
metadata. The body is one length-prefixed message: one byte compressed
flag (0), four bytes big-endian length, the bytes.

The response is either headers, messages and trailers, or Trailers-Only:
one HEADERS block that ends the stream and carries `grpc-status`.
`zugrpc` reads `grpc-status` from the trailers (§7.2, item 2) first,
then from the headers when the body is empty and the trailers absent.
An HTTP status other than 200 with no `grpc-status` maps as the
specification says: 400 `INTERNAL`, 401 `UNAUTHENTICATED`, 403
`PERMISSION_DENIED`, 404 `UNIMPLEMENTED`, 429, 502, 503 and 504
`UNAVAILABLE`, else `UNKNOWN`; `http_status` keeps the number. A
`content-type` not starting with `application/grpc` is
`zugrpc_error_protocol` with the first 1 KiB of the body, the usual
symptom of a plain HTTP server.

*Decided 2026-11-05 (Stage 2):* the order is: a `grpc-status` in the
trailers; else, when the body is empty, one in the headers (Trailers-Only;
zuhttp reports its trailers as empty); else a non-200 HTTP status maps as
above; else a `content-type` that is not gRPC is the protocol error; else
the status is the missing-status `INTERNAL`. So a `grpc-status` beats the
HTTP status. A unary response with zero messages, like one with two, or
one that ends inside a message, is `zugrpc_error_protocol`.

### 6.3 Messages and limits

A message is complete when five bytes of prefix and the declared
length are present. A compressed flag of 1 with `grpc-encoding:
identity` or absent is a protocol error; with `gzip`, before §16
ships, it is `zugrpc_error_unimplemented`. A declared length above
`max_message` (default 128 MiB, Spark's
`grpc.max_receive_message_length`) fails the call with
`RESOURCE_EXHAUSTED` and aborts the request before more is read.

The unary path performs the request with a memory sink and splits the
body; two messages on a unary call is `zugrpc_error_protocol`. The
streaming path returns one message per `$next_message()`, pulling more
body only when the buffer holds no complete message; a partial message
is kept as one remainder and concatenated at most once.

*Decided 2026-11-05 (Stage 4):* the stream keeps the pieces it has read
in a list and joins them once the five-byte prefix says the message is
complete, so a 16 MiB message costs one join, not one per read. Each
read asks for the rest of the current message, at least 64 KiB and at
most 16 MiB. The prefix is checked as soon as it is complete, so a
length above `max_message` aborts the request after five bytes. A
stream uses a second client derived from the channel's with `max_body =
Inf`, since `max_message` bounds each message and a stream's total is
unbounded.

### 6.4 Metadata

Metadata is a named character vector. A name ending in `-bin` carries
a raw vector in R and base64 on the wire, without padding, accepting
padded or unpadded on receipt, as the specification requires (D9).
*Decided 2026-11-03 (Stage 1):* because a character vector cannot hold a
raw value, `metadata` also accepts a named list, whose `-bin` entries are
raw and whose other entries are single strings of printable ASCII.
Names may use only `0-9 a-z _ . -` after lower-casing.
Names are lower-cased on the way out; a name starting with `grpc-`
that is not one `zugrpc` sets is `zugrpc_error_argument`. `te`,
`content-type`, `grpc-timeout` and the pseudo-headers cannot be set
through `metadata`; `headers` on the channel go on every call, and
per-call metadata overrides a channel header of the same name.

*Decided 2026-11-05 (Review, #26, #36):* received metadata never decides
a call's outcome. A `-bin` value may join several with commas; each
becomes an entry of the same name, as a repeated header does. A value
that is not base64 is dropped with a `zugrpc_warning_metadata`. On the
way out, `host` and the connection-specific headers RFC 9113 §8.2.2
forbids (`connection`, `keep-alive`, `proxy-connection`,
`transfer-encoding`, `upgrade`) are `zugrpc_error_argument`, and a
caller's `user-agent` is sent before zugrpc's own. One rule decides the
reserved names in both directions.

### 6.5 Status and status details

`grpc-status` is an integer mapped to its name from `statuscodes.md`
(`OK` is 0, `CANCELLED` 1, `UNKNOWN` 2, up to `UNAUTHENTICATED` 16). A
missing `grpc-status` on a completed response is `INTERNAL` with the
message "missing grpc-status in trailers". `grpc-message` is
percent-decoded as UTF-8. *Decided 2026-11-03 (Stage 1):* a `grpc-status`
that is not a decimal integer is `INTERNAL`, as grpc-go treats it, and an
integer outside 0 to 16 is `UNKNOWN`. A malformed escape in `grpc-message`
stays as received, and a message that does not decode to valid UTF-8 is
kept undecoded, so decoding never hides the status.

`grpc-status-details-bin` is base64 of a serialised `google.rpc.Status`
(`code`, `message`, `repeated Any details`). `zugrpc` decodes it with
zuproto against its bundled `google/rpc` descriptors (`status.proto`,
`error_details.proto`, `code.proto`), unpacks each `Any` whose type is
one of the ten `error_details.proto` messages, and leaves others as
`list(type_url, value)`. Spark fills `ErrorInfo` with `reason` set to
the Java class name, `domain` `org.apache.spark`, and `metadata` keys
`classes` (a JSON array of class names), `sqlState`, `errorClass`,
`messageParameters`, `errorId` and optionally `stackTrace`
(`ErrorUtils.scala`); `zuspark` reads them from the condition's
`details` field and, with `errorId`, may call `FetchErrorDetails`.

*Decided 2026-11-05 (Stage 3):* `details` is the decoded `Status` as a list
of `code`, `message` and `details`. Its `details` are named by type: an
`error_details.proto` message by its short name, so Spark's is
`cnd$details$details$ErrorInfo`, and any other `Any` by its full type
name, left as `list(type_url, value)`. Enums decode as their names. A
trailer that is not base64, or does not decode as a `Status`, raises a
warning of class `zugrpc_warning_details` (and `zugrpc_warning`), keeping
the decoding error as `parent`; the status condition then has `details =
NULL`. The details trailer is read from wherever `grpc-status` was found.

### 6.6 Deadlines, cancellation and interrupts

`deadline` is seconds from now or an absolute `POSIXct`. It becomes a
`grpc-timeout` header and the request's `total` timeout (zuhttp §24), so
a dead server cannot hold a call: when `zuhttp` raises its timeout
condition, `zugrpc` aborts the request and raises `DEADLINE_EXCEEDED`
itself. *Decided 2026-11-03 (Stage 1):* the header uses the finest unit
whose value keeps to eight digits (the specification's `n`, `u`, `m`,
`S`, `M`, `H`), since that loses the least precision, rounded up so the
server never sees a shorter deadline than the caller set. A `connect` timeout on the channel
bounds the TCP and TLS handshake through the same `zu_timeout()`.

`$cancel()` aborts the request, which over HTTP/2 is
`RST_STREAM(CANCEL)` on that stream and nothing else (§7.2, item 4);
a second call is a no-op. An R interrupt during a blocking call is
caught by `zuhttp` at its poll checkpoint (§25.1, re-raised as
`zu_interrupted_error`); `zugrpc` aborts the request, keeps the
channel, and re-raises as `zugrpc_error_interrupt`. A stream abandoned
by its caller is cancelled by its finaliser. `grpc_close()` cancels
every open stream and closes the client.

*Decided 2026-11-05 (Stage 4):* `$next_message()` takes no timeout of its
own (Q3); the call deadline is the bound. A deadline already passed fails
with `DEADLINE_EXCEEDED` before anything is sent, since zuhttp refuses a
zero timeout. Otherwise the deadline is the request's `total` timeout and,
for a stream, is also checked against the clock before each read. zuhttp
bounds each wait in `zu_resp_read()` by that timeout afresh (its §65.4),
so a stream that stalls right after its headers fails at the deadline,
but one that stalls after `t` seconds fails at about `t + deadline`.
[zuhttp#173](https://github.com/pedrobtz/zuhttp/issues/173) asks for a
per-read timeout, which would make the deadline exact; nothing in the
API changes when it lands. `$cancel()` also drops messages already
buffered, and a later `$next_message()` raises `CANCELLED`. The channel
keeps the open zuhttp responses, not the stream objects, so a stream
nobody holds can still be collected; its finaliser aborts the response
and removes it. `grpc_close()` aborts every response it holds, and each
stream sees the closed channel at its next read. A stream object is a
list of the five closures of §5 with class `zugrpc_stream`.

*Decided 2026-11-05 (Review, #23, #35):* with no deadline the request's
local timeout is `Inf`, not zuhttp's 30-second default, and a positive
deadline under 1 ms is sent to zuhttp as 1 ms, since it reads 0 as its
default. A stream that fails other than by a status (transport,
protocol, local deadline) raises the same condition on every later
`$next_message()`; one that ends with a non-OK status raises it once and
then returns `NULL`, with `$status()` set. The finaliser's
`zu_resp_abort()` from GC is the same abort zuhttp's own finaliser makes
(`zuh_open_body_free()`), and it is registered before the response is.

### 6.7 What Spark cannot use

gRPC-Web (`PROTOCOL-WEB.md`) moves trailers into the body as a frame
flagged `0x80` so browsers can read them over HTTP/1.1; Connect
(`connectrpc.com/docs/protocol`) is a similar HTTP/1.1-friendly
protocol with `application/connect+proto` and a JSON form. Both would
run on `zuhttp` today, with no HTTP/2, and are a later version (§16).
Spark Connect's server is grpc-java over HTTP/2 and speaks only the
protocol of §6.2, which is why this RFC needs §7 first.

## 7. What zuhttp must add

This section was written as the issue to file against `pedrobtz/zuhttp`
and has been filed: zuhttp's design §65 and decisions D-89 to D-95
record it, milestone M4 (v1.1.0, tracker zuhttp#128) schedules it as
the first minor after 1.0, and work packages W20 (zuhttp#129), W21
(zuhttp#130) and W22 (zuhttp#131) carry items 1, 2 to 6, and 7 below.
From here on zuhttp's design is authoritative for the names and the
semantics; this section is the request as made on 2026-11-03.
zuhttp's roadmap defines 1.0 as "the version other packages may depend
on without reservation", and M1 to M3 are already full.

### 7.1 HTTP/2 through vendored nghttp2

zuhttp's design §60 accepts HTTP/2 only "if real R workloads benefit,
parallel HTTP/1.1 is insufficient, a small library exists, and the
size budget holds". gRPC is the workload: it is HTTP/2-only, and
`zuspark` is the R user. The small library is nghttp2.

**What nghttp2 is.** nghttp2 1.71.0 was released on 2026-11-02 (tag
`v1.71.0`); 1.70.0 on 2026-07-29. `COPYING` is the MIT licence,
copyright Tatsuhiro Tsujikawa and the nghttp2 contributors. The README
needs only a C99 compiler ("gcc 4.8 is known to be adequate"), and
`--enable-lib-only` leaves out the applications with their C++23 and
OpenSSL needs. `lib/` holds 26 `.c` and 26 `.h` files: 23,100 lines of
C, of which 4,980 are the generated Huffman table, 4,900 lines of
private headers, and the public `nghttp2.h` of 6,900 lines (240 KB)
plus `nghttp2ver.h.in`; `sfparse.c` and `sfparse.h` (MIT, 1,960
lines) are inside `lib/` and count above. `lib/Makefile.am` links
nothing; the only system calls are `clock_gettime()`,
`GetTickCount64()` or `time()` for the RST_STREAM rate limiter and
`htonl()`/`ntohl()`. It is transport-agnostic: the application feeds
`nghttp2_session_mem_recv2()` and drains `nghttp2_session_mem_send2()`,
the `send`/`recv` callbacks are optional, and the session never owns
a socket, which is the shape zuhttp's §9 `zuh_stream` vtable wants.

**Building it without CMake.** `src/Makevars` compiles `lib/*.c` with
the definitions the sources read:

| Definition | Effect |
| --- | --- |
| `NGHTTP2_STATICLIB` | `NGHTTP2_EXTERN` empty, so R3's flag hides them |
| `BUILDING_NGHTTP2` | what the CMake and automake builds define |
| `HAVE_CONFIG_H` undefined | skips `config.h` (52 guarded includes) |
| `HAVE_ARPA_INET_H`, `HAVE_NETINET_IN_H` | `htonl` on Unix |
| `HAVE_WINDOWS_H`, `HAVE_GETTICKCOUNT64` | on Windows |
| `HAVE_CLOCK_GETTIME`, `HAVE_DECL_CLOCK_MONOTONIC=1` | on Unix |
| `NDEBUG` | compiles out 127 `assert()` calls |

`nghttp2ver.h` comes from `nghttp2ver.h.in` by substituting
`@PACKAGE_VERSION@` with `1.71.0` and `@PACKAGE_VERSION_NUM@` with
`0x014700`, committed and checked by the vendor script. `DEBUGBUILD`
stays undefined, which empties `DEBUGF()` and `nghttp2_debug.c`'s
`vfprintf(stderr)`. Two things would trip `R CMD check`'s scan for
calls that write to `stderr` or terminate R, each a recorded patch:
`nghttp2_map.c` has a debugging function calling `fprintf(stderr, ...)`
outside any `DEBUGBUILD` guard (excluded only on `WIN32`), and
`nghttp2_session.c` calls `abort()` three times after `assert(0)` on
unreachable `switch` arms, replaceable by returning
`NGHTTP2_ERR_CALLBACK_FAILURE`. Its two `fprintf(stderr)` calls are
under `DEBUGBUILD`. There are no `#pragma` lines in `lib/`, no
`printf`, `puts`, `exit()` or `rand()`. The tarball's SHA-256 is in
the release's `checksums.txt`.

**Why not write HTTP/2 in zuhttp.** A client needs framing (RFC 9113
§4 to §6), the stream state machine, SETTINGS and flow control on
connection and stream, HPACK with its static table, dynamic table
eviction and Huffman coding (RFC 7541), and the conformance behaviour
h2spec checks. nghttp2's `lib/` is 18,200 lines without the Huffman
table; a minimal client would still be 5,000 to 7,000 lines, nearly
all where bugs are security bugs (HPACK under hostile input,
flow-control accounting), against zuhttp's §51.3 budget of 8,000
project-owned lines. nghttp2 has twelve years of fuzzing and sits
under curl, Apache httpd and Node. The recommendation is to vendor it
under zuhttp's §48 policy, as picohttpparser is.

### 7.2 The request, item by item

1. **HTTP/2 negotiation.** ALPN offering `h2` and `http/1.1` on TLS,
   with the negotiated protocol reported by `zu_info()` and on the
   response; and an explicit h2c prior-knowledge option on the client
   for `http://` servers such as a local Spark Connect (port 15002,
   cleartext unless `use_ssl` is set). `zuh_tls_config` already has an
   `alpn` field as a single string; it becomes a list.
2. **Response trailers exposed.** §18.2 today parses chunked trailers,
   counts them against the header limits and discards them, "never
   merged into the response headers". gRPC's status lives there, so
   `zu_resp_trailers(res)` with `zu_resp_header()`'s semantics (D-16)
   and the §40 limits, for HTTP/2 and chunked alike. A Trailers-Only
   response, a HEADERS block that ends the stream, must reach the
   caller as headers with an empty body, not as an error.
3. **A pull-based body stream.** §31.8 says bodies are "fully consumed
   into memory, a file, or a callback before `zu_perform()` returns"
   and "a lazy or streaming response object is not planned". A pull
   iterator needs one: `zu_resp_read(res, n)` returning up to `n` bytes
   or an empty raw at end, with `max_body` still enforced and the
   flow-control window replenished as the caller reads, so an unread
   stream stops the server. If pull is refused, the §27 callback sink
   with D-47's unwind is the fallback and `grpc_stream()` becomes push
   (`each =`) rather than an iterator (Q2).
4. **Per-request cancel from R.** `zu_resp_abort(res)` on an open
   streaming response: over HTTP/2 `RST_STREAM(CANCEL)` on that stream
   with the connection kept in the pool (S16); over HTTP/1.1 a closed
   connection, as §26.3 already requires. The §27.2 rule that a
   callback returning `FALSE` "stops the transfer cleanly" needs the
   same HTTP/2 meaning.
5. **`te: trailers` passthrough.** The request header must reach the
   wire unchanged; gRPC servers use it to detect incompatible proxies.
   Nothing in the design says zuhttp strips it, so this is a test to
   add rather than code.
6. **Keepalive PING.** A client option (`time`, `timeout`) that sends
   PING on an idle HTTP/2 connection and evicts it from the pool when
   no ACK arrives, replacing the §26.2 readability probe, which cannot
   tell an idle HTTP/2 connection from a dead one.
7. **Later: a streaming request body.** §28 says "streaming request
   bodies are not planned before 1.0". Client-streaming RPCs
   (`AddArtifacts`) need one; it is the second request, not the first.

What gRPC reuses unchanged from the edition 1 stages: S10's proxy and
CONNECT (§20), S15's cancellation and unwind (§25), S16's pool with its
value-compared key (§26.1, which already includes ALPN), and S17's
sinks (§27). Conformance of the HTTP/2 layer, with h2spec (MIT,
v2.6.0) as far as it tests clients and with nghttp2's own error codes,
belongs to zuhttp; `zugrpc` tests only what it adds.

### 7.3 The alternative, rejected

The first draft of this RFC vendored nghttp2 in `zugrpc` and asked
`zuhttp` to export its TLS stream layer instead: a header in
`inst/include` and a versioned table on the `zukomp-r.h` pattern,
with connect-by-name (Network.framework dials rather than wraps on
macOS, D-71), ALPN as a list, read, write and poll with deadlines,
peer certificate information, proxy CONNECT and a stable error set,
callable from another package's C; `more-candidates.md` §5 had asked
for the same for `zumail`. Rejected for three reasons: it duplicates
the transport (a second TCP stream, session loop, pool and interrupt
discipline beside zuhttp's); it gates on a C API export that zuhttp's
§54 puts "out of scope before 1.0" and §36.1 keeps "internal until a
second external implementation exists", while the HTTP/2 minor gates
only on zuhttp's own roadmap; and it adds a 30,000-line vendored build
to a package whose own work is a few hundred lines of R.

## 8. C API

None, now or later, in this package: there is no C code to export
(D1). A sibling that wants to stream without an R-level copy per
message, as `zuspark` might for Arrow batches into `zuarrow`, would ask
`zuhttp` for a C-level body stream, which is §54's question there.

## 9. Errors

Every condition inherits from `zugrpc_error`. A failed call raises
`zugrpc_error_status`, whose fields are `grpc_status` (the name, such as
`UNAVAILABLE`), `grpc_code` (the integer), `message` (the decoded
`grpc-message`), `details` (the decoded `google.rpc.Status` as a list,
or `NULL`), `http_status`, `method`, `headers` and `trailers`. Its
class vector also carries the code, as `zugrpc_error_unavailable`, so
`tryCatch()` can select one status. *Decided 2026-11-03 (Stage 1),
recorded 2026-11-05:* the decoded `grpc-message` is the field
`grpc_message`; `conditionMessage()` is `"<NAME>: <grpc_message>"`.

| Class | Raised when |
| --- | --- |
| `zugrpc_error_status` | a non-OK `grpc-status` (§6.5), with the code class |
| `zugrpc_error_transport` | a `zuhttp_error` from connect, TLS, ALPN or reset |
| `zugrpc_error_protocol` | bad framing, content type, flags or lengths |
| `zugrpc_error_argument` | a bad URL, method name or metadata key |
| `zugrpc_error_interrupt` | an R interrupt cancelled the call |

A transport failure carries `grpc_status = "UNAVAILABLE"` as well, so a
caller that retries on the gRPC code need not know the layer, and the
original `zuhttp_error` is kept as `parent`. `details` is `NULL` when
the trailer is absent or does not decode; a decode failure is a
warning, never an error, so the status is not lost behind a parser.

*Decided 2026-11-05 (Stage 3):* `zugrpc_error_transport` also has the
class `zugrpc_error_unavailable`, so a handler for that status catches a
failure of either layer, but not `zugrpc_error_status`, since no server
sent it. Three zuhttp conditions are not transport failures and map to
a status instead, each keeping the zuhttp condition as `parent`:
`zu_timeout_error` is `DEADLINE_EXCEEDED` (§6.6), `zu_cancelled_error`
is `CANCELLED`, and `zu_body_limit_error` is `RESOURCE_EXHAUSTED`. An
interrupt, `zu_interrupted_error`, is `zugrpc_error_interrupt` with
`grpc_status = "CANCELLED"`. Every condition carries `method`.

## 10. Testing

- **Framing without a network.** Every function in `R/frame.R` and
  `R/status.R` against byte-exact fixtures: prefixes at 0, 1, 65,535
  and `max_message` bytes, split across chunk boundaries at every
  offset of a small message; padded and unpadded base64; every
  `grpc-timeout` unit; percent-encoded `grpc-message`; the seventeen
  codes; the HTTP-status fallback map.
- **Recorded responses.** Headers, body and trailers captured from the
  Go server (unary, streaming, Trailers-Only, every status code, `-bin`
  metadata, a `Status` with `ErrorInfo`) replayed through `zuhttp`'s
  mock transport (§37), which needs trailers added to its response
  constructor. These run on every platform. *Decided 2026-11-05
  (Stage 2):* zuhttp's `zu_response(trailers =)` carries them. Each
  fixture is a `dput()` text file under `tests/testthat/fixtures/`, so a
  diff is reviewable, holding the request zugrpc must send and the
  response as zuhttp received it. `tools/record-fixtures.R` writes them
  against `grpc-go`'s interop server at v1.67.1, built with `go install`,
  encoding the `grpc.testing` requests by hand so the fixtures check
  zugrpc's encoder rather than repeat it.
- **A local server in CI.** The Ubuntu legs run a gRPC server in Docker
  behind `ZU_GRPC_TEST_SERVER`: `grpc-go`'s interop server
  (`interop/server`, Apache-2.0), built from a pinned tag, for the
  standard `UnaryCall`, `StreamingOutputCall`, status and metadata
  cases; and the `apache/spark` image (4.2.1 tags published on
  2026-11-02, Apache-2.0) with `start-connect-server.sh`, for one
  `ExecutePlan` that streams and ends `OK` and one invalid plan that
  carries Spark's `ErrorInfo`. The gRPC project's own interop images
  live in a Google Artifact Registry and are not relied on. macOS and
  Windows legs run the recorded responses only. *Decided 2026-11-05
  (Stage 4):* the live tests run in a workflow of their own,
  `.github/workflows/live.yaml`, since `r-cmd-check.yml` cannot start a
  server and its checks must not touch a network. It runs on Ubuntu,
  macOS and Windows, not Ubuntu alone, so that TLS with ALPN `h2` is
  shown on all three. The servers are built with `go install`, as
  zuhttp's `network.yaml` builds them, not run in Docker, which the
  macOS and Windows runners lack. `tools/ci-live.sh` starts grpc-go's
  interop server at v1.67.1 over h2c and over TLS, and
  `tools/test-server` (grpc-go v1.67.1 and Go's standard library) for
  the cases the interop server lacks: a method that stalls after its
  headers, the status details of §6.5, a TLS port offering only
  `http/1.1`, and a plain HTTP/2 server that is not gRPC. It writes a
  throwaway CA and a `localhost` certificate. The variables follow
  zuhttp's: `ZU_GRPC_TEST_SERVER`, `ZU_GRPC_TEST_TLS`,
  `ZU_GRPC_TEST_CA`, `ZU_GRPC_TEST_STATUS`, `ZU_GRPC_TEST_H1_TLS` and
  `ZU_H2_TEST_SERVER`, and each live test skips unless its own is set.
  Schannel cannot take a private CA yet (zuhttp#5), so on Windows the
  TLS tests turn verification off; they test ALPN, and trust is
  zuhttp's to test. *Decided 2026-11-05 (Stage 5):* the Spark test is a
  job of `live.yaml` on Ubuntu, the one runner with Docker: the
  `apache/spark:4.2.1` image runs `start-connect-server.sh` in the
  foreground, and `ZU_SPARK_TEST_SERVER` points at it. Its messages are
  encoded with zuproto against a descriptor set that
  `tools/gen-spark-descriptors.sh` builds from Spark's Connect protos at
  tag `v4.2.1`; the set is test-only and left out of the tarball. Spark
  sends `ResultComplete` only to a reattachable execution, so the test
  asserts the rows and the `OK` status instead.
- **Hostile input, at this layer.** A declared length above
  `max_message`, a compressed flag with no encoding, trailers with no
  `grpc-status`, a `grpc-status-details-bin` that is not base64 or not
  a `Status`, `:status 200` with `text/html`, and a server that sends
  headers then stalls until the deadline. HPACK bombs, oversized
  frames and flow-control starvation are zuhttp's tests (§7.2).
- **Lifetimes.** A stream dropped mid-iteration is cancelled by its
  finaliser; `grpc_close()` with open streams; an interrupt in
  `$next_message()` leaves the channel usable; a channel after
  `readRDS()` reconnects.

## 11. Performance targets

Measured in Stage 5 and recorded in an article; nothing is claimed
before it is measured. *Measured 2026-11-05 (Stage 5)* by
`tools/bench.R`, reported in `vignettes/articles/performance.Rmd`: all
four are met. Measuring found the user-agent string costing a
millisecond per call (`packageVersion()`); it is now built once per
session. The targets: a unary call over loopback h2c
under 1 ms of `zugrpc` overhead above `zu_perform()`; streaming 1 GiB
of 16 MiB messages with the iterator holding at most one message plus
one chunk; a 100,000-message stream of small messages with one raw
vector allocated per message and no quadratic concatenation; and
`$cancel()` returning within 100 ms of a stalled server.

## 12. Build and CRAN

Pure R, `Depends: R (>= 4.1)`, `Imports: zuhttp, zuproto`, no
`SystemRequirements` of its own. `inst/descriptors/google-rpc.binpb`
is generated by `tools/gen-descriptors.sh` from pinned googleapis
`.proto` files with `protoc`, committed with its SHA-256, and the
Apache-2.0 licence is in `inst/COPYRIGHTS`. *Decided 2026-11-05 (Stage 3):* the
pin is googleapis commit `02362883cd16428e5f57fa60ca8d8f60dafcdba7`
(2026-05-04, the last to touch `google/rpc`), built with protoc 36.2
without `--include_imports`, since every zuproto pool holds the
well-known types. A test checks the SHA-256 where `tools::sha256sum()`
exists. Google LLC is listed as `cph` in `Authors@R`. The `ErrorInfo`
fixtures are recorded from `tools/test-server`, a small grpc-go
v1.67.1 server that returns Spark-shaped details with
`status.WithDetails()`; its Go sources are in `.Rbuildignore`. Spark
itself is Stage 5's test. `R CMD check` runs no
network test unless `ZU_GRPC_TEST_SERVER` or another of §10's variables
is set, following zuhttp §47.5.

**The release gate.** v0.1.0 goes to CRAN only after `zuhttp`'s minor
after 1.0 that carries §7.1 and §7.2 items 1 to 6 (the floor in
`Imports`) and `zuproto` 0.1.0 are both there. R10.2 forbids
`Remotes:` in a submitted tarball, so until then `zugrpc` installs
from GitHub. Stages 0 to 3 need neither and can start now against
recorded responses; Stage 4 needs a `zuhttp` branch with HTTP/2 and is
where the two packages' pull requests meet.

## 13. Roadmap

The stages, their exit criteria and CI tiers are in
[roadmap.md](roadmap.md).

## 14. Acceptance criteria for v0.1.0

- Every behaviour in §6 and §9 has a passing test, against the Go
  interop server on the Ubuntu legs and the recorded responses
  everywhere.
- `ExecutePlan` against `apache/spark` 4.2.1 in Docker streams and ends
  `OK`; an invalid plan raises `zugrpc_error_status` whose `details`
  holds Spark's `ErrorInfo` with `errorClass` and `sqlState`.
- Every hostile input of §10 is an error of the stated class.
- TLS with ALPN `h2` works on all three platforms through `zuhttp`,
  and an `http/1.1` negotiation is refused.
- `R CMD check --as-cran` is clean on all r-actions legs with the CRAN
  versions of `zuhttp` and `zuproto`; no `Remotes:`.
- A stage that needs a second pull request moves scope to §16, not the
  release.

## 15. Decisions

All are **(C)**: this RFC decides them and the maintainer may overturn
any of them.

- **D1 (C).** HTTP/2 lives in `zuhttp`, vendored nghttp2 and all, and
  `zugrpc` is pure R on its request API. One transport in the family,
  no C-API export gate, and a few hundred lines here.
- **D2 (C).** The §7 request is filed as one `zuhttp` issue with items
  1 to 6 for the first HTTP/2 minor and item 7 for a later one.
- **D3 (C).** v0.1.0 does not reach CRAN before that minor and
  `zuproto` 0.1.0 are on CRAN; development proceeds against recorded
  responses and a `zuhttp` branch until then.
- **D4 (C).** `Imports: zuproto`, not `Suggests`: a gRPC error without
  its `ErrorInfo` is the complaint every Spark user would file first.
  `zugrpc` decodes only `google.rpc.Status` and `error_details.proto`,
  from its own bundled descriptors, never the caller's messages.
- **D5 (C).** Unary and server streaming only in v0.1.0, every Spark
  call except `AddArtifacts`; client streaming waits for `zuhttp`'s
  streaming request body (§7.2, item 7).
- **D6 (C).** Streaming is a pull iterator on `zuhttp`'s pull-based
  body (§7.2, item 3); if `zuhttp` offers callbacks only,
  `grpc_stream()` takes `each =` and this decision is overturned.
- **D7 (C).** No C code and no C API, ever, in this package.
- **D8 (C).** Cancellation is `zuhttp`'s abort, which must mean
  `RST_STREAM` on HTTP/2; `zugrpc` never closes a connection itself.
- **D9 (C).** Base64 and percent-decoding are a page of base R each
  (`bitwAnd()` over raw, `utils::URLdecode()`); no dependency.
- **D10 (C).** Status codes are the condition classes. A caller selects
  `zugrpc_error_unavailable` by class, not by comparing strings.
- **D11 (C).** The deadline is both the `grpc-timeout` header and the
  request's `total` timeout, and the local one wins.
- **D12 (C).** `identity` is the only encoding in v0.1.0; `gzip` waits
  for `zukomp` so that no second zlib binding is written.
- **D13 (C).** MIT, with the googleapis licence in `inst/COPYRIGHTS`.

## 16. Later versions, in the order they are expected

- **`grpc-encoding: gzip`** through `zukomp`, with
  `grpc-accept-encoding: gzip, identity` and a fresh context per
  message, as the specification requires.
- **Client streaming and bidirectional calls**, with `$send()` and
  `$close_send()` on the stream object, once `zuhttp` has a streaming
  request body; `AddArtifacts` is the consumer.
- **Retries** driven by `RetryInfo` in the status details and by
  `UNAVAILABLE` on idempotent methods, with a cap and backoff, built
  on zuhttp's §33 retry model where its conditions allow.
- **Server reflection** (`grpc.reflection.v1.ServerReflection`), which
  returns `FileDescriptorProto`s that `proto_pool_add()` can load; this
  is the "descriptor source" zuproto's design §2 lists as later work.
- **Connect and gRPC-Web** over HTTP/1.1, for servers behind proxies
  that do not forward HTTP/2 trailers; these need nothing from §7.

## 17. Open questions

- **Q1.** *Settled 2026-11-05 (Stage 4):* zuhttp 0.1.0, its first
  release, carries HTTP/2 (§7.1, §7.2 items 1 to 7), so the `Imports`
  floor is `zuhttp (>= 0.1.0)` once that is on CRAN. Its CRAN
  submission waited on this package's Stage 4 live test.
- **Q2.** *Settled 2026-11-05 (Stage 4):* pull, through `zu_perform(stream
  = TRUE)` and `zu_resp_read()`; D6 stands.
- **Q3.** *Settled 2026-11-05 (Stage 4):* no `timeout` of its own in
  v0.1.0; the call deadline is enough (§6.6). One can be added later
  without breaking a caller, once zuhttp#173 gives a per-read bound.
- **Q4.** *Settled 2026-11-05 (Stage 2):* yes, as `client =` (§6.1).
- **Q5.** Is v0.1.0 a CRAN submission before `zuspark` exists, or does
  the pair go together? The board's `CRAN intent` records it.

## 18. What this RFC does not decide

The exact print methods; whether `grpc_call()` returns a plain list or
an S3 object with accessors; the names of the keepalive settings on
`zuhttp`'s side; the fixture format for recorded responses; the
precise set of `ErrorInfo` metadata keys `zuspark` reads, which is
RFC 0070's business; and the article's examples.

## 19. Sources and verification

Checked on 3 November 2026:

- [nghttp2](https://github.com/nghttp2/nghttp2): latest release
  `v1.71.0` (2026-11-02) through the GitHub API; `nghttp2-1.71.0.tar.gz`
  downloaded and read for §7.1's counts, macros, `abort()` and `fprintf`
  sites, `nghttp2ver.h.in`, `lib/Makefile.am`, `lib/CMakeLists.txt`,
  `configure.ac` and `README.rst`. `COPYING` is MIT.
- zuhttp's [design][zuhttp-design], the sections and decisions cited
  in §3, §6 and §7, [`zuh_stream.h`][zuh-stream] and
  [`zuh_tls.h`][zuh-tls] (the `alpn` field); its
  [roadmap][zuhttp-roadmap] (M0 ready to submit on 2026-10-30, M1 to
  M3, "What 1.0 means", the edition 1 stage map naming S10, S15, S16
  and S17); crandb `not_found`.
- zuproto's [design][zuproto-design] §2 (Later and Never), §3, §5,
  §6.3 (well-known types only; `google.rpc` is not among them), §10
  and §21.
- `grpc/grpc` [`doc/PROTOCOL-HTTP2.md`][grpc-http2],
  [`doc/statuscodes.md`][grpc-codes] and [`doc/PROTOCOL-WEB.md`][grpc-web];
  [`connectrpc.com/docs/protocol`](https://connectrpc.com/docs/protocol/).
- googleapis [`google/rpc/error_details.proto`][error-details]
  (Apache-2.0); Spark's `base.proto` (14 RPCs and their streaming
  kinds), `core.py` (`_handle_rpc_error`, `rpc_status.from_call`,
  `ErrorInfo`, port 15002, `use_ssl`, 128 MiB message limit, keepalive
  60/20 s) and `ErrorUtils.scala` (the metadata keys of §6.5).
- crandb for `zugrpc`, `grpc`, `GRPC`, `grpcr` (all `not_found`),
  `rgrpc` 0.1.2 and its `SystemRequirements`, `curl` 8.1.0, `httr2`
  1.3.0, `arrow` 26.0.0, `zukomp` 0.1.0; `tools::CRAN_package_db()`
  for every mention of gRPC (one) and HTTP/2 (none); CRAN's check page
  for `rgrpc`; `jeroen/curl` `src/handle.c` and `curl_options()`;
  `apache/arrow` `r/NAMESPACE` and `r/R/flight.R`; the GitHub API for
  `pedrobtz/zugrpc` (not found).
- [h2spec](https://github.com/summerwind/h2spec) (MIT, v2.6.0 of
  2020-08-04, last pushed 2023-10-15); `grpc-go`'s licence and
  `interop/`; Docker Hub tags for `apache/spark` (4.2.1, 2026-11-02);
  `grpc/grpc` `tools/interop_matrix/README.md` for its image registry.

Not verified here: that zuhttp accepts the §7 request or on what
schedule (Q1); that `R CMD check`'s symbol scan accepts the patched
nghttp2 object on every flavour, which is zuhttp's stage to prove;
that the Go interop server's streaming cases exercise back pressure as
§10 assumes (Stage 4); and whether libcurl delivers HTTP/2 trailers to
the header callback as it does chunked ones, which its documentation
describes only for the chunked case and matters only to §1.2.

[zuhttp-design]: https://github.com/pedrobtz/zuhttp/blob/main/.agents/zuhttp-design.md
[zuhttp-roadmap]: https://github.com/pedrobtz/zuhttp/blob/main/.agents/roadmap.md
[zuh-stream]: https://github.com/pedrobtz/zuhttp/blob/main/src/zuh_stream.h
[zuh-tls]: https://github.com/pedrobtz/zuhttp/blob/main/src/zuh_tls.h
[zuproto-design]: https://github.com/pedrobtz/zuproto/blob/main/.agents/design.md
[grpc-http2]: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md
[grpc-codes]: https://github.com/grpc/grpc/blob/master/doc/statuscodes.md
[grpc-web]: https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md
[error-details]: https://github.com/googleapis/googleapis/blob/master/google/rpc/error_details.proto
