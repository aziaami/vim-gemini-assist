vim9script

g:gemini_assist_history = []

# Corrected: Removed 's:' from script-local const definitions
# and improved python script path definition.
const PLUGIN_ROOT: string = fnamemodify(expand('<sfile>:p'), ':h:h') # Root of the plugin
const python_executable: string = exepath('python3')
const python_handler_script_path: string = PLUGIN_ROOT .. '/python3/gemini_handler.py'

const ASSIST_BUFFER_NAME = '__GeminiAssist__'

# Helper to log messages
def Log(message: string)
    echomsg "[GeminiAssist] " .. message
enddef

# Function to call the Python script
# This function is script-local, so no 'export'
def CallGeminiAPI(prompt_text: string, include_history: bool = true): dict<any>
    if empty(g:gemini_api_key)
        echoerr "[GeminiAssist] Error: g:gemini_api_key is not set. Please set it in your vimrc."
        return {"error": "API key not set."}
    endif

    # Use the corrected script-local constants (no s: prefix)
    if empty(python_executable)
        echoerr "[GeminiAssist] Error: python3 executable not found."
        return {"error": "python3 not found."}
    endif

    if !filereadable(python_handler_script_path)
        echoerr "[GeminiAssist] Error: Python handler script not found at " .. python_handler_script_path
        return {"error": "Python handler script not found."}
    endif

    var current_history: list<dict<any>> = []
    if include_history
        current_history = g:gemini_assist_history
    endif

    var request_payload = {
        "api_key": g:gemini_api_key,
        "prompt": prompt_text,
        "history": current_history
    }
    var payload_json = json_encode(request_payload)

    try
        # Use the corrected script-local constants
        var cmd = [python_executable, "-u", python_handler_script_path]
        var response_text = system(cmd, payload_json)
    catch /.*/
        echoerr "[GeminiAssist] Error calling Python script: " .. v:exception
        var err_dict = {"error": "Failed to execute Python script. " .. v:exception}
        return err_dict
    endtry

    if empty(response_text)
        echoerr "[GeminiAssist] Error: Empty response from Python script."
        return {"error": "Empty response from Python script."}
    endif

    var response_dict: dict<any>
    try
        response_dict = json_decode(response_text)
    catch /.*/
        echoerr "[GeminiAssist] Error: Could not decode JSON response from Python: " .. response_text
        return {"error": "Invalid JSON response from Python script: " .. response_text}
    endtry

    return response_dict
enddef

