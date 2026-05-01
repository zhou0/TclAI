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
            lappend items "\"$k\": \"[escape_json $v]\""
        }
        return "\x7b[join $items ", "]\x7d"
    }

    proc json_gen_providers {providers_data default_prompt} {
        set p_list {}
        foreach p $providers_data {
            set items {}
            foreach {k v} $p {
                if {$k eq "models"} {
                    set m_list {}
                    foreach m $v {
                        if {[llength $m] > 1} {
                            set m_items {}
                            foreach {mk mv} $m { lappend m_items "\"$mk\": \"[escape_json $mv]\"" }
                            lappend m_list "\x7b[join $m_items ", "]\x7d"
                        } else {
                            lappend m_list "\"$m\""
                        }
                    }
                    lappend items "\"models\": \x5b[join $m_list ", "]\x5d"
                } else {
                    lappend items "\"$k\": \"[escape_json $v]\""
                }
            }
            lappend p_list "\x7b[join $items ", "]\x7d"
        }
        return "\x7b\"default_prompt\": \"[escape_json $default_prompt]\", \"providers\": \x5b[join $p_list ", "]\x5d\x7d"
    }

    proc json_gen_history {messages} {
        set m_list {}
        foreach m $messages {
            set m_items {}
            foreach {k v} $m {
                lappend m_items "\"$k\": \"[escape_json $v]\""
            }
            lappend m_list "\x7b[join $m_items ", "]\x7d"
        }
        return "\x5b[join $m_list ", "]\x5d"
    }

    proc extract_ids {json key} {
        set ids {}
        set pattern "\"$key\":\\s*\"(\x5b^\x22\x5d+)\""
        set matches [regexp -all -inline $pattern $json]
        foreach {full match} $matches { lappend ids $match }
        return [lsort -unique $ids]
    }
}
