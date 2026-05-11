lappend auto_path [file join [file dirname [info script]] .. lib]

package require llm_ui::logic

set buffer ""
set chunk1 "data: {\"choices\": \[{\"delta\": {\"content\": \"Hello\"}}\]}\n"
set payloads [::llm_ui::logic::parse_sse $chunk1 buffer]
puts "Payloads 1: $payloads"

set chunk2 "data: {\"choices\": \[{\"delta\": {\"content\": \" world\"}}\]}\ndata: \[DONE\]\n"
set payloads [::llm_ui::logic::parse_sse $chunk2 buffer]
puts "Payloads 2: $payloads"

puts "SSE Parse Test Finished"
