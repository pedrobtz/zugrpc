source("<W>/hunt-2/common.R")
M <- frs("hi"); M2 <- frs("yo")
seqp <- function(name, steps) {
  cat(name, "\n"); set_scen(M = steps)
  c1 <- ch(); on.exit(grpc_close(c1))
  urun(c1, "/s.S/M")
  got <- character(); st <- NULL
  r <- tryCatch({ st <- grpc_stream(c1, "/s.S/M", raw()); repeat { x <- st$next_message(); if (is.null(x)) break; got <- c(got, rawToChar(x)) }; "END" },
    error = function(e) paste0("ERR <", paste(head(class(e), 2), collapse = ","), "> ", conditionMessage(e)))
  cat("  stream: [", paste(got, collapse = "|"), "] ", r, "\n", sep = "")
  if (!is.null(st)) {
    again <- tryCatch({ x <- st$next_message(); if (is.null(x)) "NULL" else rawToChar(x) }, error = function(e) paste0("ERR ", class(e)[1]))
    cat("    after: status=", deparse(st$status()), " trailers=", deparse(names(st$trailers())), " next again=", again, " open streams=", length(ls(c1$streams)), "\n", sep = "")
    capture.output(print(st)) -> p; cat("    ", p[2], "\n")
  }
  # the channel must still work
  set_scen(M = list(h(H0), d(M), h(TOK, TRUE))); cat("    channel reuse: "); urun(c1, "/s.S/M")
}
seqp("RST(CANCEL=8) after last message, before trailers", list(h(H0), d(M), list(sleep = 100), list(rst = 8)))
seqp("RST(NO_ERROR=0) after message", list(h(H0), d(M), list(sleep = 100), list(rst = 0)))
seqp("RST(REFUSED=7) before headers", list(list(rst = 7)))
seqp("RST(ENHANCE_YOUR_CALM=11) mid message", list(h(H0), d("0000000005aa"), list(sleep = 100), list(rst = 11)))
seqp("GOAWAY(NO_ERROR, last=this) mid-stream then finish", list(h(H0), d(M), list(goaway = 0, sleep = 100), d(M2), h(TOK, TRUE)))
seqp("GOAWAY(ENHANCE_YOUR_CALM) then close", list(h(H0), d(M), list(goaway = 11, sleep = 100), list(close = TRUE)))
seqp("conn close after message", list(h(H0), d(M), list(sleep = 100), list(close = TRUE)))
seqp("conn close before headers", list(list(close = TRUE)))
seqp("second HEADERS block (non-final, no END_STREAM) then data, trailers", list(h(H0), h(list(c("x-second", "1"))), d(M), h(TOK, TRUE)))
seqp("1xx (103) then headers", list(h(list(c(":status", "103"), c("x-early", "1"))), h(H0), d(M), h(TOK, TRUE)))
seqp("100 then headers", list(h(list(c(":status", "100"))), h(H0), d(M), h(TOK, TRUE)))
seqp("DATA after trailers", list(h(H0), d(M), h(TOK, TRUE), d(M2, TRUE)))
seqp("trailers without END_STREAM then more data+trailers", list(h(H0), d(M), h(list(c("grpc-status", "5"))), d(M2), h(TOK, TRUE)))
seqp("DATA before HEADERS", list(d(M), h(H0), h(TOK, TRUE)))
seqp("trailers with :status pseudo", list(h(H0), d(M), h(list(c(":status", "200"), c("grpc-status", "0")), TRUE)))
seqp("empty DATA frames interleaved", list(h(H0), d(""), d(M, chunk = 1), d(""), h(TOK, TRUE)))
seqp("message then long stall then trailers (200ms)", list(h(H0), d(M), list(sleep = 200), h(list(c("grpc-status", "14"), c("grpc-message", "bye")), TRUE)))
