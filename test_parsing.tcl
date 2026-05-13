lappend auto_path [file join [file dirname [info script]] lib]
package require llm_ui::logic

proc test_parsing {data} {
    set pattern "\"content\":\\s*\"((?:\[^\"\\\\\]|\\\\.)*)\""
    if {[regexp $pattern $data match content]} {
        set content [::llm_ui::logic::unescape_json $content]
        puts "Matched content: $content"
    } else {
        puts "Failed to match"
    }
}

puts "Testing non-streaming response:"
set response1 {{"choices": [{"message": {"content": "Hello, how can I help you?"}}]}}
test_parsing $response1

puts "\nTesting streaming response chunk:"
set response2 {data: {"choices": [{"delta": {"content": "Hello"}}]}}
# Strip 'data: ' prefix like SSEHandler does
set p [string trim [string range $response2 5 end]]
test_parsing $p
