lappend auto_path [file join [file dirname [info script]] lib]
package require llm_ui::logic

set chunk "data: {\"choices\":\[{\"delta\":{\"content\":\"\xe6\x88\x91\xe6\x98\xaf\"}}\]}\n"
set buffer ""
# current parse_sse
proc parse_sse_old {data buffer_var} {
    upvar 1 $buffer_var buffer
    append buffer $data
    set results {}
    while {[regexp -indices "\n" $buffer range]} {
        set end [lindex $range 0]
        set line [string range $buffer 0 $end]
        set buffer [string range $buffer [expr {$end + 1}] end]
        set line [string trim $line]
        if {[string match "data: *" $line]} {
            set payload [string trim [string range $line 5 end]]
            if {$payload ne "\[DONE\]" && $payload ne ""} {
                lappend results $payload
            }
        }
    }
    return $results
}

set payloads [parse_sse_old $chunk buffer]
set p [lindex $payloads 0]
puts "Payload raw: $p"
set pattern "\"content\":\\s*\"((?:\[^\"\\\\\]|\\\\.)*)\""
if {[regexp $pattern $p match content]} {
    puts "Matched content (old): $content"
}

# Proposed fix in parse_sse
proc parse_sse_new {data buffer_var} {
    upvar 1 $buffer_var buffer
    append buffer $data
    set results {}
    while {[regexp -indices "\n" $buffer range]} {
        set end [lindex $range 0]
        set line [string range $buffer 0 $end]
        set buffer [string range $buffer [expr {$end + 1}] end]

        # Decode here
        set line [encoding convertfrom utf-8 $line]

        set line [string trim $line]
        if {[string match "data: *" $line]} {
            set payload [string trim [string range $line 5 end]]
            if {$payload ne "\[DONE\]" && $payload ne ""} {
                lappend results $payload
            }
        }
    }
    return $results
}

set buffer ""
set payloads [parse_sse_new $chunk buffer]
set p [lindex $payloads 0]
puts "Payload decoded: $p"
if {[regexp $pattern $p match content]} {
    puts "Matched content (new): $content"
}
