set unstable

c := `echo x >> cnt; wc -l < cnt | tr -d ' '`
f(y) := y + c
a := f('')
b := c

foo:
  @echo {{ a }} {{ b }} {{ c }}
