manifest =
    Manifest {
        tools: [
            tool "hello" "return a friendly greeting"
                [
                    string_field "name" "name to greet" Bool.false,
                ],
        ],
        subscriptions: [TurnStart, MessageAdded],
        initial_state:
            state
                [
                    state_entry "greeting" "Hello from Roc extension",
                ],
        modes: [],
    }

handle_event = |input|
    kind = parse_event_kind input
    if kind == MessageAdded then
        event_result
            (
                state
                    [
                        state_entry "last_event" (event_kind_name MessageAdded),
                    ]
            )
            [
                log_effect "roc message_added handled",
            ]
            (text_panel Footer Append "roc message panel")
    else
        event_result
            (
                state
                    [
                        state_entry "last_event" (event_kind_name kind),
                    ]
            )
            [
                log_effect "roc event handled",
            ]
            (text_panel Footer Append "roc event panel")

handle_tool_call = |input|
    has_results = parse_tool_has_results input
    if has_results then
        done "hello from roc extension" "roc"
    else
        need_effect
            (log_effect "roc tool step")
            (
                state
                    [
                        state_entry "phase" "after_roc_log",
                    ]
            )

render_ui = |_input|
    text_panel Footer Append "roc panel"
