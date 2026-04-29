package provide llm_ui 0.1

package require TclOO
package require Tk
package require http
package require tls

namespace eval ::llm_ui {
    # Register HTTPS protocol
    http::register https 443 [list ::tls::socket -autoservername 1]

    # Try to load json from tcllib
    catch {package require json}

    proc parse_json {json} {
        if {[info commands ::json::json2dict] ne ""} {
            if {![catch {::json::json2dict $json} data]} {
                return $data
            }
        }
        # Fallback for providers.json
        set providers {}
        set matches [regexp -all -inline {\{"name":\s*"([^"]+)",\s*"base_url":\s*"([^"]+)",\s*"api_key":\s*"([^"]*)",\s*"models":\s*\[([^\]]*)\]\}} $json]
        foreach {full name url key models_str} $matches {
            set m_list {}
            foreach {f m} [regexp -all -inline {"([^"]+)"} $models_str] {
                lappend m_list $m
            }
            lappend providers [list name $name base_url $url api_key $key models $m_list]
        }
        if {[llength $providers] > 0} { return [list providers $providers] }

        # Fallback for models list
        set ids {}
        foreach {f m} [regexp -all -inline {"id":\s*"([^"]+)"} $json] {
            lappend ids $m
        }
        return [list data {}]
    }

    proc dict_to_json {dict_data} {
        set providers [dict get $dict_data providers]
        set p_json_list {}
        foreach p $providers {
            set items {}
            foreach {k v} $p {
                if {$k eq "models"} {
                    set m_list {}
                    foreach m $v { lappend m_list "\"$m\"" }
                    lappend items "\"models\": \[[join $m_list ", "]\]"
                } else {
                    lappend items "\"$k\": \"$v\""
                }
            }
            lappend p_json_list "\{[join $items ", "]\}"
        }
        return "\{\"providers\": \[[join $p_json_list ", "]\]\}"
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

            set headers [list "Content-Type" "application/json"]
            if {$key ne ""} { lappend headers "Authorization" "Bearer $key" }

            if {[catch {http::geturl $url -query $payload -headers $headers -command [list [self] ReadAPIResponseHttp]} token]} {
                my AddToHistory "error" "HTTP Request Failed: $token"
                return
            }
            $send configure -state disabled
            my AddToHistory "system" "Assistant is thinking..."
        }

        method ReadAPIResponseHttp {token} {
            set status [http::status $token]
            set ncode [http::ncode $token]
            set data [http::data $token]

            puts "DEBUG: API Response Status: $status, HTTP Code: $ncode"
            puts "DEBUG: Raw API Response: $data"

            if {$status eq "ok"} {
                if {$ncode == 200} {
                    my ProcessResponse $data
                } else {
                    my AddToHistory "error" "API Error (HTTP $ncode): $data"
                }
            } else {
                my AddToHistory "error" "HTTP Error: $status"
            }
            http::cleanup $token
            if {[winfo exists $send]} { $send configure -state normal }
        }

        method ProcessResponse {response} {
            set response [string trim $response]
            if {$response eq ""} {
                my AddToHistory "error" "Received empty response from API."
                return
            }
            if {[regexp {"content":\s*"((?:[^"\\]|\\.)*)"} $response -> content]} {
                set content [my UnescapeJson $content]
                my AddToHistory "assistant" $content
                lappend messages [list role "assistant" content $content]
            } elseif {[regexp {"error":\s*\{"message":\s*"([^"]*)"} $response -> err_msg]} {
                my AddToHistory "error" "API Error: $err_msg"
            } else {
                my AddToHistory "error" "Failed to parse API response. Check console for raw response."
            }
        }

        export configure cget get_option_varname SendMessage ClearChat AddToHistory BuildPayload EscapeJson UnescapeJson ProcessResponse ReadAPIResponseHttp
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
        variable w chatW providers_data current_p_name cb_p sys_p_text

        constructor {path chatWidget args} {
            set w [ttk::frame $path]
            set chatW $chatWidget
            set providers_data {}
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
                if {[llength $data] >= 2 && [lindex $data 0] eq "providers"} {
                    set providers_data [lindex $data 1]
                } else {
                    my DefaultProviders
                }
            } else {
                my DefaultProviders
            }
        }

        method DefaultProviders {} {
            set providers_data {
                {name OpenAI base_url https://api.openai.com/v1 api_key "" models {}}
                {name OpenRouter base_url https://openrouter.ai/api/v1 api_key "" models {}}
                {name Anthropic base_url https://api.anthropic.com/v1 api_key "" models {}}
                {name Local base_url http://localhost:11434/v1 api_key "" models {}}
            }
        }

        method SaveProviders {} {
            set filename "providers.json"
            set data [list providers $providers_data]
            set json [::llm_ui::dict_to_json $data]
            set fh [open $filename w]
            puts $fh $json
            close $fh
        }

        method FindProviderIdx {name} {
            set idx 0
            foreach p $providers_data {
                set p_name [lindex $p [expr {[lsearch -exact $p name] + 1}]]
                if {$p_name eq $name} { return $idx }
                incr idx
            }
            return -1
        }

        method CreateUI {} {
            set config_frame [ttk::labelframe $w.config -text "LLM Configuration"]
            pack $config_frame -fill both -expand yes -padx 10 -pady 10 -ipadx 5 -ipady 5

            set row 0

            ttk::label $config_frame.lp -text "Provider:"
            set p_names {}
            foreach p $providers_data {
                lappend p_names [lindex $p [expr {[lsearch -exact $p name] + 1}]]
            }
            set cb_p [ttk::combobox $config_frame.cbp -values $p_names -state readonly]
            grid $config_frame.lp -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $cb_p -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $cb_p <<ComboboxSelected>> [list $w OnProviderSelected %W]
            incr row

            ttk::label $config_frame.lk -text "API Key:"
            set e_k [ttk::entry $config_frame.ek -show "*"]
            grid $config_frame.lk -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $e_k -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $e_k <FocusOut> [list $w ChangeKey]
            incr row

            ttk::button $config_frame.btn_key -text "Change API Key" -command [list $w ChangeKey]
            grid $config_frame.btn_key -row $row -column 1 -sticky e -padx 5 -pady 5
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

            # System Prompt Editor
            ttk::label $config_frame.lsp -text "System Prompt:"
            grid $config_frame.lsp -row $row -column 0 -sticky ne -padx 5 -pady 5

            set sys_p_frame [ttk::frame $config_frame.spf]
            grid $sys_p_frame -row $row -column 1 -sticky nsew -padx 5 -pady 5
            set sys_p_text [text $sys_p_frame.txt -height 5 -wrap word]
            set sys_p_vsb [ttk::scrollbar $sys_p_frame.vsb -orient vertical -command [list $sys_p_text yview]]
            $sys_p_text configure -yscrollcommand [list $sys_p_vsb set]
            pack $sys_p_vsb -side right -fill y
            pack $sys_p_text -side left -fill both -expand yes

            $sys_p_text insert 1.0 [$chatW cget -system_prompt]
            incr row

            ttk::button $config_frame.btn_sysp -text "Save System Prompt" -command [list $w SaveSystemPrompt]
            grid $config_frame.btn_sysp -row $row -column 1 -sticky e -padx 5 -pady 5
            incr row

            grid columnconfigure $config_frame 1 -weight 1
            grid rowconfigure $config_frame [expr {$row - 2}] -weight 1

            if {[llength $p_names] > 0} {
                $cb_p current 0
                after idle [list $w OnProviderSelected $cb_p]
            }
        }

        method OnProviderSelected {w_cb} {
            set idx [$w_cb current]
            if {$idx == -1} return
            set p [lindex $providers_data $idx]
            set current_p_name [lindex $p [expr {[lsearch -exact $p name] + 1}]]
            set url [lindex $p [expr {[lsearch -exact $p base_url] + 1}]]
            set key [lindex $p [expr {[lsearch -exact $p api_key] + 1}]]

            $w.config.ek delete 0 end
            $w.config.ek insert 0 $key

            $chatW configure -provider $current_p_name -base_url $url -api_key $key

            my RefreshModels
        }

        method ChangeKey {} {
            set key [$w.config.ek get]
            set idx [my FindProviderIdx $current_p_name]
            if {$idx != -1} {
                set p [lindex $providers_data $idx]
                set k_idx [lsearch -exact $p api_key]
                set p [lreplace $p [expr {$k_idx+1}] [expr {$k_idx+1}] $key]
                set providers_data [lreplace $providers_data $idx $idx $p]
                my SaveProviders
                $chatW configure -api_key $key
                my RefreshModels
            }
        }

        method SaveSystemPrompt {} {
            set prompt [string trim [$sys_p_text get 1.0 end]]
            $chatW configure -system_prompt $prompt
        }

        method RefreshModels {} {
            set idx [my FindProviderIdx $current_p_name]
            if {$idx != -1} {
                set p [lindex $providers_data $idx]
                set m_idx [lsearch -exact $p models]
                if {$m_idx != -1} {
                    set models [lindex $p [expr {$m_idx+1}]]
                    if {[llength $models] > 0} {
                        my UpdateModelList $models
                        return
                    }
                }
            }
            set base_url [$chatW cget -base_url]
            my FetchModels $base_url
        }

        method FetchModels {base_url} {
            set url "$base_url/models"
            set key [$chatW cget -api_key]

            set headers {}
            if {$key ne ""} { lappend headers "Authorization" "Bearer $key" }

            if {[catch {http::geturl $url -headers $headers -timeout 5000} token]} {
                my UpdateModelList {"gpt-4o-mini" "gpt-4o"}
                return
            }

            set response ""
            if {[http::status $token] eq "ok"} {
                set response [http::data $token]
            }
            puts "DEBUG: Model Fetch Response: [http::status $token], HTTP Code: [http::ncode $token]"
            puts "DEBUG: Raw Model Response: $response"
            http::cleanup $token

            if {$response eq ""} {
                my UpdateModelList {"gpt-4o-mini" "gpt-4o"}
                return
            }

            set models [::llm_ui::extract_ids $response "id"]
            if {[llength $models] == 0} { set models {"gpt-4o-mini" "gpt-4o"} }

            set idx [my FindProviderIdx $current_p_name]
            if {$idx != -1} {
                set p [lindex $providers_data $idx]
                set m_idx [lsearch -exact $p models]
                if {$m_idx == -1} {
                    lappend p models $models
                } else {
                    set p [lreplace $p [expr {$m_idx+1}] [expr {$m_idx+1}] $models]
                }
                set providers_data [lreplace $providers_data $idx $idx $p]
                my SaveProviders
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

        export OnProviderSelected ChangeKey SaveSystemPrompt RefreshModels OnModelSelected
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
