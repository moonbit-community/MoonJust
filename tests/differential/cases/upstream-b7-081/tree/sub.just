set unstable

a := f()
f() := x
x := 'sub'

foo:
    @echo {{ a }} {{ f() }}
