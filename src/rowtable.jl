mutable struct RowTable <: AbstractRowTable
    rows::Vector
    colindex::CIndex
    function RowTable(rows::Vector{Any}, colindex::CIndex)
        new(rows, colindex)
    end
end

# For efficiency, we either need to use these methods, or else
# make a typed RowTable
# RowTable(rows::Vector, colindex::CIndex) = RowTable(Any[r for r in rows], colindex)
"""
    RowTable(rows::Vector, colindex::CIndex)

Construct a `RowTable` from `rows` and a list of column names `colindex`.
"""
RowTable(rows::Vector, colindex::CIndex) = RowTable(Any[rows...], colindex)

### Access

@inline cindex(rt::RowTable) = rt.colindex
@inline colindex(rt::RowTable, ci) = cindex(rt)[ci]  # use this, or not

"""
    rows(rt::RowTable)

Return the rows of `rt` as a Vector. `rt` itself is iteratble and
iterates over rows. But, iterating over `rows(rt)` is faster.
"""
@inline rows(rt::RowTable) = rt.rows

# Annotating the method above with return type Vector makes it 1000x slower in v0.6,
# and only a bit less slower in v0.7.
# @inline rows(rt::RowTable)::Vector = rt.rows

"""
    names(rt::RowTable)

Return a list of the column names of `rt`.
"""
Base.names(rt::RowTable) = _names(cindex(rt))
_names(rt::RowTable) = _names(cindex(rt))

"""
    size(rt::RowTable)

Return the number of rows and the number columns in `rt`.
"""
Base.size(rt::RowTable) = _numberofrows(rt), _numberofcols(rt)
_numberofcols(rt::RowTable) = length(_names(rt))
_numberofrows(rt::RowTable) = length(rows(rt))

## TODO: make sure this is optimized if n is known at compile time
## (And even if not known)
Base.size(rt::RowTable, n::Integer) = n == 1 ? _numberofrows(rt) : n == 2 ? _numberofcols(rt) :
    error(ArgumentError, ": RowTables have only two dimensions")

### Equality

Base.:(==)(rt1::RowTable, rt2::RowTable) = (cindex(rt1) == cindex(rt2) && rows(rt1) == rows(rt2))

### Constructors

newrows(n::Integer=0) = Vector{Any}(undef, n)

## We did not use the type information afterall.
const _NameTypes = Union{AbstractVector{S} where S<:Union{Symbol, AbstractString}, Tuple}

function _RowTable(a::AbstractVector{T}, keynames; tuples::Bool=false) where {T <: AbstractDict}
    isempty(a) && return RowTable(newrows(), CIndex(map(Symbol, keynames))) # JSON keys are strings
    l = length(first(a))
    all(x -> length(x) == l, a) || throw(DimensionMismatch("All dictionaries must be of the same length"))
    if tuples
        RowTable([dict_to_named_tuple(a[i], keynames) for i in LinearIndices(a)], CIndex(map(Symbol, keynames)))
    else
        RowTable([map(x -> a[i][x], keynames) for i in LinearIndices(a)], CIndex(map(Symbol, keynames)))
    end
end

# FIXME: ensue symbols as keys
function dict_to_named_tuple(d::AbstractDict, keynames)
    datatypes = Tuple{[typeof(d[k]) for k in keynames]...,}
    return NamedTuple{(keynames...,), datatypes}(([d[k] for k in keynames]...,))
end

# Construct from Array of Dicts
RowTable(a::AbstractVector{T}, keynames::_NameTypes; tuples=false) where {T<:AbstractDict} = _RowTable(a, keynames, tuples=tuples)

function _RowTable(::Type{T}, a::AbstractVector, keynames) where T <: AbstractArray
    all(x -> isa(x, AbstractArray), a) || error("Not all elements are arrays")  # They don't have to be. Just not dicts
    RowTable(a, CIndex(keynames))
end

function _RowTable(::Type{T}, a::AbstractVector, keynames) where T <: Tuple
    RowTable(a, CIndex(keynames))
end

# v0.7 requires collect (or something else) here to avoid constructing a Set, which prevents indexing
_RowTable(::Type{T}, a::AbstractVector) where T <: AbstractDict  = _RowTable(T, a, collect(keys(first(a))))

function _RowTable(::Type{T}, a::AbstractVector, keynames; tuples=false) where T <: AbstractDict
    all(x -> isa(x, AbstractDict), a) || error("Not all elements are dictionaries")
    _RowTable(a, keynames, tuples=tuples)
