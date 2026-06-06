manifest =
    Manifest {
        tools: [],
        subscriptions: [TurnStart, TurnEnd, ContextBuild, ToolResult],
        initial_state:
            state
                [
                    state_entry "turns_completed" "0",
                    state_entry "tools_used_total" "0",
                    state_entry "last_tool_failed" "false",
                    state_entry "nudge_count" "0",
                    state_entry "tools_this_turn" "0",
                    state_entry "has_written" "false",
                    state_entry "has_run_bash" "false",
                    state_entry "bash_failed" "false",
                ],
        modes: [],
    }

handle_event = |input|
    kind = parse_event_kind input
    current_state = parse_event_state input
    when kind is
        ContextBuild ->
            handle_context_build current_state
        TurnStart ->
            handle_turn_start current_state
        TurnEnd ->
            handle_turn_end current_state
        ToolResult ->
            handle_tool_result input current_state
        _ ->
            event_result empty_state [] no_panel

handle_context_build = |current_state|
    # Inject system prompt reinforcement for test-driven workflow
    system_prompt = "[AGENT INSTRUCTIONS]\nYou are solving a coding exercise. Follow this workflow EXACTLY:\n1. Read the test file to understand what is expected\n2. Read the starter/stub file (note the line numbers shown in output)\n3. Implement the solution using Write (for the initial full implementation)\n4. Run the test command using Bash\n5. If tests fail, use Edit to fix specific lines, then run tests again\n6. Repeat step 5 until ALL tests pass\n\nCRITICAL RULES:\n- After EVERY Write or Edit, you MUST run the tests with Bash. NEVER say tests passed without running them.\n- If tests fail, you MUST fix the code and re-run. Do NOT give up or claim success.\n- Use tool calls (Read, Write, Edit, Bash). Never write tool JSON in text.\n- Always read the test file FIRST to understand the expected interface.\n- Edit is two-phase: call edit(path) to see the file with line numbers, then edit(path, start_line, end_line, new=...) to replace lines.\n- Use Edit (not Write) when fixing specific lines after test failures.\n- Always include the path argument in every tool call."

    event_result
        (preserve_state current_state)
        [modify_context_effect system_prompt]
        no_panel

handle_turn_start = |current_state|
    turns_str = json_get_str current_state "turns_completed"
    turns = parse_int turns_str
    tools_total_str = json_get_str current_state "tools_used_total"

    # If turn > 1 and no tools used at all yet, nudge toward tool usage
    if turns > 1 && tools_total_str == "0" then
        nudge_count_str = json_get_str current_state "nudge_count"
        nudges = parse_int nudge_count_str
        new_nudges = Num.to_str (nudges + 1)
        event_result
            (state [
                state_entry "turns_completed" turns_str,
                state_entry "tools_used_total" tools_total_str,
                state_entry "last_tool_failed" "false",
                state_entry "nudge_count" new_nudges,
                state_entry "tools_this_turn" "0",
                state_entry "has_written" (json_get_str current_state "has_written"),
                state_entry "has_run_bash" (json_get_str current_state "has_run_bash"),
                state_entry "bash_failed" "false",
            ])
            [inject_followup_effect "You must use tools to complete this task. Start by using the Read tool to read the test file, then read the starter file, then implement and run tests."]
            no_panel
    else
        event_result
            (state [
                state_entry "turns_completed" turns_str,
                state_entry "tools_used_total" tools_total_str,
                state_entry "last_tool_failed" "false",
                state_entry "nudge_count" (json_get_str current_state "nudge_count"),
                state_entry "tools_this_turn" "0",
                state_entry "has_written" (json_get_str current_state "has_written"),
                state_entry "has_run_bash" (json_get_str current_state "has_run_bash"),
                state_entry "bash_failed" "false",
            ])
            []
            no_panel

