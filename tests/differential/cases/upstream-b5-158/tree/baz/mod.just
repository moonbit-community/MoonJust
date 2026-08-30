import 'foo/bar.just'

mmf := module_file()
mmd := module_directory()

outer: inner

@inner pmf=module_file() pmd=module_directory():
  echo module
  echo '{{ mmf }}'
  echo '{{ mmd }}'
  echo '{{ pmf }}'
  echo '{{ pmd }}'
  echo '{{ module_file() }}'
  echo '{{ module_directory() }}'
