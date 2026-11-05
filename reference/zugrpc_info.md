# What this installation of zugrpc can do

Reports the `zuhttp` that carries zugrpc's calls: its version, whether
it speaks HTTP/2, which gRPC requires, and its TLS backend.

## Usage

``` r
zugrpc_info()
```

## Value

A list with elements `version` (zugrpc's, a string), `zuhttp` (its
version, a string), `http2` (logical), `tls_backend` (a string) and
`tls_capabilities` (character), printed as a short report.

## See also

[`zuhttp::zu_info()`](https://pedrobtz.github.io/zuhttp/reference/zu_info.html)
for the full transport report.

## Examples

``` r
zugrpc_info()
#> zugrpc 0.0.0.9000 on zuhttp 0.1.0
#>   HTTP/2:      yes
#>   TLS backend: openssl
```
