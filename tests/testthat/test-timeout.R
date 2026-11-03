test_that("grpc_timeout() picks the finest unit that fits eight digits", {
  expect_identical(grpc_timeout(0.000000001), "1n")
  expect_identical(grpc_timeout(0.05), "50000000n")
  expect_identical(grpc_timeout(0.1), "100000u")
  expect_identical(grpc_timeout(1), "1000000u")
  expect_identical(grpc_timeout(30), "30000000u")
  expect_identical(grpc_timeout(600), "600000m")
  expect_identical(grpc_timeout(100000), "100000S")
  expect_identical(grpc_timeout(1e9), "16666667M")
  expect_identical(grpc_timeout(1e10), "2777778H")
})

test_that("grpc_timeout() uses each of the six units", {
  units <- vapply(
    c(1e-9, 1e-1, 1000, 1e6, 1e9, 1e12),
    function(s) substring(grpc_timeout(s), nchar(grpc_timeout(s))),
    character(1)
  )
  expect_identical(units, c("n", "u", "m", "S", "M", "H"))
})

test_that("grpc_timeout() rounds up, never down", {
  expect_identical(grpc_timeout(0.1000001), "100001u")
  expect_identical(grpc_timeout(1e-10), "1n")
})

test_that("grpc_timeout() caps at the largest value the header can carry", {
  expect_identical(grpc_timeout(1e20), "99999999H")
})

test_that("grpc_timeout() of zero is 0n", {
  expect_identical(grpc_timeout(0), "0n")
})

test_that("deadline_seconds() takes seconds or an absolute POSIXct", {
  expect_identical(deadline_seconds(30), 30)
  now <- as.POSIXct("2026-11-03 12:00:00", tz = "UTC")
  expect_identical(deadline_seconds(now + 90, now = now), 90)
  expect_identical(deadline_seconds(now - 5, now = now), 0)
  expect_null(deadline_seconds(NULL))
})

test_that("deadline_seconds() rejects bad deadlines", {
  for (d in list(-1, NA_real_, c(1, 2), "30", Inf)) {
    expect_error(deadline_seconds(d), class = "zugrpc_error_argument")
  }
})
