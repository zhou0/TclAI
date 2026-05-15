package require Tk
package require TclOO

package provide ttk::m3::navrail 0.1.0

namespace eval ttk::m3 {
    proc InitStyles {} {
        set theme [ttk::style theme use]
        set isDark 0

        # Heuristic to detect dark theme
        set bg [ttk::style lookup . -background]
        if {$bg ne ""} {
            if {[catch {
                if {[string match "#*" $bg]} {
                    set r [scan [string range $bg 1 2] %x]
                    set g [scan [string range $bg 3 4] %x]
                    set b [scan [string range $bg 5 6] %x]
                    if {[expr {($r*299 + $g*587 + $b*114)/1000}] < 128} { set isDark 1 }
                }
            }]} {
                if {$bg in {black gray10 gray20 DarkSlateGray}} { set isDark 1 }
            }
        }

        if {$isDark} {
            set surface "#141218"
            set onSurface "#E6E0E9"
            set onSurfaceVariant "#CAC4D0"
            set secondaryContainer "#4A4458"
            set onSecondaryContainer "#E8DEF8"
            set hoverBg "#2B2930"
        } else {
            set surface "#FEF7FF"
            set onSurface "#1D1B20"
            set onSurfaceVariant "#49454F"
            set secondaryContainer "#E8DEF8"
            set onSecondaryContainer "#1D192B"
            set hoverBg "#F3EDF7"
        }

        ttk::style configure M3NavRail.TFrame -background $surface
        ttk::style configure M3NavRail.Item.TLabel -background $surface -foreground $onSurfaceVariant -font {Helvetica 9} -anchor center
        ttk::style configure M3NavRail.Active.TLabel -background $surface -foreground $onSurface -font {Helvetica 9 bold} -anchor center
        ttk::style configure M3NavRail.Indicator.TFrame -background $secondaryContainer
        ttk::style configure M3NavRail.Hover.TFrame -background $hoverBg
        ttk::style configure M3NavRail.Expanded.TLabel -background $surface -foreground $onSurfaceVariant -font {Helvetica 10} -anchor w
        ttk::style configure M3NavRail.ExpandedActive.TLabel -background $surface -foreground $onSurface -font {Helvetica 10 bold} -anchor w
    }

