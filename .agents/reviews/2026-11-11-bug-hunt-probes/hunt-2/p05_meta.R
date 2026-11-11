source("<W>/hunt-2/common.R")
M <- frs("hi")
c1 <- ch()
md <- function(hk, tk = list()) {
  set_scen(M = list(h(c(H0, hk)), d(M), h(c(TOK, tk), TRUE)))
  cat("-- unary\n"); r <- show(grpc_call(c1, "/s.S/M", raw())[c("headers", "trailers")])
  cat("-- stream\n"); show({ st <- grpc_stream(c1, "/s.S/M", raw()); drain(st); list(headers = st$headers(), trailers = st$trailers()) })
  invisible(r)
}
cat("### repeated vs comma-joined\n")
md(list(c("x-a", "1"), c("x-a", "2"), c("x-b", "1, 2"), c("k-bin", "QQ"), c("k-bin", "Qg=="), c("j-bin", "QQ,Qg==")), list(c("x-a", "t1"), c("x-a", "t2")))
cat("### base64 variants\n")
for (v in c("", "QQ", "QQ=", "QQ==", "QQ===", "Q", "QUJD", "QUJD=", "QUI", "QUI=", "QR", "Q Q", "QQ, Qg", "QQ,", ",QQ", "QQ,,Qg", ",", "Q_-Q", "QQ==QQ==", "QQ,!!", "=", "==", "A===")) {
  set_scen(M = list(h(c(H0, list(c("v-bin", v)))), d(M), h(TOK, TRUE)))
  cat(sprintf("v-bin='%s': ", v))
  w <- NULL; r <- withCallingHandlers(grpc_call(c1, "/s.S/M", raw())$headers, warning = function(x) { w <<- class(x)[1]; invokeRestart("muffleWarning") })
  cat(length(r), "entries:", paste(names(r), vapply(r, hx, ""), sep = "=", collapse = " | "), if (!is.null(w)) paste("WARN", w), "\n")
}
cat("### reserved / case / odd names\n")
md(list(c("grpc-foo", "x"), c("grpc-encoding", "identity"), c("te", "x"), c("host", "h"), c("connection-x", "ok"), c("x-utf", "café"), c("x-empty", ""), c("date", "d"), c("server", "s"), c("content-length", "7"), c("user-agent", "srv"), c("bin", "notbin"), c("-bin", "QQ")),
   list(c("grpc-status-details-bin", "CAU"), c("x-tr-bin", "AAEC"), c("content-type", "x")))
cat("### grpc-message decoding\n")
for (m in list("plain", "a%20b", "%E4%BD%A0%e5%a5%bd", "100%", "%zz", "%4", "%00x", "a%0Ab", "%FF", "café", "café%20x", "%25", "%2541", "a+b", "", "%E4%BD")) {
  set_scen(M = list(h(c(H0, list(c("grpc-status", "5"), c("grpc-message", m))), TRUE)))
  e <- tryCatch(grpc_call(c1, "/s.S/M", raw()), error = function(e) e)
  cat(sprintf("  '%s' -> [%s] enc=%s bytes=%s\n", m, e$grpc_message, Encoding(e$grpc_message), hx(charToRaw(e$grpc_message))))
}
# raw invalid utf8 bytes in grpc-message, unencoded
set_scen(M = list(h(c(H0, list(c("grpc-status", "5"), c("grpc-message", "bad\xff\xfebyte"))), TRUE)))
