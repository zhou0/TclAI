package provide llm_ui 0.1

package require TclOO
package require Tk
package require llm_ui::logic
package require msgcat

namespace eval ::llm_ui {
    oo::class create ChatWidgetClass {
        variable w history input send options messages

        constructor {path args} {
            set w $path
            set history ""
            set input ""
            set messages {}
            set options(-provider) ""
            set options(-base_url) ""
            set options(-api_key) ""
            set options(-model) "gpt-4o-mini"
            set options(-system_prompt) "You are a helpful assistant."

            ttk::frame $w
            set history [text $w.history -height 15 -state disabled -wrap word]
            set input [text $w.input -height 3 -wrap word]
            set send [ttk::button $w.send -text [::llm_ui::logic::mc "Send"] -command [list [self] SendMessage]]

            pack $history -side top -fill both -expand yes -padx 5 -pady 5
            pack $input -side left -fill both -expand yes -padx 5 -pady 5
            pack $send -side right -padx 5 -pady 5

            bind $input <Return> [list [self] SendMessage]

            if {[llength $args] > 0} {
                my configure {*}$args
            }
            my LoadHistory
        }

        method UpdateTranslations {} {
            $w.send configure -text [::llm_ui::logic::mc "Send"]
        }

        method SendMessage {} {
            set msg [string trim [$input get 1.0 end]]
            if {$msg eq ""} return

            $input delete 1.0 end
            my AppendHistory "User" $msg
            lappend messages [list role "user" content $msg]
            my SaveHistory

            my CallAPI
        }

        method AppendHistory {role msg} {
            $history configure -state normal
            $history insert end "$role: $msg\n\n"
            $history configure -state disabled
            $history see end
        }

        method SaveHistory {} {
            set fh [open "history.json" w]
            puts $fh [::llm_ui::logic::json_gen_history $messages]
            close $fh
        }

        method LoadHistory {} {
            if {[file exists "history.json"]} {
                set fh [open "history.json" r]
                set json [read $fh]
                close $fh
                if {[catch {set loaded [::llm_ui::logic::json_parse $json]} err]} {
                    set messages {}
                } else {
                    set messages $loaded
                    foreach m $messages {
                        set role "User"
                        set content ""
                        foreach {k v} $m {
                            if {$k eq "role" && $v eq "assistant"} { set role "AI" }
                            if {$k eq "content"} { set content $v }
                        }
                        my AppendHistory $role $content
                    }
                }
            }
        }

        method CallAPI {} {
            set url "[my cget -base_url]/chat/completions"
            set key [my cget -api_key]
            set model [my cget -model]
            set system_prompt [my cget -system_prompt]

            if {$url eq "/chat/completions"} {
                my AppendHistory "Error" "No provider configured."
                return
            }

            set full_messages [linsert $messages 0 [list role "system" content $system_prompt]]

            set msg_json_list {}
            foreach m $full_messages {
                set r ""
                set c ""
                foreach {mk mv} $m { if {$mk eq "role"} { set r $mv } elseif {$mk eq "content"} { set c $mv } }
                lappend msg_json_list "\x7b\"role\":\"$r\",\"content\":\"[::llm_ui::logic::escape_json $c]\"\x7d"
            }
            set body "\x7b\"model\":\"$model\",\"messages\":\x5b[join $msg_json_list ", "]\x5d\x7d"

            set headers [list "Content-Type" "application/json" "Authorization" "Bearer $key"]

            if {[catch {http::geturl $url -query [encoding convertto utf-8 $body] -headers $headers -timeout 30000} token]} {
                my AppendHistory "Error" $token
                return
            }

            set status [http::status $token]
            set code [http::ncode $token]
            set data [encoding convertfrom utf-8 [http::data $token]]
            http::cleanup $token

            if {$status ne "ok" || $code != 200} {
                my AppendHistory "Error" "HTTP $code: $data"
                return
            }

            set res_dict [::llm_ui::logic::json_parse $data]
            set choices {}
            foreach {rk rv} $res_dict { if {$rk eq "choices"} { set choices $rv; break } }
            if {[llength $choices] > 0} {
                set first [lindex $choices 0]
                set msg_obj {}
                foreach {ck cv} $first { if {$ck eq "message"} { set msg_obj $cv; break } }
                set content ""
                foreach {mk mv} $msg_obj { if {$mk eq "content"} { set content $mv; break } }
                my AppendHistory "AI" $content
                lappend messages [list role "assistant" content $content]
                my SaveHistory
            }
        }

        method cget {opt} {
            if {[info exists options($opt)]} { return $options($opt) }
            return ""
        }

        method configure {args} {
            if {[llength $args] == 0} { return [array get options] }
            if {[llength $args] == 1} { return $options([lindex $args 0]) }
            foreach {opt val} $args {
                set options($opt) $val
            }
        }
        export SendMessage cget configure UpdateTranslations SaveHistory LoadHistory
    }

