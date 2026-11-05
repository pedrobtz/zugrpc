# Against a Spark Connect server (design §10, §14): apache/spark 4.2.1 in
# Docker, started by .github/workflows/live.yaml.

spark_pool <- function() {
  path <- test_path("fixtures", "spark", "spark-connect.binpb")
  skip_if_not(file.exists(path), "the Spark Connect descriptors are absent")
  zuproto::proto_pool(path)
}

spark_execute <- function(query, pool) {
  zuproto::proto_encode(
    list(
      session_id = "6ec0bd7f-11c0-43da-975e-2a8ad9ebae0b",
      user_context = list(user_id = "zugrpc"),
      client_type = "zugrpc-test",
      plan = list(root = list(sql = list(query = query)))
    ),
    "spark.connect.ExecutePlanRequest",
    pool
  )
}

execute_plan <- "/spark.connect.SparkConnectService/ExecutePlan"

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
  complete <- FALSE
  while (!is.null(m <- st$next_message())) {
    res <- zuproto::proto_decode(m, "spark.connect.ExecutePlanResponse", pool)
    if (!is.null(res$arrow_batch)) {
      rows <- rows + res$arrow_batch$row_count
    }
    if (!is.null(res$result_complete)) {
      complete <- TRUE
    }
  }
  expect_identical(st$status(), "OK")
  expect_equal(rows, 1000)
  expect_true(complete)
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
