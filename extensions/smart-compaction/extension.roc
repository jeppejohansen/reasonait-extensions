manifest =
    Manifest {
        tools: [],
        subscriptions: [ContextBuild],
        initial_state:
            state
                [
                    state_entry "compaction_count" "0",
                    state_entry "last_summary" "",
                ],
        modes: [],
    }

handle_event = |input|
    kind = parse_event_kind input
    when kind is
        ContextBuild ->
            payload = parse_event_payload input
            needs_compaction = json_get_bool payload "needs_compaction"
            if needs_compaction then
                handle_compaction input payload
            else
                current_state = parse_event_state input
                event_result
                    (state [
                        state_entry "compaction_count" (json_get_str current_state "compaction_count"),
                        state_entry "last_summary" (json_get_str current_state "last_summary"),
                    ])
                    []
                    no_panel
        _ ->
            event_result empty_state [] no_panel

handle_compaction = |input, payload|
    current_state = parse_event_state input
    count_str = json_get_str current_state "compaction_count"
    count = when Str.to_i64 count_str is
        Ok n -> n
        Err _ -> 0
    new_count = Num.to_str (count + 1)

    estimated_tokens = json_get_int payload "estimated_tokens"
    token_ceiling = json_get_int payload "token_ceiling"
    overshoot = estimated_tokens - token_ceiling

    summary = Str.concat "[Compaction #" (Str.concat new_count (Str.concat "] Trimmed ~" (Str.concat (Num.to_str overshoot) " tokens. Removed thinking blocks and redundant context.")))

    # Signal to Go core: strip thinking blocks from messages and add summary
    compaction_prompt = Str.concat "CONTEXT COMPACTED: This conversation was compacted to fit the context window. " (Str.concat "Previous thinking blocks have been removed. " (Str.concat "Compaction #" (Str.concat new_count ". Continue from where you left off.")))

    event_result
        (state [
            state_entry "compaction_count" new_count,
            state_entry "last_summary" summary,
        ])
        [modify_context_effect compaction_prompt]
        (text_panel Footer Replace summary)

handle_tool_call = |_input|
    done "smart-compaction has no tools" "smart-compaction"

render_ui = |input|
    current_state = parse_event_state input
    summary = json_get_str current_state "last_summary"
    if summary == "" then
        no_panel
    else
        text_panel Footer Append summary
