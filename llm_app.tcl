set script_dir [file dirname [info script]]
lappend auto_path [file join $script_dir  lib]

package require llm_ui

wm title . "TTK LLM Frontend"
::llm_ui::ChatWidget .chat

# You can configure it after creation as well
# .chat configure -api_key "your-key-here"

pack .chat -fill both -expand yes
