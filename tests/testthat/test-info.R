test_that("zugrpc_info() reports zuhttp, HTTP/2 and the TLS backend", {
  info <- zugrpc_info()
  expect_s3_class(info, "zugrpc_info")
  expect_identical(info$zuhttp, as.character(utils::packageVersion("zuhttp")))
  expect_true(info$http2)
  expect_type(info$tls_backend, "character")
  expect_output(print(info), "HTTP/2: +yes")
})