end

function RowTable(a::AbstractVector)
    isempty(a) && return RowTable()
    _RowTable(typeof(first(a)), a)
end

"""
    RowTable(a::AbstractVector, keynames)

Construct a `RowTable` from a vector of rows `a`, and `keynames`.
If `keynames` is a `Vector`, then the rows are `Vectors`.
If `keynames` is a `Tuple`, they are `Tuple`s.

`RowTable([], keynames)` constructs a `RowTable` with no rows.
"""
function RowTable(a::AbstractVector, keynames::_NameTypes)
    isempty(a) && return RowTable([], CIndex(keynames))
    _RowTable(typeof(first(a)), a, keynames)
end

"""
    RowTable(cols=[], names=[], tuples=false)

Return a `RowTable` constructed from the collection of columns `cols`,
with `names`. If `tuples=true`, the rows are named tuples. Otherwise,
they are `Array`s.
"""
function RowTable(; cols=[], names=[], tuples=false)
    if isempty(cols)
        isempty(names) && return RowTable(newrows(), CIndex())
        return RowTable(newrows(), CIndex(names))
    end
    length(cols) == length(names) || throw(DimensionMismatch("Number of columns and number of names must be equal."))
    isempty(cols[1]) && throw(DimensionMismatch("Support for empty columns not implmented."))
    columnlength = length(cols[1])
    for c in cols
        (length(c) == columnlength) || throw(DimensionMismatch("Columns must have the same length."))
    end
    rows = tuples ? namedtuple_rows(cols, names, columnlength) : array_rows(cols, columnlength)
    return RowTable(rows, CIndex(names))
end

function namedtuple_rows(cols, names, columnlength)
    datatypetup = (collect(c[1] for c in cols)...,) |> typeof
    nametup = (names...,)
    namedtupletype = NamedTuple{nametup}{datatypetup}
    rows = newrows(columnlength)
    for i in 1:columnlength
        rows[i] = namedtupletype(([c[i] for c in cols]...,))
    end
    return rows
end

function array_rows(cols, columnlength)
    rows = newrows(columnlength)
    for i in 1:columnlength
        rows[i] = [c[i] for c in cols]
    end
    return rows
end

"""
    RowTable(df::DataFrames.DataFrame; tuples=false)

Construct a `RowTable` from a `DataFrame`. If `tuples=true`
then the constructed rows are `Tuples` rather than `Vectors`.
"""
function RowTable(df::DataFrames.DataFrame; tuples=false)
    (nr, nc) = size(df)
    arr = newrows()
    if tuples
        @inbounds for ri in 1:nr
            push!(arr, ([df[ri, ci] for ci in 1:nc]...,))
        end
    else
        @inbounds for ri in 1:nr
            push!(arr, [df[ri, ci] for ci in 1:nc])
        end
    end
    RowTable(arr, copy(names(df)))
end


##############################################################################
##
## getindex()
##
##############################################################################

## This allows single methods to handle both Int and Symbol indices.
## But, it allows repeated mapping of the same Symbol, which is inefficient.
## So, this might not be used much
const ColInd = Union{Integer, Symbol}

## A single index is a interpreted as a column index, consistent with DataFrames
Base.getindex(rt::RowTable, cinds) = rt[:,cinds]

## Return element in a single cell
Base.getindex(rt::RowTable, ri::Integer, ci::Symbol) = rows(rt)[ri][cindex(rt)[ci]]

# If above is called in a loop with symbol arg, using below is faster

Base.getindex(rt::RowTable, ri::Integer, ci::Integer) = rows(rt)[ri][ci]

## Return a slice of a column as a Vector
function Base.getindex(rt::RowTable, ri::AbstractVector, ci::ColInd)
    ind = colindex(rt, ci) # do this so symbol mapping is only done once
    [rt[i, ind] for i in ri]
end

## Return a slice of a row as a Vector
Base.getindex(rt::RowTable, ri::Integer, cis::AbstractVector{T}) where {T <: Symbol} =
    rows(rt)[ri][[cindex(rt)[ci] for ci in cis]]

Base.getindex(rt::RowTable, ri::Integer, cis::AbstractVector{T}) where {T <: Integer} =
    rows(rt)[ri][cis]

### Return a row, vector or Tuple
Base.getindex(rt::RowTable, ri::Integer, ::Colon) = rt.rows[ri]

