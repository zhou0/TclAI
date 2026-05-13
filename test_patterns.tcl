proc test_ui_patterns {} {
    set pattern1 "\"content\":\\s*\"((?:\[^\"\\\\\]|\\\\.)*)\""
    set data "{\"content\": \"hello world\"}"
    if {[regexp $pattern1 $data match content]} {
        puts "Pattern 1 match: $content"
    } else {
        puts "Pattern 1 failed"
    }
}

proc test_logic_patterns {} {
    set key "id"
    set pattern2 "\"$key\":\\s*\"(\[^\"]+)\""
    set json "{\"id\": \"test-id\"}"
    if {[regexp -all -inline $pattern2 $json matches]} {
        puts "Pattern 2 match: [lindex $matches 1]"
    } else {
        puts "Pattern 2 failed"
    }
}

if {[catch {test_ui_patterns} err]} { puts "UI Test Error: $err" }
if {[catch {test_logic_patterns} err]} { puts "Logic Test Error: $err" }
