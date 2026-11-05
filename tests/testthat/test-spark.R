# Against a Spark Connect server (design §10, §14): apache/spark 4.2.1 in
# Docker, started by .github/workflows/live.yaml.

test_that("spark: ExecutePlan streams Arrow batches and ends OK", {
  ch <- grpc_channel(live_server("ZU_SPARK_TEST_SERVER"))
  withr::defer(grpc_close(ch))
  pool <- spark_pool()

  st <- grpc_stream(
    ch,
    execute_plan,
    spark_execute("SELECT id FROM range(1000)", pool),
    deadline = 120
  )
  rows <- 0
  while (!is.null(m <- st$next_message())) {
    res <- zuproto::proto_decode(m, "spark.connect.ExecutePlanResponse", pool)
    if (!is.null(res$arrow_batch)) {
      rows <- rows + res$arrow_batch$row_count
    }
  }
  expect_identical(st$status(), "OK")
  # No ResultComplete: Spark sends it only to a reattachable execution.
  expect_equal(rows, 1000)
})

test_that("spark: an invalid plan raises Spark's ErrorInfo", {
  ch <- grpc_channel(live_server("ZU_SPARK_TEST_SERVER"))
  withr::defer(grpc_close(ch))
  pool <- spark_pool()

  st <- grpc_stream(
    ch,
    execute_plan,
    spark_execute("SELECT * FROM zugrpc_no_such_table", pool),
    deadline = 120
  )
  cnd <- tryCatch(
    {
      while (!is.null(st$next_message())) {}
      NULL
    },
    zugrpc_error = identity
  )
  expect_s3_class(cnd, "zugrpc_error_status")
  info <- cnd$details$details$ErrorInfo
  expect_identical(info$domain, "org.apache.spark")
  expect_identical(info$metadata[["errorClass"]], "TABLE_OR_VIEW_NOT_FOUND")
  expect_identical(info$metadata[["sqlState"]], "42P01")
})
