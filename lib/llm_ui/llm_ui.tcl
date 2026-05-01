package provide llm_ui 0.1

package require Tk
package require llm_ui::logic

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
            $history yview end
        }

        method CallAPI {} {
            if {$options(-api_key) eq "" && ![string match "*localhost*" $options(-base_url)]} {
                my AppendHistory "System" "Error: API Key is missing. Please set it in Settings."
                return
            }

            set url "$options(-base_url)/chat/completions"
            set sys_msg [list role "system" content $options(-system_prompt)]
            set full_messages [linsert $messages 0 $sys_msg]

            set body_dict [list model $options(-model) messages $full_messages]
            set body [::llm_ui::logic::json_gen_history $full_messages]
            set body "\x7b\"model\": \"$options(-model)\", \"messages\": $body\x7d"

            set headers [list "Content-Type" "application/json" "Authorization" "Bearer $options(-api_key)"]

            my AppendHistory "Assistant" "..."
            set last_idx [$history index "end - 2c"]

            # Async HTTP request would be better, but for simplicity:
            if {[catch {
                set token [http::geturl $url -headers $headers -query [encoding convertto utf-8 $body] -timeout 30000]
                set status [http::status $token]
                set ncode [http::ncode $token]
                set data [encoding convertfrom utf-8 [http::data $token]]
                http::cleanup $token

                if {$ncode != 200} {
                    my UpdateLastHistory "Error: $ncode - $data"
                } else {
                    set content ""
                    # Minimal extraction logic for the response
                    set pattern "\"content\":\\s*\"((?:\[^\"\\\\]|\\\\.)*)\""
                    if {[regexp $pattern $data match content]} {
                         set content [::llm_ui::logic::unescape_json $content]
                         my UpdateLastHistory $content
                         lappend messages [list role "assistant" content $content]
                         my SaveHistory
                    } else {
                        my UpdateLastHistory "Error: Could not parse response content."
                    }
                }
            } err]} {
                my UpdateLastHistory "Error: $err"
            }
        }

        method UpdateLastHistory {msg} {
            $history configure -state normal
            set start [$history index "end - 2l"]
            set end [$history index "end - 1c"]
            $history delete $start $end
            $history insert end "Assistant: $msg\n\n"
            $history configure -state disabled
            $history yview end
        }

        method LoadHistory {} {
            if {[file exists "history.json"]} {
                set fh [open "history.json" r]
                set json [read $fh]
                close $fh
                if {![catch {set data [::llm_ui::logic::json_parse $json]}]} {
                    set messages $data
                    foreach m $messages {
                        set role "Unknown"
                        set content ""
                        foreach {k v} $m {
                            if {$k eq "role"} { set role [string totitle $v] }
                            if {$k eq "content"} { set content $v }
                        }
                        my AppendHistory $role $content
                    }
                }
            }
        }

        method SaveHistory {} {
            set fh [open "history.json" w]
            puts $fh [::llm_ui::logic::json_gen_history $messages]
            close $fh
        }

        method configure {args} {
            if {[llength $args] == 0} {
                return [array get options]
            }
            if {[llength $args] == 1} {
                return $options([lindex $args 0])
            }
            foreach {key val} $args {
                set options($key) $val
            }
        }

        method cget {key} {
            return $options($key)
        }

        export configure cget SendMessage UpdateTranslations
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
        variable w chatW providers_data current_p_name cb_p cb_m def_p_text sys_p_text cb_lang default_prompt lastchat system_prompt

        constructor {path chatWidget args} {
            set w $path
            set chatW $chatWidget
            set providers_data {}
            set current_p_name ""
            set default_prompt "You are a helpful assistant."
            set system_prompt ""
            set lastchat {provider "" model ""}

            ttk::frame $w
            my LoadPreferences
            my LoadProviders
            my LoadLastChat
            my BuildUI
        }

        method LoadPreferences {} {
            if {[file exists "preference.json"]} {
                set fh [open "preference.json" r]
                set json [read $fh]
                close $fh
                if {![catch {set d [::llm_ui::logic::json_parse $json]}]} {
                    if {[dict exists $d default_prompt]} { set default_prompt [dict get $d default_prompt] }
                    if {[dict exists $d system_prompt]} { set system_prompt [dict get $d system_prompt] }
                }
            }
        }

        method SavePreferences {args} {
            set d {}
            if {[file exists "preference.json"]} {
                set fh [open "preference.json" r]; set json [read $fh]; close $fh
                catch {set d [::llm_ui::logic::json_parse $json]}
            }
            foreach {k v} $args { dict set d $k $v }
            set fh [open "preference.json" w]; puts $fh [::llm_ui::logic::json_gen_dict $d]; close $fh
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
                    # Migrate old prompt if present
                    if {$k eq "default_prompt" && $default_prompt eq "You are a helpful assistant."} {
                        set default_prompt $v
                        my SavePreferences default_prompt $v
                    }
                }
            }

            if {[llength $providers_data] == 0} {
                set providers_data [list \
                    [list name "DeepSeek" base_url "https://api.deepseek.com/v1" api_key "" models {}] \
                    [list name "SiliconFlow" base_url "https://api.siliconflow.cn/v1" api_key "" models {}] \
                    [list name "Nvidia" base_url "https://integrate.api.nvidia.com/v1" api_key "" models {}] \
                    [list name "Cerebras" base_url "https://api.cerebras.ai/v1" api_key "" models {}] \
                    [list name "OpenRouter" base_url "https://openrouter.ai/api/v1" api_key "" models {}] \
                    [list name "Local (Ollama/LM Studio)" base_url "http://localhost:11434/v1" api_key "" models {}] \
                ]
                my SaveProviders
            }
        }

        method SaveProviders {} {
            set fh [open "providers.json" w]
            puts $fh [::llm_ui::logic::json_gen_providers $providers_data]
            close $fh
        }

        method LoadLastChat {} {
            if {[file exists "lastchat.json"]} {
                set fh [open "lastchat.json" r]
                set json [read $fh]
                close $fh
                if {![catch {set data [::llm_ui::logic::json_parse $json]}]} {
                    set lastchat $data
                }
            }
        }

        method SaveLastChat {} {
            set provider $current_p_name
            set model [$cb_m get]
            set data [list provider $provider model $model]
            set fh [open "lastchat.json" w]
            puts $fh [::llm_ui::logic::json_gen_dict $data]
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
            incr row
            ttk::button $f.btn_key -text [::llm_ui::logic::mc "Change API Key"] -command [list [self] ChangeKey]
            grid $f.btn_key -row $row -column 1 -sticky e -padx 5 -pady 5
            incr row
            ttk::label $f.lm -text [::llm_ui::logic::mc "Model"]
            grid $f.lm -row $row -column 0 -sticky e -padx 5 -pady 5
            set cb_m [ttk::combobox $f.cbm -state readonly]
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
            $sys_p_text insert 1.0 $system_prompt
            incr row
            ttk::button $f.btn_save -text [::llm_ui::logic::mc "Save Prompts"] -command [list [self] SavePrompts]
            grid $f.btn_save -row $row -column 1 -sticky e -padx 5 -pady 5
            grid columnconfigure $f 1 -weight 1
            grid rowconfigure $f [expr {$row-1}] -weight 1
            grid rowconfigure $f [expr {$row-3}] -weight 1

            set last_p [dict get $lastchat provider]
            set pidx [lsearch -exact $p_names $last_p]
            if {$pidx == -1} { set pidx 0 }
            if {[llength $p_names] > 0} {
                $cb_p current $pidx
                after idle [list [self] OnProviderSelected $cb_p]
            }
        }

        method UpdateTranslations {} {
            set f $w.config
            $f configure -text [::llm_ui::logic::mc "Settings"]
            $f.llang configure -text [::llm_ui::logic::mc "Language"]
            $f.lp configure -text [::llm_ui::logic::mc "Provider"]
            $f.lk configure -text [::llm_ui::logic::mc "API Key"]
            $f.btn_key configure -text [::llm_ui::logic::mc "Change API Key"]
            $f.lm configure -text [::llm_ui::logic::mc "Model"]
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
            my SavePreferences language $locale
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

            set sp $system_prompt
            if {$sp eq ""} { set sp $default_prompt }

            $chatW configure -provider $current_p_name -base_url $url -api_key $key -system_prompt $sp
            my RefreshModels
            my SaveLastChat
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
            set system_prompt [string trim [$sys_p_text get 1.0 end]]
            my SavePreferences default_prompt $default_prompt system_prompt $system_prompt

            set sp $system_prompt
            if {$sp eq ""} { set sp $default_prompt }
            $chatW configure -system_prompt $sp
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
                foreach id $ids { lappend m_list $id }
                set new_p {}
                foreach {k v} $p { if {$k eq "models"} { lappend new_p $k $m_list } else { lappend new_p $k $v } }
                set providers_data [lreplace $providers_data $p_idx $p_idx $new_p]
                my SaveProviders
            }
            my UpdateModelList $ids
        }

        method UpdateModelList {models} {
            $cb_m configure -values $models
            if {[llength $models] > 0} {
                set current [dict get $lastchat model]
                set midx [lsearch -exact $models $current]
                if {$midx == -1} {
                    set current [$chatW cget -model]
                    set midx [lsearch -exact $models $current]
                }
                $cb_m current [expr {$midx != -1 ? $midx : 0}]
                my OnModelSelected $cb_m
            }
        }

        method OnModelSelected {w_cb} {
            set model [$w_cb get]
            $chatW configure -model $model
            my SaveLastChat
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