handle_turn_end = |current_state|
    turns_str = json_get_str current_state "turns_completed"
    turns = parse_int turns_str
    new_turns = Num.to_str (turns + 1)
    tools_total_str = json_get_str current_state "tools_used_total"
    tools_this_turn_str = json_get_str current_state "tools_this_turn"
    tools_this_turn = parse_int tools_this_turn_str
    has_written = json_get_str current_state "has_written"
    has_run_bash = json_get_str current_state "has_run_bash"
    bash_failed = json_get_str current_state "bash_failed"
    nudge_count_str = json_get_str current_state "nudge_count"

    # Cap nudges at 2 to prevent infinite followup loops
    nudges = parse_int nudge_count_str
    if nudges >= 2 then
        event_result
            (state [
                state_entry "turns_completed" new_turns,
                state_entry "tools_used_total" tools_total_str,
                state_entry "last_tool_failed" (json_get_str current_state "last_tool_failed"),
                state_entry "nudge_count" nudge_count_str,
                state_entry "tools_this_turn" "0",
                state_entry "has_written" has_written,
                state_entry "has_run_bash" has_run_bash,
                state_entry "bash_failed" bash_failed,
            ])
            []
            no_panel
    # Key logic: if model has written files but hasn't run tests yet, force it
    else if has_written == "true" && has_run_bash == "false" then
        new_nudges = Num.to_str (nudges + 1)
        event_result
            (state [
                state_entry "turns_completed" new_turns,
                state_entry "tools_used_total" tools_total_str,
                state_entry "last_tool_failed" (json_get_str current_state "last_tool_failed"),
                state_entry "nudge_count" new_nudges,
                state_entry "tools_this_turn" "0",
                state_entry "has_written" has_written,
                state_entry "has_run_bash" has_run_bash,
                state_entry "bash_failed" bash_failed,
            ])
            [inject_followup_effect "You have written code but have NOT run the tests yet. You MUST run the tests now. Use the Bash tool to run the test command. Do not stop until tests pass."]
            no_panel
    # If bash failed, nudge to fix and re-run
    else if bash_failed == "true" then
        new_nudges = Num.to_str (nudges + 1)
        event_result
            (state [
                state_entry "turns_completed" new_turns,
                state_entry "tools_used_total" tools_total_str,
                state_entry "last_tool_failed" (json_get_str current_state "last_tool_failed"),
                state_entry "nudge_count" new_nudges,
                state_entry "tools_this_turn" "0",
                state_entry "has_written" has_written,
                state_entry "has_run_bash" has_run_bash,
                state_entry "bash_failed" "false",
            ])
            [inject_followup_effect "The tests failed. Use edit(path) to see line numbers, then edit(path, start_line, end_line, new=...) to fix the lines. Run tests again. Do not stop until all tests pass."]
            no_panel
    # If no tools used this turn, nudge (model may have dumped code as text)
    else if tools_this_turn == 0 then
        new_nudges = Num.to_str (nudges + 1)
        event_result
            (state [
                state_entry "turns_completed" new_turns,
                state_entry "tools_used_total" tools_total_str,
                state_entry "last_tool_failed" (json_get_str current_state "last_tool_failed"),
                state_entry "nudge_count" new_nudges,
                state_entry "tools_this_turn" "0",
                state_entry "has_written" has_written,
                state_entry "has_run_bash" has_run_bash,
                state_entry "bash_failed" bash_failed,
            ])
            [inject_followup_effect "You produced text but didn't use any tools. You MUST use tools (Read, Edit, Write, Bash) to complete this task. Start by reading the test file."]
            no_panel
    else
        event_result
            (state [
                state_entry "turns_completed" new_turns,
                state_entry "tools_used_total" tools_total_str,
                state_entry "last_tool_failed" (json_get_str current_state "last_tool_failed"),
                state_entry "nudge_count" nudge_count_str,
                state_entry "tools_this_turn" "0",
                state_entry "has_written" has_written,
                state_entry "has_run_bash" has_run_bash,
                state_entry "bash_failed" "false",
            ])
            []
            no_panel

handle_tool_result = |input, current_state|
    payload = parse_event_payload input
    success = json_get_bool payload "success"
    tool_name = json_get_str payload "tool_name"

    tools_total_str = json_get_str current_state "tools_used_total"
    tools_total = parse_int tools_total_str
    new_total = Num.to_str (tools_total + 1)
    tools_this_turn_str = json_get_str current_state "tools_this_turn"
    tools_this_turn = parse_int tools_this_turn_str
    new_this_turn = Num.to_str (tools_this_turn + 1)
    failed = if success then "false" else "true"

    # Track whether model has written files or run bash
    has_written = json_get_str current_state "has_written"
    has_run_bash = json_get_str current_state "has_run_bash"
    bash_failed_now = json_get_str current_state "bash_failed"

    new_has_written = if tool_name == "write" || tool_name == "edit" then "true" else has_written
    # Reset has_run_bash when model writes new code — forces re-test
    new_has_run_bash = if (tool_name == "write" || tool_name == "edit") && success then "false" else if tool_name == "bash" then "true" else has_run_bash
    new_bash_failed = if tool_name == "bash" && !(success) then "true" else bash_failed_now

    # Reset nudge count on successful tool use (model is making progress)
    new_nudge_count = if success then "0" else json_get_str current_state "nudge_count"

    event_result
        (state [
            state_entry "turns_completed" (json_get_str current_state "turns_completed"),
            state_entry "tools_used_total" new_total,
            state_entry "last_tool_failed" failed,
            state_entry "nudge_count" new_nudge_count,
            state_entry "tools_this_turn" new_this_turn,
            state_entry "has_written" new_has_written,
            state_entry "has_run_bash" new_has_run_bash,
            state_entry "bash_failed" new_bash_failed,
        ])
        []
        no_panel

# Helpers

parse_int : Str -> I64
parse_int = |s|
    when Str.to_i64 s is
        Ok n -> n
        Err _ -> 0

preserve_state = |current_state|
    state [
        state_entry "turns_completed" (json_get_str current_state "turns_completed"),
        state_entry "tools_used_total" (json_get_str current_state "tools_used_total"),
        state_entry "last_tool_failed" (json_get_str current_state "last_tool_failed"),
        state_entry "nudge_count" (json_get_str current_state "nudge_count"),
        state_entry "tools_this_turn" (json_get_str current_state "tools_this_turn"),
        state_entry "has_written" (json_get_str current_state "has_written"),
        state_entry "has_run_bash" (json_get_str current_state "has_run_bash"),
        state_entry "bash_failed" (json_get_str current_state "bash_failed"),
    ]

handle_tool_call = |_input|
    done "small-model-harness has no tools" "small-model-harness"

render_ui = |_input|
    no_panel
