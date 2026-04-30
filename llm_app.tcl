set script_dir [file dirname [info script]]
lappend auto_path [file join $script_dir lib]

package require Tk
package require llm_ui
package require ttk::m3::navrail
package require msgcat

# Load preferences
set locale en
if {[file exists "preference.json"]} {
    set fh [open "preference.json" r]
    set prefs [::llm_ui::parse_json [read $fh]]
    close $fh
    foreach {k v} $prefs { if {$k eq "language"} { set locale $v } }
}
::msgcat::mclocale $locale

wm title . "TTK LLM Frontend"
wm geometry . 800x600

# Create Navigation Rail
ttk::m3::navrail .nav
.nav add_item toggle "☰" ""
.nav add_item chat "💬" [::msgcat::mc "Chat"]
.nav add_item settings "⚙️" [::msgcat::mc "Settings"]

# Main container for screens
ttk::frame .main
pack .nav -side left -fill y
pack .main -side right -fill both -expand yes

# Screens
::llm_ui::ChatWidget .main.chat
::llm_ui::SettingsWidget .main.settings .main.chat

proc ShowScreen {id} {
    if {$id eq "toggle"} {
        set current [.nav cget -state]
        set new [expr {$current eq "collapsed" ? "expanded" : "collapsed"}]
        .nav configure -state $new
        return
    }
    pack forget .main.chat
    pack forget .main.settings
    switch -- $id {
        chat { pack .main.chat -fill both -expand yes }
        settings { pack .main.settings -fill both -expand yes }
    }
}

bind .nav <<NavRailSelected>> { ShowScreen [%W get_selection] }
bind . <<LanguageChanged>> {
    wm title . "TTK LLM Frontend"
    .nav configure -state [.nav cget -state] ;# trigger layout update
    # Note: Full dynamic relabeling of nav items might need navrail extension
    # For now, we update what we can.
}

ShowScreen chat

if {[info exists tcl_interactive] && $tcl_interactive} {
} else {
    vwait forever
}
