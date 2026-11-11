source("<W>/hunt-2/common.R")
c1 <- ch(); pool <- zugrpc:::rpc_pool(); b64 <- zugrpc:::base64_encode
any_ <- function(type, msg, prefix = "type.googleapis.com/") list(type_url = paste0(prefix, type), value = zuproto::proto_encode(msg, type, pool))
enc <- function(s) zuproto::proto_encode(s, "google.rpc.Status", pool)
ei <- any_("google.rpc.ErrorInfo", list(reason = "R", domain = "d", metadata = c(k = "v")))
cases <- list(
  basic = b64(enc(list(code = 5L, message = "m", details = list(ei)))),
  two_same = b64(enc(list(code = 5L, details = list(ei, ei)))),
  unknown_type = b64(enc(list(code = 5L, details = list(list(type_url = "type.googleapis.com/foo.Bar", value = as.raw(1:3)))))),
  empty_url = b64(enc(list(code = 5L, details = list(list(type_url = "", value = raw()))))),
  empty = "", code_mismatch = b64(enc(list(code = 3L, message = "other"))),
  good_plus_bad = b64(enc(list(code = 5L, message = "keepme", details = list(ei, list(type_url = "type.googleapis.com/google.rpc.RetryInfo", value = as.raw(c(0xff, 0xff))))))),
  utf8msg = b64(enc(list(code = 5L, message = "caf\u00e9")))
)
for (n in names(cases)) {
  cat(n, ":\n")
  set_scen(M = list(h(c(H0, list(c("grpc-status", "5"), c("grpc-message", "gm"), c("grpc-status-details-bin", cases[[n]]))), TRUE)))
  e <- withCallingHandlers(tryCatch(grpc_call(c1, "/s.S/M", raw()), error = function(e) e), warning = function(w) { cat("   WARN", class(w)[1], "\n"); invokeRestart("muffleWarning") })
  str(e$details, max.level = 3); if (n == "utf8msg") cat(Encoding(e$details$message), hx(charToRaw(e$details$message)), "\n")
}
# C-locale header value marking
set_scen(M = list(h(c(H0, list(c("x-utf", "caf\u00e9"), c("grpc-status", "5"), c("grpc-message", "caf\u00e9"))), TRUE)))
e <- tryCatch(grpc_call(c1, "/s.S/M", raw()), error = function(e) e)
cat("locale", Sys.getlocale("LC_CTYPE"), "x-utf bytes", hx(charToRaw(e$headers[["x-utf"]])), Encoding(e$headers[["x-utf"]]), "| msg", hx(charToRaw(e$grpc_message)), Encoding(e$grpc_message), "\n")
