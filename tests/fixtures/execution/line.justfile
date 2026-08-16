name := "world"

build:
  echo hello {{name}}
  @echo hidden
  -false
