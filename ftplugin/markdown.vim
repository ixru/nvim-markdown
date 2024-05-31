" Disable inbuilt markdown ftplugin
if exists("b:did_ftplugin")
    finish
else
    let b:did_ftplugin=1
endif

" For each level, contains the regexp that matches at that level only.
"
let s:levelRegexpDict = {
    \ 1: '\v^(#[^#]@=|.+\n\=+$)',
    \ 2: '\v^(##[^#]@=|.+\n-+$)',
    \ 3: '\v^###[^#]@=',
    \ 4: '\v^####[^#]@=',
    \ 5: '\v^#####[^#]@=',
    \ 6: '\v^######[^#]@='
\ }

" Maches any header level of any type.
"
" This could be deduced from `s:levelRegexpDict`, but it is more
" efficient to have a single regexp for this.
"
let s:headersRegexp = '\v^(#|.+\n(\=+|-+)$)'

" Returns the line number of the first header before `line`, called the
" current header.
"
" If there is no current header, return `0`.
"
" @param a:1 The line to look the header of. Default value: `getpos('.')`.
"
function! s:GetHeaderLineNum(...)
    if a:0 == 0
        let l:l = line('.')
    else
        let l:l = a:1
    endif
    while(l:l > 0)
        if join(getline(l:l, l:l + 1), "\n") =~ s:headersRegexp
            return l:l
        endif
        let l:l -= 1
    endwhile
    return 0
endfunction

" -  if inside a header goes to it.
"    Return its line number.
"
" -  if on top level outside any headers,
"    print a warning
"    Return `0`.
"
function! s:MoveToCurHeader()
    let l:lineNum = s:GetHeaderLineNum()
    if l:lineNum != 0
        call cursor(l:lineNum, 1)
    else
        echo 'outside any header'
        "normal! gg
    endif
    return l:lineNum
endfunction

" Move cursor to next header of any level.
"
" If there are no more headers, print a warning.
"
function! s:MoveToNextHeader()
    if search(s:headersRegexp, 'W') == 0
        "normal! G
        echo 'no next header'
    endif
endfunction

" Move cursor to previous header (before current) of any level.
"
" If it does not exist, print a warning.
"
function! s:MoveToPreviousHeader()
    let l:curHeaderLineNumber = s:GetHeaderLineNum()
    let l:noPreviousHeader = 0
    if l:curHeaderLineNumber <= 1
        let l:noPreviousHeader = 1
    else
        let l:previousHeaderLineNumber = s:GetHeaderLineNum(l:curHeaderLineNumber - 1)
        if l:previousHeaderLineNumber == 0
            let l:noPreviousHeader = 1
        else
            call cursor(l:previousHeaderLineNumber, 1)
        endif
    endif
    if l:noPreviousHeader
        echo 'no previous header'
    endif
endfunction

" - if line is inside a header, return the header level (h1 -> 1, h2 -> 2, etc.).
"
" - if line is at top level outside any headers, return `0`.
"
function! s:GetHeaderLevel(...)
    if a:0 == 0
        let l:line = line('.')
    else
        let l:line = a:1
    endif
    let l:linenum = s:GetHeaderLineNum(l:line)
    if l:linenum != 0
        return s:GetLevelOfHeaderAtLine(l:linenum)
    else
        return 0
    endif
endfunction

" Return list of headers and their levels.
"
function! s:GetHeaderList()
    let l:bufnr = bufnr('%')
    let l:fenced_block = 0
    let l:front_matter = 0
    let l:header_list = []
    let l:vim_markdown_frontmatter = get(g:, "vim_markdown_frontmatter", 0)
    for i in range(1, line('$'))
        let l:lineraw = getline(i)
        let l:l1 = getline(i+1)
        let l:line = substitute(l:lineraw, "#", "\\\#", "g")
        " exclude lines in fenced code blocks
        if l:line =~ '````*' || l:line =~ '\~\~\~\~*'
            if l:fenced_block == 0
                let l:fenced_block = 1
            elseif l:fenced_block == 1
                let l:fenced_block = 0
            endif
        " exclude lines in frontmatters
        elseif l:vim_markdown_frontmatter == 1
            if l:front_matter == 1
                if l:line == '---'
                    let l:front_matter = 0
                endif
            elseif i == 1
                if l:line == '---'
                    let l:front_matter = 1
                endif
            endif
        endif
        " match line against header regex
        if join(getline(i, i + 1), "\n") =~ s:headersRegexp && l:line =~ '^\S'
            let l:is_header = 1
        else
            let l:is_header = 0
        endif
        if l:is_header == 1 && l:fenced_block == 0 && l:front_matter == 0
            " remove hashes from atx headers
            if match(l:line, "^#") > -1
                let l:line = substitute(l:line, '\v^#*[ ]*', '', '')
                let l:line = substitute(l:line, '\v[ ]*#*$', '', '')
            endif
            " append line to list
            let l:level = s:GetHeaderLevel(i)
            let l:item = {'level': l:level, 'text': l:line, 'lnum': i, 'bufnr': bufnr}
            let l:header_list = l:header_list + [l:item]
        endif
    endfor
    return l:header_list
