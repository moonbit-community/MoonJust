imf := module_file()
imd := module_directory()

import-outer: import-inner

@import-inner pmf=module_file() pmd=module_directory():
  echo import
  echo '{{ imf }}'
  echo '{{ imd }}'
  echo '{{ pmf }}'
  echo '{{ pmd }}'
  echo '{{ module_file() }}'
  echo '{{ module_directory() }}'
