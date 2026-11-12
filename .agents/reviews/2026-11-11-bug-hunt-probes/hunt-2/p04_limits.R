source("<W>/hunt-2/common.R")
pre <- function(n, flag = 0) hx(as.raw(c(flag, (n %/% 16777216) %% 256, (n %/% 65536) %% 256, (n %/% 256) %% 256, n %% 256)))
bothm <- function(name, steps, mm) {
  cat(name, "\n"); do.call(set_scen, list(M = steps))
  c1 <- ch(max_message = mm); on.exit(grpc_close(c1))
  urun(c1, "/s.S/M"); r <- srun(c1, "/s.S/M"); cat("   events:", tail(log_events(), 1), "\n")
}
msg <- function(n) list(d = pre(n), fill = n)
for (mm in c(0, 1, 100)) for (n in c(mm - 1, mm, mm + 1)) if (n >= 0)
  bothm(sprintf("max_message=%d, message len %d", mm, n), list(h(H0), msg(n), h(TOK, TRUE)), mm)
bothm("max 100: two 60-byte messages (total 130 > max_body 105)", list(h(H0), msg(60), msg(60), h(TOK, TRUE)), 100)
bothm("max 100: 100-byte msg + status 5", list(h(H0), msg(100), h(list(c("grpc-status", "5")), TRUE)), 100)
bothm("max 100: 101-byte msg + status 5", list(h(H0), msg(101), h(list(c("grpc-status", "5")), TRUE)), 100)
bothm("max 100: good 'hi' then oversize prefix same DATA", list(h(H0), d(paste0(frs("hi"), pre(101))), list(sleep = 200), h(TOK, TRUE)), 100)
bothm("max 100: good 'hi' / gap / oversize prefix", list(h(H0), d(frs("hi")), list(sleep = 300), d(pre(101)), list(sleep = 200), h(TOK, TRUE)), 100)
bothm("max 0: http 404 html 300 bytes", list(h(list(c(":status", "404"), c("content-type", "text/html"))), list(fill = 300, end = TRUE)), 0)
bothm("max 100: http 503 html 300 bytes", list(h(list(c(":status", "503"), c("content-type", "text/html"))), list(fill = 300, end = TRUE)), 100)
bothm("max 100: 200 text/html 300 bytes", list(h(list(c(":status", "200"), c("content-type", "text/html"))), list(fill = 300, end = TRUE)), 100)
bothm("len 0xFFFFFFFF, max default", list(h(H0), d("00ffffffff"), list(sleep = 200), h(TOK, TRUE)), 128 * 1024^2)
bothm("len 0xFFFFFFFF, max 4294967295, then end", list(h(H0), d("00ffffffff41"), h(TOK, TRUE)), 4294967295)
bothm("len 0x80000000, max 4294967295, then end", list(h(H0), d("008000000041"), h(TOK, TRUE)), 4294967295)
bothm("len 2^31-1 max 4294967295 then end", list(h(H0), d("007fffffff41"), h(TOK, TRUE)), 4294967295)
bothm("max_message 4294967295 normal", list(h(H0), msg(10), h(TOK, TRUE)), 4294967295)
# big messages across read sizes
for (n in c(65535, 65536, 65537, 16 * 1024^2 - 1, 16 * 1024^2, 16 * 1024^2 + 1, 16 * 1024^2 + 65536 + 3)) {
  cat("stream big", n, "\n"); set_scen(M = list(h(H0), d(frs("a")), msg(n), d(frs("z")), h(TOK, TRUE)))
  c1 <- ch(); st <- grpc_stream(c1, "/s.S/M", raw()); l <- drain(st); cat("   lens:", lengths(l), "status", st$status(), "\n")
  r <- tryCatch(length(grpc_call(c1, "/s.S/M", raw())$message), error = function(e) class(e)[1]); grpc_close(c1)
}
for (n in c(16 * 1024^2 + 1)) { set_scen(M = list(h(H0), msg(n), h(TOK, TRUE))); c1 <- ch(); cat("unary big", n, length(grpc_call(c1, "/s.S/M", raw())$message), "\n"); grpc_close(c1) }
# body excerpt
for (n in c(0, 1023, 1024, 1025, 5000)) {
  set_scen(M = list(h(list(c(":status", "200"), c("content-type", "text/html"))), if (n > 0) list(fill = n, end = TRUE) else d("", TRUE)))
  c1 <- ch(); e <- tryCatch(grpc_call(c1, "/s.S/M", raw()), error = function(e) e)
  e2 <- tryCatch(grpc_stream(c1, "/s.S/M", raw()), error = function(e) e)
  cat("excerpt body", n, "-> unary", length(e$body), "ct", e$content_type, "http", e$http_status, "method", e$method, "| stream", length(e2$body), "http", e2$http_status, "method", e2$method, "\n"); grpc_close(c1)
}
