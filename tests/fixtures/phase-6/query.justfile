# greeting
[doc("hello")]
hello name="world":
  echo {{ name }}

[group("ci")]
build:
  echo build

alias h := hello

x := "a"
y := x + "b"
