source("<W>/hunt-2/common.R")
print(Sys.getlocale())
M <- frs("hi")
c1 <- ch()
one <- function(hk, tk = list()) {
  set_scen(M = list(h(c(H0, hk)), d(M), h(c(TOK, tk), TRUE)))
  r <- tryCatch(withCallingHandlers(grpc_call(c1, "/s.S/M", raw()), warning = function(w) { cat("   WARN", class(w)[1], "\n"); invokeRestart("muffleWarning") }), error = function(e) e)
  if (inherits(r, "error")) cat("  ", deparse(hk), "-> ERR", class(r)[1], conditionMessage(r), "\n") else cat("  ", vapply(hk, paste, "", collapse = ":"), "/", vapply(tk, paste, "", collapse = ":"), "-> headers {", paste(names(r$headers), vapply(r$headers, function(x) if (is.raw(x)) hx(x) else paste0(x, "(", Encoding(x), ")"), ""), sep = "=", collapse = ", "), "} trailers {", paste(names(r$trailers), vapply(r$trailers, function(x) if (is.raw(x)) hx(x) else x, ""), sep = "=", collapse = ", "), "}\n")
}
for (kv in list(c("grpc-foo", "x"), c("grpc-encoding", "identity"), c("te", "trailers"), c("host", "h"), c("connection-x", "ok"), c("x-utf", "café"), c("x-empty", ""), c("date", "d"), c("server", "s"), c("user-agent", "srv"), c("bin", "notbin"), c("-bin", "QQ"), c("x-bin-x", "notb64!"), c("X-Upper", "v"), c("content-length", "7"), c("set-cookie", "a=b"), c("x-sp", "a  b"), c("x-latin", "\xe9"))) one(list(kv))
one(list(), list(c("grpc-status-details-bin", "CAU"), c("x-tr-bin", "AAEC"), c("content-type", "x"), c("grpc-zzz", "1")))
cat("### grpc-message\n")
for (m in list("café", "café%20x", "%E4%BD%A0", "bad\xff", "%C3%A9té")) {
  set_scen(M = list(h(c(H0, list(c("grpc-status", "5"), c("grpc-message", m))), TRUE)))
  e <- tryCatch(grpc_call(c1, "/s.S/M", raw()), error = function(e) e)
  cat(sprintf("  -> class %s enc=%s valid=%s bytes=%s\n", class(e)[1], Encoding(e$grpc_message), validUTF8(e$grpc_message), hx(charToRaw(e$grpc_message))))
}
cat("### details\n")
.libPaths(); suppressPackageStartupMessages(library(zuproto))
pool <- zugrpc:::rpc_pool()
b64 <- zugrpc:::base64_encode
any_ <- function(type, msg, prefix = "type.googleapis.com/") list(type_url = paste0(prefix, type), value = zuproto::proto_encode(msg, type, pool))
enc <- function(s) zuproto::proto_encode(s, "google.rpc.Status", pool)
ei <- any_("google.rpc.ErrorInfo", list(reason = "R", domain = "d", metadata = c(k = "v")))
cases <- list(
  basic = b64(enc(list(code = 5L, message = "m", details = list(ei)))),
  padded = paste0(b64(enc(list(code = 5L, message = "mm"))), "="),
  two_same = b64(enc(list(code = 5L, details = list(ei, ei)))),
  no_slash = b64(enc(list(code = 5L, details = list(any_("google.rpc.ErrorInfo", list(reason = "R"), prefix = ""))))),
  unknown_type = b64(enc(list(code = 5L, details = list(list(type_url = "type.googleapis.com/foo.Bar", value = as.raw(1:3)))))),
  bad_value_known = b64(enc(list(code = 5L, details = list(ei, list(type_url = "type.googleapis.com/google.rpc.RetryInfo", value = as.raw(c(0xff, 0xff))))))),
  empty_url = b64(enc(list(code = 5L, details = list(list(type_url = "", value = raw()))))),
  empty = "",
  garbage = "!!!!",
  notproto = b64(as.raw(c(0xff, 0xff, 0xff))),
  code_mismatch = b64(enc(list(code = 3L, message = "other"))),
  comma_two = paste0(b64(enc(list(code = 5L, message = "a"))), ",", b64(enc(list(code = 5L, message = "b"))))
)
for (n in names(cases)) {
  cat(" ", n, ":\n")
  set_scen(M = list(h(c(H0, list(c("grpc-status", "5"), c("grpc-message", "gm"), c("grpc-status-details-bin", cases[[n]]))), TRUE)))
  e <- withCallingHandlers(tryCatch(grpc_call(c1, "/s.S/M", raw()), error = function(e) e), warning = function(w) { cat("   WARN", class(w)[1], conditionMessage(w), "\n"); invokeRestart("muffleWarning") })
  cat("   ", class(e)[1], "| details: "); str(e$details, max.level = 2, give.attr = FALSE, comp.str = " ", no.list = TRUE, nest.lev = 2)
}
# details in trailers with OK status / details in headers but status in trailers / stream
set_scen(M = list(h(c(H0, list(c("grpc-status-details-bin", cases$basic)))), d(M), h(list(c("grpc-status", "5")), TRUE)))
e <- tryCatch(grpc_call(c1, "/s.S/M", raw()), error = function(e) e); cat("details in headers, status in trailers: details null?", is.null(e$details), " headers names:", names(e$headers), "\n")
set_scen(M = list(h(H0), d(M), h(list(c("grpc-status", "5"), c("grpc-status-details-bin", cases$basic)), TRUE)))
e <- tryCatch(grpc_call(c1, "/s.S/M", raw()), error = function(e) e); cat("unary trailers details:", names(e$details$details), " trailers names:", names(e$trailers), "\n")
e <- tryCatch({ st <- grpc_stream(c1, "/s.S/M", raw()); drain(st) }, error = function(e) e); cat("stream trailers details:", names(e$details$details), "status()", st$status(), "trailers:", names(st$trailers()), "next:", deparse(tryCatch(st$next_message(), error = function(e) class(e)[1])), "\n")
