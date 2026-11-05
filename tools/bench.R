# The performance measurements of design §11, reported in
# vignettes/articles/performance.Rmd. Run from the package root against
# grpc-go's interop server and tools/test-server over h2c:
#
#   Rscript tools/bench.R http://127.0.0.1:50051 http://127.0.0.1:50052
#
# It prints one line per target.
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-live.R")

args <- commandArgs(trailingOnly = TRUE)
interop <- if (length(args) >= 1L) args[[1]] else "http://127.0.0.1:50051"
status <- if (length(args) >= 2L) args[[2]] else "http://127.0.0.1:50052"
svc <- "/grpc.testing.TestService/"

ms <- function(t) sprintf("%.3f ms", 1000 * t)
# Sys.time() has microsecond resolution; proc.time() here has 1 ms.
elapsed <- function(expr) {
  t0 <- Sys.time()
  force(expr)
  as.numeric(Sys.time()) - as.numeric(t0)
}
# Peak R heap above the start, in MiB, while running `expr`.
# gc()'s columns differ between R versions; "max used" in Mb is the last.
peak_mib <- function(expr) {
  g <- gc(reset = TRUE)
  base <- sum(g[, 2])
  force(expr)
  g <- gc()
  sum(g[, ncol(g)]) - base
}

ch <- grpc_channel(interop, keepalive = NULL)
cat(sprintf("zugrpc %s, zuhttp %s, %s, %s\n",
  utils::packageVersion("zugrpc"), utils::packageVersion("zuhttp"),
  R.version.string, utils::sessionInfo()$running))

# 1. Unary overhead: grpc_call() against the zu_perform() it wraps, the same
#    EmptyCall on the same pooled connection. Medians of alternating runs.
req <- build_request(ch, paste0(svc, "EmptyCall"), raw(), NULL, NULL)$request
n <- 2000L
for (i in 1:200) grpc_call(ch, paste0(svc, "EmptyCall"), raw())
t_zu <- t_grpc <- numeric(n)
for (i in seq_len(n)) {
  t_zu[i] <- elapsed(zuhttp::zu_perform(req, client = ch$client))
  t_grpc[i] <- elapsed(grpc_call(ch, paste0(svc, "EmptyCall"), raw()))
}
cat(sprintf(
  "unary: zu_perform() median %s, grpc_call() median %s, overhead %s\n",
  ms(median(t_zu)), ms(median(t_grpc)), ms(median(t_grpc) - median(t_zu))
))

# 2. 1 GiB as 64 messages of 16 MiB: time, and the peak heap while reading.
big <- streaming_request(rep(16 * 1024^2, 64))
bytes <- 0
held <- 0
peak <- peak_mib({
  t_big <- elapsed({
    st <- grpc_stream(ch, paste0(svc, "StreamingOutputCall"), big)
    base <- sum(gc()[, 2])
    while (!is.null(m <- st$next_message())) {
      bytes <- bytes + length(m)
      # What the iterator holds, with this message: live memory after a
      # full collection, above what was live before the call.
      held <- max(held, sum(gc()[, 2]) - base)
      rm(m)
    }
  })
})
cat(sprintf(
  "1 GiB in 16 MiB messages: %.0f MiB in %.2f s, live at most %.0f MiB, peak heap %.0f MiB\n",
  bytes / 1024^2, t_big, held, peak
))

# 3. Many small messages: time per message at 10,000 and 100,000. Linear
#    cost keeps the two close.
per_message <- function(k) {
  req <- streaming_request(rep(1, k))
  count <- 0L
  t <- elapsed({
    st <- grpc_stream(ch, paste0(svc, "StreamingOutputCall"), req)
    while (!is.null(st$next_message())) count <- count + 1L
  })
  stopifnot(count == k)
  t / k
}
small_10k <- per_message(1e4)
small_100k <- per_message(1e5)
cat(sprintf(
  "small messages: %.1f us each at 10,000, %.1f us each at 100,000 (ratio %.2f)\n",
  1e6 * small_10k, 1e6 * small_100k, small_100k / small_10k
))

# 4. $cancel() on a stream whose server has stalled after its headers.
sch <- grpc_channel(status, keepalive = NULL)
t_cancel <- vapply(seq_len(20), function(i) {
  st <- grpc_stream(sch, "/zugrpc.test.Status/Stall", raw(), deadline = 30)
  elapsed(st$cancel())
}, numeric(1))
cat(sprintf("cancel: median %s, max %s over 20\n", ms(median(t_cancel)), ms(max(t_cancel))))

# 5. Many small messages in each read, offline through zuhttp's mock: a
#    64 KiB read of 1-byte messages queues about 11,000 at once, so popping
#    them must not copy the queue (review #34). Microseconds per message.
in_one_read <- function(k) {
  body <- rep(as.raw(c(0, 0, 0, 0, 1, 7)), k)
  fake <- zuhttp::zu_mock_transport(function(req) {
    zuhttp::zu_response(
      200L,
      headers = c("content-type" = "application/grpc"),
      body = body,
      trailers = c("grpc-status" = "0")
    )
  })
  mch <- grpc_channel("http://localhost:1", client = zuhttp::zu_client(transport = fake))
  st <- grpc_stream(mch, "/a.B/C", raw())
  elapsed(while (!is.null(st$next_message())) NULL) / k
}
cat(sprintf(
  "small messages, offline: %.1f us each at 10,000, %.1f us each at 50,000\n",
  1e6 * in_one_read(1e4), 1e6 * in_one_read(5e4)
))
