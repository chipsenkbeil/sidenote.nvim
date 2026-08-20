" Syntax for the sidenote browser buffer.
"
" The id prefix is concealed exactly as oil does it. The class is \w\+ to
" mirror the grammar: ids are word characters, which is what keeps a prose
" line opening with a path like /etc/hosts from reading as a header.

if exists("b:current_syntax")
  finish
endif

syn match sidenoteId /^\/\w\+ / conceal nextgroup=sidenoteKind
syn match sidenoteKind /\S\+/ contained nextgroup=sidenoteState skipwhite
syn match sidenoteState /\S\+/ contained nextgroup=sidenotePen skipwhite
syn match sidenotePen /\S\+/ contained nextgroup=sidenoteLocation skipwhite
" The location is the last column and runs to the end of the line, so a path
" holding spaces still highlights as one thing
syn match sidenoteLocation /.*$/ contained

" Prose is every line without the marker
syn match sidenoteProse /^\(\/\w\+ \)\@!.*$/

hi def link sidenoteKind Identifier
hi def link sidenoteState Keyword
hi def link sidenotePen Special
hi def link sidenoteLocation Directory
hi def link sidenoteProse Comment

let b:current_syntax = "sidenote"
