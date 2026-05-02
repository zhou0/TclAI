set fh [open lib/llm_ui/llm_ui.tcl r]
set content [read $fh]
close $fh

set count 0
set line 1
foreach char [split $content ""] {
    if {$char eq "\n"} { incr line }
    if {$char eq "\{"} {
        incr count
    } elseif {$char eq "\}"} {
        set count [expr {$count - 1}]
        if {$count < 0} {
            puts "Extra closing brace at line $line"
            set count 0
        }
    }
}
if {$count > 0} {
    puts "Missing $count closing braces"
} elseif {$count == 0} {
    puts "Braces are balanced"
}
