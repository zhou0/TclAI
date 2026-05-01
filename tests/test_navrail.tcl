# Headless test for NavRail
lappend auto_path [file join [file dirname [info script]] .. lib]

# Mocking Tk
namespace eval ttk {
    proc frame {path args} { proc ::$path {args} {}; return $path }
    proc label {path args} { proc ::$path {args} {}; return $path }
    proc style {args} {}
}

# Override package to handle Tk in headless env
rename package _original_package
proc package {args} {
    set cmd [lindex $args 0]
    set pkg [lindex $args 1]
    if {$cmd eq "require" && ($pkg eq "Tk" || $pkg eq "TclOO")} { return 1 }
    return [uplevel 1 _original_package $args]
}

proc bind {args} {}
proc pack {args} {}
proc canvas {path args} { proc ::$path {args} {}; return $path }
proc event {args} {}

package require ttk::m3::navrail

proc assert {condition msg} {
    if {![uplevel 1 [list expr $condition]]} {
        error "Assertion failed: $msg"
    }
}

puts "--- Starting NavRail Test ---"

set nav [ttk::m3::navrail .nav]
$nav add_item chat "icon" "Chat"
$nav add_item settings "icon" "Settings"

assert {[$nav get_selection] eq "chat"} "Initial selection is first item"

$nav select settings
assert {[$nav get_selection] eq "settings"} "Selection update works"

# Test state toggle
$nav configure -state expanded
assert {[$nav cget -state] eq "expanded"} "State change works"

puts "--- NavRail Test Passed ---"
