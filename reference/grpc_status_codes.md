# gRPC status codes

The 17 status codes a gRPC call can end with, as the gRPC specification
defines them. A failed call raises a condition of class
`zugrpc_error_<name>` in lower case, for example
`zugrpc_error_unavailable`.

## Usage

``` r
grpc_status_codes()
```

## Value

A data frame with one row per code and columns `code` (integer), `name`
and `description` (character).

## Examples

``` r
grpc_status_codes()
#>    code                name
#> 1     0                  OK
#> 2     1           CANCELLED
#> 3     2             UNKNOWN
#> 4     3    INVALID_ARGUMENT
#> 5     4   DEADLINE_EXCEEDED
#> 6     5           NOT_FOUND
#> 7     6      ALREADY_EXISTS
#> 8     7   PERMISSION_DENIED
#> 9     8  RESOURCE_EXHAUSTED
#> 10    9 FAILED_PRECONDITION
#> 11   10             ABORTED
#> 12   11        OUT_OF_RANGE
#> 13   12       UNIMPLEMENTED
#> 14   13            INTERNAL
#> 15   14         UNAVAILABLE
#> 16   15           DATA_LOSS
#> 17   16     UNAUTHENTICATED
#>                                                      description
#> 1                             Not an error; returned on success.
#> 2          The operation was cancelled, typically by the caller.
#> 3                                                 Unknown error.
#> 4                      The client specified an invalid argument.
#> 5      The deadline expired before the operation could complete.
#> 6                           Some requested entity was not found.
#> 7   The entity that a client attempted to create already exists.
#> 8  The caller does not have permission to execute the operation.
#> 9                              Some resource has been exhausted.
#> 10      The system is not in a state required for the operation.
#> 11                                    The operation was aborted.
#> 12             The operation was attempted past the valid range.
#> 13            The operation is not implemented or not supported.
#> 14                                               Internal error.
#> 15                         The service is currently unavailable.
#> 16                        Unrecoverable data loss or corruption.
#> 17   The request does not have valid authentication credentials.
```
