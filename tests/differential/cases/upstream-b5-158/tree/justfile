import 'foo/bar.just'
mod baz

rmf := module_file()
rmd := module_directory()

outer: inner

@inner pmf=module_file() pmd=module_directory():
  echo root
  echo '{{ rmf }}'
  echo '{{ rmd }}'
  echo '{{ pmf }}'
  echo '{{ pmd }}'
  echo '{{ module_file() }}'
  echo '{{ module_directory() }}'
