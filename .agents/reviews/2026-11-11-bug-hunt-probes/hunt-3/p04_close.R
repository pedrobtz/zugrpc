source(file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE))), "common.R"))
ch <- grpc_channel(URL)
s_open   <- scn(ch, "h,m3,w")                      # open, nothing read
s_part   <- scn(ch, "h,m3,w"); invisible(s_part$next_message())   # open, 2 buffered
s_ended  <- scn(ch, "h,m1,t0"); while (!is.null(s_ended$next_message())) {}  # ended OK
s_canc   <- scn(ch, "h,m1,w"); s_canc$cancel()     # cancelled
s_err    <- scn(ch, "h,b,w"); try(s_err$next_message(), silent = TRUE)  # failed
s_st     <- scn(ch, "h,t5"); try(s_st$next_message(), silent = TRUE)    # non-OK
s_full   <- scn(ch, "h,m3,t0"); invisible(s_full$next_message()); Sys.sleep(.2) # body fully arrived (server done), 2 unread
s_drop   <- scn(ch, "h,m1,w")                      # will be dropped after close
print(ch); snew()
cat("## grpc_close\n"); r <- withVisible(grpc_close(ch)); cat("visible:", r$visible, " identical:", identical(r$value, ch), "\n"); print(ch); snew()
for (nm in c("s_open", "s_part", "s_ended", "s_canc", "s_err", "s_st", "s_full")) {
  s <- get(nm); cat("# ", nm, " before read after close: "); print(s)
  show("  status", s$status()); show("  headers", length(s$headers()))
  show("  next", s$next_message()); show("  next", s$next_message()); show("  cancel", s$cancel()); show("  next", s$next_message()); state(s)
}
cat("## close twice, close then cancel on untouched stream, GC of dropped\n")
grpc_close(ch); s2 <- s_drop; rm(s_drop); show("cancel", s2$cancel()); state(s2); show("next", s2$next_message()); rm(s2, s); invisible(gc()); snew()
cat("## calls on closed channel\n")
show("call", grpc_call(ch, M, raw())); show("stream", scn(ch, "h,m1,t0")); print(ch)
cat("## new channel, same URL works\n"); ch2 <- grpc_channel(URL); show("call", grpc_call(ch2, M, raw())$message); snew()
cat("## close with caller's client: caller's pool untouched?\n")
cl <- zuhttp::zu_client(http2 = "required", check = FALSE)
rq <- zuhttp::zu_body_raw(zuhttp::zu_headers(zuhttp::zu_request("POST", paste0(URL, M)), te = "trailers"), as.raw(c(0,0,0,0,0)), type = "application/grpc")
invisible(zuhttp::zu_perform(rq, client = cl)); cA <- grpc_channel(URL, client = cl); cB <- grpc_channel(URL, client = cl)
invisible(grpc_call(cA, M, raw())); invisible(grpc_call(cB, M, raw())); snew(); grpc_close(cA); cat("after close(cA):\n"); snew()
invisible(zuhttp::zu_perform(rq, client = cl)); invisible(grpc_call(cB, M, raw())); snew()
