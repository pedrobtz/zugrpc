source(file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE))), "common.R"))
ch <- grpc_channel(URL, headers = c(authorization = "Bearer SECRET-TOKEN"))
f <- tempfile(fileext = ".rds")
rt <- function(x) { saveRDS(x, f); readRDS(f) }
cat("## A: channel round trip (same session)\n")
show("call orig", grpc_call(ch, M, raw())$message)
c2 <- show("saveRDS/readRDS", rt(ch))$ok; cat("size:", file.size(f), " token in file:", any(grepl("SECRET-TOKEN", rawToChar(memDecompress(readBin(f, "raw", 1e6), "gzip")[memDecompress(readBin(f, "raw", 1e6), "gzip") != 0]), fixed = TRUE)), "\n")
if (!is.null(c2)) { print(c2); r <- show("call on copy", grpc_call(c2, M, raw())$message); if (!is.null(r$err)) print(class(r$err))
  r <- show("stream on copy", scn(c2, "h,m1,t0")); show("close copy", grpc_close(c2)); print(c2); cat("orig closed?", ch$closed, "\n") }
show("call orig after", grpc_call(ch, M, raw())$message); snew()
cat("## B: stream round trip: open (1 of 3 read)\n")
s <- scn(ch, "h,m3,s300,m1,t0"); invisible(s$next_message()); s2 <- show("rt", rt(s))$ok
if (!is.null(s2)) { print(s2); for (i in 1:5) { r <- show(paste(" copy next", i), s2$next_message()) }; if (!is.null(r$err)) print(class(r$err)); state(s2); show(" copy cancel", s2$cancel()); state(s2) }
for (i in 1:5) show(paste(" orig next", i), s$next_message()); state(s); snew()
cat("## C: ended stream round trip\n")
s2 <- rt(s); print(s2); show("next", s2$next_message()); show("status", s2$status()); show("trailers", names(s2$trailers())); show("cancel", s2$cancel())
cat("## D: cancelled stream round trip\n")
s <- scn(ch, "h,m3,w"); s$cancel(); s2 <- rt(s); print(s2); show("next", s2$next_message())
cat("## E: open stream copy: cancel on copy, then GC copy: does it RST the ORIGINAL's wire stream?\n")
s <- scn(ch, "h,m1,s500,m1,t0"); s2 <- rt(s); show("copy cancel", s2$cancel()); rm(s2); invisible(gc()); for (i in 1:3) show(" orig next", s$next_message()); snew()
cat("## F: fresh session load\n"); s <- scn(ch, "h,m3,w"); invisible(s$next_message()); saveRDS(list(ch = ch, s = s), file.path(W, "p09.rds"))
out <- system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(sprintf('.libPaths(c("%s", .libPaths())); library(zugrpc); x <- readRDS("%s"); print(x$ch); print(x$s); for (e in list(quote(grpc_call(x$ch, "/t.S/M", raw())), quote(x$s$next_message()), quote(x$s$next_message()), quote(x$s$next_message()), quote(x$s$next_message()), quote(x$s$cancel()), quote(grpc_close(x$ch)), quote(grpc_stream(x$ch, "/t.S/M", raw())))) { r <- tryCatch(eval(e), error = function(e) e); cat(deparse(e), "->", if (inherits(r, "condition")) paste("ERR", paste(class(r), collapse = ","), conditionMessage(r)) else paste(format(r), collapse = " "), "\n") }', file.path(dirname(W), "lib"), file.path(W, "p09.rds")))), stdout = TRUE, stderr = TRUE)
cat(out, sep = "\n"); snew()
