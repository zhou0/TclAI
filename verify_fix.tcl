lappend auto_path [file join [file dirname [info script]] lib]
package require http
package require llm_ui::logic
package require msgcat

# Simulate missing tls
if {[info commands ::tls::socket] ne ""} {
    rename ::tls::socket ::tls::socket_orig
}

puts "Testing is_https_available when tls is missing: [::llm_ui::logic::is_https_available]"

set msg [::llm_ui::logic::mc "HTTPS requires the 'tls' package, which is not installed."]
puts "Localization test (en): $msg"

::msgcat::mclocale zh_cn
::llm_ui::logic::mcload_msgs
set msg [::llm_ui::logic::mc "HTTPS requires the 'tls' package, which is not installed."]
puts "Localization test (zh_cn): $msg"

# Simulate registered https
proc mock_tls {args} {
    # Return a real channel or at least something that looks like one if we were actually calling it
    # But we just want to see if it finds the protocol
    return "stdout"
}
http::register https 443 mock_tls
http::register HTTPS 443 mock_tls

if {[catch {http::geturl HTTPS://example.com -timeout 1} err]} {
    puts "HTTP geturl HTTPS result: $err"
} else {
    puts "HTTP geturl HTTPS result: Success (mocked)"
}
