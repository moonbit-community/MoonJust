foo := if 'Foo' !~ '^ab+c' {
  'mismatch'
} else {
  'match'
}

bar := if 'Foo' !~ 'Foo' {
  'mismatch'
} else {
  'match'
}

@default:
  echo {{ foo }} {{ bar }}
