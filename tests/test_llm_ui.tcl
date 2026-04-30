# Headless test suite for LLM UI core logic
lappend auto_path [file join [file dirname [info script]] .. lib]

# Mocking packages and procedures that require a GUI or specific environment
namespace eval msgcat {
    proc mc {src args} { return "translated_$src" }
    proc mclocale {args} { return "en" }
    proc mcload {args} {}
}
namespace eval ttk {
    proc frame {path args} { proc ::$path {args} {}; return $path }
    proc labelframe {path args} { proc ::$path {args} {}; return $path }
    proc label {path args} { proc ::$path {args} {}; return $path }
    proc button {path args} { proc ::$path {args} {}; return $path }
    proc entry {path args} { proc ::$path {args} {}; return $path }
    proc combobox {path args} { proc ::$path {args} {}; return $path }
    namespace eval style { proc configure {args} {}; proc lookup {args} { return "" } }
}

# Override package to handle Tk and tls in headless env
rename package _original_package
proc package {args} {
    set cmd [lindex $args 0]
    set pkg [lindex $args 1]
    if {$cmd eq "require" && ($pkg eq "Tk" || $pkg eq "tls")} { return 1 }
    return [uplevel 1 _original_package $args]
}

proc wm {args} {}
proc text {path args} { proc ::$path {args} {}; return $path }
proc winfo {args} { return 1 }
proc bind {args} {}
proc pack {args} {}
proc grid {args} {}
proc after {args} { if {[llength $args] > 1} { uplevel 1 [lindex $args 1] } }
proc canvas {path args} { proc ::$path {args} {}; return $path }
proc event {args} {}

namespace eval http {
    proc register {args} {}
    proc geturl {args} { return "token123" }
    proc status {token} { return "ok" }
    proc ncode {token} { return 200 }
    proc data {token} { return "{\"choices\":[{\"message\":{\"content\":\"mock response\"}}]}" }
    proc cleanup {token} {}
}

# Load the package
package require llm_ui

# --- Utility procs for testing ---
proc assert {condition msg} {
    if {![uplevel 1 [list expr $condition]]} {
        error "Assertion failed: $msg"
    }
}

puts "--- Starting Test Suite ---"

# 1. Test JSON Parser
puts "Testing JSON Parser..."
set json {{"a": 1, "b": [2, "3"], "c": {"d": true, "e": null}}}
set d [::llm_ui::logic::json_parse $json]
assert {[dict get $d a] == 1} "json_parse simple value"
assert {[lindex [dict get $d b] 1] eq "3"} "json_parse array"
assert {[dict get [dict get $d c] d] == 1} "json_parse nested object"
puts "JSON Parser: OK"

# 2. Test JSON Generator (History)
puts "Testing History JSON Generator..."
set msgs { {role user content "hello"} {role assistant content "hi world"} }
set gen [::llm_ui::logic::json_gen_history $msgs]
assert {[string match {*role*: *user*} $gen]} "json_gen_history contains role"
assert {[string match {*content*: *hi world*} $gen]} "json_gen_history contains content"
puts "History JSON Generator: OK"

# 3. Test Provider JSON Generator
puts "Testing Provider JSON Generator..."
set providers {
    {name "P1" base_url "U1" api_key "K1" models {{id "M1" system_prompt "S1"}}}
}
set gen [::llm_ui::logic::json_gen_providers $providers "Default"]
assert {[string match {*default_prompt*: *Default*} $gen]} "json_gen_providers contains default prompt"
assert {[string match {*name*: *P1*} $gen]} "json_gen_providers contains provider name"
puts "Provider JSON Generator: OK"

# 4. Test ChatWidget Logic (Headless)
puts "Testing ChatWidget Logic..."
set chatW [::llm_ui::ChatWidget .test_chat]
set obj ::.test_chat:obj

$obj configure -model "test-model"
assert {[$obj cget -model] eq "test-model"} "configure/cget works"
puts "ChatWidget: OK"

# 5. Test SettingsWidget Logic (Headless)
puts "Testing SettingsWidget Logic..."
set settingsW [::llm_ui::SettingsWidget .test_settings .test_chat]
set s_obj ::.test_settings:obj
puts "SettingsWidget: OK"

puts "--- All Tests Passed ---"
