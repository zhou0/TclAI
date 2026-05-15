set script_dir [file dirname [info script]]
lappend auto_path [file join [file dirname $script_dir] lib]

package require llm_ui::logic
package require msgcat

# Mock missing tls package by renaming ::tls::socket if it exists
if {[info commands ::tls::socket] ne ""} {
    rename ::tls::socket ::tls::socket_bak
}

puts "Checking is_tls_available (should be 0): [::llm_ui::logic::is_tls_available]"
puts "Checking has_curl (should be 1): [::llm_ui::logic::has_curl]"
puts "Checking is_https_available (should be 1 if curl exists): [::llm_ui::logic::is_https_available]"

set headers [list "User-Agent" "TclAI-Test"]
puts "Testing http_get fallback to curl..."
if {[catch {::llm_ui::logic::http_get "https://google.com" $headers} result]} {
    puts "http_get failed: $result"
} else {
    lassign $result ncode body
    puts "http_get success! ncode: $ncode"
    puts "Body length: [string length $body]"
}

# Restore bak
if {[info commands ::tls::socket_bak] ne ""} {
    rename ::tls::socket_bak ::tls::socket
}
