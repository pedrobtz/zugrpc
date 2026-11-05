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
if (nrow(live) == 0L || any(live$skipped)) {
  stop(
    "live tests were skipped: ",
    paste(live$test[live$skipped], collapse = "; ")
  )
}
cat(sprintf("%d live tests ran\n", nrow(live)))
