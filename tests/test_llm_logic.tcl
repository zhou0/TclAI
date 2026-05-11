# Headless test for LLM Logic
lappend auto_path [file join [file dirname [info script]] .. lib]

package require llm_ui::logic

proc assert {condition msg} {
    if {![uplevel 1 [list expr $condition]]} {
        error "Assertion failed: $msg"
    }
}

puts "--- Starting Logic Test ---"

# Test JSON
set json {{"a": 1}}
set d [::llm_ui::logic::json_parse $json]
assert {[dict get $d a] == 1} "json_parse"

set esc [::llm_ui::logic::escape_json "hello \"world\""]
assert {$esc eq "hello \\\"world\\\""} "escape_json"

puts "--- Logic Test Passed ---"
