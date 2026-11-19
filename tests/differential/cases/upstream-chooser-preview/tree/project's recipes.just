set shell := ['sh', '-cu', 'PATH="$PWD/bin:$PATH"; export PATH; exec sh -cu "$1"', 'sh']
_setup:
    @chmod +x bin/fzf
    @ln -s "{{just_executable()}}" bin/just

foo:
    @echo foo

_cleanup:
    @rm -f bin/just
