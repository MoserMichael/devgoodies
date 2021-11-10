
"======================================================
" utility functions
"======================================================
function! s:Chomp(string)
    return substitute(a:string, '\n\+$', '', '')
endfunction


if !exists(":SetModeForBuffer")

"############################################
" set tabs vs spaces depending on buffer type
"############################################
command! -nargs=* SetModeForBuffer call s:SetModeForBuffer()

function! s:SetModeForBuffer()

    let s:extension = expand('%:e')
    let s:fname = expand("%")
    echo s:fname

    if s:extension == "go" || s:fname == "Makefile" || s:fname =='makefile' || s:extension == 'mk' || s:fname == "GNUmakefile"
        " in go and makefiles they like tabs. strange but true.
        set noexpandtab
    else
        " every other languages is preferring tabs, apparently
        set expandtab
    endif
endfunction

autocmd BufEnter * :SetModeForBuffer

endif

"======================================================
"open quickfix window, and make it a third of the screen
"======================================================

if !exists(":OpenQuickFix")

command! -nargs=* OpenQuickFix call s:OpenQuickFix()

function!  s:OpenQuickFix()
	let size = &lines
	let size = size / 3
    let s:ccmdo = 'copen ' . size
    execute s:ccmdo
endfunction

endif

"======================================================
" check if there is a makefile here; 
" optionally checks if target exists.
"======================================================

function! s:MakeHasTarget(targetName)
    " name of default makefiles:  
    let s:makefilenames = [ 'GNUmakefile', 'makefile', 'Makefile' ]

    for s:item in s:makefilenames 
        if filereadable(s:item)
            if a:targetName == ''
                return 1
            endif
            let s:cmd = "grep -cE '^" . a:targetName . ":'" 
            let s:hasTarget=system(s:cmd) 
            if s:hasTarget != "0"
                return 1
            endif
        endif
    endfor
endfunction

if !exists(":PrevBuildResults")

"======================================================
"Build  script
"======================================================

command! -nargs=* PrevBuildResults call s:SetPrevBuildResults()

" bring back the result of the last build (restores quickfix window)
function! s:SetPrevBuildResults()
  if exists("g:buildCommandOutput")
      " Read the output from the command into the quickfix window
      "execute "cfile! " . g:buildCommandOutput
      "
      let old_efm = &efm
      set efm=%f:%l:%m
      execute "silent! cgetfile " . g:buildCommandOutput
      let &efm = old_efm
      " Open the quickfix window
      OpenQuickFix
  endif
endfunction 

endif

if !exists(":Build")

function! BuildJobEofCallbackGlobal(job, exit_status)
    call delete(g:buildCommandWraper) 

    " make quickfix window readonly again, now that the build has ended.
    let s:quick_fix_buffer = getqflist({'qfbufnr' : 0}).qfbufnr
    call setbufvar(s:quick_fix_buffer, "&modifiable", 0)
    call setbufvar(s:quick_fix_buffer, "&modified", 0)

    unlet g:build_job

    " delete previous build results
    if !exists("g:buildCommandOutput")
      g:buildCommandOutput = tempname()
    endif
    call writefile( getbufline(s:quick_fix_buffer, 1, "$"), g:buildCommandOutput )

endfunction

command! -nargs=* B call s:RunBuild()
command! -nargs=* Build call s:RunBuild()