    ::oo::class create NavRailClass {

        variable w container items selected state options

        constructor {path args} {
            set w $path
            set items {}
            set selected ""
            set state "collapsed"
            set options(-style) "M3NavRail.TFrame"
            set options(-class) "M3NavRail"
            ttk::frame $w -style $options(-style) -class $options(-class) -width 80
            pack propagate $w 0
            set container ${w}_widget
            rename $w $container
            set f [ttk::frame $w.f -style [my cget -style]]
            pack $f -fill both -expand 1 -pady 10
            if {[llength $args] > 0} { my configure {*}$args }

            my UpdateStyles
            bind $container <<ThemeChanged>> [list $w UpdateStyles]
        }


        method UpdateStyles {} {
            ::ttk::m3::InitStyles
            set itemStyle [my cget -style]
            set bg [ttk::style lookup $itemStyle -background]
            if {$bg eq ""} { set bg "#FEF7FF" }
            [my f] configure -style $itemStyle
            foreach id [dict keys $items] {
                set data [dict get $items $id]
                set itemFrame [dict get $data frame]
                set wrapper [dict get $data wrapper]
                set label [dict get $data label]
                $itemFrame configure -style $itemStyle
                $wrapper configure -bg $bg
                my update_item_layout $id
            }
            my select $selected 1
        }
        method add_item {id icon text} {
            set itemStyle [my cget -style]
            set itemFrame [ttk::frame [my f].item_$id -style $itemStyle -cursor hand2]
            set bg [ttk::style lookup $itemStyle -background]
            set fg [ttk::style lookup M3NavRail.Item.TLabel -foreground]
            set iconWrapper [canvas $itemFrame.wrapper -width 80 -height 44 -bg $bg -highlightthickness 0]
            $iconWrapper create text 40 22 -text $icon -fill $fg -font {Helvetica 16} -tags icon
            set label [ttk::label $itemFrame.label -text $text -style M3NavRail.Item.TLabel]
            dict set items $id [list frame $itemFrame wrapper $iconWrapper label $label icon_char $icon text $text]
            my update_item_layout $id
            pack $itemFrame -side top -fill x
            foreach sub {frame wrapper label} { bind [dict get [dict get $items $id] $sub] <Button-1> [list $w select $id] }
            bind $itemFrame <Enter> [list $w on_hover $id 1]
            bind $itemFrame <Leave> [list $w on_hover $id 0]
            if {$selected eq ""} { my select $id }
            return $itemFrame
        }

        method itemconfigure {id args} {
            if {![dict exists $items $id]} return
            set data [dict get $items $id]
            set label [dict get $data label]
            foreach {opt val} $args {
                switch -- $opt {
                    -text {
                        $label configure -text $val
                        dict set data text $val
                    }
                    -icon {
                        set wrapper [dict get $data wrapper]
                        $wrapper itemconfigure icon -text $val
                        dict set data icon_char $val
                    }
                }
            }
            dict set items $id $data
        }

        method update_item_layout {id} {
            set data [dict get $items $id]
            set wrapper [dict get $data wrapper]
            set label [dict get $data label]
            pack forget $wrapper
            pack forget $label
            if {$state eq "collapsed"} {
                $wrapper configure -width 80
                $wrapper coords icon 40 22
                $label configure -style [expr {$id eq $selected ? "M3NavRail.Active.TLabel" : "M3NavRail.Item.TLabel"}]
                pack $wrapper -side top -fill x
                pack $label -side top -fill x -pady {0 12}
            } else {
                $wrapper configure -width 72
                $wrapper coords icon 36 22
                $label configure -style [expr {$id eq $selected ? "M3NavRail.ExpandedActive.TLabel" : "M3NavRail.Expanded.TLabel"}]
                pack $wrapper -side left
                pack $label -side left -fill both -expand 1 -padx {0 16}
            }
        }

        method update_layout {} {
            $container configure -width [expr {$state eq "collapsed" ? 80 : 240}]
            foreach id [dict keys $items] { my update_item_layout $id }
            my select $selected 1
        }

        method cget {opt} {
            if {$opt eq "-state"} { return $state }
            if {[info exists options($opt)]} { return $options($opt) }
            return [$container cget $opt]
        }

        method configure {args} {
            if {[llength $args] == 0} {
                set res [$container configure]
                lappend res [list -state state State collapsed $state]
                return $res
            }
            if {[llength $args] == 1} {
                set opt [lindex $args 0]
                if {$opt eq "-state"} { return [list -state state State collapsed $state] }
                return [$container configure $opt]
            }
            foreach {opt val} $args {
                switch -- $opt {
                    -state { if {$val in {collapsed expanded}} { set state $val; my update_layout } }
                    -style { set options($opt) $val; $container configure -style $val; my update_layout }
                    default { if {[info exists options($opt)]} { set options($opt) $val } else { $container configure $opt $val } }
                }
            }
        }

        method on_hover {id entering} {
            set data [dict get $items $id]
            set wrapper [dict get $data wrapper]
            if {$id ne $selected} {
                if {$entering} {
                    set hoverBg [ttk::style lookup M3NavRail.Hover.TFrame -background]
                    $wrapper configure -bg $hoverBg
                } else {
                    set bg [ttk::style lookup [my cget -style] -background]
                    $wrapper configure -bg $bg
                }
            }
        }

        method select {id {quiet 0}} {
            if {$id eq "" || ![dict exists $items $id]} return
            if {$selected ne "" && [dict exists $items $selected]} {
                set oldData [dict get $items $selected]
                set oldWrapper [dict get $oldData wrapper]
                $oldWrapper delete indicator
                set inactiveFg [ttk::style lookup M3NavRail.Item.TLabel -foreground]
                $oldWrapper itemconfigure icon -fill $inactiveFg
                [dict get $oldData label] configure -style [expr {$state eq "collapsed" ? "M3NavRail.Item.TLabel" : "M3NavRail.Expanded.TLabel"}]
            }
            set selected $id
            set data [dict get $items $id]
            set wrapper [dict get $data wrapper]
            set indicatorBg [ttk::style lookup M3NavRail.Indicator.TFrame -background]
            set activeFg [ttk::style lookup M3NavRail.Active.TLabel -foreground]
            set r 16
            if {$state eq "collapsed"} { set x1 12; set y1 6; set x2 68; set y2 38 } else { set x1 8; set y1 6; set x2 64; set y2 38 }
            $wrapper delete indicator
            $wrapper create oval $x1 $y1 [expr {$x1+2*$r}] $y2 -fill $indicatorBg -outline "" -tags indicator
            $wrapper create oval [expr {$x2-2*$r}] $y1 $x2 $y2 -fill $indicatorBg -outline "" -tags indicator
            $wrapper create rectangle [expr {$x1+$r}] $y1 [expr {$x2-$r}] $y2 -fill $indicatorBg -outline "" -tags indicator
            $wrapper lower indicator
            $wrapper itemconfigure icon -fill $activeFg
            [dict get $data label] configure -style [expr {$state eq "collapsed" ? "M3NavRail.Active.TLabel" : "M3NavRail.ExpandedActive.TLabel"}]
            if {!$quiet} { event generate $w <<NavRailSelected>> -data $id }
        }

        method get_selection {} { return $selected }
        export UpdateStyles
        method f {} { return $w.f }
        method unknown {method args} { return [$container $method {*}$args] }
    }
}

proc ttk::m3::navrail {path args} {
    set obj [ttk::m3::NavRailClass create ${path}_obj $path {*}$args]
    interp alias {} $path {} $obj
    return $path
}

ttk::m3::InitStyles
