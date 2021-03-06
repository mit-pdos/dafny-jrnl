#!/usr/bin/env bash
set -eu

# Compiles from Dafny to Go.
#
# The rest of the compilation is redundantly run by the benchmarking scripts,
# but we run it here to cache the build.

if [ ! -d "$DAISY_NFSD_PATH" ]; then
    echo "DAISY_NFSD_PATH is unset" 1>&2
    exit 1
fi
if [ ! -d "$GO_NFSD_PATH" ]; then
    echo "GO_NFSD_PATH is unset" 1>&2
    exit 1
fi

cd "$GO_NFSD_PATH"
go build ./cmd/fs-smallfile
go build ./cmd/fs-largefile

cd "$DAISY_NFSD_PATH"
make compile
go build ./cmd/daisy-nfsd
rm daisy-nfsd