function! s:RunBuild()

    " save the current file
    execute "silent! :w"

    " run build command ---
    if filereadable("./make_override")
        let s:buildcmd = './make_override'
    elseif filereadable("./build.gradle") 
        if filereadable("./gradlew")
            let s:buildcmd = "./gradlew build cleanTest test --fail-fast"
        else
            let s:buildcmd = "gradle cleanTest test --fail-fast"
        endif
    elseif filereadable("./pom.xml")
        let s:buildcmd = 'mvn test'
    elseif  s:MakeHasTarget('') == 0
        let s:buildcmd = "make " . $MAKE_OPT
    else
        echo "don't know how to build this"
            return
    endif

    let g:buildCommandWraper = tempname()
    let g:buildCommandOutput = tempname()

    "use files
    "let s:wrapper = [ "echo 'Build command: '" . s:buildcmd, "echo ''", s:buildcmd . " 2>&1 | tee " . g:buildCommandOutput  ]
    
    " use buffers
    let s:wrapper = [ "echo 'Build command: '" . s:buildcmd, "echo ''", s:buildcmd . " 2>&1" ]
    call writefile( s:wrapper, g:buildCommandWraper)
    
    OpenQuickFix

    "use buffers
    let s:quick_fix_buffer = getqflist({'qfbufnr' : 0}).qfbufnr
    "must set quickfix window as modifiable, for the duration of the build."(otherwise it can't append anything)
    call setbufvar(s:quick_fix_buffer, "&modifiable", 1)

    let g:build_job = job_start( [ "/bin/sh", g:buildCommandWraper ], {'out_io' : 'buffer', 'out_buf': s:quick_fix_buffer, 'exit_cb': function('BuildJobEofCallbackGlobal') })

endfunction
            
endif

if !exists(":StopBuild")

command! -nargs=* StopBuild call s:StopBuild()

function! s:StopBuild()
    if exists("g:build_job")
       echo "stopping build"
       call job_stop(g:build_job)
       unlet g:build_job
       call delete( g:buildCommandOutput )
       unlet g:buildCommandOutput
    else
       echo "no build running"
    endif

endfunction

endif

"======================================================
" pretty print/format the current source file.
"======================================================

if !exists(":Format")

command! -nargs=* Format call s:RunFormat()

function! s:RunOnCurrentBuffer(cmd, opts)

    if executable(a:cmd)
        let s:file = expand('%:p')
        if filewritable(s:file)
            execute "silent! :w"
            let s:cmd = a:cmd . " " . a:opts . " " . s:file
            call system( s:cmd )
            execute "silent! e ". s:file
        else 
            echo "Error: file " . s:file . " is not writable"
        endif
    else
        echo "Error: " . a:cmd . " program is not in the current path"
    endif

endfunction

function! s:RunFormat()

    let s:extension = expand('%:e')

    " remove trailing spaces, in an case
    if s:extension == "go"
        echo "formatting go code in current buffer"
        if !executable("gofmt")
            echo "Error: executable gofmt is not found in current path"
            return
        endif
        call s:RunOnCurrentBuffer("gofmt", "-w")
        echo "go code formatted'

    elseif s:extension == "c" || s:extension == "cpp" || s:extension == "h" || s:extension == "hpp"
        echo "formatting c/c++ code in current buffer"
        if !executable("clang-format")
            echo "Error: executable clang-format is not found in current path'
            return
        endif
        
        call s:RunOnCurrentBuffer("clang-format", "-i")
        echo "c/c++ code formatted"

    elseif s:extension == "py"
        echo "formatting python code"
        if !executable("black")
            echo "Error: executable block is not found in current path"
            return
        endif
        call s:RunOnCurrentBuffer("black","")
        echo "python code formatted"

    else
        echo "for file with extension ". s:extension " in current buffer: tabs to spaces & removing trailing spaces only."
        "tabs to spaces
        :retab
        "remove trailing newlines
        :%s/\s\+$//e
        :set ff=unix
        execute "silent! :w"
        echo "command completed"
    endif
endfunction

endif

"======================================================
"" check/lint the current source file.
"======================================================

if !exists(":Lint")

command! -nargs=* Lint call s:RunLint()

function! s:RunLint()

    " save the current file
    execute "silent! :w"

    let s:extension = expand('%:e')

    let s:file = expand('%:p')
    let s:tmpfile = tempname()

    if s:extension == "sh"
        execute "silent! :w"

        if !executable("shellcheck")
            echo "Error: shellcheck is not found in the current path"
            return
        endif

        let s:cmd = "shellcheck -f gcc " . s:file . " > " . s:tmpfile . " 2>&1"

        let old_efm = &efm
        set efm=%f:%l:%m

    elseif s:extension == "py"

        if !executable("pylint")
            echo "Error: pylint is not found in the current path"
            return
        endif

        " remove trailing whitespaces (tha's one of the issues)
        :%s/\s\+$//e
        execute "silent! :w"

        " enable warnings and errors
        let s:cmd = "pylint --disable=C0301 --disable=C0116 --disable=C0115 --disable=C0114 " . s:file . " > " . s:tmpfile . " 2>&1"

        "let s:cmd = "pylint --reports=n --output-format=parseable %:p --disable=R,C " . s:file . " > " . s:tmpfile . " 2>&1"

        " enable errors only
        "let s:cmd = "pylint -E " . s:file . " > " . s:tmpfile . " 2>&1"

        let old_efm = &efm
        set efm=%f:%l:%m
    elseif s:extension == "pl"

        if !executable("perl")
            echo "Error: perl5 is not installed in current path"
            return
        endif

        call system("perl -MPerl::Critic -e 1 2>/dev/null")
        if v:shell_error == 0
            let s:critic = "perl -E 'use Perl::Critic::Command qw< run >; exit run() if not caller or $ENV{PAR_0};' -- -2 --verbose 1 --nocolor "

            let s:cmd = s:critic . s:file . " > " . s:tmpfile . " 2>&1"
     
            let old_efm = &efm
            set efm=%f:%l:%m
        else 
            echo "Error: perl5 critic is not installed, install with: cpan Perl::Critic"
            return
        endif

    elseif s:extension == "go"

        execute "silent! :w"

        if s:MakeHasTarget('vet') 
            let s:cmd = "make vet > " . s:tmpfile . " 2>&1"

            let old_efm = &efm
            set efm=%f:%l:%m
        else
            echo "for go it assumes a Makefile with target vet in the current directory"
        endif
    else
        echo "no action for file extension ". s:extension
        call delete(s:tmpfile)
        return
    endif

    call system( s:cmd )
    let &efm = old_efm

    OpenQuickFix

	execute "silent! cgetfile " . s:tmpfile
    call delete(s:tmpfile)

    if getfsize(s:tmpfile)  == 0
        echohl WarningMsg |
        \ echomsg "*** no lint errors found ***" |
        \ echohl None
        return
    endif
endfunction

endif

"======================================================
" comment out a selection of lines
"======================================================

if !exists(":Comment")

command! -nargs=* Comment call s:RunComment()


function! s:RunComment()

    let s:extension = expand('%:e')
    let s:file=expand('%:p')

    if has('win32') || has ('win64')
        let  s:VIMRC = $VIM."/.vimrc"
    else
        let  s:VIMRC = $HOME."/.vimrc"
    endif

    if s:extension == "vim" || s:file == s:VIMRC

        let s:cmt='"'

    elseif s:extension == "sh" || s:extension == "py" || s:extension == "pl" || s:extension == "yaml"

        let s:cmt="#"

    elseif s:extension == "java" || s:extension == "go" || s:extension == "cpp" || s:extension == "c" || s:extension == "h" || s:extension == "hpp"

        let s:cmt="//"

    else
        " default of the default.
        let s:cmt="#"

        "echo "can't comment out buffer with extension " . s:extension
        "return

    endif

    let [s:line_start, s:column_start] = getpos("'<")[1:2]
    let [s:line_end, s:column_end] = getpos("'>")[1:2]


    let s:cur = s:line_start
    while s:cur <= s:line_end
    "
        let s:line = s:cmt . getline(s:cur)
        call setline(s:cur, s:line)
        let s:cur = s:cur + 1
    endwhile
endfunction

endif

if !exists(":UnComment")

command! -nargs=* UnComment call s:RunUnComment()

function! s:RunUncomment()

    let s:extension = expand('%:e')
    let s:file=expand('%:p')

    if has('win32') || has ('win64')
        let  s:VIMRC = $VIM."/.vimrc"
    else
        let  s:VIMRC = $HOME."/.vimrc"
    endif

    if s:extension == "vim" || s:file == s:VIMRC

        let s:cmt='"'
        let s:cmtlen=1

    elseif s:extension == "sh" || s:extension == "py" || s:extension == "pl" || s:extension == "yaml"

        let s:cmt="#"
        let s:cmtlen=1

    elseif s:extension == "go" || s:extension == "cpp" || s:extension == "c" || s:extension == "h" || s:extension == "hpp"

        let s:cmt="//"
        let s:cmtlen=2

    else

        let s:cmt="#"
        let s:cmtlen=1

    endif

    let [s:line_start, s:column_start] = getpos("'<")[1:2]
    let [s:line_end, s:column_end] = getpos("'>")[1:2]


    let s:cur = s:line_start
    let s:extractlen=s:cmtlen-1
    while s:cur <= s:line_end
    "
        let s:line = getline(s:cur)

        if s:line[0:s:extractlen] == s:cmt
            call setline(s:cur, s:line[s:cmtlen:])
        endif
        let s:cur = s:cur + 1
    endwhile
endfunction

endif

if !exists(":UseTags")

"======================================================
" Use tags (search in git root, else in current dir)
"======================================================
command! -nargs=* UseTags call s:RunUseTags()

function s:RunUseTags()

    let s:get_root="git rev-parse --show-toplevel 2>/dev/null"
    let s:top_dir = system(s:get_root)

    if s:top_dir == ""
        let s:top_dir = getcwd()
    endif

    let s:top_dir=s:Chomp(s:top_dir)


    let s:tag_file = s:top_dir . "/tags"

    if filereadable(s:tag_file)
        let s:set_cmd = "set tags=". s:tag_file
        execute s:set_cmd
        "echo "set tags ". s:tag_file
    endif

endfunction

call s:RunUseTags()

endif

if !exists(":MakeTags")

"======================================================
" Build tags based on the extenson of file open in the editor
"======================================================
command! -nargs=* MakeTags call s:RunMakeTags(<q-args>)

function! s:RunMakeTags(type)

    let s:get_root="git rev-parse --show-toplevel 2>/dev/null"
    let s:top_dir = system(s:get_root)

    if s:top_dir == ""
        let s:top_dir = getcwd()
    endif
    
    let s:type = ""
    let s:extension = expand('%:e')

    if a:type != ""
        let s:type = a:type
    elseif s:extension == "go"
        let s:type = "go"
    "don't know how to distinguish c or c++ for header files..
    elseif s:extension == "c" 
        s:type ="c"
    elseif s:extension == "c" || s:extension == "cpp" || s:extension == "cxx" || s:extension == "h" || s:extension == "hpp" || s:extension == "hxx"
        s:type ="cpp"
    elseif s:extension == "py"
        let s:type = "py"
    elseif s:extension == "java"
        let s:type = "java"
    endif

    if s:type == "go"
        if !executable("gotags")
            echo "Error: can't find gotags program, required for tagging of go files"
            return
        endif
    else
        if !executable("ctags")
            echo "Error: can't find ctags program, required for tagging"
            return
        endif
    endif

    if s:type == "go"
        echo "building go tags"
        let s:cmd="find . -type f ( -name \'*.go\' ) -print0 | xargs -0 /usr/bin/gotags >tags"

    elseif s:type == "c"
        echo "building c tags"
        let s:cmd="find . -type f ( -name \'*.c\' -o -name \'*.h\' ) | xargs ctags -a --language-force=C"

    elseif s:type == "cpp"
        echo "building c/c++ tags"
        let s:cmd="find . -type f ( -name \'*.c\' -o -name \'*.cpp\' -o -name \'*.cxx\' -o -name \'*.hpp\' -o -name \'*.hxx\' -o -name \'*.h\' ) | xargs ctags -a --c++-kinds=+p --fields=+iaS --extra=+q --language-force=C++"

    elseif s:type == "py"
        echo "building python tags"
        let s:cmd="find . -type f ( -name \'*.py\' ) | xargs ctags -a --language-force=Python"

    elseif s:type == "java"
        echo "building java tags"
        let s:cmd="find . -type f ( -name \'*.java\' ) | xargs ctags -a --language-force=java"
    else
        echo "building any tags, recursively"
        let s:cmd = "ctags -R  ./*"
    endif


    "save current buffer.
    execute "silent! :w"

    let s:get_root="git rev-parse --show-toplevel 2>/dev/null"
    let s:top_dir = system(s:get_root)
    if s:top_dir == ""
        let s:top_dir = getcwd()
    endif

    let s:top_dir=s:Chomp(s:top_dir)

    call chdir(s:top_dir)
    call system(s:cmd)
    call chdir("-")

    let s:set_tags = "set tags=". s:top_dir . "/tags"
    execute s:set_tags

    echo "building of tags completed"

endfunction

endif


if !exists(":DoGrep")

"======================================================
"grep script
"Courtesy of Yegappan Lakshmanan
"
"(with my modifications)
"======================================================
command! -nargs=* DoGrep call s:RunGrep()

if !exists("Grep_Default_Filelist")
    let Grep_Default_Filelist = '*.cc *.c *.cpp *.cxx *.h *.inl *.hpp *.hxx *.py *.go'
endif

if !exists("Grep_Default_Dir")
    let Grep_Default_Dir = '.'
endif

" Character to use to quote patterns and filenames before passing to grep.
if !exists("Grep_Shell_Quote_Char")
    if has("win32") || has("win16") || has("win95")
        let Grep_Shell_Quote_Char = ''
    else
        let Grep_Shell_Quote_Char = "'"
    endif
endif

function! s:RunGrep()
   " --- No argument supplied. Get the identifier and file list from user ---
    let s:pattern = input("Grep for pattern: ", expand("<cword>"))
    if s:pattern == ""
        return
    endif
    let s:pattern = g:Grep_Shell_Quote_Char . s:pattern . g:Grep_Shell_Quote_Char

    let s:filenames = input("Grep in files: ", g:Grep_Default_Filelist)
    if s:filenames == ""
        return
    endif

"   if filenames != g:Grep_Default_Filelist
"     let g:Grep_Default_Filelist = filenames
"   endif

    let s:searchdir = input("Grep in directory: ", g:Grep_Default_Dir)
    if s:searchdir == ""
        return
    endif
    if s:searchdir != g:Grep_Default_Dir
      let g:Grep_Default_Dir = s:searchdir
    endif


    " --- build find command ---
    let s:txt = s:filenames . ' '
    let s:find_file_pattern = ''

    while s:txt != ''
        let s:one_pattern = strpart(s:txt, 0, stridx(s:txt, ' '))
        if s:find_file_pattern != ''
            let s:find_file_pattern = s:find_file_pattern . ' -o'
        endif
        let s:find_file_pattern = s:find_file_pattern . ' -name ' . g:Grep_Shell_Quote_Char . s:one_pattern . g:Grep_Shell_Quote_Char

        let s:txt = strpart(s:txt, stridx(s:txt, ' ') + 1)
     endwhile

    let s:tmpfile = tempname()
    let s:grepcmd = 'find ' . s:searchdir . " " . s:find_file_pattern . " | xargs grep -Hn " . s:pattern . " |  tee " . s:tmpfile

    " --- run grep command ---
    let s:cmd_output = system(s:grepcmd)

    if s:cmd_output == ""
        echohl WarningMsg |
        \ echomsg "Error: Pattern " . s:pattern . " not found" |
        \ echohl None
        return
    endif

    " --- put output of grep command into message window ---
    let s:old_efm = &efm
    set efm=%f:%l:%m

   "open search results, but do not jump to the first message (unlike cfile)
   "execute "silent! cfile " . tmpfile
    execute "silent! cgetfile " . s:tmpfile

    let &efm = s:old_efm

    OpenQuickFix

    call delete(s:tmpfile)

endfunction

endif

if !exists(":ReDir")



" copied from here: https://gist.github.com/romainl/eae0a260ab9c135390c30cd370c20cd7
function! s:Redir(cmd, rng, start, end)
	for win in range(1, winnr('$'))
		if getwinvar(win, 'scratch')
			execute win . 'windo close'
		endif
	endfor
	if a:cmd =~ '^!'
		let s:cmd = a:cmd =~' %'
			\ ? matchstr(substitute(a:cmd, ' %', ' ' . expand('%:p'), ''), '^!\zs.*')
			\ : matchstr(a:cmd, '^!\zs.*')
		if a:rng == 0
			let s:output = systemlist(s:cmd)
		else
			let s:joined_lines = join(getline(a:start, a:end), '\n')
			let s:cleaned_lines = substitute(shellescape(s:joined_lines), "'\\\\''", "\\\\'", 'g')
			let s:output = systemlist(s:cmd . " <<< $" . s:cleaned_lines)
		endif
	else
		redir => s:output
		execute a:cmd
		redir END
		let  s:output = split(s:output, "\n")
	endif
	vnew
	let w:scratch = 1
	setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile
	call setline(1, s:output)

    let s:rename="file " . s:cmd
    execute s:rename
endfunction

command! -nargs=1 -complete=command -bar -range Redir silent call s:Redir(<q-args>, <range>, <line1>, <line2>)

endif

