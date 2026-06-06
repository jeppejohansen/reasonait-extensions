manifest =
    Manifest {
        tools: [],
        subscriptions: [TurnStart, TurnEnd, ContextBuild, ToolCall, ToolResult, ModeChanged],
        initial_state:
            state
                [
                    state_entry "active" "false",
                    state_entry "turn" "0",
                    state_entry "estimated_tokens" "0",
                    state_entry "token_ceiling" "0",
                    state_entry "needs_compaction" "false",
                    state_entry "compaction_count" "0",
                    state_entry "message_count" "0",
                    state_entry "tools_this_turn" "0",
                    state_entry "tools_total" "0",
                    state_entry "followup_depth" "0",
                    state_entry "last_event" "idle",
                ],
        modes: [
            Mode {
                name: "observe",
                display_name: "Agent Monitor",
                description: "Live agent loop state",
            },
        ],
    }

handle_event = |input|
    kind = parse_event_kind input
    current_state = parse_event_state input
    payload = parse_event_payload input
    when kind is
        ModeChanged ->
            mode_name = json_get_str payload "mode"
            is_active = if mode_name == "agent-monitor.observe" then "true" else "false"
            event_result
                (preserve_state current_state is_active)
                []
                no_panel
        ContextBuild ->
            est_tokens = json_get_str payload "estimated_tokens"
            ceiling = json_get_str payload "token_ceiling"
            compaction = json_get_str payload "needs_compaction"
            msg_count = json_get_str payload "message_count"
            followup = json_get_str payload "followup_queue_depth"
            turn_val = json_get_str payload "turn"
            # Track compaction triggers
            old_compaction = json_get_str current_state "needs_compaction"
            old_count_str = json_get_str current_state "compaction_count"
            old_count = when Str.to_i64 old_count_str is
                Ok n -> n
                Err _ -> 0
            new_count = if compaction == "true" && old_compaction == "false" then
                old_count + 1
            else
                old_count
            event_result
                (state [
                    state_entry "active" (json_get_str current_state "active"),
                    state_entry "turn" (if turn_val == "" then json_get_str current_state "turn" else turn_val),
                    state_entry "estimated_tokens" (if est_tokens == "" then "0" else est_tokens),
                    state_entry "token_ceiling" (if ceiling == "" then "0" else ceiling),
                    state_entry "needs_compaction" (if compaction == "" then "false" else compaction),
                    state_entry "compaction_count" (Num.to_str new_count),
                    state_entry "message_count" (if msg_count == "" then "0" else msg_count),
                    state_entry "tools_this_turn" (json_get_str current_state "tools_this_turn"),
                    state_entry "tools_total" (json_get_str current_state "tools_total"),
                    state_entry "followup_depth" (if followup == "" then "0" else followup),
                    state_entry "last_event" "context_build",
                ])
                []
                no_panel
        TurnStart ->
            turn_val = json_get_str payload "turn"
            event_result
                (state [
                    state_entry "active" (json_get_str current_state "active"),
                    state_entry "turn" (if turn_val == "" then json_get_str current_state "turn" else turn_val),
                    state_entry "estimated_tokens" (json_get_str current_state "estimated_tokens"),
                    state_entry "token_ceiling" (json_get_str current_state "token_ceiling"),
                    state_entry "needs_compaction" (json_get_str current_state "needs_compaction"),
                    state_entry "compaction_count" (json_get_str current_state "compaction_count"),
                    state_entry "message_count" (json_get_str current_state "message_count"),
                    state_entry "tools_this_turn" "0",
                    state_entry "tools_total" (json_get_str current_state "tools_total"),
                    state_entry "followup_depth" (json_get_str current_state "followup_depth"),
                    state_entry "last_event" "turn_start",
                ])
                []
                no_panel
        TurnEnd ->
            event_result
                (preserve_state_with current_state "last_event" "turn_end")
                []
                no_panel
        ToolCall ->
            tools_turn_str = json_get_str current_state "tools_this_turn"
            tools_total_str = json_get_str current_state "tools_total"
            tools_turn = when Str.to_i64 tools_turn_str is
                Ok n -> n
                Err _ -> 0
            tools_total = when Str.to_i64 tools_total_str is
                Ok n -> n
                Err _ -> 0
            tool_name = json_get_str payload "tool_name"
            last_ev = if tool_name == "" then "tool_call" else Str.concat "tool:" tool_name
            event_result
                (state [
                    state_entry "active" (json_get_str current_state "active"),
                    state_entry "turn" (json_get_str current_state "turn"),
                    state_entry "estimated_tokens" (json_get_str current_state "estimated_tokens"),
                    state_entry "token_ceiling" (json_get_str current_state "token_ceiling"),
                    state_entry "needs_compaction" (json_get_str current_state "needs_compaction"),
                    state_entry "compaction_count" (json_get_str current_state "compaction_count"),
                    state_entry "message_count" (json_get_str current_state "message_count"),
                    state_entry "tools_this_turn" (Num.to_str (tools_turn + 1)),
                    state_entry "tools_total" (Num.to_str (tools_total + 1)),
                    state_entry "followup_depth" (json_get_str current_state "followup_depth"),
                    state_entry "last_event" last_ev,
                ])
                []
                no_panel
        ToolResult ->
            status = json_get_str payload "status"
            last_ev = if status == "" then "tool_result" else Str.concat "result:" status
            event_result
                (preserve_state_with current_state "last_event" last_ev)
                []
                no_panel
        _ ->
            event_result empty_state [] no_panel

