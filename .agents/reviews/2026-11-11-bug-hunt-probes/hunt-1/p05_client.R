source("common.R")
ps <- function(cl) attr(cl, "pool_state")
cat("== own pool\n")
base <- zuhttp::zu_client()
c1 <- grpc_channel("http://h:1", client = base); c2 <- grpc_channel("http://h:1", client = base); c3 <- grpc_channel("http://h:1")
cat("ch pool != caller's:", !identical(ps(c1$client), ps(base)), " ch1 != ch2:", !identical(ps(c1$client), ps(c2$client)), " unary==stream:", identical(ps(c1$client), ps(c1$stream_client)), "\n")
c4 <- grpc_channel("http://h:1", client = base, keepalive = NULL)
cat("keepalive NULL: ch pool != caller's:", !identical(ps(c4$client), ps(base)), "\n")
cat("== caller's pool settings kept?\n")
for (p in list(zuhttp::zu_pool(max_idle = 3L, max_per_host = 2L, idle_timeout = 7.5), zuhttp::zu_pool(idle_timeout = 0.0015), zuhttp::zu_pool(idle_timeout = 0.001), zuhttp::zu_pool(idle_timeout = 2147483.647),zuhttp::zu_pool(idle_timeout = 1e7), zuhttp::zu_pool(keepalive_time = 5, keepalive_timeout = 2))) {
  cl <- zuhttp::zu_client(pool = p); cat("in: "); cat(unlist(unclass(p)), "\n")
  for (ka in list(grpc_keepalive(), NULL)) { ch <- try_(grpc_channel("http://h:1", client = cl, keepalive = ka)); if (inherits(ch, "caught")) print(ch) else { cat("  out:"); cat(unlist(unclass(ch$client$pool)), "\n") } }
}
cat("== pool = NULL client\n")
cl <- try_(zuhttp::zu_client(pool = NULL)); if (inherits(cl, "caught")) print(cl) else { str(cl$pool); ch <- try_(grpc_channel("http://h:1", client = cl)); if (inherits(ch, "caught")) print(ch) else { str(ch$client$pool); print(try_(grpc_close(ch))) } }
cat("== client settings as the mock sees them\n")
seen <- NULL
fake <- zuhttp::zu_mock_transport(function(req) { seen <<- req; zuhttp::zu_response(200L, headers = c("content-type" = "application/grpc"), body = as.raw(c(0,0,0,0,0)), trailers = c("grpc-status" = "0")) })
cl <- zuhttp::zu_client(transport = fake, base_url = "http://other:9/prefix", headers = c("x-client" = "1", te = "gzip", "grpc-timeout" = "1S", "content-type" = "text/plain", a = "client"), query = list(q = "1"), timeout = 3, user_agent = "mine/1", max_body = 10, check = TRUE, http2 = "never", retry = NULL)
ch <- grpc_channel("http://h:1", client = cl, headers = c(a = "chan"))
r <- try_(grpc_call(ch, M, raw())); if (inherits(r, "caught")) print(r)
str(unclass(seen))
for (n in c("http2", "check", "max_body", "user_agent", "timeout", "base_url", "query", "headers")) { cat(n, ": "); str(ch$client[[n]]) }
cat("== not a client\n"); print(try_(grpc_channel("http://h:1", client = list()))); print(try_(grpc_channel("http://h:1", tls = list())));print(try_(grpc_channel("https://h:1", tls = list()))); print(try_(grpc_channel("https://h:1", tls = "x")))
cat("== close\n")
m <- mock(); grpc_close(m$ch); print(try_(grpc_call(m$ch, M, raw()))); print(try_(grpc_stream(m$ch, M, raw()))); print(try_(grpc_close(m$ch))); print(m$ch); print(try_(grpc_close(NULL))); print(try_(grpc_close(list())))
cat("== order of checks on closed channel with bad method\n"); print(try_(grpc_call(m$ch, "bad", raw())))
cat("== request matrix\n")
m <- mock()
for (rq in list(raw(), as.raw(1:3), NULL, "abc", 1:3, list(as.raw(1)), structure(as.raw(1:3), class = "blob"), c(a = as.raw(1), b = as.raw(2)), matrix(as.raw(1:4), 2), NA, charToRaw("é"))) {
  cat(deparse(rq)[1], " => "); r <- try_(grpc_call(m$ch, M, rq)); if (inherits(r, "caught")) print(r) else { b <- sent(m)$body; cat(class(b), "|", format(as.raw(b)), "| attrs:", names(attributes(b)), "\n") }
}