## Return slice as RowTable
## Following method calls the next method with integer arguments
Base.getindex(rt::RowTable, ri::AbstractVector{T}, ci::AbstractVector{V}) where {T<:Integer, V<:Symbol} =
    Base.getindex(rt, ri, [cindex(rt)[s] for s in ci])

## Return rectangular slice in both dimensions as RowTable
function Base.getindex(rt::RowTable, ri::AbstractVector, ci::AbstractVector{T}) where T<:Integer
    ar = newrows(length(ri))
    for (i, ind) in enumerate(ri)
        ar[i] = rows(rt)[ind][ci]
    end
    RowTable(ar, CIndex(cindex(rt).names[ci]))
end

Base.getindex(rt::RowTable, ::Colon, ci) = rt[1:length(rows(rt)), ci]

Base.getindex(rt::RowTable, ri::AbstractVector, ::Colon) = RowTable(rows(rt)[ri], rt.colindex)

##############################################################################
##
## setindex!()
##
##############################################################################

## Set a single element
Base.setindex!(rt::RowTable, val, ri::Integer, ci::Integer) = (rows(rt)[ri][ci] = val)
Base.setindex!(rt::RowTable, val, ri::Integer, ci::Symbol) = (rows(rt)[ri][cindex(rt)[ci]] = val)

### Convert

"""
    columns(rt::RowTable)::Vector

Return the columns of `rt`.
"""
function columns(rt::RowTable)
    (nr, nc) = size(rt)
    @inbounds colarr =  [newrows(nr) for i in 1:nc] # misusing newrows for columns here
    return _columns!(rt, colarr)
end

function columnstyped(rt::RowTable)
    (nr, nc) = size(rt)
    @inbounds colarr =  [Vector{typeof(rt[1, i])}(undef, nr) for i in 1:nc]
    return _columns!(rt, colarr)
end

@inline function _columns!(rt, colarr)
    (nr, nc) = size(rt)
    for rowind in 1:nr
      @inbounds row = rows(rt)[rowind]
        for colind in 1:nc
        @inbounds colarr[colind][rowind] = row[colind]
        end
    end
    return colarr
end

"""
    DataFrame(rt::RowTable; typed=false)

Convert `rt` to a `DataFrame`. If `typed` is `true`,
then the eltype of each column is the type of the first
element in the column. This will raise an error if the
elements are in fact not of the same type.
"""
function DataFrames.DataFrame(rt::RowTable; typed=false)
    cols = (typed ? columnstyped(rt) : columns(rt))
    DataFrames.DataFrame(cols,_names(rt))
end

### Copy

Base.copy(rt::RowTable) = RowTable(copy(rows(rt)), copy(cindex(rt)))
Base.deepcopy(rt::RowTable) = RowTable(deepcopy(rows(rt)), deepcopy(cindex(rt)))

### Iterate over rows
## DataFrames does not define iterating over a DataFrame, rather requires
## specifying rows or columns

for f in (:length, :iterate)
    @eval begin
        (Base.$f)(rt::RowTable) = (Base.$f)(rows(rt))
    end
end

for f in (:iterate,)
    @eval begin
        (Base.$f)(rt::RowTable, args...) = (Base.$f)(rows(rt), args...)
    end
end

### Transform

for f in (:deleteat!, :push!, :pushfirst!, :insert!, :append!, :prepend!, :splice!, :permute!)
    @eval begin
        (Base.$f)(rt::RowTable, args...) = (($f)(rows(rt), args...); rt)
    end
end

for f in (:pop!, :popfirst!)
    @eval begin
        (Base.$f)(rt::RowTable, args...) = ($f)(rows(rt), args...)
    end
end

permute!(rt::RowTable, p::AbstractVector) = (permute!(rows(rt), p); rt)
permute(rt::RowTable, p::AbstractVector) = permute!(copy(rt), p)

Random.shuffle!(rng::Random.AbstractRNG, rt::RowTable) = (shuffle!(rng, rows(rt)); rt)
Random.shuffle!(rt::RowTable) = (shuffle!(rows(rt)); rt)
Random.shuffle(rt::RowTable) = shuffle!(copy(rt))
Random.shuffle(rng::Random.AbstractRNG, rt::RowTable) = shuffle!(rng, copy(rt))

DataFrames.rename!(rt::RowTable, d) = (rename!(cindex(rt), d); rt)
DataFrames.rename(rt::RowTable, d) = rename!(copy(rt), d)
