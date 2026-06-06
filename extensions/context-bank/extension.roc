manifest =
    Manifest {
        tools: [],
        subscriptions: [ToolResult],
        initial_state:
            state
                [
                    state_entry "banked_count" "0",
                    state_entry "total_chars_saved" "0",
                ],
        modes: [],
    }

handle_event = |input|
    kind = parse_event_kind input
    if kind == ToolResult then
        payload = parse_event_payload input
        state_data = parse_event_state input
        banked_count = json_get_int state_data "banked_count"
        total_saved = json_get_int state_data "total_chars_saved"
        # Parse tool_results array from payload to find large outputs
        effects = parse_tool_results_for_banking payload
        new_banked = banked_count + Num.to_i64 (List.len effects)
        # Estimate chars saved (rough: each banked item saves ~1200 chars on average)
        new_saved = total_saved + Num.to_i64 (List.len effects) * 1200
        event_result
            (
                state
                    [
                        state_entry "banked_count" (Num.to_str new_banked),
                        state_entry "total_chars_saved" (Num.to_str new_saved),
                    ]
            )
            effects
            no_panel
    else
        event_result
            (parse_state_passthrough input)
            []
            no_panel

handle_tool_call = |_input|
    done "context-bank has no tools" "context-bank"

render_ui = |input|
    state_data = parse_event_state input
    banked = json_get_str state_data "banked_count"
    saved = json_get_str state_data "total_chars_saved"
    if banked == "0" then
        no_panel
    else
        panel Footer Append (
            key_value [
                key_value_entry "Banked" banked,
                key_value_entry "Chars saved" saved,
            ]
        )

# Parse the tool_results JSON array and emit store_context effects for large outputs.
# Expected format in payload: "tool_results":[{"tool_call_id":"x","tool_name":"y","content_length":8000},...]
parse_tool_results_for_banking = |payload|
    # Find the tool_results array in the payload
    when Str.split_first payload "\"tool_results\":" is
        Ok { after } ->
            trimmed = Str.trim_start after
            if Str.starts_with trimmed "[" then
                parse_tool_results_array trimmed
            else
                []
        Err _ -> []

parse_tool_results_array = |arr_str|
    # Split by },{ to get individual entries
    # Remove outer brackets
    inner = Str.replace_first arr_str "[" ""
    stripped = strip_trailing_bracket inner
    if stripped == "" then
        []
    else
        entries = Str.split_on stripped "},{"
        List.keep_oks entries |entry_raw|
            # Re-add braces for proper JSON parsing
            entry = ensure_braces entry_raw
            content_length = json_get_int entry "content_length"
            if content_length > 1500 then
                tool_call_id = json_get_str entry "tool_call_id"
                if tool_call_id == "" then
                    Err NotLargeEnough
                else
                    Ok (store_context_effect tool_call_id "tool_outputs" "auto")
            else
                Err NotLargeEnough

strip_trailing_bracket = |s|
    bytes = Str.to_utf8 s
    len = List.len bytes
    if len == 0 then
        ""
    else
        last = List.get bytes (len - 1) |> Result.with_default 0
        if last == 93 then # ']'
            trimmed_bytes = List.take_first bytes (len - 1)
            when Str.from_utf8 trimmed_bytes is
                Ok result -> result
                Err _ -> s
        else
            s

ensure_braces = |s|
    trimmed = Str.trim s
    has_open = Str.starts_with trimmed "{"
    has_close = when Str.split_last trimmed "}" is
        Ok _ -> Bool.true
        Err _ -> Bool.false
    if has_open && has_close then
        trimmed
    else if has_open then
        Str.concat trimmed "}"
    else if has_close then
        Str.concat "{" trimmed
    else
        Str.concat "{" (Str.concat trimmed "}")

parse_state_passthrough = |input|
    state_data = parse_event_state input
    banked = json_get_str state_data "banked_count"
    saved = json_get_str state_data "total_chars_saved"
    state
        [
            state_entry "banked_count" (if banked == "" then "0" else banked),
            state_entry "total_chars_saved" (if saved == "" then "0" else saved),
        ]
