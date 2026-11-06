## Submission

This is a new submission.

zugrpc depends on two packages by the same maintainer, 'zuhttp' and
'zuproto'. They are submitted first, and zugrpc is submitted only once both
are on CRAN.

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Test environments

`R CMD check --as-cran`, on GitHub Actions through the shared
`pedrobtz/r-actions` workflows:

* macOS, R release
* Windows, R release
* Windows, R devel
* Ubuntu, R release
* Ubuntu, R oldrel-1
* r-devel containers: `clang23`, `ubuntu-clang`, `ubuntu-gcc16`
* `nosuggests` (no Suggests installed) and `nold` (no long double)

## Network use

Examples and the tests CRAN runs need no network. They use 'zuhttp''s mock
transport and recorded server responses committed under `tests/testthat/`.
The live tests against gRPC servers are skipped unless an environment
variable naming the server is set, which happens only in the package's own
CI.

## Bundled files

`inst/descriptors/` holds a protocol buffer descriptor set compiled from
Google's `google/rpc` definitions, under the Apache License 2.0. Google LLC
is listed as copyright holder in `Authors@R`, and `inst/COPYRIGHTS` gives
the source and the licence.

## Method references

There are no published references describing the methods in this package.
It implements the gRPC protocol as its specification defines it:
<https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md>.
