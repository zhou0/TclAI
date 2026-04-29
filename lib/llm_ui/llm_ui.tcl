package provide llm_ui 0.1

package require TclOO
package require Tk

namespace eval ::llm_ui {
    # Internal class
    oo::class create ChatWidgetClass {
        variable w history input send
        variable options
        variable messages
        variable api_buffer

        constructor {path args} {
            set w [ttk::frame $path]
            set messages {}
            set api_buffer ""
            array set options {
                -provider "OpenAI"
                -model "gpt-4o-mini"
                -base_url "https://api.openai.com/v1/chat/completions"
                -api_key ""
                -system_prompt "You are a helpful assistant."
            }
            my configure {*}$args
            my CreateUI
        }

        method configure {args} {
            foreach {opt val} $args {
                if {[info exists options($opt)]} {
                    set options($opt) $val
                }
            }
        }

        method cget {opt} {
            return $options($opt)
        }

        method get_option_varname {opt} {
            return [my varname options($opt)]
        }

        method CreateUI {} {
            # History Area
            set history_frame [ttk::frame $w.hframe]
            grid $history_frame -row 0 -column 0 -sticky nsew -padx 5 -pady 5
            
            set history [text $history_frame.txt -wrap word -state disabled -height 15]
            set hscroll [ttk::scrollbar $history_frame.vsb -orient vertical -command [list $history yview]]
            $history configure -yscrollcommand [list $hscroll set]
            
            pack $hscroll -side right -fill y
            pack $history -side left -fill both -expand yes

            # Tags for history
            $history tag configure user -foreground blue -font {Helvetica 10 bold}
            $history tag configure assistant -foreground darkgreen -font {Helvetica 10 bold}
            $history tag configure system -foreground gray -font {Helvetica 10 italic}
            $history tag configure error -foreground red

            # Input Area
            set input_frame [ttk::frame $w.iframe]
            grid $input_frame -row 1 -column 0 -sticky ew -padx 5 -pady 5
            
            set input [text $input_frame.txt -wrap word -height 4]
            set iscroll [ttk::scrollbar $input_frame.vsb -orient vertical -command [list $input yview]]
            $input configure -yscrollcommand [list $iscroll set]
            
            pack $iscroll -side right -fill y
            pack $input -side left -fill both -expand yes

            # Buttons
            set btn_frame [ttk::frame $w.bframe]
            grid $btn_frame -row 2 -column 0 -sticky ew -padx 5 -pady 5
            
            set send [ttk::button $btn_frame.send -text "Send" -command [list [self] SendMessage]]
            set clear [ttk::button $btn_frame.clear -text "Clear Chat" -command [list [self] ClearChat]]
            pack $send -side right -padx 5
            pack $clear -side left -padx 5

            grid rowconfigure $w 0 -weight 1
            grid columnconfigure $w 0 -weight 1
            
            my AddToHistory "system" $options(-system_prompt)
        }

        method AddToHistory {role message} {
            $history configure -state normal
            $history insert end "\n$role: " $role
            $history insert end "$message\n"
            $history configure -state disabled
            $history see end
        }

        method ClearChat {} {
            set messages {}
            $history configure -state normal
            $history delete 1.0 end
            $history configure -state disabled
            my AddToHistory "system" $options(-system_prompt)
        }

        method SendMessage {} {
            set msg [string trim [$input get 1.0 end]]
            if {$msg eq ""} return
            
            $input delete 1.0 end
            my AddToHistory "user" $msg
            
            lappend messages [list role "user" content $msg]
            
            my CallAPI
        }

        method BuildPayload {} {
            set mlist {}
            lappend mlist [format {{"role": "system", "content": "%s"}} [my EscapeJson $options(-system_prompt)]]
            foreach msg $messages {
                set r [dict get $msg role]
                set c [dict get $msg content]
                lappend mlist [format {{"role": "%s", "content": "%s"}} $r [my EscapeJson $c]]
            }
            set body [format {{"model": "%s", "messages": [%s]}} $options(-model) [join $mlist ","]]
            return $body
        }

        method EscapeJson {str} {
            return [string map {\" \\\" \\ \\\\ \n \\n \r \\r \t \\t} $str]
        }

        method UnescapeJson {str} {
            return [string map {\\\" \" \\\\ \\ \\n \n \\r \r \\t \t} $str]
        }

        method CallAPI {} {
            set payload [my BuildPayload]
            set url $options(-base_url)
            set key $options(-api_key)
            set api_buffer ""

            set tmpfile [file join [file dirname [info script]] "payload_[pid].json"]
            set fh [open $tmpfile w]
            puts -nonewline $fh $payload
            close $fh

            set cmd [list curl -s -X POST $url \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $key" \
                -d @$tmpfile]

            if {[catch {open "|$cmd" r} chan]} {
                my AddToHistory "error" "Failed to start curl: $chan"
                file delete -force $tmpfile
                return
            }
            
            fconfigure $chan -blocking 0
            fileevent $chan readable [list [self] ReadAPIResponse $chan $tmpfile]
            $send configure -state disabled
            my AddToHistory "system" "Assistant is thinking..."
        }

        method ReadAPIResponse {chan tmpfile} {
            set data [read $chan]
            append api_buffer $data
            if {[eof $chan]} {
                catch {close $chan}
                if {[file exists $tmpfile]} {
                    file delete -force $tmpfile
                }
                my ProcessResponse $api_buffer
                $send configure -state normal
            }
        }

        method ProcessResponse {response} {
            if {[regexp {"content":\s*"((?:[^"\\]|\\.)*)"} $response -> content]} {
                set content [my UnescapeJson $content]
                my AddToHistory "assistant" $content
                lappend messages [list role "assistant" content $content]
            } elseif {[regexp {"error":\s*\{"message":\s*"([^"]*)"} $response -> err_msg]} {
                my AddToHistory "error" "API Error: $err_msg"
            } else {
                my AddToHistory "error" "Failed to parse API response. Raw response: $response"
            }
        }

        export configure cget get_option_varname SendMessage ClearChat AddToHistory BuildPayload EscapeJson UnescapeJson ProcessResponse
    }

    # Convenience procedure to create the ChatWidget
    proc ChatWidget {path args} {
        set obj [ChatWidgetClass create ::$path:obj $path {*}$args]
        rename $path ::$path:widget
        proc ::$path {cmd args} [format {
            set obj ::%s:obj
            if {[lsearch -exact [info object methods $obj] $cmd] != -1} {
                return [$obj $cmd {*}$args]
            } else {
                return [%s:widget $cmd {*}$args]
            }
        } $path $path]
        return $path
    }

    # Settings Widget Class
    oo::class create SettingsWidgetClass {
        variable w chatW

        constructor {path chatWidget args} {
            set w [ttk::frame $path]
            set chatW $chatWidget
            my CreateUI
        }

        method CreateUI {} {
            set config_frame [ttk::labelframe $w.config -text "LLM Configuration"]
            pack $config_frame -fill x -padx 10 -pady 10 -ipadx 5 -ipady 5

            set row 0
            foreach {label opt} {
                "Provider:" -provider
                "Model:" -model
                "Base URL:" -base_url
                "API Key:" -api_key
            } {
                ttk::label $config_frame.l$row -text $label
                ttk::entry $config_frame.e$row -textvariable [$chatW get_option_varname $opt]
                grid $config_frame.l$row -row $row -column 0 -sticky e -padx 5 -pady 5
                grid $config_frame.e$row -row $row -column 1 -sticky ew -padx 5 -pady 5
                incr row
            }
            grid columnconfigure $config_frame 1 -weight 1
        }
    }

    # Convenience procedure to create the SettingsWidget
    proc SettingsWidget {path chatWidget args} {
        set obj [SettingsWidgetClass create ::$path:obj $path $chatWidget {*}$args]
        rename $path ::$path:widget
        proc ::$path {cmd args} [format {
            set obj ::%s:obj
            if {[lsearch -exact [info object methods $obj] $cmd] != -1} {
                return [$obj $cmd {*}$args]
            } else {
                return [%s:widget $cmd {*}$args]
            }
        } $path $path]
        return $path
    }
}
