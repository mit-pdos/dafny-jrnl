# dafny-jrnl

[![verify](https://github.com/mit-pdos/dafny-jrnl/workflows/verify/badge.svg)](https://github.com/mit-pdos/dafny-jrnl/actions?query=workflow%3Averify)

Verifying crash-safe, concurrent code with sequential proofs. The goal is to
connect goose-nfsd's verified journal with sequential verification in Dafny: the
idea is that the journal should make reasoning sequential, in which case we can
prove applications correct using only sequential reasoning in a productive proof
system like Dafny while carrying out the complicated concurrency and
crash-safety reasoning in Perennial.

## Status

[Notes on research directions](./research.md)

[Spec for journal interface, assuming 2PL](./src/Dafny/jrnl/jrnl.s.dfy)

[Bank example](./src/Dafny/examples/bank.dfy)

[File-system example](./src/Dafny/examples/fs/byte_fs.dfy)

## Compiling

Run `make verify` to verify everything and `make compile` to compile
the file-system and bank examples to Go (the generated code goes into
`dafnygen/`).

You'll need Dafny 3 on your $PATH. Compilation additionally depends on
goimports to remove unused imports:

```sh
go get golang.org/x/tools/cmd/goimports
```

Then you can run some sanity tests over the bank and file-system examples.
These are ordinary Go tests that import the code generated from Dafny and
run it, linking with [goose-nfsd](https://github.com/mit-pdos/goose-nfsd),
specifically with its txn and buftxn packages. To run these tests,
after compiling with `make compile`, run:

```sh
go test -v ./tests
```

## Developing

We provide a library at `dafny_go` that exports some external APIs that are
axiomatized using `{:extern}` modules, classes, and methods in Dafny. Some of
these are core primitives, like `[]byte` and little-endian encoding, while the
big one is the `jrnl` package which interfaces between Dafny and
`github.com/mit-pdos/goose-nfsd/txn`.

The support library is trusted and hence its agreement with the Dafny spec is
important.

You can run tests for this support library with `go test`:

```sh
go test ./dafny_go/...
```