endfunction

" Returns the level of the header at the given line.
"
" If there is no header at the given line, returns `0`.
"
function! s:GetLevelOfHeaderAtLine(linenum)
    let l:lines = join(getline(a:linenum, a:linenum + 1), "\n")
    for l:key in keys(s:levelRegexpDict)
        if l:lines =~ get(s:levelRegexpDict, l:key)
            return l:key
        endif
    endfor
    return 0
endfunction

" Move cursor to parent header of the current header.
"
" If it does not exit, print a warning and do nothing.
"
function! s:MoveToParentHeader()
    let l:linenum = s:GetParentHeaderLineNumber()
    if l:linenum != 0
        call setpos("''", getpos('.'))
        call cursor(l:linenum, 1)
    else
        echo 'no parent header'
    endif
endfunction

" Return the line number of the parent header of line `line`.
"
" If it has no parent, return `0`.
"
function! s:GetParentHeaderLineNumber(...)
    if a:0 == 0
        let l:line = line('.')
    else
        let l:line = a:1
    endif
    let l:level = s:GetHeaderLevel(l:line)
    if l:level > 1
        let l:linenum = s:GetPreviousHeaderLineNumberAtLevel(l:level - 1, l:line)
        return l:linenum
    endif
    return 0
endfunction

" Return the line number of the previous header of given level.
" in relation to line `a:1`. If not given, `a:1 = getline()`
"
" `a:1` line is included, and this may return the current header.
"
" If none return 0.
"
function! s:GetNextHeaderLineNumberAtLevel(level, ...)
    if a:0 < 1
        let l:line = line('.')
    else
        let l:line = a:1
    endif
    let l:l = l:line
    while(l:l <= line('$'))
        if join(getline(l:l, l:l + 1), "\n") =~ get(s:levelRegexpDict, a:level)
            return l:l
        endif
        let l:l += 1
    endwhile
    return 0
endfunction

" Return the line number of the previous header of given level.
" in relation to line `a:1`. If not given, `a:1 = getline()`
"
" `a:1` line is included, and this may return the current header.
"
" If none return 0.
"
function! s:GetPreviousHeaderLineNumberAtLevel(level, ...)
    if a:0 == 0
        let l:line = line('.')
    else
        let l:line = a:1
    endif
    let l:l = l:line
    while(l:l > 0)
        if join(getline(l:l, l:l + 1), "\n") =~ get(s:levelRegexpDict, a:level)
            return l:l
        endif
        let l:l -= 1
    endwhile
    return 0
endfunction

" Move cursor to next sibling header.
"
" If there is no next siblings, print a warning and don't move.
"
function! s:MoveToNextSiblingHeader()
    let l:curHeaderLineNumber = s:GetHeaderLineNum()
    let l:curHeaderLevel = s:GetLevelOfHeaderAtLine(l:curHeaderLineNumber)
    let l:curHeaderParentLineNumber = s:GetParentHeaderLineNumber()
    let l:nextHeaderSameLevelLineNumber = s:GetNextHeaderLineNumberAtLevel(l:curHeaderLevel, l:curHeaderLineNumber + 1)
    let l:noNextSibling = 0
    if l:nextHeaderSameLevelLineNumber == 0
        let l:noNextSibling = 1
    else
        let l:nextHeaderSameLevelParentLineNumber = s:GetParentHeaderLineNumber(l:nextHeaderSameLevelLineNumber)
        if l:curHeaderParentLineNumber == l:nextHeaderSameLevelParentLineNumber
            call cursor(l:nextHeaderSameLevelLineNumber, 1)
        else
            let l:noNextSibling = 1
        endif
    endif
    if l:noNextSibling
        echo 'no next sibling header'
    endif
