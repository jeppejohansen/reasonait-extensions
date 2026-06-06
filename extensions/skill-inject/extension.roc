manifest =
    Manifest {
        tools: [],
        subscriptions: [ContextBuild, ToolResult, TurnStart],
        initial_state:
            state
                [
                    state_entry "last_tools" "",
                    state_entry "last_failed" "",
                    state_entry "repair_count" "0",
                ],
        modes: [],
    }

handle_event = |input|
    kind = parse_event_kind input
    when kind is
        TurnStart ->
            # Reset repair count each turn
            event_result
                (state [state_entry "last_tools" "", state_entry "last_failed" "", state_entry "repair_count" "0"])
                []
                no_panel
        ToolResult ->
            payload = parse_event_payload input
            tool_used = json_get_str payload "tool_name"
            success = json_get_bool payload "success"
            current_state = parse_event_state input
            last_tools = json_get_str current_state "last_tools"
            updated_tools = if last_tools == "" then tool_used else Str.concat last_tools (Str.concat "," tool_used)
            failed = if success then "" else tool_used
            event_result
                (state [
                    state_entry "last_tools" updated_tools,
                    state_entry "last_failed" failed,
                    state_entry "repair_count" (json_get_str current_state "repair_count"),
                ])
                []
                no_panel
        ContextBuild ->
            current_state = parse_event_state input
            last_tools = json_get_str current_state "last_tools"
            last_failed = json_get_str current_state "last_failed"
            cards = select_skill_cards last_tools last_failed input
            if cards == "" then
                event_result
                    (state [
                        state_entry "last_tools" last_tools,
                        state_entry "last_failed" last_failed,
                        state_entry "repair_count" (json_get_str current_state "repair_count"),
                    ])
                    []
                    no_panel
            else
                event_result
                    (state [
                        state_entry "last_tools" last_tools,
                        state_entry "last_failed" last_failed,
                        state_entry "repair_count" (json_get_str current_state "repair_count"),
                    ])
                    [modify_context_effect cards]
                    no_panel
        _ ->
            event_result empty_state [] no_panel

select_skill_cards : Str, Str, Str -> Str
select_skill_cards = |last_tools, last_failed, _input|
    cards = []
        |> maybe_add_card last_failed "edit" edit_card
        |> maybe_add_card last_failed "write" write_card
        |> maybe_add_card last_failed "bash" bash_card
        |> maybe_add_recency_card last_tools "grep" grep_card
        |> maybe_add_recency_card last_tools "read" read_card
        |> maybe_add_recency_card last_tools "edit" edit_card
    Str.join_with cards "\n\n"

maybe_add_card : List Str, Str, Str, Str -> List Str
maybe_add_card = |cards, failed, tool_name, card|
    if failed == tool_name then
        List.append cards card
    else
        cards

maybe_add_recency_card : List Str, Str, Str, Str -> List Str
maybe_add_recency_card = |cards, last_tools, tool_name, card|
    if str_contains last_tools tool_name then
        # Only add if not already present
        if List.any cards |c| c == card then
            cards
        else
            List.append cards card
    else
        cards

# Skill cards (concise tool usage guidance)

edit_card : Str
edit_card =
    "[SKILL:edit] Use Edit for targeted replacements. Provide unique old_string context (3+ surrounding lines). Never guess file content - always Read first."

write_card : Str
write_card =
    "[SKILL:write] Use Write only for NEW files. For existing files, use Edit. Check file existence before deciding. Include complete content - no placeholders."

bash_card : Str
bash_card =
    "[SKILL:bash] Keep commands focused and safe. Quote paths with spaces. Prefer specialized tools (Read, Edit, Grep) over cat/sed/awk. Check exit codes."

grep_card : Str
grep_card =
    "[SKILL:grep] Use regex patterns for flexible matching. Filter with glob param for file types. Use output_mode:files_with_matches for discovery, content for details."

read_card : Str
read_card =
    "[SKILL:read] Read files before editing. Use offset/limit for large files. Read multiple related files in parallel. Works with images and PDFs."

handle_tool_call = |_input|
    done "skill-inject has no tools" "skill-inject"

render_ui = |_input|
    no_panel
