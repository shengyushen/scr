set hlsearch
set incsearch
set ts=2
set autoindent

filetype plugin on
au BufRead,BufNewFile *.ml,*.mli compiler ocaml
syntax on
