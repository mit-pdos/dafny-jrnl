include "../../util/marshal.i.dfy"
include "../../nonlin/roundup.dfy"

// NOTE: this module, unlike the others in this development, is not intended to
// be opened
module Inode {
  import opened Machine
  import opened Round
  import IntEncoding
  import opened Arith
  import opened Collections
  import opened ByteSlice
  import opened Marshal

  const MAX_SZ_u64: uint64 := 4096 * (8 + 3*512 + 512*512*512);
  const MAX_SZ: nat := MAX_SZ_u64 as nat;

  datatype InodeType = InvalidType | FileType | DirType
  {
    function method to_u32(): uint32
    {
      match this {
        case InvalidType => 0
        case FileType => 1
        case DirType => 2
      }
    }

    static function method from_u32(x: uint32): InodeType
    {
      if x == 0 then InvalidType else if x == 1 then FileType else DirType
    }

    lemma from_to_u32()
      ensures from_u32(to_u32()) == this
    {}

    function enc(): seq<byte>
    {
      IntEncoding.le_enc32(to_u32())
    }

    lemma enc_dec()
      ensures from_u32(IntEncoding.le_dec32(this.enc())) == this
    {
      IntEncoding.lemma_le_enc_dec32(to_u32());
      from_to_u32();
    }
  }

