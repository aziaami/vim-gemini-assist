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

    var assist_bufnr = bufwinnr(ASSIST_BUFFER_NAME)
    if assist_bufnr == -1 # If no window is associated with the buffer
        # Try to find the buffer number directly, maybe it exists but has no window
        assist_bufnr = bufnr(ASSIST_BUFFER_NAME)
        if assist_bufnr == -1 # Buffer truly doesn't exist
            OpenAssistBuffer() # This will create it and a window
            assist_bufnr = bufnr(ASSIST_BUFFER_NAME) # Get its number
        else # Buffer exists, but no window - OpenAssistBuffer will switch or open a window
            OpenAssistBuffer() 
        endif
        # Re-check window association after OpenAssistBuffer
        assist_bufnr = bufwinnr(ASSIST_BUFFER_NAME) 
    endif

    if assist_bufnr == -1 # If still -1, OpenAssistBuffer failed to create/find window
        echoerr "[GeminiAssist] Could not open or find assist buffer window."
        return
    endif

    var current_buf_nr_on_entry = bufnr('%') # Store current buffer number when function is called
    var current_win_id_on_entry = win_getid()   # Store current window ID
    var switched_to_assist_buffer_window = false

    # Check if the current buffer (in the active window) is the assist buffer
    # Corrected line:
    if bufnr('%') != bufnr(ASSIST_BUFFER_NAME)
        # If not, we need to find the assist buffer's window and switch to it
        var assist_win_id = 0
        # Iterate through all windows in all tabpages to find the assist buffer's window
        for tabnr in range(1, tabpagenr('$'))
            for winid_in_tab in tabpagebuflist(tabnr)
                # getbufinfo returns a list, check if it's not empty
                var buf_info_list = getbufinfo(winbufnr(winid_in_tab))
                if !empty(buf_info_list) && buf_info_list[0].name =~ ASSIST_BUFFER_NAME 
                    assist_win_id = winid_in_tab
                    break
                endif
            endfor
            if assist_win_id > 0
              break
            endif
        endfor
        
        if assist_win_id > 0
            win_gotoid(assist_win_id) # Switch to the assist buffer's window
            switched_to_assist_buffer_window = true
        else
            # This case should ideally be handled by OpenAssistBuffer ensuring a window exists.
            # If we reach here, it means assist_bufnr (from bufwinnr) found a window,
            # but now we can't find it by iterating, which is contradictory.
            # Or, if assist_bufnr was from bufnr() only, and OpenAssistBuffer didn't set up a window correctly.
            Log("Assist window not found by iteration, cannot append message. Buffer may exist without window.")
            # Attempt to force OpenAssistBuffer again to ensure a window context
            OpenAssistBuffer()
            if bufnr('%') != bufnr(ASSIST_BUFFER_NAME) # If still not in assist buffer window
                echoerr "[GeminiAssist] Failed to switch to the assist buffer window."
                return
            endif
            # If OpenAssistBuffer switched context, mark it
            switched_to_assist_buffer_window = true 
        endif
    endif
    
    # At this point, we should be in the assist buffer's window
    # Make buffer modifiable to append text
    setlocal modifiable

    append('$', printf("You: %s", user_message))
    add(g:gemini_assist_history, {"role": "user", "parts": [{"text": user_message}]})
    if len(g:gemini_assist_history) > 40
        g:gemini_assist_history = g:gemini_assist_history[-40:]
    endif

    append('$', "Gemini: Thinking...")
    var thinking_line = line('$')
    redraw # Show "Thinking..."

    # No longer modifiable while thinking, API call can take time
    setlocal nomodifiable 

    var response = CallGeminiAPI(user_message)

    # Make modifiable again to write response
    setlocal modifiable

    call setline(thinking_line, "Gemini: ") 
    
    if has_key(response, "error")
        var current_line_content = getline(thinking_line)
        call setline(thinking_line, current_line_content .. "Error: " .. response.error)
    elseif has_key(response, "text")
        var gemini_response_text = response.text
        add(g:gemini_assist_history, {"role": "model", "parts": [{"text": gemini_response_text}]})

        var lines = split(gemini_response_text, '\n')
        
        if len(lines) > 0
            if !matchstr(lines[0], '^```') # If first line is not a code block start
                call setline(thinking_line, getline(thinking_line) .. lines[0]) # Append to "Gemini: " line
                remove(lines, 0) # Remove processed line
            endif
        elseif len(lines) == 0 # Empty response text
             call setline(thinking_line, getline(thinking_line) .. "[Empty Response]")
        endif
        
        # Append remaining lines
        var append_target_line = thinking_line 
        if line('$') > thinking_line && getline(thinking_line + 1) != "" # If first line was already part of a multi-line initial setline
            # This condition might be tricky. Simpler to just append after current last line if lines exist.
        endif

        # Ensure appending after the (potentially updated) thinking_line
        append_target_line = line('$') 

        for lnum in range(len(lines))
            var line_text = lines[lnum]
            # append() adds after the given line number. So, append after current last line.
            append(line('$'), line_text) 
        endfor

    else # Unexpected response format
        var current_line_content = getline(thinking_line)
        call setline(thinking_line, current_line_content .. "Unexpected response format: " .. json_encode(response))
    endif

    # Ensure view is at the bottom and cursor is on the last line
    cursor(line('$'), 1) 
    normal! Gz$          
    
    # Restore original modifiable state (usually nomodifiable for the chat buffer)
    setlocal nomodifiable 

    # Switch back to the original window if we switched
    if switched_to_assist_buffer_window && win_getid() != current_win_id_on_entry
        win_gotoid(current_win_id_on_entry)
        # Restore modifiable state of the original buffer too if necessary (usually not affected by setlocal)
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
    
    # Set options that don't prevent modification first
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal filetype=markdown

    nnoremap <buffer> <silent> q :bdelete<CR>

    # Now, append initial content
    if empty(g:gemini_assist_history)
        append(0, ["Gemini Assist Initialized. Type :GeminiAssist <your message> or use mappings."])
    else
        append(0, "Gemini Assist (restored)")
        for entry in g:gemini_assist_history
            var prefix = (entry.role == "user") ? "You: " : "Gemini: "
            var text_parts = entry.parts
            var message_text = ""
            if !empty(text_parts) && has_key(text_parts[0], "text")
                message_text = text_parts[0].text
            endif
            append('$', prefix .. message_text) 
        endfor
    endif
    
    # All initial content is appended. Now make the buffer non-modifiable.
    setlocal nomodifiable 

    # Go to the end of the buffer
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
