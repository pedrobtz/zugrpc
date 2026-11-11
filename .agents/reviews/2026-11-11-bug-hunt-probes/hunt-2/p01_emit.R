source("<W>/hunt-2/common.R")
set_scen(M = list(h(H0), d(frs("hi")), h(TOK, TRUE)))
c1 <- ch(headers = c("x-chan" = "c1", "x-over" = "chan"))
r <- show(grpc_call(c1, "/s.S/M", as.raw(1:3),
  metadata = list("x-over" = "call", "X-Up" = "V", "k-bin" = as.raw(c(0, 255, 16)), "e-bin" = raw(), sp = " a  b ", empty = "", "user-agent" = "me/1"),
  deadline = 5))
q <- last_req(); for (p in q$headers) cat("   ", p[[1]], "=[", p[[2]], "]\n", sep = ""); cat("   body:", q$body_hex, "len", q$body_len, "frames", unlist(q$data_frames), "\n")
# no deadline, empty request
r <- show(grpc_call(c1, "/s.S/M", raw()))
q <- last_req(); for (p in q$headers) cat("   ", p[[1]], "=[", p[[2]], "]\n", sep = ""); cat("   body:", q$body_hex, "len", q$body_len, "\n")
# large request 100000 bytes
r <- show(grpc_call(c1, "/s.S/M", as.raw(rep(7, 100000))))
q <- last_req(); cat("   body len", q$body_len, "prefix", substr(q$body_hex, 1, 10), "frames", length(q$data_frames), "\n")
# stream emit
st <- grpc_stream(c1, "/s.S/M", as.raw(9), deadline = 0.0015)
q <- last_req(); for (p in q$headers) cat("   ", p[[1]], "=[", p[[2]], "]\n", sep = ""); cat("   body:", q$body_hex, "\n")
for (dl in c(1e-9, 0.001, 1, 99999.999, 100000, 1e9, 1e30)) { try(grpc_call(c1, "/s.S/M", raw(), deadline = dl), silent = TRUE); q <- last_req(); cat(dl, "->", unlist(Filter(function(p) p[[1]] == "grpc-timeout", q$headers)), "\n") }
grpc_close(c1)
c1 <- ch()
e <- tryCatch(grpc_call(c1, "/s.S/M", raw(), metadata = c(dup = "1", dup = "2")), error = function(e) e); print(class(e)); cat(conditionMessage(e), "\n")
e <- tryCatch(grpc_call(ch(headers = c(dup = "1", dup = "2")), "/s.S/M", raw()), error = function(e) e); print(class(e)); cat(conditionMessage(e), "\n")
e <- tryCatch(grpc_call(c1, "/s.S/M", raw(), metadata = c(Dup = "1", dup = "2")), error = function(e) e); print(class(e))
