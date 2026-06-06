manifest =
    Manifest {
        tools: [],
        subscriptions: [TurnStart, StreamDelta],
        initial_state:
            state
                [
                    state_entry "thinking_tokens" "0",
                    state_entry "budget" "8000",
                    state_entry "aborted" "false",
                ],
        modes: [],
    }

handle_event = |input|
    kind = parse_event_kind input
    current_state = parse_event_state input
    when kind is
        TurnStart ->
            # Reset token counter each turn
            budget = json_get_str current_state "budget"
            event_result
                (state [
                    state_entry "thinking_tokens" "0",
                    state_entry "budget" (if budget == "" then "8000" else budget),
                    state_entry "aborted" "false",
                ])
                []
                no_panel
        StreamDelta ->
            aborted = json_get_str current_state "aborted"
            if aborted == "true" then
                # Already aborted this turn, no-op
                event_result
                    (state [
                        state_entry "thinking_tokens" (json_get_str current_state "thinking_tokens"),
                        state_entry "budget" (json_get_str current_state "budget"),
                        state_entry "aborted" "true",
                    ])
                    []
                    no_panel
            else
                payload = parse_event_payload input
                thinking_text = json_get_str payload "thinking"
                if thinking_text == "" then
                    # No thinking content in this delta
                    event_result
                        (state [
                            state_entry "thinking_tokens" (json_get_str current_state "thinking_tokens"),
                            state_entry "budget" (json_get_str current_state "budget"),
                            state_entry "aborted" "false",
                        ])
                        []
                        no_panel
                else
                    current_tokens_str = json_get_str current_state "thinking_tokens"
                    current_tokens = when Str.to_i64 current_tokens_str is
                        Ok n -> n
                        Err _ -> 0
                    new_tokens = current_tokens + estimate_tokens thinking_text
                    budget_str = json_get_str current_state "budget"
                    budget = when Str.to_i64 budget_str is
                        Ok n -> n
                        Err _ -> 8000
                    if new_tokens > budget then
                        # Budget exceeded - abort and nudge
                        nudge = "Thinking budget exceeded. Please respond concisely without extended reasoning. Focus on the immediate next action."
                        event_result
                            (state [
                                state_entry "thinking_tokens" (Num.to_str new_tokens),
                                state_entry "budget" budget_str,
                                state_entry "aborted" "true",
                            ])
                            [
                                abort_turn_effect "thinking budget exceeded",
                                inject_followup_effect nudge,
                                set_model_params_effect "" "" "",
                            ]
                            no_panel
                    else
                        event_result
                            (state [
                                state_entry "thinking_tokens" (Num.to_str new_tokens),
                                state_entry "budget" budget_str,
                                state_entry "aborted" "false",
                            ])
                            []
                            no_panel
        _ ->
            event_result empty_state [] no_panel

handle_tool_call = |_input|
    done "thinking-budget has no tools" "thinking-budget"

render_ui = |input|
    current_state = parse_event_state input
    tokens_str = json_get_str current_state "thinking_tokens"
    budget_str = json_get_str current_state "budget"
    if tokens_str == "0" || tokens_str == "" then
        no_panel
    else
        label = Str.concat "thinking: " (Str.concat tokens_str (Str.concat "/" budget_str))
        text_panel Footer Append label
