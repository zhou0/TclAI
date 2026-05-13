package provide llm_ui::logic 0.1

package require http
catch {package require tls}
package require msgcat

namespace eval ::llm_ui::logic {
    variable script_dir [file dirname [info script]]

    proc mcload_msgs {} {
        variable script_dir
        ::msgcat::mcload [file join $script_dir msgs]
    }

    if {[info commands ::tls::socket] ne ""} {
        http::register https 443 [list ::tls::socket -autoservername 1]
        http::register HTTPS 443 [list ::tls::socket -autoservername 1]
    }

    proc is_https_available {} {
        return [expr {[info commands ::tls::socket] ne ""}]
    }

    proc mc {src} {
        return [::msgcat::mc $src]
    }

    proc escape_json {str} {
        return [string map [list "\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"] $str]
    }

    proc unescape_json {str} {
        return [string map [list "\\\"" "\"" "\\\\" "\\" "\\n" "\n" "\\r" "\r" "\\t" "\t"] $str]
    }

    proc json_parse {json} {
        set json [string trim $json]
        set i 0
        return [json_parse_val $json i]
    }

    proc json_parse_val {json i_var} {
        upvar 1 $i_var i
        json_skip_space $json i
        if {$i >= [string length $json]} { return "" }
        set char [string index $json $i]
        if {$char eq "\x7b"} { return [json_parse_obj $json i] }
        if {$char eq "\["} { return [json_parse_arr $json i] }
        if {$char eq "\""} { return [json_parse_str $json i] }
        return [json_parse_lit $json i]
    }

    proc json_skip_space {json i_var} {
        upvar 1 $i_var i
        while {$i < [string length $json] && [string is space [string index $json $i]]} { incr i }
    }

    proc json_parse_obj {json i_var} {
        upvar 1 $i_var i
        set result {}
        incr i
        while {$i < [string length $json]} {
            json_skip_space $json i
            if {$i >= [string length $json]} break
            set c [string index $json $i]
            if {$c eq "\x7d"} { incr i; return $result }
            if {$c eq "\""} {
                set key [json_parse_str $json i]
                json_skip_space $json i
                if {$i < [string length $json] && [string index $json $i] eq ":"} { incr i }
                set val [json_parse_val $json i]
                lappend result $key $val
            } else {
                incr i
            }
            json_skip_space $json i
            if {$i < [string length $json] && [string index $json $i] eq ","} { incr i }
        }
        return $result
    }

    proc json_parse_arr {json i_var} {
        upvar 1 $i_var i
        set result {}
        incr i
        while {$i < [string length $json]} {
            json_skip_space $json i
            if {$i >= [string length $json]} break
            set c [string index $json $i]
            if {$c eq "\x5d"} { incr i; return $result }
            lappend result [json_parse_val $json i]
            json_skip_space $json i
            if {$i < [string length $json] && [string index $json $i] eq ","} { incr i }
        }
        return $result
    }

    proc json_parse_str {json i_var} {
        upvar 1 $i_var i
        if {$i >= [string length $json] || [string index $json $i] ne "\""} { return "" }
        incr i
        set start $i
        while {$i < [string length $json]} {
            set c [string index $json $i]
            if {$c eq "\""} {
                set val [string range $json $start [expr {$i-1}]]
                incr i
                return [unescape_json $val]
            }
            if {$c eq "\\"} { incr i }
            incr i
        }
        return ""
    }

    proc json_parse_lit {json i_var} {
        upvar 1 $i_var i
        set rest [string range $json $i end]
        if {[regexp {^[^,\x5d\x7d \t\n\r]+} $rest match]} {
            set i [expr {$i + [string length $match]}]
            if {$match eq "true"} { return 1 }
            if {$match eq "false"} { return 0 }
            if {$match eq "null"} { return "" }
            return $match
        }
        incr i
        return ""
    }

    proc json_gen_dict {data} {
        set items {}
        foreach {k v} $data {
            lappend items "\"$k\": [json_gen_val $v]"
        }
        return "\x7b[join $items ", "]\x7d"
    }

    proc json_gen_val {val} {
        if {[string is integer -strict $val]} { return $val }
        if {$val eq "true"} { return "true" }
        if {$val eq "false"} { return "false" }
        set trimmed [string trim $val]
        if {[string index $trimmed 0] eq "\x7b" && [string index $trimmed end] eq "\x7d"} { return $val }
        if {[string index $trimmed 0] eq "\[" && [string index $trimmed end] eq "\]"} { return $val }

        return "\"[escape_json $val]\""
    }

    proc extract_ids {json key} {
        set ids {}
        set pattern "\"$key\":\\s*\"(\[^\"]+)\""
        set matches [regexp -all -inline $pattern $json]
        foreach {full match} $matches { lappend ids $match }

        if {[llength $ids] == 0} {
             set pattern "\"(\[^\"]+)\""
             set matches [regexp -all -inline $pattern $json]
             foreach {full match} $matches {
                if {$match ne "id" && $match ne "object" && $match ne "models" && $match ne "data"} {
                    lappend ids $match
                }
             }
        }
        return [lsort -unique $ids]
    }

    proc json_pretty {json {indent "  "}} {
        set result ""
        set level 0
        set in_string 0
        set escaped 0

        for {set i 0} {$i < [string length $json]} {incr i} {
            set char [string index $json $i]

            if {$escaped} {
                append result $char
                set escaped 0
                continue
            }

            if {$char eq "\\"} {
                append result $char
                set escaped 1
                continue
            }

            if {$char eq "\""} {
                append result $char
                set in_string [expr {!$in_string}]
                continue
            }

            if {$in_string} {
                append result $char
                continue
            }

            switch -exact -- $char {
                "{" - "[" {
                    incr level
                    append result $char "\n" [string repeat $indent $level]
                }
                "}" - "]" {
                    set level [expr {$level - 1}]
                    append result "\n" [string repeat $indent $level] $char
                }
                "," {
                    append result $char "\n" [string repeat $indent $level]
                }
                ":" {
                    append result $char " "
                }
                " " - "\t" - "\n" - "\r" {
                    # Skip existing whitespace outside of strings
                }
                default {
                    append result $char
                }
            }
        }
        return $result
    }

    proc parse_sse {data buffer_var} {
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
}
