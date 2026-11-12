.libPaths(c(Sys.getenv("VLIB"), .libPaths())); library(zugrpc)
wm <- function(b, flag = 0L) { n <- length(b); c(as.raw(c(flag, (n %/% 2^24) %% 256, (n %/% 2^16) %% 256, (n %/% 2^8) %% 256, n %% 256)), b) }
chan <- function(body, headers = c("content-type"="application/grpc"), trailers = c("grpc-status"="0"), status = 200L, ...) {
  f <- function(req) zuhttp::zu_response(status, headers = headers, body = body, trailers = trailers)
  grpc_channel("http://localhost:1", client = zuhttp::zu_client(transport = zuhttp::zu_mock_transport(f)), ...) }
cls <- function(expr) tryCatch({v <- force(expr); if (is.raw(v)) paste("raw", paste(v, collapse=" ")) else if (is.null(v)) "NULL" else paste(v)}, error = function(e) paste(class(e)[1], "|", conditionMessage(e)))
# F1: good msg + bad flag in one read
st <- grpc_stream(chan(c(wm(charToRaw("hi")), wm(as.raw(1), flag = 2L))), "/a.B/C", raw())
cat("F1 first read:", cls(st$next_message()), "\n")
# F2: partial body + trailers status 5
ch <- chan(as.raw(c(0,0,0,0,5,0xaa)), trailers = c("grpc-status"="5", "grpc-message"="nf"))
cat("F2 unary:", cls(grpc_call(ch, "/a.B/C", raw())), "\n"); st <- grpc_stream(ch, "/a.B/C", raw()); cat("F2 stream:", cls(st$next_message()), " status:", cls(st$status()), "\n")
# F4: text/html + grpc-status 0 in headers
ch <- chan(wm(charToRaw("hi")), headers = c("content-type"="text/html", "grpc-status"="0"))
cat("F4 unary:", cls(grpc_call(ch, "/a.B/C", raw())), "\n"); st <- grpc_stream(ch, "/a.B/C", raw()); cat("F4 stream:", cls(st$next_message()), cls(st$next_message()), cls(st$status()), "\n")
# F9: max_message 100, 503 with 300-byte html
ch <- chan(charToRaw(strrep("x", 300)), headers = c("content-type"="text/html"), trailers = NULL, status = 503L, max_message = 100)
cat("F9 unary:", cls(grpc_call(ch, "/a.B/C", raw())), "\n"); cat("F9 stream:", cls(grpc_stream(ch, "/a.B/C", raw())), "\n")
# F11
print(names(zugrpc:::metadata_decode(c("v-bin"="QQ,")))); print(length(zugrpc:::metadata_decode(c("v-bin"=",QQ"))))
# F6: ErrorInfo + bad RetryInfo Any
pool <- zuproto::proto_pool(system.file("descriptors","google-rpc.binpb", package="zugrpc"))
ei <- zuproto::proto_encode(list(reason="R", domain="D"), "google.rpc.ErrorInfo", pool)
any1 <- list(type_url="type.googleapis.com/google.rpc.ErrorInfo", value=ei)
any2 <- list(type_url="type.googleapis.com/google.rpc.RetryInfo", value=as.raw(c(0xff,0xff)))
sb <- zuproto::proto_encode(list(code=5L, message="m", details=list(any1, any2)), "google.rpc.Status", pool)
d <- withCallingHandlers(zugrpc:::status_details_decode(zugrpc:::base64_encode(sb)), warning = function(w) { cat("F6 warning:", class(w)[1], "\n"); invokeRestart("muffleWarning") })
cat("F6 details NULL:", is.null(d), "\n")
sb1 <- zuproto::proto_encode(list(code=5L, message="m", details=list(any1)), "google.rpc.Status", pool)
cat("F6 control ErrorInfo ok:", zugrpc:::status_details_decode(zugrpc:::base64_encode(sb1))$details$ErrorInfo$reason, "\n")
