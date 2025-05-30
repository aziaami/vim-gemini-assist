# ~/.vim/plugin/gemini_assist_plugin.vim
vim9script

if exists("g:loaded_gemini_assist_plugin") # Renamed
    finish
endif
let g:loaded_gemini_assist_plugin = 1 # Renamed

var autoload_path = fnamemodify(expand('<sfile>:p'), ':h:h') .. '/autoload'
if !isdirectory(autoload_path)
    echoerr "[GeminiAssist] Error: Autoload directory not found at " .. autoload_path # Renamed
    finish
endif

# --- User Commands --- Renamed commands
command! GeminiAssistOpen call gemini_assist.OpenAssistBuffer()
command! -nargs=+ GeminiAssist call gemini_assist.SendMessage(<q-args>)
command! -nargs=* -range GeminiAssistSelection <line1>,<line2>call s:HandleSelection(<q-args>, <line1>, <line2>)
command! -nargs=+ GeminiAssistBuffer call s:HandleCurrentBuffer(<q-args>)

# --- Helper functions for commands ---
def s:HandleSelection(custom_prompt_parts: list<string>, first: number, last: number)
    var selected_lines = getline(first, last)
    var selected_text = join(selected_lines, "\n")

    if empty(selected_text)
        echo "[GeminiAssist] No text selected." # Renamed
        return
    endif

    var custom_prompt = join(custom_prompt_parts, " ")
    var full_prompt: string
    if !empty(custom_prompt)
        full_prompt = custom_prompt .. "\n\n```\n" .. selected_text .. "\n```"
    else
        full_prompt = "Regarding the following code:\n\n```\n" .. selected_text .. "\n```\n\nWhat would you like to do or know?"
    endif
    
    gemini_assist.SendMessage(full_prompt) # Renamed module and function
enddef

def s:HandleCurrentBuffer(custom_prompt_parts: list<string>)
    var buffer_content = gemini_assist.GetCurrentBufferContent() # Renamed module
    if empty(buffer_content)
        echo "[GeminiAssist] Current buffer is empty." # Renamed
        return
    endif

    var custom_prompt = join(custom_prompt_parts, " ")
    var full_prompt: string
    if !empty(custom_prompt)
        full_prompt = custom_prompt .. "\n\nContext from current file:\n---\n" .. buffer_content .. "\n---"
    else
        full_prompt = "Regarding the content of the current file:\n---\n" .. buffer_content .. "\n---\n\nWhat would you like to do or know?"
    endif

    gemini_assist.SendMessage(full_prompt) # Renamed module and function
enddef

# This internal <SID> function is for mappings defined within this plugin file.
# For user .vimrc mappings calling an autoloaded function, they should use gemini_assist#PromptAndSendSelection
def s:PromptAndSendSelection(base_cmd: string)
    var user_prompt = input("Gemini prompt for selection: ")
    if empty(user_prompt)
        echo "[GeminiAssist] Prompt cancelled." # Renamed
        return
    endif
    var [sl, sc] = getpos("'<")[1:2]
    var [el, ec] = getpos("'>")[1:2]
    if sl == 0 || el == 0
      echo "[GeminiAssist] No visual selection to send." # Renamed
      return
    endif
    # Escape user_prompt for command execution
    var escaped_user_prompt = escape(user_prompt, ' ')
    execute printf("%d,%d%s %s", sl, el, base_cmd, escaped_user_prompt)
enddef


echomsg "Gemini Assist Plugin Loaded. Use :GeminiAssistOpen, :GeminiAssist, etc." # Renamed
