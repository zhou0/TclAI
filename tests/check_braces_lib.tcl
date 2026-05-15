proc check_braces {file} {
    set f [open $file r]
    set content [read $f]
    close $f
    set balance 0
    set line 1
    for {set i 0} {$i < [string length $content]} {incr i} {
        set char [string index $content $i]
        if {$char eq "\n"} { incr line }
        if {$char eq "\x7b"} { incr balance }
        if {$char eq "\x7d"} {
            incr balance -1
            if {$balance < 0} {
                puts "Unbalanced closing brace at line $line"
                return 0
            }
        }
    }
    if {$balance != 0} {
        puts "Unbalanced braces in $file: $balance"
        return 0
    }
    puts "$file: Braces are balanced."
    return 1
}

check_braces [lindex $argv 0]
