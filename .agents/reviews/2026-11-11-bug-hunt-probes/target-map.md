# zugrpc target map, commit 90cc3c0

Boundaries
- emits: frame_encode (R/frame.R), request_headers / build_request (R/frame.R, R/call.R),
  grpc_timeout (R/timeout.R), metadata_encode / base64_encode (R/metadata.R), channel headers
  merge, user-agent prefixing, URL/method -> :path, parse_target (R/channel.R)
- decodes: frame_split / check_flag (R/frame.R), unary_outcome status order (R/call.R),
  stream_take / stream_end (R/stream.R), status_from_header / status_from_http /
  grpc_message_decode / percent_decode (R/status.R), metadata_decode / base64_decode,
  user_metadata reserved filter, status_details_decode / unpack_details (R/details.R),
  check_content_type, transport_abort mapping (R/conditions.R)
Limits
- max_message (0..4294967295; unary also zuhttp max_body = max_message + 5; stream per message)
- frame_encode 4294967295; grpc-timeout 8 digits / 99999999H cap; local timeout floor 1 ms
- grpc-status ^[0-9]{1,9}$; status codes 0..16; read_size 64 KiB..16 MiB; 1 KiB body excerpt
- keepalive time/timeout > 0; deadline >= 0, POSIXct or seconds
Long-lived objects
- zugrpc_channel (env; two zuhttp clients sharing one pool; streams registry; closed flag; next_id)
- zugrpc_stream (env; pulled zuhttp response; queue/head; pending/need; done/cancelled/error;
  finaliser; registry id); rpc_env caches (descriptor pool, user agent)
Numbers crossing into C: none in zugrpc (pure R); values handed to zuhttp: max_body, timeout,
  read size n, keepalive seconds
Second cases: repeated headers (metadata, grpc-status, grpc-message, content-type),
  Trailers-Only vs trailers, status in headers and trailers, -bin comma joins, padded base64,
  grpc-encoding present without compressed flag, uppercase names from the server
Platform/backend: zuhttp TLS backend network-framework (built here); OpenSSL/Windows backends of
  zuhttp unverified here.
Weakest (suite): limits only straddled for status codes; no other-side check of grpc-timeout;
  no unary-vs-stream differential; no fork test; no hostile-session test; no stream readRDS test.
Late code: R/stream.R and R/details.R (stages 3-4), review-fixes commits.
