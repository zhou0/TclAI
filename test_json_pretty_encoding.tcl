lappend auto_path [file join [file dirname [info script]] lib]
package require llm_ui::logic

set json "{\"content\": \"我是\"}"
# If we don't decode correctly, it might show incorrectly
set pretty [::llm_ui::logic::json_pretty $json]
puts "Pretty JSON: $pretty"
