package provide llm_ui 0.1

package require TclOO
package require Tk

namespace eval ::llm_ui {
    # Try to load json from tcllib
    catch {package require json}

    proc parse_json {json} {
        if {[info commands ::json::json2dict] ne ""} {
            if {![catch {::json::json2dict $json} data]} {
                return $data
            }
        }
        # Very limited fallback for providers.json and models list
        return [simple_json_parse $json]
    }

    proc simple_json_parse {json} {
        set json [string trim $json]
        set LB "\{"
        set RB "\}"
        if {[string index $json 0] eq $LB} {
            set dict {}
            # Match top-level keys
            set re_key_val "\"(\[^\"]+)\":\\s*(\[^,${RB}\]+|\\\[\[^\\\]\]+\\\]|${LB}\[^\n${RB}\]+${RB})"
            set matches [regexp -all -inline $re_key_val $json]
            foreach {full key val} $matches {
                set val [string trim $val]
                if {[string index $val 0] eq "\["} {
                    set list {}
                    set inner [string range $val 1 end-1]
                    # Match objects in list
                    set re_obj "${LB}\[^${RB}\]+${RB}"
                    set omatches [regexp -all -inline $re_obj $inner]
                    foreach om $omatches {
                        lappend list [simple_json_parse $om]
                    }
                    lappend dict $key $list
                } elseif {[string index $val 0] eq $LB} {
                    lappend dict $key [simple_json_parse $val]
                } else {
                    lappend dict $key [string trim $val " \""]
                }
            }
            return $dict
        }
        return [string trim $json " \""]
    }

    proc extract_ids {json key} {
        set ids {}
        set pattern "\"$key\":\\s*\"(\[^\"]+)\""
        set matches [regexp -all -inline $pattern $json]
        foreach {full match} $matches {
            lappend ids $match
        }
        return [lsort -unique $ids]
    }

    # Chat Widget Class
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
                -base_url "https://api.openai.com/v1"
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
            set history_frame [ttk::frame $w.hframe]
            grid $history_frame -row 0 -column 0 -sticky nsew -padx 5 -pady 5
            
            set history [text $history_frame.txt -wrap word -state disabled -height 15]
            set hscroll [ttk::scrollbar $history_frame.vsb -orient vertical -command [list $history yview]]
            $history configure -yscrollcommand [list $hscroll set]
            
            pack $hscroll -side right -fill y
            pack $history -side left -fill both -expand yes

            $history tag configure user -foreground blue -font {Helvetica 10 bold}
            $history tag configure assistant -foreground darkgreen -font {Helvetica 10 bold}
            $history tag configure system -foreground gray -font {Helvetica 10 italic}
            $history tag configure error -foreground red

            set input_frame [ttk::frame $w.iframe]
            grid $input_frame -row 1 -column 0 -sticky ew -padx 5 -pady 5
            
            set input [text $input_frame.txt -wrap word -height 4]
            set iscroll [ttk::scrollbar $input_frame.vsb -orient vertical -command [list $input yview]]
            $input configure -yscrollcommand [list $iscroll set]
            
            pack $iscroll -side right -fill y
            pack $input -side left -fill both -expand yes

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
            if {![winfo exists $history]} return
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
            set url "$options(-base_url)/chat/completions"
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
                if {[winfo exists $send]} { $send configure -state normal }
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

    # Convenience procedure
    proc ChatWidget {path args} {
        set obj [ChatWidgetClass create ::$path:obj $path {*}$args]
        rename $path ::$path:widget
        proc ::$path {cmd args} [format {
            set obj ::%s:obj
            set methods [info object methods $obj -all]
            if {[lsearch -exact $methods $cmd] != -1} {
                return [$obj $cmd {*}$args]
            } else {
                return [::%s:widget $cmd {*}$args]
            }
        } $path $path]
        return $path
    }

