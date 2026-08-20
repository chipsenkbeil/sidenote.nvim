" Syntax for the sidenote browser buffer.
"
" The id prefix is concealed exactly as oil does it. The class is \S\+ and
" never \x\+: ids are Crockford base32 ULIDs, so most of them carry letters
" past F and a hex class would conceal only part of the prefix.

if exists("b:current_syntax")
  finish
endif

syn match sidenoteId /^\/\S\+ / conceal nextgroup=sidenoteKind
syn match sidenoteKind /\S\+/ contained nextgroup=sidenoteState skipwhite
syn match sidenoteState /\S\+/ contained nextgroup=sidenoteLocation skipwhite
" The location is the last column and runs to the end of the line, so a path
" holding spaces still highlights as one thing
syn match sidenoteLocation /.*$/ contained

" Prose is every line the renderer indented beneath a header
syn match sidenoteProse /^\s.*$/

hi def link sidenoteKind Identifier
hi def link sidenoteState Keyword
hi def link sidenoteLocation Directory
hi def link sidenoteProse Comment

let b:current_syntax = "sidenote"
