dir := 'bar'

set working-directory := dir + '-baz'

foo:
  @cat file.txt
