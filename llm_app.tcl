set script_dir [file dirname [info script]]
lappend auto_path [file join $script_dir lib]

package require llm_ui
package require ttk::m3::navrail

wm title . "TTK LLM Frontend"
wm geometry . 800x600

# Create Navigation Rail
ttk::m3::navrail .nav
.nav add_item chat "💬" "Chat"
.nav add_item settings "⚙️" "Settings"

# Main container for screens
ttk::frame .main
pack .nav -side left -fill y
pack .main -side right -fill both -expand yes

# Screens
::llm_ui::ChatWidget .main.chat
::llm_ui::SettingsWidget .main.settings .main.chat

proc ShowScreen {id} {
    # Hide all screens
    pack forget .main.chat
    pack forget .main.settings

    # Show selected screen
    switch -- $id {
        chat {
            pack .main.chat -fill both -expand yes
        }
        settings {
            pack .main.settings -fill both -expand yes
        }
    }
}

# Bind navrail selection
bind .nav <<NavRailSelected>> {
    ShowScreen [%W get_selection]
}

# Initial screen
ShowScreen chat
