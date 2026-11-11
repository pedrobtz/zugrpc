source("common.R")
cat("== parse_target\n")
l1 <- "http://caf\xe9:1"; Encoding(l1) <- "latin1"
for (u in list("http://localhost:50051", "http://localhost:50051/", "HTTP://LocalHost:50051", "https://h", "http://h:1\n", "http://h:1 ", " http://h:1", "http://a b:1", "http://:50051", "http://h:99999", "http://h:port", "http://[::1]:50051", "http://h:1//", "http://h:1/x", "http://u@h:1", "http://h:1?x", "h:1", "grpc://h:1", "dns:///h:1", "http://café:1", l1, "http://h:1\r\nx: y", c("http://a:1", "http://b:1"), NA_character_, character(), NULL, 1, factor("http://h:1"), c(a = "http://h:1"), list("http://h:1"), "http://h:-1", "http://h:", "http://h:0", "http://%41:1", "http://h\\x:1")) {
  cat(encodeString(deparse(u)[1]), " => "); r <- try_(zugrpc:::parse_target(u)); if (inherits(r, "caught")) print(r) else cat(encodeString(r$origin), "|", encodeString(r$authority), "|", r$tls, "\n")
}
cat("== weird targets at call time\n")
for (u in c("http://h:1\n", "http://h:1 ", "http://a b:1", "http://:50051", "http://h:99999", "http://h:port", "http://h:", "http://h:1\r\nx: y", "http://h\\x:1")) {
  cat(encodeString(u), ": ")
  ch <- try_(grpc_channel(u)); if (inherits(ch, "caught")) { print(ch); next }
  r <- try_(grpc_call(ch, M, raw(), deadline = 2)); if (inherits(r, "caught")) print(r) else print("OK?!")
  r <- try_(grpc_stream(ch, M, raw(), deadline = 2)); if (inherits(r, "caught")) print(r) else print("OK?!")
  grpc_close(ch)
}
cat("== check_method\n")
for (me in list("/a.B/C", "/a.B/C\n", "a.B/C", "/a.B/C/", "/B/C", "/a..B/C", "/.a/C", "/a./C", "/a.B/C?x=1", "/a.B/C#f", "/a.B/C D", "/a.B/Ç", "//C", "/a.B/", c("/a.B/C", "/a.B/D"), NA_character_, character(), NULL, factor("/a.B/C"), c(x = "/a.B/C"), list("/a.B/C"), "/a.B/1C", "/1a.B/C", "/a.B/C.D", "/a-b.B/C", "/a.B/%43")) {
  cat(encodeString(deparse(me)[1]), " => "); r <- try_(zugrpc:::check_method(me)); if (inherits(r, "caught")) print(r) else cat("ok\n")
}
cat("== max_message\n")
for (mm in list(0, 1, 0.5, 10.7, 5L, .Machine$integer.max, .Machine$integer.max + 1, 4294967295, 4294967296, -1, NA, NA_real_, NA_integer_, Inf, c(1, 2), numeric(), "5", TRUE, NULL, c(a = 5), 2^53)) {
  cat(deparse(mm)[1], " => "); r <- try_(grpc_channel("http://h:1", max_message = mm)); if (inherits(r, "caught")) print(r) else cat("unary max_body=", format(r$client$max_body, digits = 17), " stream max_body=", r$stream_client$max_body, " ch$max_message=", format(r$max_message, digits = 17), "\n")
}
cat("== keepalive\n")
for (k in list(list(60, 20), list(0.0004, 20), list(0.001, 0.001), list(0.0015, 0.0025), list(1e10, 20), list(2147483.647, 1), list(2147483.648, 1), list(60, 1e10), list(.Machine$integer.max + 1, 5), list(Inf, 1), list(0, 1), list(-1, 1), list(NA, 1), list(60L, 20L), list(TRUE, 1), list("60", 1), list(c(1, 2), 1), list(NULL, 1), list(1e-320, 1), list(0.5, 0.25), list(1234567, 7654321))) {
  cat(deparse(k)[1], " => "); ka <- try_(do.call(grpc_keepalive, k)); if (inherits(ka, "caught")) { print(ka); next }
  print(ka)
  r <- try_(grpc_channel("http://h:1", keepalive = ka)); if (inherits(r, "caught")) print(r) else cat("   pool: time_ms=", r$client$pool$keepalive_time_ms, " timeout_ms=", r$client$pool$keepalive_timeout_ms, "\n")
}
cat("== keepalive NULL / bad\n")
r <- grpc_channel("http://h:1", keepalive = NULL); str(unclass(r$client$pool))
print(try_(grpc_channel("http://h:1", keepalive = list(time = 1, timeout = 1))))
print(try_(grpc_channel("http://h:1", keepalive = 60)))
ka <- grpc_keepalive(); ka$time <- "x"; print(try_(grpc_channel("http://h:1", keepalive = ka)))
ka <- grpc_keepalive(); ka$time <- NULL; r <- try_(grpc_channel("http://h:1", keepalive = ka)); if (inherits(r, "caught")) print(r) else str(unclass(r$client$pool))
cat("partial: ka$ti =", grpc_keepalive()$ti, "\n")
