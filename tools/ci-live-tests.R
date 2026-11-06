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

# The one allowed skip: a TLS backend that cannot take a private CA, today
# Windows' Schannel (zuhttp#5). It is allowed only where zuhttp says so, so
# the test still has to run everywhere else.
allowed <- character()
if (!"ca_file" %in% zuhttp::zu_info()$tls_capabilities) {
  allowed <- "live: tls = zu_tls(ca_file =) trusts a private CA"
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
