# ~/.vim/python3/gemini_handler.py
import os
import sys
import json
import google.generativeai as genai

def main():
    try:
        # Read input from Vim (stdin)
        # Expecting a JSON string with "api_key", "prompt", and "history"
        raw_input = sys.stdin.read()
        input_data = json.loads(raw_input)

        api_key = input_data.get("api_key")
        user_prompt = input_data.get("prompt")
        # History is a list of {"role": "user/model", "parts": [{"text": "..."}]}
        history_data = input_data.get("history", [])

        if not api_key:
            print_error("API key is missing.")
            return

        if not user_prompt:
            print_error("Prompt is missing.")
            return

        genai.configure(api_key=api_key)

        # For this example, we'll use a model that supports general queries and chat.
        # You might want to adjust the model name based on availability and your needs.
        # e.g., 'gemini-1.5-flash', 'gemini-1.0-pro'
        model = genai.GenerativeModel(model_name='gemini-1.5-flash')

        # Reconstruct history for the API
        chat_history_for_api = []
        for item in history_data:
            role = item.get("role")
            text = item.get("parts", [{}])[0].get("text", "")
            if role and text:
                chat_history_for_api.append({"role": role, "parts": [{"text": text}]})
        
        # Start a chat session if history is provided
        if chat_history_for_api:
            chat = model.start_chat(history=chat_history_for_api)
            response = chat.send_message(user_prompt)
        else:
            # If no history, send a single prompt
            response = model.generate_content(user_prompt)

        # Output the response as JSON to stdout for Vim to capture
        # The response object might contain more complex structures,
        # for simplicity, we're taking the text part.
        # Handle cases where the response might not have text or might be blocked.
        if response.parts:
            result = {"text": "".join(part.text for part in response.parts)}
        elif response.prompt_feedback and response.prompt_feedback.block_reason:
            result = {"error": f"Blocked: {response.prompt_feedback.block_reason.name} - {response.prompt_feedback.block_reason_message}"}
        else:
            # Try to get candidate text if parts is empty for some reason
            try:
                candidate_text = response.candidates[0].content.parts[0].text
                result = {"text": candidate_text}
            except (IndexError, AttributeError, TypeError):
                result = {"error": "No content in response or response format unexpected."}


        sys.stdout.write(json.dumps(result))

    except Exception as e:
        print_error(f"Python script error: {str(e)}\nInput was: {raw_input[:500]}") # Log part of raw_input for debugging

def print_error(message):
    """Prints an error message in JSON format to stdout."""
    error_response = {"error": message}
    sys.stdout.write(json.dumps(error_response))
    sys.exit(1)

if __name__ == "__main__":
    main()