endfunction

" Move cursor to previous sibling header.
"
" If there is no previous siblings, print a warning and do nothing.
"
function! s:MoveToPreviousSiblingHeader()
    let l:curHeaderLineNumber = s:GetHeaderLineNum()
    let l:curHeaderLevel = s:GetLevelOfHeaderAtLine(l:curHeaderLineNumber)
    let l:curHeaderParentLineNumber = s:GetParentHeaderLineNumber()
    let l:previousHeaderSameLevelLineNumber = s:GetPreviousHeaderLineNumberAtLevel(l:curHeaderLevel, l:curHeaderLineNumber - 1)
    let l:noPreviousSibling = 0
    if l:previousHeaderSameLevelLineNumber == 0
        let l:noPreviousSibling = 1
    else
        let l:previousHeaderSameLevelParentLineNumber = s:GetParentHeaderLineNumber(l:previousHeaderSameLevelLineNumber)
        if l:curHeaderParentLineNumber == l:previousHeaderSameLevelParentLineNumber
            call cursor(l:previousHeaderSameLevelLineNumber, 1)
        else
            let l:noPreviousSibling = 1
        endif
    endif
    if l:noPreviousSibling
        echo 'no previous sibling header'
    endif
endfunction

function! s:Toc(...)
    if a:0 > 0
        let l:window_type = a:1
    else
        let l:window_type = 'vertical'
    endif


    let l:cursor_line = line('.')
    let l:cursor_header = 0
    let l:header_list = s:GetHeaderList()
    let l:indented_header_list = []
    if len(l:header_list) == 0
        echom "Toc: No headers."
        return
    endif
    let l:header_max_len = 0
    let l:vim_markdown_toc_autofit = get(g:, "vim_markdown_toc_autofit", 0)
    for h in l:header_list
        " set header number of the cursor position
        if l:cursor_header == 0
            let l:header_line = h.lnum
            if l:header_line == l:cursor_line
                let l:cursor_header = index(l:header_list, h) + 1
            elseif l:header_line > l:cursor_line
                let l:cursor_header = index(l:header_list, h)
            endif
        endif
        " indent header based on level
        let l:text = repeat('  ', h.level-1) . h.text
        " keep track of the longest header size (heading level + title)
        let l:total_len = strdisplaywidth(l:text)
        if l:total_len > l:header_max_len
            let l:header_max_len = l:total_len
        endif
        " append indented line to list
        let l:item = {'lnum': h.lnum, 'text': l:text, 'valid': 1, 'bufnr': h.bufnr, 'col': 1}
        let l:indented_header_list = l:indented_header_list + [l:item]
    endfor
    call setloclist(0, l:indented_header_list)

    if l:window_type ==# 'horizontal'
        lopen
    elseif l:window_type ==# 'vertical'
        vertical lopen
        " auto-fit toc window when possible to shrink it
        if (&columns/2) > l:header_max_len && l:vim_markdown_toc_autofit == 1
            " header_max_len + 1 space for first header + 3 spaces for line numbers
            execute 'vertical resize ' . (l:header_max_len + 1 + 3)
        else
            execute 'vertical resize ' . (&columns/2)
        endif
    else
        lopen
    endif
    setlocal modifiable
    for i in range(1, line('$'))
        " this is the location-list data for the current item
        let d = getloclist(0)[i-1]
        call setline(i, d.text)
    endfor
    setlocal nomodified
    setlocal nomodifiable
    syn match Level0 '^[^\s].*$'
    syn match Level1 '^\s\{2\}.*$'
    syn match Level2 '^\s\{4\}.*$'
    syn match Level3 '^\s\{6\}.*$'
    syn match Level4 '^\s\{8\}.*$'
    syn match Level5 '^\s\{10\}.*$'
    syn match Level6 '^\s\{12\}.*$'
    syn match Level7 '^\s\{14\}.*$'
    syn match Level8 '^\s\{15\}.*$'
    syn match Level9 '^\s\{16\}.*$'
    hi def link Level0 Title
    hi def link Level1 Statement
    hi def link Level2 Type
    hi def link Level3 String
    hi def link Level4 Identifier
    hi def link Level5 Normal
    hi def link Level6 Normal
    hi def link Level7 Normal
    hi def link Level8 Normal
    hi def link Level9 Normal
    execute 'normal! ' . l:cursor_header . 'G'
