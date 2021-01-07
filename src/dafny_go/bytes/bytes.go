package bytes

// Bytes wraps a byte slice []byte
type Bytes struct {
	Data []byte
}

func NewBytes(sz uint64) *Bytes {
	return &Bytes{Data: make([]byte, sz)}
}

func (bs *Bytes) Len() uint64 {
	return uint64(len(bs.Data))
}

func (bs *Bytes) Get(i uint64) byte {
	return bs.Data[i]
}

func (bs *Bytes) Append(b byte) {
	bs.Data = append(bs.Data, b)
}

func (bs *Bytes) Set(i uint64, b byte) {
	bs.Data[i] = b
}