# Helper: preserve all state fields, only updating "active"
preserve_state = |current_state, active_val|
    state [
        state_entry "active" active_val,
        state_entry "turn" (json_get_str current_state "turn"),
        state_entry "estimated_tokens" (json_get_str current_state "estimated_tokens"),
        state_entry "token_ceiling" (json_get_str current_state "token_ceiling"),
        state_entry "needs_compaction" (json_get_str current_state "needs_compaction"),
        state_entry "compaction_count" (json_get_str current_state "compaction_count"),
        state_entry "message_count" (json_get_str current_state "message_count"),
        state_entry "tools_this_turn" (json_get_str current_state "tools_this_turn"),
        state_entry "tools_total" (json_get_str current_state "tools_total"),
        state_entry "followup_depth" (json_get_str current_state "followup_depth"),
        state_entry "last_event" (json_get_str current_state "last_event"),
    ]

# Helper: preserve all state fields, updating one specific key
preserve_state_with = |current_state, _key, value|
    state [
        state_entry "active" (json_get_str current_state "active"),
        state_entry "turn" (json_get_str current_state "turn"),
        state_entry "estimated_tokens" (json_get_str current_state "estimated_tokens"),
        state_entry "token_ceiling" (json_get_str current_state "token_ceiling"),
        state_entry "needs_compaction" (json_get_str current_state "needs_compaction"),
        state_entry "compaction_count" (json_get_str current_state "compaction_count"),
        state_entry "message_count" (json_get_str current_state "message_count"),
        state_entry "tools_this_turn" (json_get_str current_state "tools_this_turn"),
        state_entry "tools_total" (json_get_str current_state "tools_total"),
        state_entry "followup_depth" (json_get_str current_state "followup_depth"),
        state_entry "last_event" value,
    ]

handle_tool_call = |_input|
    done "agent-monitor has no tools" "agent-monitor"

render_ui = |input|
    current_state = parse_event_state input
    active = json_get_str current_state "active"
    if active == "true" then
        panel Header Prepend
            (key_value [
                key_value_entry "Turn" (json_get_str current_state "turn"),
                key_value_entry "Tokens" (Str.concat (json_get_str current_state "estimated_tokens") (Str.concat " / " (json_get_str current_state "token_ceiling"))),
                key_value_entry "Compaction" (Str.concat (json_get_str current_state "needs_compaction") (Str.concat " (" (Str.concat (json_get_str current_state "compaction_count") "x)"))),
                key_value_entry "Messages" (json_get_str current_state "message_count"),
                key_value_entry "Tools (turn)" (json_get_str current_state "tools_this_turn"),
                key_value_entry "Tools (total)" (json_get_str current_state "tools_total"),
                key_value_entry "Followups" (json_get_str current_state "followup_depth"),
                key_value_entry "Status" (json_get_str current_state "last_event"),
            ])
    else
        no_panel
