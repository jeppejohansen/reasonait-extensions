manifest =
    Manifest {
        tools: [
            tool "write" "write content to a file (shadows builtin)"
                [
                    string_field "file_path" "absolute path to the file to write" Bool.true,
                    string_field "content" "the content to write to the file" Bool.true,
                ],
        ],
        subscriptions: [],
        initial_state:
            state
                [
                    state_entry "phase" "idle",
                    state_entry "file_path" "",
                    state_entry "content" "",
                ],
        modes: [],
    }

handle_event = |_input|
    event_result empty_state [] no_panel

handle_tool_call = |input|
    has_results = parse_tool_has_results input
    current_state = parse_event_state input
    phase = json_get_str current_state "phase"
    if Bool.not has_results then
        # Initial call - check if file exists
        args = parse_tool_arguments input
        file_path = json_get_str args "file_path"
        content = json_get_str args "content"
        need_effect
            (read_file_effect file_path)
            (state [
                state_entry "phase" "checking",
                state_entry "file_path" file_path,
                state_entry "content" content,
            ])
    else if phase == "checking" then
        # Got read result - check if file exists
        file_path = json_get_str current_state "file_path"
        content = json_get_str current_state "content"
        # If read_file succeeded, file exists → deny write
        # We check the effect result to determine success
        # In the effect_results, if success=true, file exists
        results_contains_success = str_contains input "\"success\":true"
        if results_contains_success then
            # File exists - deny and suggest edit
            denial = Str.concat "DENIED: File already exists at " (Str.concat file_path (Str.concat ". Use the Edit tool instead to modify existing files. Example: Edit { file_path: \"" (Str.concat file_path "\", old_string: \"<text to replace>\", new_string: \"<replacement>\" }")))
            done denial "write-guard"
        else
            # File does not exist - proceed with write
            need_effect
                (write_file_effect file_path content)
                (state [
                    state_entry "phase" "writing",
                    state_entry "file_path" file_path,
                    state_entry "content" "",
                ])
    else if phase == "writing" then
        # Write completed
        file_path = json_get_str current_state "file_path"
        done (Str.concat "Successfully wrote file: " file_path) "write-guard"
    else
        done "write-guard: unexpected state" "write-guard"

render_ui = |_input|
    no_panel
