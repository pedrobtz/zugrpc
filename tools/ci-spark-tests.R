# The Spark Connect live tests against the installed package and the server
# live.yaml started. A test that skips here is a failure.
results <- as.data.frame(testthat::test_dir(
  "tests/testthat",
  package = "zugrpc",
  load_package = "installed",
  filter = "spark",
  reporter = "summary",
  stop_on_failure = TRUE
))
if (nrow(results) == 0L || any(results$skipped)) {
  stop(
    "Spark tests were skipped: ",
    paste(results$test[results$skipped], collapse = "; ")
  )
}
cat(sprintf("%d Spark tests ran\n", nrow(results)))
