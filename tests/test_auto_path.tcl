set script_dir [file dirname [info script]]
lappend auto_path [file join [file dirname $script_dir] lib]
package require llm_ui::logic

puts "Initial auto_path: $auto_path"
puts "Testing init_tls..."
if {[::llm_ui::logic::init_tls]} {
    puts "init_tls succeeded"
    puts "Updated auto_path: $auto_path"
} else {
    puts "init_tls failed (as expected in this environment if tls is missing)"
}
