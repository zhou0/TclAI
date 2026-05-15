set script_dir [file dirname [info script]]
lappend auto_path [file join [file dirname $script_dir] lib]

package require llm_ui::logic

# Mock missing tls
if {[info commands ::tls::socket] ne ""} {
    rename ::tls::socket ::tls::socket_bak
}

set headers [list "Content-Type" "application/json"]
set body "{\"test\": \"data\"}"
puts "Testing http_post fallback to curl..."
if {[catch {::llm_ui::logic::http_post "https://httpbin.org/post" $headers $body} result]} {
    puts "http_post failed: $result"
} else {
    lassign $result ncode res
    puts "http_post success! ncode: $ncode"
    if {[string match "*\"data\": \"{\\\"test\\\": \\\"data\\\"}\"*" $res]} {
        puts "Data verified in response."
    } else {
        puts "Data NOT verified in response. Response: [string range $res 0 200]..."
    }
}

if {[info commands ::tls::socket_bak] ne ""} {
    rename ::tls::socket_bak ::tls::socket
}
