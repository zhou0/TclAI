package provide ttk::messagebox 0.1

package require Tk

namespace eval ::ttk::messagebox {
    proc show {parent title message {type "info"}} {
        set top .msgbox_[clock clicks]
        toplevel $top
        wm title $top $title
        if {[winfo exists $parent]} {
            wm transient $top [winfo toplevel $parent]
        }

        # Center relative to parent if possible
        if {[winfo exists $parent]} {
            set x [expr {[winfo rootx $parent] + ([winfo width $parent] / 2) - 150}]
            set y [expr {[winfo rooty $parent] + ([winfo height $parent] / 2) - 75}]
            wm geometry $top "+$x+$y"
        }

        ttk::frame $top.f -padding 20
        pack $top.f -fill both -expand yes

        set icon_char "ℹ️"
        if {$type eq "error"} { set icon_char "❌" }
        if {$type eq "warning"} { set icon_char "⚠️" }

        ttk::label $top.f.icon -text $icon_char -font {Helvetica 24}
        ttk::label $top.f.msg -text $message -wraplength 250

        grid $top.f.icon -row 0 -column 0 -padx {0 15} -sticky n
        grid $top.f.msg -row 0 -column 1 -sticky nw

        ttk::button $top.f.btn -text "OK" -command [list set ::ttk::messagebox::done_$top 1]
        grid $top.f.btn -row 1 -column 1 -sticky e -pady {15 0}

        bind $top <Return> [list $top.f.btn invoke]
        bind $top <Escape> [list $top.f.btn invoke]

        wm protocol $top WM_DELETE_WINDOW [list set ::ttk::messagebox::done_$top 1]

        grab $top
        focus $top.f.btn
        vwait ::ttk::messagebox::done_$top

        destroy $top
        unset ::ttk::messagebox::done_$top
    }
}
