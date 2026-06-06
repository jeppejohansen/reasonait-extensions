manifest =
    Manifest {
        tools: [],
        subscriptions: [TurnStart, TurnEnd, MessageAdded, ToolResult],
        initial_state:
            state
                [
                    state_entry "phase" "awaiting_criteria",
                    state_entry "criteria" "",
                    state_entry "criteria_prompted" "false",
                    state_entry "tools_this_turn" "0",
                    state_entry "challenge_count" "0",
                    state_entry "last_test_summary" "",
                ],
        modes: [],
    }

handle_event = |input|
    kind = parse_event_kind input
    current_state = parse_event_state input
    phase = json_get_str current_state "phase"
    when kind is
        TurnStart ->
            handle_turn_start current_state phase
        TurnEnd ->
            handle_turn_end current_state phase
        MessageAdded ->
            handle_message_added input current_state phase
        ToolResult ->
            handle_tool_result input current_state
        _ ->
            event_result (passthrough current_state) [] no_panel

handle_turn_start = |current_state, phase|
    if phase == "awaiting_criteria" then
        prompted = json_get_str current_state "criteria_prompted"
        if prompted == "false" then
            # First turn — ask the model to state its success criteria
            prompt = "Before you begin: state your SPECIFIC success criteria for this task. What exact evidence (test output, file contents, command results) will prove you are done? Be concrete — e.g. 'all 20 tests pass' or 'file X exists with function Y'. State criteria now, then begin work."
            event_result
                (state [
                    state_entry "phase" "awaiting_criteria",
                    state_entry "criteria" "",
                    state_entry "criteria_prompted" "true",
                    state_entry "tools_this_turn" "0",
                    state_entry "challenge_count" "0",
                    state_entry "last_test_summary" "",
                ])
                [inject_followup_effect prompt]
                no_panel
        else
            # Already prompted, reset tool counter
            event_result
                (set_tools current_state "0")
                []
                no_panel
    else
        # Working phase — reset tool counter
        event_result
            (set_tools current_state "0")
            []
            no_panel

handle_message_added = |input, current_state, phase|
    payload = parse_event_payload input
    role = json_get_str payload "role"
    content = json_get_str payload "content"
    if role == "assistant" && phase == "awaiting_criteria" && content != "" then
        # Capture the model's first substantive response as criteria
        # Truncate to keep state manageable
        truncated = truncate_str content 500
        event_result
            (state [
                state_entry "phase" "working",
                state_entry "criteria" truncated,
                state_entry "criteria_prompted" "true",
                state_entry "tools_this_turn" (json_get_str current_state "tools_this_turn"),
                state_entry "challenge_count" "0",
                state_entry "last_test_summary" "",
            ])
            []
            no_panel
    else
        event_result (passthrough current_state) [] no_panel

handle_tool_result = |input, current_state|
    payload = parse_event_payload input
    tools_str = json_get_str current_state "tools_this_turn"
    tools = parse_int tools_str
    new_tools = Num.to_str (tools + 1)

    # Try to extract test summary from tool result content
    # Look for patterns like "X passed" or "X failed" or "PASS"/"FAIL"
    content = json_get_str payload "content"
    test_summary = extract_test_summary content
    old_summary = json_get_str current_state "last_test_summary"
    updated_summary = if test_summary != "" then test_summary else old_summary

    event_result
        (state [
            state_entry "phase" (json_get_str current_state "phase"),
            state_entry "criteria" (json_get_str current_state "criteria"),
            state_entry "criteria_prompted" (json_get_str current_state "criteria_prompted"),
            state_entry "tools_this_turn" new_tools,
            state_entry "challenge_count" (json_get_str current_state "challenge_count"),
            state_entry "last_test_summary" updated_summary,
        ])
        []
        no_panel

