source("<W>/hunt-2/common.R")
M <- frs("hi")
# split at every offset: 3 messages "abc","", "defgh" in chunks of k bytes, with gap so reads see separate frames
body <- paste0(frs("abc"), frame(raw()), frs("defgh"))
c1 <- ch()
for (k in 1:12) {
  set_scen(M = list(h(H0), d(body, chunk = k, gap = 3), h(TOK, TRUE)))
  cat("chunk", k, ""); r <- srun(c1, "/s.S/M")
}
set_scen(M = list(h(H0), d(frs("solo"), chunk = 1, gap = 2), h(TOK, TRUE))); urun(c1, "/s.S/M")
grpc_close(c1)
# flags
for (f in c(1, 2, 128, 255)) {
  both(sprintf("flag %d no encoding", f), list(h(H0), d(frame(charToRaw("hi"), f)), h(TOK, TRUE)))
}
both("flag 1 grpc-encoding identity", list(h(c(H0, list(c("grpc-encoding", "identity")))), d(frame(charToRaw("hi"), 1)), h(TOK, TRUE)))
both("flag 1 grpc-encoding gzip", list(h(c(H0, list(c("grpc-encoding", "gzip")))), d(frame(charToRaw("hi"), 1)), h(TOK, TRUE)))
both("flag 0 grpc-encoding gzip", list(h(c(H0, list(c("grpc-encoding", "gzip")))), d(M), h(TOK, TRUE)))
both("flag 1 grpc-encoding IDENTITY", list(h(c(H0, list(c("grpc-encoding", "IDENTITY")))), d(frame(charToRaw("hi"), 1)), h(TOK, TRUE)))
both("flag 1 grpc-encoding empty", list(h(c(H0, list(c("grpc-encoding", "")))), d(frame(charToRaw("hi"), 1)), h(TOK, TRUE)))
both("flag 1 + non-OK status 5", list(h(H0), d(frame(charToRaw("hi"), 1)), h(list(c("grpc-status", "5")), TRUE)))
both("good msg then flag-2 msg, same DATA", list(h(H0), d(paste0(M, frame(charToRaw("zz"), 2))), h(TOK, TRUE)))
both("good msg then flag-2 msg, separate DATA w/ gap", list(h(H0), d(M), list(sleep = 300), d(frame(charToRaw("zz"), 2)), h(TOK, TRUE)))
# content types
for (ct in c("application/grpc", "application/grpc+proto", "application/grpc;charset=utf-8", "APPLICATION/GRPC", "application/grpc-web", "application/grpc-web-text", "application/grpcx", "application/json", "", " application/grpc")) {
  both(sprintf("content-type '%s'", ct), list(h(list(c(":status", "200"), c("content-type", ct))), d(M), h(TOK, TRUE)))
}
both("no content-type", list(h(list(c(":status", "200"))), d(M), h(TOK, TRUE)))
both("content-type twice (text/html, application/grpc)", list(h(list(c(":status", "200"), c("content-type", "text/html"), c("content-type", "application/grpc"))), d(M), h(TOK, TRUE)))
both("content-type twice (application/grpc, text/html)", list(h(list(c(":status", "200"), c("content-type", "application/grpc"), c("content-type", "text/html"))), d(M), h(TOK, TRUE)))
both("no content-type, trailers-only status 5", list(h(list(c(":status", "200"), c("grpc-status", "5")), TRUE)))
both("text/html + trailers-only status 0", list(h(list(c(":status", "200"), c("content-type", "text/html"), c("grpc-status", "0")), TRUE)))
both("text/html + status0 in headers + body msg + trailers 0", list(h(list(c(":status", "200"), c("content-type", "text/html"), c("grpc-status", "0"))), d(M), h(TOK, TRUE)))
both("text/html, body, trailers status 5", list(h(list(c(":status", "200"), c("content-type", "text/html"))), d(M), h(list(c("grpc-status", "5")), TRUE)))
