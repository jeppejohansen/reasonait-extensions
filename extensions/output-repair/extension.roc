manifest =
    Manifest {
        tools: [],
        subscriptions: [TurnEnd, MessageAdded],
        initial_state:
            state
                [
                    state_entry "repair_count" "0",
                    state_entry "last_text" "",
                ],
        modes: [],
    }

handle_event = |input|
    kind = parse_event_kind input
    current_state = parse_event_state input
    repair_count_str = json_get_str current_state "repair_count"
    repair_count = when Str.to_i64 repair_count_str is
        Ok n -> n
        Err _ -> 0
    when kind is
        MessageAdded ->
            payload = parse_event_payload input
            role = json_get_str payload "role"
            content = json_get_str payload "content"
            if role == "assistant" then
                event_result
                    (state [
                        state_entry "repair_count" repair_count_str,
                        state_entry "last_text" content,
                    ])
                    []
                    no_panel
            else
                event_result
                    (state [
                        state_entry "repair_count" repair_count_str,
                        state_entry "last_text" (json_get_str current_state "last_text"),
                    ])
                    []
                    no_panel
        TurnEnd ->
            last_text = json_get_str current_state "last_text"
            if repair_count >= 5 then
                # Cap at 5 repairs per session
                event_result
                    (state [
                        state_entry "repair_count" repair_count_str,
                        state_entry "last_text" "",
                    ])
                    []
                    no_panel
            else if has_text_mode_tool_call last_text then
                new_count = Num.to_str (repair_count + 1)
                nudge = "I notice you wrote a tool call in text instead of using a native tool call. Please re-issue the operation using the actual tool interface rather than writing it as text/markdown."
                event_result
                    (state [
                        state_entry "repair_count" new_count,
                        state_entry "last_text" "",
                    ])
                    [inject_followup_effect nudge]
                    no_panel
            else
                event_result
                    (state [
                        state_entry "repair_count" repair_count_str,
                        state_entry "last_text" "",
                    ])
                    []
                    no_panel
        _ ->
            event_result empty_state [] no_panel

has_text_mode_tool_call = |msg_text|
    # Detect common patterns of text-mode tool calls
    str_contains msg_text "```tool" ||
    str_contains msg_text "<tool_call>" ||
    str_contains msg_text "\"tool_name\":" ||
    str_contains msg_text "<function_calls>" ||
    str_contains msg_text "```bash\n$"

handle_tool_call = |_input|
    done "output-repair has no tools" "output-repair"

render_ui = |_input|
    no_panel