handle_turn_end = |current_state, phase|
    if phase != "working" then
        event_result (passthrough current_state) [] no_panel
    else
        tools_str = json_get_str current_state "tools_this_turn"
        tools = parse_int tools_str
        challenge_str = json_get_str current_state "challenge_count"
        challenges = parse_int challenge_str

        if tools == 0 && challenges < 3 then
            # Model produced text without tools — challenge it with its own criteria
            criteria = json_get_str current_state "criteria"
            test_summary = json_get_str current_state "last_test_summary"
            challenge = build_challenge criteria test_summary
            new_challenges = Num.to_str (challenges + 1)
            event_result
                (state [
                    state_entry "phase" "working",
                    state_entry "criteria" criteria,
                    state_entry "criteria_prompted" "true",
                    state_entry "tools_this_turn" "0",
                    state_entry "challenge_count" new_challenges,
                    state_entry "last_test_summary" test_summary,
                ])
                [inject_followup_effect challenge]
                no_panel
        else
            # Used tools this turn, or max challenges reached — let it through
            event_result
                (state [
                    state_entry "phase" "working",
                    state_entry "criteria" (json_get_str current_state "criteria"),
                    state_entry "criteria_prompted" "true",
                    state_entry "tools_this_turn" "0",
                    state_entry "challenge_count" (if tools > 0 then "0" else challenge_str),
                    state_entry "last_test_summary" (json_get_str current_state "last_test_summary"),
                ])
                []
                no_panel

build_challenge = |criteria, test_summary|
    base = Str.concat "STOP. You stated your success criteria as:\n\"" (Str.concat criteria "\"\n\nHave you actually observed this evidence? ")
    if test_summary != "" then
        Str.concat base (Str.concat "Your most recent test output showed: " (Str.concat test_summary "\n\nIf your criteria are not met, keep working. Run the tests again to verify."))
    else
        Str.concat base "You have not shown test results that confirm success. Run the tests to verify before claiming you are done."

# Extract a brief test summary from content (e.g. "20 failed" or "5 passed, 2 failed")
extract_test_summary = |content|
    if content == "" then
        ""
    else
        has_failed = str_contains content "FAILED" || str_contains content "failed"
        has_passed = str_contains content "PASSED" || str_contains content "passed"
        if has_failed || has_passed then
            # Try to find the pytest summary line (e.g. "20 failed" or "5 passed, 2 failed")
            extract_summary_line content
        else
            ""

extract_summary_line = |content|
    # Look for "X passed" and "X failed" patterns
    # We'll scan for the last line containing "passed" or "failed" with numbers
    lines = Str.split_on content "\n"
    summary = List.walk lines "" |acc, line|
        trimmed = Str.trim line
        has_count = str_contains trimmed " passed" || str_contains trimmed " failed"
        if has_count then
            trimmed
        else
            acc
    if summary == "" then
        # Fallback: just report presence of FAILED
        if str_contains content "FAILED" then
            "tests FAILED"
        else if str_contains content "PASSED" || str_contains content "passed" then
            "tests passed"
        else
            ""
    else
        summary

# Helpers

parse_int : Str -> I64
parse_int = |s|
    when Str.to_i64 s is
        Ok n -> n
        Err _ -> 0

passthrough = |current_state|
    state [
        state_entry "phase" (json_get_str current_state "phase"),
        state_entry "criteria" (json_get_str current_state "criteria"),
        state_entry "criteria_prompted" (json_get_str current_state "criteria_prompted"),
        state_entry "tools_this_turn" (json_get_str current_state "tools_this_turn"),
        state_entry "challenge_count" (json_get_str current_state "challenge_count"),
        state_entry "last_test_summary" (json_get_str current_state "last_test_summary"),
    ]

set_tools = |current_state, val|
    state [
        state_entry "phase" (json_get_str current_state "phase"),
        state_entry "criteria" (json_get_str current_state "criteria"),
        state_entry "criteria_prompted" (json_get_str current_state "criteria_prompted"),
        state_entry "tools_this_turn" val,
        state_entry "challenge_count" (json_get_str current_state "challenge_count"),
        state_entry "last_test_summary" (json_get_str current_state "last_test_summary"),
    ]

truncate_str = |s, max_len|
    bytes = Str.to_utf8 s
    if List.len bytes <= max_len then
        s
    else
        taken = List.take_first bytes max_len
        when Str.from_utf8 taken is
            Ok result -> result
            Err _ ->
                fallback = List.take_first bytes (max_len - 1)
                when Str.from_utf8 fallback is
                    Ok result2 -> result2
                    Err _ -> ""

handle_tool_call = |_input|
    done "critical-assessor has no tools" "critical-assessor"

render_ui = |input|
    current_state = parse_event_state input
    phase = json_get_str current_state "phase"
    challenges = json_get_str current_state "challenge_count"
    if phase == "working" && challenges != "0" then
        panel Footer Append
            (key_value [
                key_value_entry "Challenges" challenges,
            ])
    else
        no_panel
