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
    proc checkbutton {path args} { proc ::$path {args} {}; return $path }
    proc scrollbar {path args} { proc ::$path {args} {}; return $path }
    namespace eval style { proc configure {args} {}; proc lookup {args} { return "" } }
    namespace eval messagebox { proc show {args} {} }
}

# Override package to handle Tk and tls in headless env
rename package _original_package
proc package {args} {
    set cmd [lindex $args 0]
    set pkg [lindex $args 1]
    if {$cmd eq "require" && ($pkg eq "Tk" || $pkg eq "tls" || $pkg eq "ttk::messagebox")} { return 1 }
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

# Ensure directories exist for test
file mkdir data

puts "--- Starting UI Test Suite ---"

# 1. Test ChatWidget Logic (Headless)
puts "Testing ChatWidget Logic..."
set chatW [::llm_ui::ChatWidget .test_chat]
set obj ::.test_chat:obj

$obj configure -model "test-model"
assert {[$obj cget -model] eq "test-model"} "configure/cget works"
puts "ChatWidget: OK"

# 2. Test SettingsWidget Logic (Headless)
puts "Testing SettingsWidget Logic..."
set settingsW [::llm_ui::SettingsWidget .test_settings .test_chat]
set s_obj ::.test_settings:obj
puts "SettingsWidget: OK"

puts "--- UI Tests Passed ---"

# 3. Test Preference Saving
puts "Testing Preference Saving..."
$s_obj SavePreferences
set pref_file [file join "settings" "preference.json"]
if {[file exists $pref_file]} {
    set fh [open $pref_file r]; set json [read $fh]; close $fh
    puts "preference.json content: $json"
} else {
    error "preference.json was not created in settings/"
}
puts "Preference Saving: OK"
