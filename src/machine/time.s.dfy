include "machine.dfy"

module {:extern "time", "github.com/mit-pdos/daisy-nfsd/dafny_go/time"} Time {
  import opened Machine

  // current time in number of nanoseconds since January 1, 1970 UTC
  method {:extern} TimeUnixNano() returns (x:uint64)
}
