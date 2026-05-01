set script_dir [file dirname [info script]]
lappend auto_path [file join $script_dir lib]

package require Tk
package require llm_ui
package require ttk::m3::navrail
package require msgcat

# Detect system locale and map to supported languages
proc DetectSystemLocale {} {
    set locale [::msgcat::mclocale]
    set locale [string tolower $locale]
    if {[string match "zh_cn*" $locale] || [string match "zh-cn*" $locale]} {
        return "zh_cn"
    } elseif {[string match "zh_tw*" $locale] || [string match "zh-tw*" $locale] || [string match "zh_hk*" $locale] || [string match "zh-hk*" $locale]} {
        return "zh_tw"
    }
    return "en"
}

# Load preferences
set locale ""
if {[file exists "preference.json"]} {
    set fh [open "preference.json" r]
    set json [read $fh]
    close $fh
    if {![catch {set d [::llm_ui::logic::json_parse $json]}]} {
        foreach {k v} $d { if {$k eq "language"} { set locale $v } }
    }
}

if {$locale eq ""} {
    set locale [DetectSystemLocale]
}

::msgcat::mclocale $locale
::llm_ui::logic::mcload_msgs

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
        after idle [list .nav configure -state [expr {[.nav cget -state] eq "collapsed" ? "expanded" : "collapsed"}]]
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
    .nav itemconfigure chat -text [::msgcat::mc "Chat"]
    .nav itemconfigure settings -text [::msgcat::mc "Settings"]
    .nav configure -state [.nav cget -state]
}

ShowScreen chat

if {[info exists tcl_interactive] && $tcl_interactive} {
} else {
    vwait forever
}
