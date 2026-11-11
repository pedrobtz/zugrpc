source("<W>/hunt-2/common.R")
c1 <- ch()
for (v in list(c(0x62, 0x61, 0x64, 0xff, 0x25, 0x32, 0x30, 0x78), c(0x61, 0x25, 0x46, 0x46, 0x25, 0x32, 0x30, 0x62), c(0x61, 0x09, 0x62), c(0x61, 0xe9, 0x62))) {
  set_scen(M = list(h(c(H0, list(c("x-raw", paste0("hex:", hx(as.raw(v)))), c("grpc-status", "5"), c("grpc-message", paste0("hex:", hx(as.raw(v)))))), TRUE)))
  e <- tryCatch(grpc_call(c1, "/s.S/M", raw()), error = function(e) e)
  cat("sent", hx(as.raw(v)), "->", class(e)[1], "msg bytes", if (!is.null(e$grpc_message)) hx(charToRaw(e$grpc_message)), "enc", if (!is.null(e$grpc_message)) Encoding(e$grpc_message), "| x-raw", if (!is.null(e$headers[["x-raw"]])) hx(charToRaw(e$headers[["x-raw"]])), "| cm ok:", !inherits(try(nchar(conditionMessage(e)), silent = TRUE), "try-error"), "\n")
}
