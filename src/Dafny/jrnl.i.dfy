include "pow.dfy"

/*
Spec for sequential journal API, assuming we're using 2PL.
*/

type Blkno = nat
datatype Addr = Addr(blkno: Blkno, off: nat)
type byte = bv8
type Object = seq<byte>
type Kind = k:int | 0 <= k <= 15

function method objSize(obj: Object): nat
{
    |obj| * 8
}

function method kindSize(k: Kind): nat
{
    pow_nonneg(2, k);
    pow(2,k)
}

function kindCount(k: Kind): nat
{
    pow_nonneg(2, 15-k);
    pow(2, 15-k)
}

lemma kindSize_and_kindCount_sensible(k: Kind)
ensures kindSize(k) * kindCount(k) == 4096*8
{
    assert 4096*8 == pow(2, 15);
    pow_plus(2, k, 15-k);
}

lemma kindSize_bounds(k: Kind)
ensures kindSize(k) <= 4096*8
{
    pow_increasing(2, k, 15);
    assert pow(2,15) == 4096*8;
}

function method repeat<T>(x: T, count: nat): (xs:seq<T>)
ensures |xs| == count && forall i :: 0 <= i < |xs| ==> xs[i] == x
{
    if count == 0 then [] else [x] + repeat(x, count-1)
}

function method zeroObject(k: Kind): (obj:Object)
//requires kindSize(k)/8*8 == kindSize(k)
ensures objSize(obj) == kindSize(k)
{
    // TODO: figure this out
    assume false;
    if kindSize(k)/8 == 0 then [0 as bv8]
    else repeat(0 as bv8, kindSize(k)/8)
}

function method addrsForKinds(kinds: map<Blkno, Kind>): set<Addr>
{
    var dom := set blkno | blkno in kinds;
    set blkno : Blkno, off : int |
    && blkno in dom
    && 0 <= off < 4096*8
    // TODO: need to add this restriction later, otherwise finite map heuristics fail
    // && kindSize(kinds[blkno]) > 0 ==> off % kindSize(kinds[blkno]) == 0
    :: Addr(blkno, off)
}

class {:autocontracts} Jrnl
{
    var data: map<Addr, Object>;
    ghost const domain: set<Addr>;
    const kinds: map<Blkno, Kind>;
    var has_readbuf: bool;

    predicate Valid() reads this {
        && (forall a :: a in data ==>
            && a.blkno in kinds
            && objSize(data[a]) == kindSize(kinds[a.blkno]))
        && (forall a :: a in data <==> a in domain)
    }

    constructor(kinds: map<Blkno, Kind>)
    requires forall k | k in kinds :: kindSize(k)/8*8 == kindSize(k)
    {
        this.kinds := kinds;
        var data: map<Addr, Object> :=
            map a:Addr | a in addrsForKinds(kinds) :: zeroObject(kinds[a.blkno]);
        this.data := data;
        this.domain := set a:Addr | a in data;
    }

    function size(a: Addr): nat
    requires a in this.domain
    {
        kindSize(this.kinds[a.blkno])
    }

    method Read(a: Addr, sz: nat)
    returns (buf:ReadBuf)
    requires Valid()
    modifies this
    requires !has_readbuf
    requires a in domain
    requires sz == size(a)
    ensures
    && data == old(data)
    && has_readbuf
    && buf.a == a
    && buf.obj == data[a]
    && objSize(buf.obj) == sz
    && buf.jrnl == this
    {
        has_readbuf := true;
        return new ReadBuf(a, data[a], this);
    }

    method Write(a: Addr, obj: Object)
    requires Valid() ensures Valid()
    modifies this
    requires !has_readbuf
    requires a in domain
    requires objSize(obj) == size(a)
    ensures
    && data == old(data)[a:=obj]
    && has_readbuf == old(has_readbuf)
    {
        data := data[a:=obj];
    }
}

class ReadBuf
{
    var a: Addr;
    var obj: Object;
    var jrnl: Jrnl;

    constructor(a: Addr, obj: Object, jrnl: Jrnl)
    requires jrnl.Valid()
    requires a in jrnl.domain
    requires jrnl.has_readbuf
    requires objSize(obj) == jrnl.size(a)
    ensures Valid()
    ensures
    && this.a == a
    && this.obj == obj
    && this.jrnl == jrnl;
    {
        this.a := a;
        this.obj := obj;
        this.jrnl := jrnl;
    }

    predicate Valid()
    reads this, jrnl, jrnl.Repr
    {
        && jrnl.Valid()
        && a in jrnl.domain
        && objSize(obj) == jrnl.size(a)
        && jrnl.has_readbuf
    }

    method Finish()
    modifies jrnl
    requires Valid()
    ensures !Valid() && jrnl.Valid()
    ensures jrnl.data == old(jrnl.data)
    ensures !jrnl.has_readbuf
    {
        jrnl.has_readbuf := false;
    }

    // SetDirty() models writing the buffer out after manually changing the
    // object
    method SetDirty()
    modifies jrnl;
    requires Valid()
    // intentionally does not guarantee validity (consumes the buffer)
    ensures !Valid() && jrnl.Valid()
    ensures !jrnl.has_readbuf
    {
        Finish();
        jrnl.Write(a, obj);
    }
}