    # Settings Widget Class
    oo::class create SettingsWidgetClass {
        variable w chatW providers_data provider_keys current_p_name cb_p

        constructor {path chatWidget args} {
            set w [ttk::frame $path]
            set chatW $chatWidget
            set providers_data {}
            set provider_keys {}
            set current_p_name ""
            my LoadProviders
            my CreateUI
        }

        method LoadProviders {} {
            set filename "providers.json"
            if {[file exists $filename]} {
                set fh [open $filename r]
                set content [read $fh]
                close $fh
                set data [::llm_ui::parse_json $content]
                if {[dict exists $data providers]} {
                    set providers_data [dict get $data providers]
                }
            } else {
                set providers_data {
                    {name "OpenAI" base_url "https://api.openai.com/v1"}
                    {name "Local" base_url "http://localhost:11434/v1"}
                }
            }
        }

        method CreateUI {} {
            set config_frame [ttk::labelframe $w.config -text "LLM Configuration"]
            pack $config_frame -fill x -padx 10 -pady 10 -ipadx 5 -ipady 5

            set row 0

            ttk::label $config_frame.lp -text "Provider:"
            set p_names {}
            foreach p $providers_data { lappend p_names [dict get $p name] }
            set cb_p [ttk::combobox $config_frame.cbp -values $p_names -state readonly]
            grid $config_frame.lp -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $cb_p -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $cb_p <<ComboboxSelected>> [list $w OnProviderSelected %W]
            incr row

            ttk::label $config_frame.lk -text "API Key:"
            set e_k [ttk::entry $config_frame.ek -show "*"]
            grid $config_frame.lk -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $e_k -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $e_k <FocusOut> [list $w SaveKeyAndRefresh %W]
            incr row

            ttk::label $config_frame.lm -text "Model:"
            set cb_m [ttk::combobox $config_frame.cbm -state readonly]
            grid $config_frame.lm -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $cb_m -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $cb_m <<ComboboxSelected>> [list $w OnModelSelected %W]
            incr row

            ttk::button $config_frame.btn_refresh -text "Refresh Models" -command [list $w RefreshModels]
            grid $config_frame.btn_refresh -row $row -column 1 -sticky e -padx 5 -pady 5
            incr row

            grid columnconfigure $config_frame 1 -weight 1

            if {[llength $p_names] > 0} {
                $cb_p current 0
                after idle [list $w OnProviderSelected $cb_p]
            }
        }

        method OnProviderSelected {w_cb} {
            set idx [$w_cb current]
            if {$idx == -1} return
            set p [lindex $providers_data $idx]
            set current_p_name [dict get $p name]
            set url [dict get $p base_url]

            set key ""
            if {[dict exists $provider_keys $current_p_name]} {
                set key [dict get $provider_keys $current_p_name]
            }
            $w.config.ek delete 0 end
            $w.config.ek insert 0 $key

            $chatW configure -provider $current_p_name -base_url $url -api_key $key

            my RefreshModels
        }

        method SaveKeyAndRefresh {w_entry} {
            set key [$w_entry get]
            dict set provider_keys $current_p_name $key
            $chatW configure -api_key $key
            my RefreshModels
        }

        method RefreshModels {} {
            set base_url [$chatW cget -base_url]
            my FetchModels $base_url
        }

        method FetchModels {base_url} {
            set url "$base_url/models"
            set key [$chatW cget -api_key]

            set cmd [list curl -s -X GET $url]
            if {$key ne ""} {
                lappend cmd -H "Authorization: Bearer $key"
            }

            if {[catch {exec {*}$cmd} response]} {
                my UpdateModelList {"gpt-4o-mini" "gpt-4o"}
                return
            }

            set models [::llm_ui::extract_ids $response "id"]

            if {[llength $models] == 0} {
                set models {"gpt-4o-mini" "gpt-4o"}
            }
            my UpdateModelList $models
        }

        method UpdateModelList {models} {
            set cb_m $w.config.cbm
            $cb_m configure -values $models
            if {[llength $models] > 0} {
                set current [$chatW cget -model]
                set midx [lsearch -exact $models $current]
                if {$midx != -1} { $cb_m current $midx } else { $cb_m current 0 }
                my OnModelSelected $cb_m
            }
        }

        method OnModelSelected {w_cb} {
            set model [$w_cb get]
            $chatW configure -model $model
        }

        export OnProviderSelected SaveKeyAndRefresh RefreshModels OnModelSelected
    }

    # Convenience procedure
    proc SettingsWidget {path chatWidget args} {
        set obj [SettingsWidgetClass create ::$path:obj $path $chatWidget {*}$args]
        rename $path ::$path:widget
        proc ::$path {cmd args} [format {
            set obj ::%s:obj
            set methods [info object methods $obj -all]
            if {[lsearch -exact $methods $cmd] != -1} {
                return [$obj $cmd {*}$args]
            } else {
                return [::%s:widget $cmd {*}$args]
            }
        } $path $path]
        return $path
    }
}
