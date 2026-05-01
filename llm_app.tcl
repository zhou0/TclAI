set script_dir [file dirname [info script]]
lappend auto_path [file join $script_dir lib]

package require Tk
package require llm_ui
package require ttk::m3::navrail
package require msgcat

# Set native theme based on OS
proc SetNativeTheme {} {
    global tcl_platform
    set theme "clam"
    set available [ttk::style theme names]

    if {$tcl_platform(os) eq "Darwin"} {
        if {[lsearch -exact $available "aqua"] != -1} { set theme "aqua" }
    } elseif {$tcl_platform(platform) eq "windows"} {
        if {[lsearch -exact $available "vista"] != -1} {
            set theme "vista"
        } elseif {[lsearch -exact $available "xpnative"] != -1} {
            set theme "xpnative"
        }
    } else {
        if {[lsearch -exact $available "gtk1"] != -1} {
            set theme "gtk1"
        } elseif {[lsearch -exact $available "clam"] != -1} {
            set theme "clam"
        }
    }

    catch {ttk::style theme use $theme}
}

# Detect system locale and map to supported languages
proc DetectSystemLocale {} {
    set locale [string tolower [::msgcat::mclocale]]
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
        if {[dict exists $d language]} {
            set locale [dict get $d language]
        }
    }
}

if {$locale eq ""} {
    set locale [DetectSystemLocale]
}

::msgcat::mclocale $locale
::llm_ui::logic::mcload_msgs

SetNativeTheme

wm title . "TTK LLM Frontend"
wm geometry . 800x600

# Create Navigation Rail
ttk::m3::navrail .nav
.nav add_item toggle "☰" ""
.nav add_item chat "💬" [::llm_ui::logic::mc "Chat"]
.nav add_item settings "⚙️" [::llm_ui::logic::mc "Settings"]

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
    .nav itemconfigure chat -text [::llm_ui::logic::mc "Chat"]
    .nav itemconfigure settings -text [::llm_ui::logic::mc "Settings"]
    # Force a redraw of the navrail to update labels if expanded
    .nav configure -state [.nav cget -state]
}

ShowScreen chat

if {[info exists tcl_interactive] && $tcl_interactive} {
} else {
    vwait forever
}