export def SendMessage(user_message: string)
    if empty(user_message)
        return
    endif

    var assist_bufnr = bufwinnr(ASSIST_BUFFER_NAME) # ASSIST_BUFFER_NAME is a script-local const
    if assist_bufnr == -1
        OpenAssistBuffer()
        assist_bufnr = bufwinnr(ASSIST_BUFFER_NAME)
    endif
    if assist_bufnr == -1
        echoerr "[GeminiAssist] Could not open or find assist buffer."
        return
    endif

    var current_buf = bufnr()
    var current_win = win_getid()
    var switched_to_assist = false

    if bufnr('%') != buf číslo(ASSIST_BUFFER_NAME)
        var assist_winid = 0
        for tabnr in range(1, tabpagenr('$'))
            for winid in tabpage_winids(tabnr)
                if bufwinnr(winid) > 0 && getbufvar(winbufnr(winid), '&buftype') == 'nofile' && getbufvar(winbufnr(winid), 'bufname') == ASSIST_BUFFER_NAME
                    assist_winid = winid
                    break
                endif
            endfor
            if assist_winid > 0 then break endif
        endfor
        
        if assist_winid > 0
            win_gotoid(assist_winid)
            switched_to_assist = true
        else
            Log("Assist window not found, cannot append message.")
            return
        endif
    endif
    
    append('$', printf("You: %s", user_message))
    add(g:gemini_assist_history, {"role": "user", "parts": [{"text": user_message}]})
    if len(g:gemini_assist_history) > 40
        g:gemini_assist_history = g:gemini_assist_history[-40:]
    endif

    append('$', "Gemini: Thinking...")
    var thinking_line = line('$')
    redraw

    var response = CallGeminiAPI(user_message) # Internal call to script-local function

    call setline(thinking_line, "Gemini: ") 
    
    if haskey(response, "error")
        var current_line_content = getline(thinking_line)
        call setline(thinking_line, current_line_content .. "Error: " .. response.error)
    elseif haskey(response, "text")
        var gemini_response_text = response.text
        add(g:gemini_assist_history, {"role": "model", "parts": [{"text": gemini_response_text}]})

        var lines = split(gemini_response_text, '\n')
        
        if len(lines) > 0
            if !matchstr(lines[0], '^```')
                call setline(thinking_line, getline(thinking_line) .. lines[0])
                remove(lines, 0) 
            endif
        elseif len(lines) == 0 
             call setline(thinking_line, getline(thinking_line) .. "[Empty Response]")
        endif
        
        var append_target_line = thinking_line 
        for lnum in range(len(lines))
            var line_text = lines[lnum]
            append(append_target_line, line_text)
            append_target_line += 1 
        endfor

    else
        var current_line_content = getline(thinking_line)
        call setline(thinking_line, current_line_content .. "Unexpected response format: " .. json_encode(response))
    endif

    cursor(line('$'), 1) 
    normal! Gz$          
    
    if switched_to_assist
        win_gotoid(current_win)
    endif
    
    redraw
enddef

export def OpenAssistBuffer()
    var assist_buf_target = bufwinnr(ASSIST_BUFFER_NAME)
    if assist_buf_target != -1
        execute assist_buf_target .. 'wincmd w'
        return
    endif

    silent execute 'botright vsplit ' .. ASSIST_BUFFER_NAME
    
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal filetype=markdown
    setlocal nomodifiable

    nnoremap <buffer> <silent> q :bdelete<CR>

    if empty(g:gemini_assist_history)
        append(0, ["Gemini Assist Initialized. Type :GeminiAssist <your message> or use mappings."])
    else
        append(0, "Gemini Assist (restored)")
        for entry in g:gemini_assist_history
            var prefix = (entry.role == "user") ? "You: " : "Gemini: "
            var text_parts = entry.parts
            var message_text = ""
            if !empty(text_parts) && haskey(text_parts[0], "text")
                message_text = text_parts[0].text
            endif
            append('$', prefix .. message_text) 
        endfor
    endif
    normal! G
    redraw
    Log("Assist buffer opened.")
enddef

export def GetVisualSelection(): string
    var [line_start, col_start] = getpos("'<")[1:2]
    var [line_end, col_end] = getpos("'>")[1:2]
    if line_start == 0 || line_end == 0
        return "" 
    endif
    if line_start > line_end 
        [line_start, line_end] = [line_end, line_start]
    endif
    var lines = getline(line_start, line_end)
    if empty(lines)
        return ""
    endif
    return join(lines, "\n")
enddef

export def SyntaxHighlightBlock(start_line: number, end_line: number, language: string)
    Log(printf("Syntax highlight attempt for lines %d-%d as '%s' (via markdown)", start_line, end_line, language))
enddef

export def GetCurrentBufferContent(): string
    return join(getline(1, line('$')), "\n")
enddef

export def PromptAndSendSelection(base_cmd_name: string)
    var user_prompt = input("Gemini prompt for selection: ")
    if empty(user_prompt)
        echo "[GeminiAssist] Prompt cancelled."
        return
    endif
    var [sl, sc] = getpos("'<")[1:2] 
    var [el, ec] = getpos("'>")[1:2] 
    if sl == 0 || el == 0 
      echo "[GeminiAssist] No visual selection to send."
      return
    endif
    execute printf("%d,%d%s %s", sl, el, base_cmd_name, user_prompt)
enddef
