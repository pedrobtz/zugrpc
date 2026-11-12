# The whole test suite against the installed package, with the live servers
# that tools/ci-live.sh started. A live test that skips here is a failure:
# the point of the run is that none does.
results <- as.data.frame(testthat::test_dir(
  "tests/testthat",
  package = "zugrpc",
  load_package = "installed",
  reporter = "summary",
  stop_on_failure = TRUE
))
live <- results[results$file == "test-live.R", ]

# The allowed skips, each only where the platform cannot run the test, so
# it still has to run everywhere else: a TLS backend that cannot take a
# private CA, today Windows' Schannel (zuhttp#5); and fork(), which Windows
# does not have.
allowed <- character()
if (!"ca_file" %in% zuhttp::zu_info()$tls_capabilities) {
  allowed <- c(allowed, "live: tls = zu_tls(ca_file =) trusts a private CA")
}
if (.Platform$OS.type == "windows") {
  allowed <- c(
    allowed,
    "live: a forked child leaves the parent's channel and stream alone"
  )
}
skipped <- live$skipped & !live$test %in% allowed
if (nrow(live) == 0L || any(skipped)) {
  stop(
    "live tests were skipped: ",
    paste(live$test[skipped], collapse = "; ")
  )
}
cat(sprintf(
  "%d live tests ran, %d skipped as allowed\n",
  sum(!live$skipped),
  sum(live$skipped)
))
