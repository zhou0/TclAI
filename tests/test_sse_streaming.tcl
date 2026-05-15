set script_dir [file dirname [info script]]
lappend auto_path [file join [file dirname $script_dir] lib]

package require llm_ui::logic

# Use {} to avoid command substitution and treat the whole thing as a literal string
set sse_data "data: {\"choices\": \[{\"delta\": {\"content\": \"Hello\"}}\]}\n\ndata: {\"choices\": \[{\"delta\": {\"content\": \" world\"}}\]}\n\ndata: \[DONE\]\n"
set buffer ""
puts "Testing parse_sse..."
set payloads [::llm_ui::logic::parse_sse $sse_data buffer]
puts "Payloads: $payloads"

foreach p $payloads {
    set pattern "\"content\":\\s*\"((?:\[^\"\\\\\]|\\\\.)*)\""
    if {[regexp $pattern $p match content]} {
        puts "Extracted content: $content"
    }
}