  datatype NfsTime = NfsTime(sec: uint32, nsec: uint32)
  {
    static const zero: NfsTime := NfsTime(0, 0)

    function enc(): seq<byte>
    {
      IntEncoding.le_enc32(sec) + IntEncoding.le_enc32(nsec)
    }

    static lemma enc_zero()
      ensures C.repeat(0 as byte, 8) == zero.enc()
    {
      IntEncoding.lemma_enc_32_0();
    }

    static method decode(bs: Bytes, off: uint64, ghost t: NfsTime)
      returns (t': NfsTime)
      requires bs.Valid()
      requires off as nat + 8 <= |bs.data|
      requires bs.data[off .. off + 8] == t.enc()
      ensures t' == t
    {
      var sec := IntEncoding.UInt32Get(bs, off);
      var nsec := IntEncoding.UInt32Get(bs, off + 4);
      assert bs.data[off..off+4] == t.enc()[..4];
      assert bs.data[off+4..off+8] == t.enc()[4..];
      IntEncoding.lemma_le_enc_dec32(t.sec);
      IntEncoding.lemma_le_enc_dec32(t.nsec);
      return NfsTime(sec, nsec);
    }

    method put(off: uint64, bs: Bytes)
      modifies bs
      requires bs.Valid()
      requires off as nat + 8 <= |bs.data|
      ensures bs.data == old(C.splice(bs.data, off as nat, enc()))
    {
      IntEncoding.UInt32Put(sec, off, bs);
      IntEncoding.UInt32Put(nsec, off + 4, bs);
    }
  }

  datatype Attrs = Attrs(mode: uint32, atime: NfsTime, mtime: NfsTime)
  {
    static const zero: Attrs := Attrs(0, NfsTime.zero, NfsTime.zero)

    function enc(): seq<byte>
    {
      IntEncoding.le_enc32(mode) + atime.enc() + mtime.enc()
    }

    lemma enc_len()
      ensures |enc()| == 20 // 4+8+8
    {}

    static lemma enc_zero()
      ensures C.repeat(0 as byte, 20) == zero.enc()
    {
      IntEncoding.lemma_enc_32_0();
      NfsTime.enc_zero();
    }

    static method decode(bs: Bytes, off: uint64, ghost attrs: Attrs)
      returns (attrs': Attrs)
      requires bs.Valid()
      requires off as nat + 20 <= |bs.data|
      requires bs.data[off .. off + 20] == attrs.enc()
      ensures attrs' == attrs
    {
      var mode := IntEncoding.UInt32Get(bs, off);
      assert mode == attrs.mode by {
        calc {
          bs.data[off .. off + 4];
          attrs.enc()[..4];
          IntEncoding.le_enc32(attrs.mode);
        }
        IntEncoding.lemma_le_enc_dec32(attrs.mode);
      }
      assert bs.data[off + 4 .. off + 12] == attrs.enc()[4..12] by {
        C.double_subslice_auto(bs.data);
      }
      var atime := NfsTime.decode(bs, off + 4, attrs.atime);
      var mtime := NfsTime.decode(bs, off + 4 + 8, attrs.mtime);
      return Attrs(mode, atime, mtime);
    }

    method put(off: uint64, bs: Bytes)
      modifies bs
      requires bs.Valid()
      requires off as nat + 20 <= |bs.data|
      ensures bs.data == old(C.splice(bs.data, off as nat, enc()))
    {
      IntEncoding.UInt32Put(mode, off, bs);
      atime.put(off + 4, bs);
      mtime.put(off + 4 + 8, bs);
    }
  }

  datatype Meta = Meta(sz: uint64, ty: InodeType, attrs: Attrs)
  {
    function enc(): seq<byte>
    {
      (IntEncoding.le_enc64(sz) + ty.enc()) + attrs.enc()
    }

    lemma enc_len()
      ensures |enc()| == 32 // 8 + 4 + 20
    {}

    method put(off: uint64, bs: Bytes)
      modifies bs
      requires bs.Valid()
      requires off as nat + 32 <= |bs.data|
      ensures bs.data == old(C.splice(bs.data, off as nat, enc()))
    {
      IntEncoding.UInt64Put(sz, off, bs);
      IntEncoding.UInt32Put(ty.to_u32(), off + 8, bs);
      attrs.put(off + 8 + 4, bs);
    }
  }

  datatype preInode = Mk(meta: Meta, blks: seq<uint64>)
  {
    const sz: uint64 := meta.sz
    const ty: InodeType := meta.ty

    static const preZero: preInode := Mk(Meta(0, InvalidType, Attrs.zero), C.repeat(0 as uint64, 12))

    predicate Valid()
    {
      && |blks| == 12
      && sz as nat <= MAX_SZ
    }
  }
  // NOTE(tej): we specifically don't provide a witness for performance reasons:
  // if there is a witness, the generated code starts every function that
  // returns an Inode by instantiating it with the witness, and this requires
  // allocating and filling a seq.
  type Inode = x:preInode | x.Valid() ghost witness preInode.preZero

  const zero: Inode := preInode.preZero

  lemma zero_encoding()
    ensures repeat(0 as byte, 128) == enc(zero)
  {
    IntEncoding.lemma_enc_0();
    IntEncoding.lemma_enc_32_0();
    zero_encode_seq_uint64(12);
    reveal enc();
  }

  function {:opaque} enc(i: Inode): (bs:seq<byte>)
    ensures |bs| == 128
  {
    assert i.Valid();
    var blk_enc := seq_enc_uint64(i.blks);
    enc_uint64_len(i.blks);
    i.meta.enc() + blk_enc
  }

  lemma enc_app(i: Inode)
    ensures enc(i) ==
    (IntEncoding.le_enc64(i.meta.sz) + i.meta.ty.enc() + i.meta.attrs.enc()) +
    seq_enc_uint64(i.blks)
  {
    reveal enc();
  }

  method decode_meta(bs: Bytes, off: uint64, ghost m: Meta)
    returns (m': Meta)
    requires bs.Valid()
    requires off as nat + 32 <= |bs.data|
    requires bs.data[off .. off as nat + 32] == m.enc()
    ensures m' == m
  {
    C.double_subslice_auto(bs.data);
    var sz := IntEncoding.UInt64Get(bs, off);
    assert sz == m.sz by {
      calc {
        bs.data[off .. off + 8];
        m.enc()[..8];
        IntEncoding.le_enc64(m.sz);
      }
      IntEncoding.lemma_le_enc_dec64(m.sz);
    }
    var ty_u32 := IntEncoding.UInt32Get(bs, off + 8);
    var ty := InodeType.from_u32(ty_u32);
    assert ty == m.ty by {
      calc {
        bs.data[off + 8 .. off + 8 + 4];
        m.enc()[8..12];
        m.ty.enc();
      }
      m.ty.enc_dec();
    }
    var attrs := Attrs.decode(bs, off + 12, m.attrs);
    return Meta(sz, ty, attrs);
  }
}
