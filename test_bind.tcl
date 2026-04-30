package require Tk
set t [text .t]
if {[catch {$t bind <Return> {puts "Hi"}} err]} {
    puts "Method call failed: $err"
} else {
    puts "Method call success"
}
if {[catch {bind $t <Return> {puts "Hi"}} err]} {
    puts "Command failed: $err"
} else {
    puts "Command success"
}
