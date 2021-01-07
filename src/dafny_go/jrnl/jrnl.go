package jrnl

import (
	"github.com/mit-pdos/dafny-jrnl/src/dafny_go/bytes"
	"github.com/mit-pdos/goose-nfsd/addr"
	"github.com/mit-pdos/goose-nfsd/buftxn"
	"github.com/mit-pdos/goose-nfsd/txn"
	"github.com/tchajed/goose/machine/disk"
)

type Disk = disk.Disk
type Blkno = uint64
type Txn struct {
	btxn *buftxn.BufTxn
}

// manual definition of Addr datatype

type Addr_Addr struct {
	Blkno Blkno
	Off   uint64
}

type Addr struct {
	// note this is not exactly what Dafny would emit: it would put an interface
	// here which in practice is always the Addr_Addr struct
	Addr_Addr
}

func (_this Addr) Dtor_blkno() uint64 {
	return _this.Addr_Addr.Blkno
}

func (_this Addr) Dtor_off() uint64 {
	return _this.Addr_Addr.Off
}

// end of Addr datatype

func dafnyAddrToAddr(a Addr) addr.Addr {
	return addr.Addr{Blkno: a.Blkno, Off: a.Off}
}

type Jrnl struct {
	txn *txn.Txn
}

func NewJrnl(d *Disk) *Jrnl {
	return &Jrnl{txn: txn.MkTxn(*d)}
}

func (jrnl *Jrnl) Begin() *Txn {
	return &Txn{btxn: buftxn.Begin(jrnl.txn)}
}

func (txn *Txn) Read(a Addr, sz uint64) *bytes.Bytes {
	a_ := dafnyAddrToAddr(a)
	buf := txn.btxn.ReadBuf(a_, sz)
	return &bytes.Bytes{Data: buf.Data}
}

func is_bit_set(b byte, off uint64) bool {
	return b&(1<<off) != 0
}

func (txn *Txn) ReadBit(a Addr) bool {
	a_ := dafnyAddrToAddr(a)
	buf := txn.btxn.ReadBuf(a_, 1)
	data := buf.Data[0]
	return is_bit_set(data, a.Off%8)
}

func (txn *Txn) Write(a Addr, bs *bytes.Bytes) {
	a_ := dafnyAddrToAddr(a)
	txn.btxn.OverWrite(a_, bs.Len()*8, bs.Data)
}

func (txn *Txn) WriteBit(a Addr, b bool) {
	a_ := dafnyAddrToAddr(a)
	var data byte
	if b {
		data = 0xFF
	} else {
		data = 0
	}
	txn.btxn.OverWrite(a_, 1, []byte{data})
}

func (txn *Txn) Commit() bool {
	ok := txn.btxn.CommitWait(true)
	return ok
}
