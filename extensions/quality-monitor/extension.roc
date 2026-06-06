manifest =
    Manifest {
        tools: [],
        subscriptions: [TurnEnd, ToolResult, MessageAdded],
        initial_state:
            state
                [
                    state_entry "consecutive_corrections" "0",
                    state_entry "last_messages" "",
                    state_entry "turns_without_tools" "0",
                    state_entry "saw_tool_this_turn" "false",
                ],
        modes: [],
    }

handle_event = |input|
    kind = parse_event_kind input
    current_state = parse_event_state input
    corrections_str = json_get_str current_state "consecutive_corrections"
    corrections = when Str.to_i64 corrections_str is
        Ok n -> n
        Err _ -> 0
    when kind is
        ToolResult ->
            event_result
                (state [
                    state_entry "consecutive_corrections" corrections_str,
                    state_entry "last_messages" (json_get_str current_state "last_messages"),
                    state_entry "turns_without_tools" (json_get_str current_state "turns_without_tools"),
                    state_entry "saw_tool_this_turn" "true",
                ])
                []
                no_panel
        MessageAdded ->
            payload = parse_event_payload input
            role = json_get_str payload "role"
            content = json_get_str payload "content"
            if role == "assistant" then
                last_msgs = json_get_str current_state "last_messages"
                # Keep last 3 messages as pipe-separated
                updated_msgs = append_rolling last_msgs content 3
                event_result
                    (state [
                        state_entry "consecutive_corrections" corrections_str,
                        state_entry "last_messages" updated_msgs,
                        state_entry "turns_without_tools" (json_get_str current_state "turns_without_tools"),
                        state_entry "saw_tool_this_turn" (json_get_str current_state "saw_tool_this_turn"),
                    ])
                    []
                    no_panel
            else
                event_result
                    (state [
                        state_entry "consecutive_corrections" corrections_str,
                        state_entry "last_messages" (json_get_str current_state "last_messages"),
                        state_entry "turns_without_tools" (json_get_str current_state "turns_without_tools"),
                        state_entry "saw_tool_this_turn" (json_get_str current_state "saw_tool_this_turn"),
                    ])
                    []
                    no_panel
        TurnEnd ->
            if corrections >= 2 then
                # Cap consecutive corrections
                event_result
                    (state [
                        state_entry "consecutive_corrections" corrections_str,
                        state_entry "last_messages" (json_get_str current_state "last_messages"),
                        state_entry "turns_without_tools" "0",
                        state_entry "saw_tool_this_turn" "false",
                    ])
                    []
                    no_panel
            else
                detect_failures input current_state corrections
        _ ->
            event_result empty_state [] no_panel

detect_failures = |_input, current_state, corrections|
    last_msgs = json_get_str current_state "last_messages"
    saw_tool = json_get_str current_state "saw_tool_this_turn"
    turns_no_tools_str = json_get_str current_state "turns_without_tools"
    turns_no_tools = when Str.to_i64 turns_no_tools_str is
        Ok n -> n
        Err _ -> 0

    new_turns_no_tools = if saw_tool == "true" then 0 else turns_no_tools + 1

    # Check for empty response
    last_msg = get_last_rolling last_msgs
    if last_msg == "" then
        emit_correction "Your last response was empty. Please provide a substantive response addressing the user's request." corrections current_state new_turns_no_tools
    # Check for hallucinated tool
    else if str_contains last_msg "unknown tool" then
        emit_correction "You attempted to use a tool that doesn't exist. Please check available tools and use a valid one." corrections current_state new_turns_no_tools
    # Check for repetition (3 identical messages)
    else if has_repetition last_msgs then
        emit_correction "You appear to be repeating yourself. Please try a different approach to make progress." corrections current_state new_turns_no_tools
    # Check for no progress (5+ turns without tools)
    else if new_turns_no_tools >= 5 then
        emit_correction "You haven't used any tools in several turns. If you're stuck, try using Read, Grep, or Bash to gather information." corrections current_state new_turns_no_tools
    else
        event_result
            (state [
                state_entry "consecutive_corrections" "0",
                state_entry "last_messages" last_msgs,
                state_entry "turns_without_tools" (Num.to_str new_turns_no_tools),
                state_entry "saw_tool_this_turn" "false",
            ])
            []
            no_panel

emit_correction = |message, corrections, current_state, turns_no_tools|
    new_corrections = Num.to_str (corrections + 1)
    event_result
        (state [
            state_entry "consecutive_corrections" new_corrections,
            state_entry "last_messages" (json_get_str current_state "last_messages"),
            state_entry "turns_without_tools" (Num.to_str turns_no_tools),
            state_entry "saw_tool_this_turn" "false",
        ])
        [inject_followup_effect message]
        no_panel

# Rolling message buffer (pipe-separated, capped at n entries)
append_rolling : Str, Str, I64 -> Str
append_rolling = |buffer, new_item, max_count|
    if buffer == "" then
        new_item
    else
        parts = Str.split_on buffer "|||"
        updated = List.append parts new_item
        trimmed = if List.len updated > Num.to_u64 max_count then
            List.drop_first updated 1
        else
            updated
        Str.join_with trimmed "|||"

get_last_rolling : Str -> Str
get_last_rolling = |buffer|
    if buffer == "" then
        ""
    else
        parts = Str.split_on buffer "|||"
        List.last parts |> Result.with_default ""

has_repetition : Str -> Bool
has_repetition = |buffer|
    parts = Str.split_on buffer "|||"
    if List.len parts < 3 then
        Bool.false
    else
        a = List.get parts 0 |> Result.with_default ""
        b = List.get parts 1 |> Result.with_default ""
        c = List.get parts 2 |> Result.with_default ""
        a == b && b == c && a != ""

handle_tool_call = |_input|
    done "quality-monitor has no tools" "quality-monitor"

render_ui = |_input|
    no_panel
