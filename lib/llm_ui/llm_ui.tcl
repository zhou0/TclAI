package provide llm_ui 0.1

package require TclOO
package require Tk
package require http
package require tls
package require msgcat

namespace eval ::llm_ui {
    ::msgcat::mcload [file join [file dirname [info script]] msgs]
    http::register https 443 [list ::tls::socket -autoservername 1]
    catch {package require json}

    proc parse_json {json} {
        if {[info commands ::json::json2dict] ne ""} {
            if {![catch {::json::json2dict $json} data]} { return $data }
        }
        return [simple_json_parse $json]
    }

    proc simple_json_parse {json} {
        set json [string trim $json]
        if {[string index $json 0] eq "\{" || [string index $json 0] eq "\["} {
            set result {}
            set i 0
            set len [string length $json]
            incr i
            while {$i < $len - 1} {
                set char [string index $json $i]
                if {[string is space $char] || $char eq "," || $char eq ":"} { incr i; continue }
                if {$char eq "\""} {
                    set start [expr {$i + 1}]
                    set end [string first "\"" $json $start]
                    while {$end != -1 && [string index $json [expr {$end - 1}]] eq "\\"} {
                        set end [string first "\"" $json [expr {$end + 1}]]
                    }
                    lappend result [unescape_json [string range $json $start [expr {$end - 1}]]]
                    set i [expr {$end + 1}]
                } elseif {$char eq "\{" || $char eq "\["} {
                    set start $i
                    set depth 1
                    set open $char
                    set close [expr {$char eq "\{" ? "\}" : "\]"}]
                    incr i
                    while {$depth > 0 && $i < $len} {
                        set c [string index $json $i]
                        if {$c eq "\""} {
                             set s [expr {$i + 1}]
                             set e [string first "\"" $json $s]
                             while {$e != -1 && [string index $json [expr {$e - 1}]] eq "\\"} {
                                 set e [string first "\"" $json [expr {$e + 1}]]
                             }
                             set i [expr {$e + 1}]
                        } else {
                            if {$c eq $open} { incr depth } elseif {$c eq $close} { incr depth -1 }
                            incr i
                        }
                    }
                    lappend result [simple_json_parse [string range $json $start [expr {$i - 1}]]]
                } else {
                    if {[regexp -start $i -- {[^,\]\} ]+} $json match]} {
                        lappend result $match
                        set i [expr {$i + [string length $match]}]
                    } else { incr i }
                }
            }
            return $result
        }
        return $json
    }

    proc dict_to_json {dict_data} {
        set items {}
        foreach {k v} $dict_data {
            if {$k eq "providers"} {
                set p_json_list {}
                foreach p $v {
                    set p_items {}
                    foreach {pk pv} $p {
                        if {$pk eq "models"} {
                             set m_list {}
                             foreach m $pv {
                                 if {[llength $m] > 1} {
                                     set m_items {}
                                     foreach {mk mv} $m { lappend m_items "\"$mk\": \"[escape_json $mv]\"" }
                                     lappend m_list "\{[join $m_items ", "]\}"
                                 } else { lappend m_list "\"$m\"" }
                             }
                             lappend p_items "\"models\": \[[join $m_list ", "]\]"
                        } else { lappend p_items "\"$pk\": \"[escape_json $pv]\"" }
                    }
                    lappend p_json_list "\{[join $p_items ", "]\}"
                }
                lappend items "\"providers\": \[[join $p_json_list ", "]\]"
            } else { lappend items "\"$k\": \"[escape_json $v]\"" }
        }
        return "\{[join $items ", "]\}"
    }

    proc escape_json {str} { return [string map {\\ \\\\ \" \\\" \n \\n \r \\r \t \\t} $str] }
    proc unescape_json {str} { return [string map {\\\" \" \\\\ \\ \\n \n \\r \r \\t \t} $str] }

    proc extract_ids {json key} {
        set ids {}
        set pattern "\"$key\":\\s*\"(\[^\"]+)\""
        set matches [regexp -all -inline $pattern $json]
        foreach {full match} $matches { lappend ids $match }
        return [lsort -unique $ids]
    }

    # Chat Widget Class
    oo::class create ChatWidgetClass {
        variable w history input send options messages

        constructor {path args} {
            set w [ttk::frame $path]
            set messages {}
            array set options {-provider "" -model "" -base_url "" -api_key "" -system_prompt ""}
            my configure {*}$args
            my CreateUI
        }

        method configure {args} {
            foreach {opt val} $args { if {[info exists options($opt)]} { set options($opt) $val } }
        }

        method cget {opt} { return $options($opt) }
        method get_option_varname {opt} { return [my varname options($opt)] }

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
            set send [ttk::button $btn_frame.send -text [::msgcat::mc "Send"] -command [list [self] SendMessage]]
            set clear [ttk::button $btn_frame.clear -text [::msgcat::mc "Clear Chat"] -command [list [self] ClearChat]]
            pack $send -side right -padx 5
            pack $clear -side left -padx 5
            grid rowconfigure $w 0 -weight 1
            grid columnconfigure $w 0 -weight 1
        }

        method UpdateTranslations {} {
            $w.bframe.send configure -text [::msgcat::mc "Send"]
            $w.bframe.clear configure -text [::msgcat::mc "Clear Chat"]
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
            lappend mlist [format {{"role": "system", "content": "%s"}} [::llm_ui::escape_json $options(-system_prompt)]]
            foreach msg $messages {
                set r [dict get $msg role]
                set c [dict get $msg content]
                lappend mlist [format {{"role": "%s", "content": "%s"}} $r [::llm_ui::escape_json $c]]
            }
            return [format {{"model": "%s", "messages": [%s]}} $options(-model) [join $mlist ","]]
        }

        method CallAPI {} {
            set payload [my BuildPayload]
            set url "$options(-base_url)/chat/completions"
            set headers [list "Content-Type" "application/json"]
            if {$options(-api_key) ne ""} { lappend headers "Authorization" "Bearer $options(-api_key)" }
            if {[catch {http::geturl $url -query [encoding convertto utf-8 $payload] -type "application/json" -headers $headers -command [list [self] ReadAPIResponseHttp]} token]} {
                my AddToHistory "error" "HTTP Request Failed: $token"
                return
            }
            $send configure -state disabled
            my AddToHistory "system" [::msgcat::mc "Assistant is thinking"]
        }

        method ReadAPIResponseHttp {token} {
            set status [http::status $token]
            set ncode [http::ncode $token]
            set data [encoding convertfrom utf-8 [http::data $token]]
            if {$status eq "ok"} {
                if {$ncode == 200} { my ProcessResponse $data } else { my AddToHistory "error" "API Error (HTTP $ncode): $data" }
            } else { my AddToHistory "error" "HTTP Error: $status" }
            http::cleanup $token
            if {[winfo exists $send]} { $send configure -state normal }
        }

        method ProcessResponse {response} {
            if {[regexp {"content":\s*"((?:[^"\\]|\\.)*)"} $response -> content]} {
                set content [::llm_ui::unescape_json $content]
                my AddToHistory "assistant" $content
                lappend messages [list role "assistant" content $content]
            } elseif {[regexp {"error":\s*\{"message":\s*"([^"]*)"} $response -> err_msg]} {
                my AddToHistory "error" "API Error: $err_msg"
            } else { my AddToHistory "error" "Failed to parse API response." }
        }
        export configure cget get_option_varname SendMessage ClearChat AddToHistory BuildPayload ProcessResponse ReadAPIResponseHttp UpdateTranslations
    }

    proc ChatWidget {path args} {
        set obj [ChatWidgetClass create ::$path:obj $path {*}$args]
        rename $path ::$path:widget
        proc ::$path {cmd args} [format {
            set obj ::%s:obj
            if {[lsearch -exact [info object methods $obj -all] $cmd] != -1} { return [$obj $cmd {*}$args] } else { return [::%s:widget $cmd {*}$args] }
        } $path $path]
        return $path
    }

    oo::class create SettingsWidgetClass {
        variable w chatW providers_data current_p_name cb_p def_p_text sys_p_text cb_lang default_prompt

        constructor {path chatWidget args} {
            set w [ttk::frame $path]
            set chatW $chatWidget
            set providers_data {}
            set current_p_name ""
            set default_prompt ""
            my LoadProviders
            my CreateUI
        }

        method LoadProviders {} {
            set filename "providers.json"
            if {[file exists $filename]} {
                set fh [open $filename r]
                set data [::llm_ui::parse_json [read $fh]]
                close $fh
                foreach {k v} $data { if {$k eq "default_prompt"} { set default_prompt $v } elseif {$k eq "providers"} { set providers_data $v } }
            }
            if {[llength $providers_data] == 0} {
                set default_prompt "You are a helpful assistant."
                set providers_data {{name OpenAI base_url https://api.openai.com/v1 api_key "" models {}}}
            }
        }

        method SaveProviders {} {
            set data [list default_prompt $default_prompt providers $providers_data]
            set fh [open "providers.json" w]
            puts $fh [::llm_ui::dict_to_json $data]
            close $fh
        }

        method FindProviderIdx {name} {
            set idx 0
            foreach p $providers_data {
                set p_name ""
                foreach {k v} $p { if {$k eq "name"} { set p_name $v; break } }
                if {$p_name eq $name} { return $idx }
                incr idx
            }
            return -1
        }

        method CreateUI {} {
            set f [ttk::labelframe $w.config -text [::msgcat::mc "Settings"]]
            pack $f -fill both -expand yes -padx 10 -pady 10 -ipadx 5 -ipady 5
            set row 0
            ttk::label $f.llang -text [::msgcat::mc "Language"]
            set cb_lang [ttk::combobox $f.cblang -values {"English" "简体中文" "繁體中文"} -state readonly]
            grid $f.llang -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $cb_lang -row $row -column 1 -sticky ew -padx 5 -pady 5
            set current_lang [::msgcat::mclocale]
            if {[string match zh_cn* $current_lang]} { $cb_lang current 1 } elseif {[string match zh_tw* $current_lang] || [string match zh_hk* $current_lang]} { $cb_lang current 2 } else { $cb_lang current 0 }
            bind $cb_lang <<ComboboxSelected>> [list [self] OnLanguageSelected]
            incr row
            ttk::label $f.lp -text [::msgcat::mc "Provider"]
            set p_names {}
            foreach p $providers_data { foreach {k v} $p { if {$k eq "name"} { lappend p_names $v; break } } }
            set cb_p [ttk::combobox $f.cbp -values $p_names -state readonly]
            grid $f.lp -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $cb_p -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $cb_p <<ComboboxSelected>> [list [self] OnProviderSelected %W]
            incr row
            ttk::label $f.lk -text [::msgcat::mc "API Key"]
            set e_k [ttk::entry $f.ek -show "*"]
            grid $f.lk -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $e_k -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $e_k <FocusOut> [list [self] ChangeKey]
            incr row
            ttk::button $f.btn_key -text [::msgcat::mc "Change API Key"] -command [list [self] ChangeKey]
            grid $f.btn_key -row $row -column 1 -sticky e -padx 5 -pady 5
            incr row
            ttk::label $f.lm -text [::msgcat::mc "Model"]
            set cb_m [ttk::combobox $f.cbm -state readonly]
            grid $f.lm -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $cb_m -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $cb_m <<ComboboxSelected>> [list [self] OnModelSelected %W]
            incr row
            ttk::button $f.btn_refresh -text [::msgcat::mc "Refresh Models"] -command [list [self] RefreshModels]
            grid $f.btn_refresh -row $row -column 1 -sticky e -padx 5 -pady 5
            incr row
            ttk::label $f.ldp -text [::msgcat::mc "Default Prompt"]
            grid $f.ldp -row $row -column 0 -sticky ne -padx 5 -pady 5
            set def_p_frame [ttk::frame $f.dpf]
            grid $def_p_frame -row $row -column 1 -sticky nsew -padx 5 -pady 5
            set def_p_text [text $def_p_frame.txt -height 3 -wrap word]
            pack $def_p_text -fill both -expand yes
            $def_p_text insert 1.0 $default_prompt
            incr row
            ttk::label $f.lsp -text [::msgcat::mc "System Prompt"]
            grid $f.lsp -row $row -column 0 -sticky ne -padx 5 -pady 5
            set sys_p_frame [ttk::frame $f.spf]
            grid $sys_p_frame -row $row -column 1 -sticky nsew -padx 5 -pady 5
            set sys_p_text [text $sys_p_frame.txt -height 3 -wrap word]
            pack $sys_p_text -fill both -expand yes
            incr row
            ttk::button $f.btn_save -text [::msgcat::mc "Save Prompts"] -command [list [self] SavePrompts]
            grid $f.btn_save -row $row -column 1 -sticky e -padx 5 -pady 5
            grid columnconfigure $f 1 -weight 1
            grid rowconfigure $f [expr {$row-2}] -weight 1
            grid rowconfigure $f [expr {$row-3}] -weight 1
            if {[llength $p_names] > 0} { $cb_p current 0; after idle [list [self] OnProviderSelected $cb_p] }
        }

        method UpdateTranslations {} {
            set f $w.config
            $f configure -text [::msgcat::mc "Settings"]
            $f.llang configure -text [::msgcat::mc "Language"]
            $f.lp configure -text [::msgcat::mc "Provider"]
            $f.lk configure -text [::msgcat::mc "API Key"]
            $f.btn_key configure -text [::msgcat::mc "Change API Key"]
            $f.lm configure -text [::msgcat::mc "Model"]
            $f.btn_refresh configure -text [::msgcat::mc "Refresh Models"]
            $f.ldp configure -text [::msgcat::mc "Default Prompt"]
            $f.lsp configure -text [::msgcat::mc "System Prompt"]
            $f.btn_save configure -text [::msgcat::mc "Save Prompts"]
        }

        method OnLanguageSelected {} {
            set lang [$cb_lang get]
            set locale en
            if {$lang eq "简体中文"} { set locale zh_cn } elseif {$lang eq "繁體中文"} { set locale zh_tw }
            ::msgcat::mclocale $locale
            set fh [open "preference.json" w]; puts $fh "\{\"language\": \"$locale\"\}"; close $fh
            my UpdateTranslations
            $chatW UpdateTranslations
            event generate . <<LanguageChanged>>
        }

        method OnProviderSelected {w_cb} {
            set idx [$w_cb current]
            if {$idx == -1} return
            set p [lindex $providers_data $idx]
            set current_p_name ""
            set url ""
            set key ""
            foreach {k v} $p { if {$k eq "name"} { set current_p_name $v } elseif {$k eq "base_url"} { set url $v } elseif {$k eq "api_key"} { set key $v } }
            $w.config.ek delete 0 end; $w.config.ek insert 0 $key
            $chatW configure -provider $current_p_name -base_url $url -api_key $key -system_prompt $default_prompt
            my RefreshModels
        }

        method ChangeKey {} {
            set key [$w.config.ek get]
            set idx [my FindProviderIdx $current_p_name]
            if {$idx != -1} {
                set p [lindex $providers_data $idx]
                set new_p {}
                foreach {k v} $p { if {$k eq "api_key"} { lappend new_p $k $key } else { lappend new_p $k $v } }
                set providers_data [lreplace $providers_data $idx $idx $new_p]
                my SaveProviders
                $chatW configure -api_key $key
                my RefreshModels
            }
        }

        method SavePrompts {} {
            set default_prompt [string trim [$def_p_text get 1.0 end]]
            set sys_prompt [string trim [$sys_p_text get 1.0 end]]
            set m_name [$w.config.cbm get]
            set p_idx [my FindProviderIdx $current_p_name]
            if {$p_idx != -1} {
                set p [lindex $providers_data $p_idx]
                set models {}
                foreach {k v} $p { if {$k eq "models"} { set models $v; break } }
                set new_models {}
                foreach m $models {
                    set id ""
                    foreach {mk mv} $m { if {$mk eq "id"} { set id $mv; break } }
                    if {$id eq $m_name || $m eq $m_name} { set m [list id $m_name system_prompt $sys_prompt] }
                    lappend new_models $m
                }
                set new_p {}
                foreach {k v} $p { if {$k eq "models"} { lappend new_p $k $new_models } else { lappend new_p $k $v } }
                set providers_data [lreplace $providers_data $p_idx $p_idx $new_p]
                my SaveProviders
            }
            $chatW configure -system_prompt $sys_prompt
        }

        method RefreshModels {} {
            set p [lindex $providers_data [my FindProviderIdx $current_p_name]]
            set models {}
            foreach {k v} $p { if {$k eq "models"} { set models $v; break } }
            if {[llength $models] > 0} {
                set ids {}
                foreach m $models { if {[llength $m] > 1} { foreach {mk mv} $m { if {$mk eq "id"} { lappend ids $mv; break } } } else { lappend ids $m } }
                my UpdateModelList $ids; return
            }
            my FetchModels [$chatW cget -base_url]
        }

        method FetchModels {base_url} {
            set url "$base_url/models"
            set headers [list "Authorization" "Bearer [$chatW cget -api_key]"]
            if {[catch {http::geturl $url -headers $headers -timeout 5000} token]} {
                my UpdateModelList {"gpt-4o-mini" "gpt-4o"}; return
            }
            set res [encoding convertfrom utf-8 [http::data $token]]; http::cleanup $token
            set ids [::llm_ui::extract_ids $res "id"]
            if {[llength $ids] == 0} { set ids {"gpt-4o-mini" "gpt-4o"} }
            set p_idx [my FindProviderIdx $current_p_name]
            if {$p_idx != -1} {
                set p [lindex $providers_data $p_idx]
                set m_list {}
                foreach id $ids { lappend m_list [list id $id system_prompt $default_prompt] }
                set new_p {}
                foreach {k v} $p { if {$k eq "models"} { lappend new_p $k $m_list } else { lappend new_p $k $v } }
                set providers_data [lreplace $providers_data $p_idx $p_idx $new_p]
                my SaveProviders
            }
            my UpdateModelList $ids
        }

        method UpdateModelList {models} {
            $w.config.cbm configure -values $models
            if {[llength $models] > 0} {
                set current [$chatW cget -model]
                set midx [lsearch -exact $models $current]
                $w.config.cbm current [expr {$midx != -1 ? $midx : 0}]
                my OnModelSelected $w.config.cbm
            }
        }

        method OnModelSelected {w_cb} {
            set model [$w_cb get]
            $chatW configure -model $model
            set p [lindex $providers_data [my FindProviderIdx $current_p_name]]
            set models {}; foreach {k v} $p { if {$k eq "models"} { set models $v; break } }
            set prompt $default_prompt
            foreach m $models {
                set id ""; set sp ""
                foreach {mk mv} $m { if {$mk eq "id"} { set id $mv } elseif {$mk eq "system_prompt"} { set sp $mv } }
                if {$id eq $model} { if {$sp ne ""} { set prompt $sp }; break }
            }
            $sys_p_text delete 1.0 end; $sys_p_text insert 1.0 $prompt
            $chatW configure -system_prompt $prompt
        }
        export OnProviderSelected ChangeKey RefreshModels OnModelSelected OnLanguageSelected SavePrompts UpdateTranslations
    }

    proc SettingsWidget {path chatWidget args} {
        set obj [SettingsWidgetClass create ::$path:obj $path $chatWidget {*}$args]
        rename $path ::$path:widget
        proc ::$path {cmd args} [format {
            set obj ::%s:obj
            if {[lsearch -exact [info object methods $obj -all] $cmd] != -1} { return [$obj $cmd {*}$args] } else { return [::%s:widget $cmd {*}$args] }
        } $path $path]
        return $path
    }
}
