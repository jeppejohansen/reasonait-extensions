manifest =
    Manifest {
        tools: [
            tool "glob" "find files matching a glob pattern"
                [
                    string_field "pattern" "glob pattern to match (e.g. **/*.go)" Bool.true,
                    string_field "path" "directory to search in (defaults to .)" Bool.false,
                ],
            tool "web_fetch" "fetch content from a URL"
                [
                    string_field "url" "the URL to fetch" Bool.true,
                    string_field "prompt" "what to extract from the page" Bool.false,
                ],
            tool "evidence_add" "store a key-value evidence pair"
                [
                    string_field "key" "evidence key" Bool.true,
                    string_field "value" "evidence value" Bool.true,
                ],
            tool "evidence_get" "retrieve an evidence pair by key"
                [
                    string_field "key" "evidence key to retrieve" Bool.true,
                ],
            tool "evidence_list" "list all stored evidence keys"
                [],
        ],
        subscriptions: [],
        initial_state: state [state_entry "evidence" "{}"],
        modes: [],
    }

handle_event = |_input|
    event_result empty_state [] no_panel

handle_tool_call = |input|
    called_tool = parse_tool_name input
    args = parse_tool_arguments input
    has_results = parse_tool_has_results input
    if called_tool == "glob" then
        handle_glob args has_results input
    else if called_tool == "web_fetch" then
        handle_web_fetch args has_results input
    else if called_tool == "evidence_add" then
        handle_evidence_add args input
    else if called_tool == "evidence_get" then
        handle_evidence_get args input
    else if called_tool == "evidence_list" then
        handle_evidence_list input
    else
        done "unknown tool" "extra-tools"

handle_glob = |args, has_results, input|
    if has_results then
        # Read result from effect
        state_json = parse_event_state input
        output = json_get_str state_json "cmd_output"
        done output "extra-tools"
    else
        pattern = json_get_str args "pattern"
        path = json_get_str args "path"
        dir = if path == "" then "." else path
        cmd = Str.concat "find " (Str.concat dir (Str.concat " -path '" (Str.concat pattern "' -type f 2>/dev/null | head -50")))
        need_effect
            (run_command_effect cmd)
            (state [state_entry "phase" "glob_pending"])

handle_web_fetch = |args, has_results, input|
    if has_results then
        state_json = parse_event_state input
        body = json_get_str state_json "fetch_body"
        # Truncate to 8000 bytes
        truncated = truncate_str body 8000
        done truncated "extra-tools"
    else
        url = json_get_str args "url"
        need_effect
            (http_request_effect "GET" url "")
            (state [state_entry "phase" "fetch_pending"])

handle_evidence_add = |args, input|
    key = json_get_str args "key"
    value = json_get_str args "value"
    current_state = parse_event_state input
    current_evidence = json_get_str current_state "evidence"
    # Store in state (simple key=value append approach)
    new_entry = Str.concat key (Str.concat "=" value)
    updated = if current_evidence == "{}" then
        new_entry
    else
        Str.concat current_evidence (Str.concat "|" new_entry)
    done_with_state
        (Str.concat "stored evidence: " key)
        "extra-tools"
        (state [state_entry "evidence" updated])

handle_evidence_get = |args, input|
    key = json_get_str args "key"
    current_state = parse_event_state input
    evidence = json_get_str current_state "evidence"
    value = find_evidence evidence key
    if value == "" then
        done (Str.concat "no evidence found for key: " key) "extra-tools"
    else
        done value "extra-tools"

handle_evidence_list = |input|
    current_state = parse_event_state input
    evidence = json_get_str current_state "evidence"
    if evidence == "{}" then
        done "no evidence stored" "extra-tools"
    else
        done (Str.concat "evidence keys: " (extract_keys evidence)) "extra-tools"

# Simple key=value store with | separator
find_evidence : Str, Str -> Str
find_evidence = |store, key|
    needle = Str.concat key "="
    when Str.split_first store needle is
        Ok { after } ->
            when Str.split_first after "|" is
                Ok { before } -> before
                Err _ -> after
        Err _ -> ""

extract_keys : Str -> Str
extract_keys = |store|
    entries = Str.split_on store "|"
    keys = List.map entries |entry|
        when Str.split_first entry "=" is
            Ok { before } -> before
            Err _ -> entry
    Str.join_with keys ", "

truncate_str = |s, max_bytes|
    bytes = Str.to_utf8 s
    if List.len bytes <= max_bytes then
        s
    else
        taken = List.take_first bytes max_bytes
        when Str.from_utf8 taken is
            Ok result -> result
            Err _ ->
                # If truncation splits a UTF-8 sequence, drop one more byte
                fallback = List.take_first bytes (max_bytes - 1)
                when Str.from_utf8 fallback is
                    Ok result2 -> result2
                    Err _ -> ""

render_ui = |_input|
    no_panel