endfunction

function! s:InsertToc(format, ...)
    if a:0 > 0
        if type(a:1) != type(0)
            echohl WarningMsg
            echomsg '[vim-markdown] Invalid argument, must be an integer >= 2.'
            echohl None
            return
        endif
        let l:max_level = a:1
        if l:max_level < 2
            echohl WarningMsg
            echomsg '[vim-markdown] Maximum level cannot be smaller than 2.'
            echohl None
            return
        endif
    else
        let l:max_level = 0
    endif

    let l:toc = []
    let l:header_list = s:GetHeaderList()
    if len(l:header_list) == 0
        echom "InsertToc: No headers."
        return
    endif

    if a:format ==# 'numbers'
        let l:h2_count = 0
        for header in l:header_list
            if header.level == 2
                let l:h2_count += 1
            endif
        endfor
        let l:max_h2_number_len = strlen(string(l:h2_count))
    else
        let l:max_h2_number_len = 0
    endif

    let l:h2_count = 0
    for header in l:header_list
        let l:level = header.level
        if l:level == 1
            " skip level-1 headers
            continue
        elseif l:max_level != 0 && l:level > l:max_level
            " skip unwanted levels
            continue
        elseif l:level == 2
            " list of level-2 headers can be bullets or numbers
            if a:format ==# 'bullets'
                let l:indent = ''
                let l:marker = '* '
            else
                let l:h2_count += 1
                let l:number_len = strlen(string(l:h2_count))
                let l:indent = repeat(' ', l:max_h2_number_len - l:number_len)
                let l:marker = l:h2_count . '. '
            endif
        else
            let l:indent = repeat(' ', l:max_h2_number_len + 2 * (l:level - 2))
            let l:marker = '* '
        endif
        let l:text = '[' . header.text . ']'
        let l:link = '(#' . substitute(tolower(header.text), '\v[ ]+', '-', 'g') . ')'
        let l:line = l:indent . l:marker . l:text . l:link
        let l:toc = l:toc + [l:line]
    endfor

    call append(line('.'), l:toc)
endfunction

" Convert Setex headers in range `line1 .. line2` to Atx.
"
" Return the number of conversions.
"
function! s:SetexToAtx(line1, line2)
    let l:originalNumLines = line('$')
    execute 'silent! ' . a:line1 . ',' . a:line2 . 'substitute/\v(.*\S.*)\n\=+$/# \1/'
    execute 'silent! ' . a:line1 . ',' . a:line2 . 'substitute/\v(.*\S.*)\n-+$/## \1/'
    return l:originalNumLines - line('$')
endfunction

" If `a:1` is 0, decrease the level of all headers in range `line1 .. line2`.
"
" Otherwise, increase the level. `a:1` defaults to `0`.
"
function! s:HeaderDecrease(line1, line2, ...)
    if a:0 > 0
        let l:increase = a:1
    else
        let l:increase = 0
    endif
    if l:increase
        let l:forbiddenLevel = 6
        let l:replaceLevels = [5, 1]
        let l:levelDelta = 1
    else
        let l:forbiddenLevel = 1
        let l:replaceLevels = [2, 6]
        let l:levelDelta = -1
    endif
    for l:line in range(a:line1, a:line2)
        if join(getline(l:line, l:line + 1), "\n") =~ s:levelRegexpDict[l:forbiddenLevel]
            echomsg 'There is an h' . l:forbiddenLevel . ' at line ' . l:line . '. Aborting.'
            return
        endif
    endfor
    let l:numSubstitutions = s:SetexToAtx(a:line1, a:line2)
    let l:flags = (&gdefault ? '' : 'g')
    for l:level in range(replaceLevels[0], replaceLevels[1], -l:levelDelta)
        execute 'silent! ' . a:line1 . ',' . (a:line2 - l:numSubstitutions) . 'substitute/' . s:levelRegexpDict[l:level] . '/' . repeat('#', l:level + l:levelDelta) . '/' . l:flags
    endfor
endfunction

