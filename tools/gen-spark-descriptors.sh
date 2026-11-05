#!/bin/sh
# Builds tests/testthat/fixtures/spark/spark-connect.binpb, the descriptor
# set the Spark Connect live test encodes and decodes its messages with.
# Run from the package root; needs curl and protoc. Spark is pinned to the
# tag the live test's Docker image runs. The file is test-only and is left
# out of the package tarball (.Rbuildignore).
set -eu

SPARK_TAG=v4.2.1
FILES="base catalog commands common expressions ml ml_common pipelines relations types"
SRC=sql/connect/common/src/main/protobuf/spark/connect
OUT=tests/testthat/fixtures/spark/spark-connect.binpb

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/spark/connect" "$(dirname "$OUT")"

protos=""
for f in $FILES; do
  curl -fsSL -o "$tmp/spark/connect/$f.proto" \
    "https://raw.githubusercontent.com/apache/spark/$SPARK_TAG/$SRC/$f.proto"
  protos="$protos spark/connect/$f.proto"
done

# No --include_imports: the imports are well-known types, which every
# zuproto pool holds.
(cd "$tmp" && protoc --proto_path=. --descriptor_set_out=out.binpb $protos)
cp "$tmp/out.binpb" "$OUT"
echo "wrote $OUT with $(protoc --version), Spark $SPARK_TAG"