    proc ChatWidget {path args} {
        set obj [ChatWidgetClass create ::$path:obj $path {*}$args]
        rename $path ::$path:widget
        proc ::$path {cmd args} [format {
            set obj ::%s:obj
            if {[lsearch -exact [info object methods $obj -all] $cmd] != -1} {
                return [$obj $cmd {*}$args]
            }
            return [::%s:widget $cmd {*}$args]
        } $path $path]
        return $path
    }

    oo::class create SettingsWidgetClass {
        variable w chatW providers_data current_p_name cb_p def_p_text sys_p_text cb_lang default_prompt

        constructor {path chatWidget args} {
            set w $path
            set chatW $chatWidget
            set providers_data {}
            set current_p_name ""
            set default_prompt "You are a helpful assistant."

            ttk::frame $w
            my LoadProviders
            my BuildUI
        }

        method LoadProviders {} {
            if {[file exists "providers.json"]} {
                set fh [open "providers.json" r]
                set json [read $fh]
                close $fh
                set data [::llm_ui::logic::json_parse $json]
                set providers_data {}
                foreach {k v} $data {
                    if {$k eq "providers"} { set providers_data $v }
                    if {$k eq "default_prompt"} { set default_prompt $v }
                }
            } else {
                set providers_data [list \
                    [list name "OpenAI" base_url "https://api.openai.com/v1" api_key "" models {}] \
                    [list name "DeepSeek" base_url "https://api.deepseek.com/v1" api_key "" models {}] \
                    [list name "SiliconFlow" base_url "https://api.siliconflow.cn/v1" api_key "" models {}] \
                ]
            }
        }

        method SaveProviders {} {
            set fh [open "providers.json" w]
            puts $fh [::llm_ui::logic::json_gen_providers $providers_data $default_prompt]
            close $fh
        }

        method FindProviderIdx {name} {
            set i 0
            foreach p $providers_data {
                set found 0
                foreach {k v} $p { if {$k eq "name" && $v eq $name} { set found 1; break } }
                if {$found} { return $i }
                incr i
            }
            return -1
        }

        method BuildUI {} {
            set f [ttk::labelframe $w.config -text [::llm_ui::logic::mc "Settings"]]
            pack $f -fill both -expand yes -padx 10 -pady 10

            set row 0
            ttk::label $f.llang -text [::llm_ui::logic::mc "Language"]
            grid $f.llang -row $row -column 0 -sticky e -padx 5 -pady 5
            set current_locale [::msgcat::mclocale]
            set lang_name "English"
            if {$current_locale eq "zh_cn"} { set lang_name "简体中文" } elseif {$current_locale eq "zh_tw"} { set lang_name "繁體中文" }
            set cb_lang [ttk::combobox $f.cblang -values [list "English" "简体中文" "繁體中文"] -state readonly]
            $cb_lang set $lang_name
            grid $cb_lang -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $cb_lang <<ComboboxSelected>> [list [self] OnLanguageSelected]
            incr row
            ttk::label $f.lp -text [::llm_ui::logic::mc "Provider"]
            set p_names {}
            foreach p $providers_data { foreach {k v} $p { if {$k eq "name"} { lappend p_names $v; break } } }
            set cb_p [ttk::combobox $f.cbp -values $p_names -state readonly]
            grid $f.lp -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $cb_p -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $cb_p <<ComboboxSelected>> [list [self] OnProviderSelected %W]
            incr row
            ttk::label $f.lk -text [::llm_ui::logic::mc "API Key"]
            set e_k [ttk::entry $f.ek -show "*"]
            grid $f.lk -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $e_k -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $e_k <FocusOut> [list [self] ChangeKey]
            incr row
            ttk::button $f.btn_key -text [::llm_ui::logic::mc "Change API Key"] -command [list [self] ChangeKey]
            grid $f.btn_key -row $row -column 1 -sticky e -padx 5 -pady 5
            incr row
            ttk::label $f.lm -text [::msgcat::mc "Model"]
            set cb_m [ttk::combobox $f.cbm -state readonly]
            grid $f.lm -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $cb_m -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $cb_m <<ComboboxSelected>> [list [self] OnModelSelected %W]
            incr row
            ttk::button $f.btn_refresh -text [::llm_ui::logic::mc "Refresh Models"] -command [list [self] RefreshModels]
            grid $f.btn_refresh -row $row -column 1 -sticky e -padx 5 -pady 5
            incr row
            ttk::label $f.ldp -text [::llm_ui::logic::mc "Default Prompt"]
            grid $f.ldp -row $row -column 0 -sticky ne -padx 5 -pady 5
            set def_p_frame [ttk::frame $f.dpf]
            grid $def_p_frame -row $row -column 1 -sticky nsew -padx 5 -pady 5
            set def_p_text [text $def_p_frame.txt -height 3 -wrap word]
            pack $def_p_text -fill both -expand yes
            $def_p_text insert 1.0 $default_prompt
            incr row
            ttk::label $f.lsp -text [::llm_ui::logic::mc "System Prompt"]
            grid $f.lsp -row $row -column 0 -sticky ne -padx 5 -pady 5
            set sys_p_frame [ttk::frame $f.spf]
            grid $sys_p_frame -row $row -column 1 -sticky nsew -padx 5 -pady 5
            set sys_p_text [text $sys_p_frame.txt -height 3 -wrap word]
            pack $sys_p_text -fill both -expand yes
            incr row
            ttk::button $f.btn_save -text [::llm_ui::logic::mc "Save Prompts"] -command [list [self] SavePrompts]
            grid $f.btn_save -row $row -column 1 -sticky e -padx 5 -pady 5
            grid columnconfigure $f 1 -weight 1
            grid rowconfigure $f [expr {$row-1}] -weight 1
            grid rowconfigure $f [expr {$row-3}] -weight 1
            if {[llength $p_names] > 0} { $cb_p current 0; after idle [list [self] OnProviderSelected $cb_p] }
        }

        method UpdateTranslations {} {
            set f $w.config
            $f configure -text [::llm_ui::logic::mc "Settings"]
            $f.llang configure -text [::llm_ui::logic::mc "Language"]
            $f.lp configure -text [::llm_ui::logic::mc "Provider"]
            $f.lk configure -text [::llm_ui::logic::mc "API Key"]
            $f.btn_key configure -text [::llm_ui::logic::mc "Change API Key"]
            $f.lm configure -text [::msgcat::mc "Model"]
            $f.btn_refresh configure -text [::llm_ui::logic::mc "Refresh Models"]
            $f.ldp configure -text [::llm_ui::logic::mc "Default Prompt"]
            $f.lsp configure -text [::llm_ui::logic::mc "System Prompt"]
            $f.btn_save configure -text [::llm_ui::logic::mc "Save Prompts"]
        }

        method OnLanguageSelected {} {
            set lang [$cb_lang get]
            set locale en
            if {$lang eq "简体中文"} { set locale zh_cn } elseif {$lang eq "繁體中文"} { set locale zh_tw }
            ::msgcat::mclocale $locale
            ::llm_ui::logic::mcload_msgs
            set fh [open "preference.json" w]; puts $fh "\x7b\"language\": \"$locale\"\x7d"; close $fh
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
                    if {[llength $m] > 1} {
                        set midx [lsearch -exact $m "id"]
                        if {$midx != -1} { set id [lindex $m [expr {$midx + 1}]] }
                    } else { set id $m }
                    if {$id eq $m_name} { set m [list id $m_name system_prompt $sys_prompt] }
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
            set p_idx [my FindProviderIdx $current_p_name]
            if {$p_idx == -1} return
            set p [lindex $providers_data $p_idx]
            set models {}
            foreach {k v} $p { if {$k eq "models"} { set models $v; break } }
            if {[llength $models] > 0} {
                set ids {}
                foreach m $models {
                    if {[llength $m] > 1} {
                        set midx [lsearch -exact $m "id"]
                        if {$midx != -1} { lappend ids [lindex $m [expr {$midx + 1}]] }
                    } else { lappend ids $m }
                }
                my UpdateModelList $ids; return
            }
            my FetchModels [my cget_chatW_base_url]
        }

        method cget_chatW_base_url {} { return [$chatW cget -base_url] }

        method FetchModels {base_url} {
            set url "$base_url/models"
            set headers [list "Authorization" "Bearer [$chatW cget -api_key]"]
            if {[catch {http::geturl $url -headers $headers -timeout 5000} token]} {
                my UpdateModelList [list "gpt-4o-mini" "gpt-4o"]; return
            }
            set res [encoding convertfrom utf-8 [http::data $token]]; http::cleanup $token
            set ids [::llm_ui::logic::extract_ids $res "id"]
            if {[llength $ids] == 0} { set ids [list "gpt-4o-mini" "gpt-4o"] }
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
            set p_idx [my FindProviderIdx $current_p_name]
            if {$p_idx == -1} return
            set p [lindex $providers_data $p_idx]
            set models {}; foreach {k v} $p { if {$k eq "models"} { set models $v; break } }
            set prompt $default_prompt
            foreach m $models {
                set id ""; set sp ""
                if {[llength $m] > 1} {
                    set midx [lsearch -exact $m "id"]
                    if {$midx != -1} { set id [lindex $m [expr {$midx + 1}]] }
                    set sidx [lsearch -exact $m "system_prompt"]
                    if {$sidx != -1} { set sp [lindex $m [expr {$sidx + 1}]] }
                } else { set id $m }
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
            if {[lsearch -exact [info object methods $obj -all] $cmd] != -1} {
                return [$obj $cmd {*}$args]
            }
            return [::%s:widget $cmd {*}$args]
        } $path $path]
        return $path
    }
}