" Format table under cursor.
"
" Depends on Tabularize.
"
function! s:TableFormat()
    let l:pos = getpos('.')
    normal! {
    " Search instead of `normal! j` because of the table at beginning of file edge case.
    call search('|')
    normal! j
    " Remove everything that is not a pipe, colon or hyphen next to a colon othewise
    " well formated tables would grow because of addition of 2 spaces on the separator
    " line by Tabularize /|.
    let l:flags = (&gdefault ? '' : 'g')
    execute 's/\(:\@<!-:\@!\|[^|:-]\)//e' . l:flags
    execute 's/--/-/e' . l:flags
    Tabularize /\(\\\)\@<!|
    " Move colons for alignment to left or right side of the cell.
    execute 's/:\( \+\)|/\1:|/e' . l:flags
    execute 's/|\( \+\):/|:\1/e' . l:flags
    execute 's/|:\?\zs[ -]\+\ze:\?|/\=repeat("-", len(submatch(0)))/' . l:flags
    call setpos('.', l:pos)
endfunction

" Parameters:
"
" - step +1 for right, -1 for left
"
" TODO: multiple lines.
"
function! s:FindCornerOfSyntax(lnum, col, step)
    let l:col = a:col
    let l:syn = synIDattr(synID(a:lnum, l:col, 1), 'name')
    while synIDattr(synID(a:lnum, l:col, 1), 'name') ==# l:syn
        let l:col += a:step
    endwhile
    return l:col - a:step
endfunction

" Return the next position of the given syntax name,
" inclusive on the given position.
"
" TODO: multiple lines
"
function! s:FindNextSyntax(lnum, col, name)
    let l:col = a:col
    let l:step = 1
    while synIDattr(synID(a:lnum, l:col, 1), 'name') !=# a:name
        let l:col += l:step
    endwhile
    return [a:lnum, l:col]
endfunction

function! s:FindCornersOfSyntax(lnum, col)
    return [<sid>FindLeftOfSyntax(a:lnum, a:col), <sid>FindRightOfSyntax(a:lnum, a:col)]
endfunction

function! s:FindRightOfSyntax(lnum, col)
    return <sid>FindCornerOfSyntax(a:lnum, a:col, 1)
endfunction

function! s:FindLeftOfSyntax(lnum, col)
    return <sid>FindCornerOfSyntax(a:lnum, a:col, -1)
endfunction

" Returns:
"
" - a string with the the URL for the link under the cursor
" - an empty string if the cursor is not on a link
"
" TODO
"
" - multiline support
" - give an error if the separator does is not on a link
"
function! s:Markdown_GetUrlForPosition(lnum, col)
    let l:lnum = a:lnum
    let l:col = a:col
    let l:syn = synIDattr(synID(l:lnum, l:col, 1), 'name')

    if l:syn ==# 'mkdInlineURL' || l:syn ==# 'mkdURL' || l:syn ==# 'mkdLinkDefTarget'
        " Do nothing.
    elseif l:syn ==# 'mkdLink'
        let [l:lnum, l:col] = <sid>FindNextSyntax(l:lnum, l:col, 'mkdURL')
        let l:syn = 'mkdURL'
    elseif l:syn ==# 'mkdDelimiter'
        let l:line = getline(l:lnum)
        let l:char = l:line[col - 1]
        if l:char ==# '<'
            let l:col += 1
        elseif l:char ==# '>' || l:char ==# ')'
            let l:col -= 1
        elseif l:char ==# '[' || l:char ==# ']' || l:char ==# '('
            let [l:lnum, l:col] = <sid>FindNextSyntax(l:lnum, l:col, 'mkdURL')
        else
            return ''
        endif
    else
        return ''
    endif

    let [l:left, l:right] = <sid>FindCornersOfSyntax(l:lnum, l:col)
    return getline(l:lnum)[l:left - 1 : l:right - 1]
endfunction

function! s:VersionAwareNetrwBrowseX(url)
    if has('patch-7.4.567')
        call netrw#BrowseX(a:url, 0)
    else
        call netrw#NetrwBrowseX(a:url, 0)
    endif
endf

command! -buffer -range=% HeaderDecrease call s:HeaderDecrease(<line1>, <line2>)
command! -buffer -range=% HeaderIncrease call s:HeaderDecrease(<line1>, <line2>, 1)
command! -buffer -range=% SetexToAtx call s:SetexToAtx(<line1>, <line2>)
command! -buffer TableFormat call s:TableFormat()
command! -buffer Toc call s:Toc()
command! -buffer Toch call s:Toc('horizontal')
command! -buffer Tocv call s:Toc('vertical')
command! -buffer -nargs=? InsertToc call s:InsertToc('bullets', <args>)
command! -buffer -nargs=? InsertNToc call s:InsertToc('numbers', <args>)

" Heavily based on vim-notes - http://peterodding.com/code/vim/notes/
if exists('g:vim_markdown_fenced_languages')
    let s:filetype_dict = {}
    for s:filetype in g:vim_markdown_fenced_languages
        let key = matchstr(s:filetype, "[^=]*")
        let val = matchstr(s:filetype, "[^=]*$")
        let s:filetype_dict[key] = val
    endfor
else
    let s:filetype_dict = {
        \ 'c++': 'cpp',
        \ 'viml': 'vim',
        \ 'bash': 'sh',
        \ 'ini': 'dosini'
    \ }
endif

function! s:MarkdownHighlightSources(force)
    " Syntax highlight source code embedded in notes.
    " Look for code blocks in the current file
    let filetypes = {}
    for line in getline(1, '$')
        let ft = matchstr(line, '```\s*\zs[0-9A-Za-z_+-]*\ze.*')
        if !empty(ft) && ft !~ '^\d*$' | let filetypes[ft] = 1 | endif
    endfor
    if !exists('b:mkd_known_filetypes')
        let b:mkd_known_filetypes = {}
    endif
    if !exists('b:mkd_included_filetypes')
        " set syntax file name included
        let b:mkd_included_filetypes = {}
    endif
    if !a:force && (b:mkd_known_filetypes == filetypes || empty(filetypes))
        return
    endif

    " Now we're ready to actually highlight the code blocks.
    let startgroup = 'mkdCodeStart'
    let endgroup = 'mkdCodeEnd'
    for ft in keys(filetypes)
        if a:force || !has_key(b:mkd_known_filetypes, ft)
            if has_key(s:filetype_dict, ft)
                let filetype = s:filetype_dict[ft]
            else
                let filetype = ft
            endif
            let group = 'mkdSnippet' . toupper(substitute(filetype, "[+-]", "_", "g"))
            if !has_key(b:mkd_included_filetypes, filetype)
                let include = s:SyntaxInclude(filetype)
                let b:mkd_included_filetypes[filetype] = 1
            else
                let include = '@' . toupper(filetype)
            endif
            let command = 'syntax region %s matchgroup=%s start="^\s*```\s*%s.*$" matchgroup=%s end="\s*```$" keepend contains=%s'
            execute printf(command, group, startgroup, ft, endgroup, include)
            execute printf('syntax cluster mkdNonListItem add=%s', group)

            let b:mkd_known_filetypes[ft] = 1
        endif
    endfor
endfunction

function! s:SyntaxInclude(filetype)
    " Include the syntax highlighting of another {filetype}.
    let grouplistname = '@' . toupper(a:filetype)
    " Unset the name of the current syntax while including the other syntax
    " because some syntax scripts do nothing when "b:current_syntax" is set
    if exists('b:current_syntax')
        let syntax_save = b:current_syntax
        unlet b:current_syntax
    endif
    try
        execute 'syntax include' grouplistname 'syntax/' . a:filetype . '.vim'
        execute 'syntax include' grouplistname 'after/syntax/' . a:filetype . '.vim'
    catch /E484/
        " Ignore missing scripts
    endtry
    " Restore the name of the current syntax
    if exists('syntax_save')
        let b:current_syntax = syntax_save
    elseif exists('b:current_syntax')
        unlet b:current_syntax
    endif
    return grouplistname
endfunction


function! s:MarkdownRefreshSyntax(force)
    if &filetype =~ 'markdown' && line('$') > 1
        call s:MarkdownHighlightSources(a:force)
    endif
endfunction

function! s:MarkdownClearSyntaxVariables()
    if &filetype =~ 'markdown'
        unlet! b:mkd_included_filetypes
    endif
endfunction

augroup Mkd
    autocmd! * <buffer>
    autocmd BufWinLeave <buffer> silent! mkview!
    autocmd BufWinEnter <buffer> silent! loadview
    autocmd BufWinEnter <buffer> call s:MarkdownRefreshSyntax(1)
    " workaround, even without options in viewoptions it still saves this
    " so it needs to be reset every time so that someone who has set their own
    " foldmethod(not manual) isn't stuck on it.
    autocmd BufWinEnter <buffer> setlocal foldmethod=manual
    autocmd BufUnload <buffer> call s:MarkdownClearSyntaxVariables()
    autocmd BufWritePost <buffer> call s:MarkdownRefreshSyntax(0)
    autocmd InsertEnter,InsertLeave <buffer> call s:MarkdownRefreshSyntax(0)
    autocmd CursorHold,CursorHoldI <buffer> call s:MarkdownRefreshSyntax(0)
augroup END

function! Foldtext_markdown()
    let line = getline(v:foldstart)
    return line . ' ...' .  repeat(" ", winwidth(0))
endfunction

setlocal comments=b:> " blockquote
setlocal formatoptions+=r " auto-insert > on newline
setlocal conceallevel=2
setlocal viewoptions=folds,cursor
setlocal foldtext=Foldtext_markdown()
setlocal foldopen-=undo

function! s:Map(lhs,rhs)
    execute 'nnoremap <buffer> <silent> ' . a:lhs . ' :call ' . a:rhs . '()<cr>'
    execute 'vnoremap <buffer> <silent> ' . a:lhs . ' <cmd>call ' . a:rhs .'()<cr>'
    execute 'inoremap <buffer> <silent> ' . a:lhs . ' <cmd>call ' . a:rhs .'()<cr>'
endfunction

function! s:MapNotHasMapTo(lhs, rhs, modes)
    for mode in split(a:modes, '\zs')
        if !hasmapto('<Plug>' . a:rhs, mode)
            execute mode . 'map <buffer> ' . a:lhs . ' <Plug>' . a:rhs
        endif
    endfor
endfunction

call <sid>Map('<Plug>Markdown_MoveToNextHeader', '<sid>MoveToNextHeader')
call <sid>Map('<Plug>Markdown_MoveToPreviousHeader', '<sid>MoveToPreviousHeader')
call <sid>Map('<Plug>Markdown_MoveToNextSiblingHeader', '<sid>MoveToNextSiblingHeader')
call <sid>Map('<Plug>Markdown_MoveToPreviousSiblingHeader', '<sid>MoveToPreviousSiblingHeader')
call <sid>Map('<Plug>Markdown_MoveToParentHeader', '<sid>MoveToParentHeader')
call <sid>Map('<Plug>Markdown_MoveToCurHeader', '<sid>MoveToCurHeader')
call <sid>Map('<Plug>Markdown_Checkbox', 'v:lua.require("markdown").toggle_checkbox')
call <sid>Map('<Plug>Markdown_Fold', 'v:lua.require("markdown").fold')
call <sid>Map('<Plug>Markdown_Jump', 'v:lua.require("markdown").jump')
call <sid>Map('<Plug>Markdown_CreateLink', 'v:lua.require("markdown").create_link')
call <sid>Map('<Plug>Markdown_FollowLink', 'v:lua.require("markdown").follow_link')
call <sid>Map('<Plug>Markdown_NewLineAbove', 'v:lua.require("markdown").new_line_above')
call <sid>Map('<Plug>Markdown_NewLineBelow', 'v:lua.require("markdown").new_line_below')

if !get(g:, 'vim_markdown_no_default_key_mappings', 0)
    call <sid>MapNotHasMapTo(']]', 'Markdown_MoveToNextHeader', 'nv')
    call <sid>MapNotHasMapTo('[[', 'Markdown_MoveToPreviousHeader', 'nv')
    call <sid>MapNotHasMapTo('][', 'Markdown_MoveToNextSiblingHeader', 'nv')
    call <sid>MapNotHasMapTo('[]', 'Markdown_MoveToPreviousSiblingHeader', 'nv')
    call <sid>MapNotHasMapTo(']u', 'Markdown_MoveToParentHeader', 'nv')
    call <sid>MapNotHasMapTo(']c', 'Markdown_MoveToCurHeader', 'nv')
    call <sid>MapNotHasMapTo('<C-c>', 'Markdown_Checkbox', 'n')
    call <sid>MapNotHasMapTo('<TAB>', 'Markdown_Fold', 'n')
    call <sid>MapNotHasMapTo('<TAB>', 'Markdown_Jump', 'i')
    call <sid>MapNotHasMapTo('<C-k>', 'Markdown_CreateLink', 'vi')
    call <sid>MapNotHasMapTo('<CR>', 'Markdown_FollowLink', 'n')
    call <sid>MapNotHasMapTo('o', 'Markdown_NewLineBelow', 'n')
    call <sid>MapNotHasMapTo('O', 'Markdown_NewLineAbove', 'n')
    call <sid>MapNotHasMapTo('<CR>', 'Markdown_NewLineBelow', 'i')
endif
