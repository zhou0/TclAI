package provide llm_ui 0.1

package require Tk
package require http
package require llm_ui::logic
package require ttk::messagebox

namespace eval ::llm_ui {
    variable use_streaming 1

    ::oo::class create ChatWidgetClass {
        variable w history input send options messages last_raw_json last_assistant_marker sse_buffer accumulated_data stream_token

        constructor {path args} {
            set w $path
            set history ""
            set input ""
            set messages {}
            set last_raw_json ""
            set last_assistant_marker ""
            set options(-stream) 1
            set sse_buffer ""
            set accumulated_data ""
            set stream_token ""
            set options(-provider) ""
            set options(-base_url) ""
            set options(-api_key) ""
            set options(-model) ""
            set options(-system_prompt) "You are a helpful assistant."

            ttk::frame $w
            set history [text $w.history -height 15 -state disabled -wrap word]
            $history tag configure right_aligned -justify right

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
            if {$role eq "Assistant" && $msg eq "..."} {
                set last_assistant_marker [$history index "end - 1c"]
                $history insert end "$role: $msg\n\n"
            } else {
                $history insert end "$role: $msg\n"
                if {$role eq "Assistant"} {
                    my AddMessageButtons $msg
                } else {
                    $history insert end "\n"
                }
            }
            $history configure -state disabled
            $history yview end
        }


        method CallAPI {} {
            if {$options(-api_key) eq "" && ![string match "*localhost*" $options(-base_url)]} {
                set err_msg [::llm_ui::logic::mc "Error: API Key is missing. Please set it in Settings."]
                my AppendHistory "System" $err_msg
                ::ttk::messagebox::show $w [::llm_ui::logic::mc "Settings Error"] $err_msg "error"
                return
            }
            if {$options(-model) eq ""} {
                set err_msg [::llm_ui::logic::mc "Error: No model selected."]
                my AppendHistory "System" $err_msg
                ::ttk::messagebox::show $w [::llm_ui::logic::mc "Model Error"] $err_msg "error"
                return
            }

            set url "$options(-base_url)/chat/completions"
            set sys_msg [list role "system" content $options(-system_prompt)]
            set full_messages [linsert $messages 0 $sys_msg]
            
            set m_list {}
            foreach m $full_messages { lappend m_list [::llm_ui::logic::json_gen_dict $m] }
            set messages_json "\[[join $m_list ,]\]"
            
            set body_dict [list \
                model $options(-model) \
                messages $messages_json \
                stream [expr {$options(-stream) ? "true" : "false"}] \
                max_tokens 1024 \
                temperature 1 \
                top_p 1 \
            ]
            set body [::llm_ui::logic::json_gen_dict $body_dict]

            set headers [list \
                "Accept" "application/json" \
                "Authorization" "Bearer [string trim $options(-api_key)]" \
                "User-Agent" "OpenAI/Python 1.51.2" \
            ]
            
            my AppendHistory "Assistant" "..."

            set sse_buffer ""
            set accumulated_data ""

            if {$options(-stream)} {
                if {[catch {
                    set stream_token [http::geturl $url -headers $headers -query [encoding convertto utf-8 $body] \
                        -type "application/json" -handler [list [self] SSEHandler] -command [list [self] APIComplete]]
                } err]} {
                    my UpdateLastHistory "Error: $err"
                }
            } else {
                if {[catch {
                    set token [http::geturl $url -headers $headers -query [encoding convertto utf-8 $body] -type "application/json" -timeout 60000]
                    set ncode [http::ncode $token]
                    set data [encoding convertfrom utf-8 [http::data $token]]
                    http::cleanup $token
                    set last_raw_json $data
                    if {$ncode != 200} {
                        my UpdateLastHistory "Error: $ncode - $data"
                    } else {
                        set content ""
                        set pattern "\"content\":\\s*\"((?:\[^\"\\\\\]|\\\\.)*)\""
                        if {[regexp $pattern $data match content]} {
                             set content [::llm_ui::logic::unescape_json $content]
                             my UpdateLastHistory $content
                             lappend messages [list role "assistant" content $content]
                             my SaveHistory
                        } else {
                             my UpdateLastHistory [::llm_ui::logic::mc "Error: Could not parse response content."]
                        }
                    }
                } err]} {
                    my UpdateLastHistory "Error: $err"
                }
            }
        }

        method SSEHandler {sock token} {
            set chunk [read $sock]
            append accumulated_data $chunk
            set payloads [::llm_ui::logic::parse_sse $chunk sse_buffer]
            foreach p $payloads {
                set pattern "\"content\":\\s*\"((?:\[^\"\\\\\]|\\\\.)*)\""
                if {[regexp $pattern $p match content]} {
                    set content [::llm_ui::logic::unescape_json $content]
                    my AppendAssistantContent $content
                }
            }
            return [string length $chunk]
        }

        method APIComplete {token} {
            set ncode [http::ncode $token]
            set last_raw_json $accumulated_data
            if {$ncode != 200} {
                my UpdateLastHistory "Error: $ncode - $accumulated_data"
            } else {
                $history configure -state normal
                set assistant_msg ""
                set payloads [::llm_ui::logic::parse_sse "" sse_buffer]
                if {$last_assistant_marker ne ""} {
                    set assistant_msg [string range [$history get $last_assistant_marker "end - 1c"] 11 end]
                    set assistant_msg [string trim $assistant_msg]
                    lappend messages [list role "assistant" content $assistant_msg]
                    my SaveHistory
                }
                my UpdateLastHistory $assistant_msg
            }
            http::cleanup $token
        }

        method AppendAssistantContent {content} {
            $history configure -state normal
            if {$last_assistant_marker ne ""} {
                $history insert "end - 1c" $content
            }
            $history configure -state disabled
            $history yview end
        }

        method CopyText {txt} {
            clipboard clear
            clipboard append $txt
        }

        method CopyAsImage {txt} {
            set filename [tk_getSaveFile -defaultextension ".png" -filetypes {{"PNG Files" ".png"} {"All Files" "*.*"}}]
            if {$filename eq ""} return

            set temp_top .temp_render
            if {[winfo exists $temp_top]} { destroy $temp_top }
            toplevel $temp_top
            wm withdraw $temp_top

            set c [canvas $temp_top.c -bg white]
            set tid [$c create text 10 10 -text $txt -anchor nw -width 600 -font {Helvetica 12}]
            set bbox [$c bbox $tid]
            set w [expr {[lindex $bbox 2] + 20}]
            set h [expr {[lindex $bbox 3] + 20}]
            $c configure -width $w -height $h

            update idletasks

            set img [image create photo -format window -data $c]
            if {[catch {$img write $filename -format png} err]} {
                ::ttk::messagebox::show $w "Error" "Failed to save image: $err" "error"
            }

            image delete $img
            destroy $temp_top
        }

        method ShowJSON {json} {
            set top .json_popup
            if {[winfo exists $top]} { destroy $top }
            toplevel $top
            wm title $top "Raw JSON Response"
            wm geometry $top 600x400
            set txt [text $top.t -wrap none -font {Courier 10}]
            set sbx [ttk::scrollbar $top.sbx -orient horizontal -command [list $txt xview]]
            set sby [ttk::scrollbar $top.sby -orient vertical -command [list $txt yview]]
            $txt configure -xscrollcommand [list $sbx set] -yscrollcommand [list $sby set]

            grid $txt -row 0 -column 0 -sticky nsew
            grid $sby -row 0 -column 1 -sticky ns
            grid $sbx -row 1 -column 0 -sticky ew
            grid rowconfigure $top 0 -weight 1
            grid columnconfigure $top 0 -weight 1
            
            $txt insert 1.0 [::llm_ui::logic::json_pretty $json]
            $txt configure -state disabled
        }

        method AddMessageButtons {msg {json ""}} {
            set f_path "$history.f_[clock clicks]_[expr {int(rand()*1000)}]"
            ttk::frame $f_path

            ttk::button $f_path.copy -text [::llm_ui::logic::mc "Copy Answer"] -command [list [self] CopyText $msg] -padding 2
            ttk::button $f_path.copyimg -text [::llm_ui::logic::mc "Copy Answer as Image"] -command [list [self] CopyAsImage $msg] -padding 2
            pack $f_path.copy $f_path.copyimg -side left -padx 2

            if {$json ne ""} {
                ttk::button $f_path.showjson -text [::llm_ui::logic::mc "Show full response data"] -command [list [self] ShowJSON $json] -padding 2
                pack $f_path.showjson -side right -padx 2
            }

            set btn_idx [$history index "end - 1c"]
            $history window create end -window $f_path -padx 5
            $history tag add right_aligned "$btn_idx linestart" "$btn_idx lineend"
            $history insert end "\n\n"
        }

        method UpdateLastHistory {msg} {
            $history configure -state normal
            if {$last_assistant_marker ne ""} {
                $history delete $last_assistant_marker end
            }
            $history insert end "Assistant: $msg\n"

            my AddMessageButtons $msg $last_raw_json

            $history configure -state disabled
            $history yview end
            set last_assistant_marker ""
        }


        method LoadHistory {} {
            set data_dir "data"
            if {![file isdirectory $data_dir]} { file mkdir $data_dir }
            set hist_file [file join $data_dir "history.json"]
            if {[file exists $hist_file]} {
                set fh [open $hist_file r]
                fconfigure $fh -encoding utf-8
                set json [read $fh]; close $fh
                if {![catch {set data [::llm_ui::logic::json_parse $json]}]} {
                    set messages $data
                    foreach m $messages {
                        set role "Unknown"; set content ""
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
            set data_dir "data"
            if {![file isdirectory $data_dir]} { file mkdir $data_dir }
            set hist_file [file join $data_dir "history.json"]
            set fh [open $hist_file w]
            fconfigure $fh -encoding utf-8
            set m_list {}
            foreach m $messages { lappend m_list [::llm_ui::logic::json_gen_dict $m] }
            puts $fh "\[[join $m_list ,]\]"
            close $fh
        }

        method configure {args} {
            if {[llength $args] == 0} { return [array get options] }
            if {[llength $args] == 1} { return $options([lindex $args 0]) }
            foreach {key val} $args { set options($key) $val }
        }

        method cget {key} { return $options($key) }

        export configure cget SendMessage UpdateTranslations ShowJSON CopyText CopyAsImage AddMessageButtons
    }

    ::oo::class create SettingsWidgetClass {
        variable w chatW providers_data current_p_name cb_p cb_m def_p_text sys_p_text cb_lang default_prompt lastchat system_prompt cb_stream

        constructor {path chatWidget args} {
            set w $path
            set chatW $chatWidget
            set providers_data {}
            set current_p_name ""
            set default_prompt "You are a helpful assistant."
            set system_prompt ""
            set ::llm_ui::use_streaming 1
            set lastchat {provider "" model "" api_key ""}

            ttk::frame $w
            my LoadPreferences
            my BuildUI
        }

        method LoadPreferences {} {
            set settings_dir "settings"
            set data_dir "data"
            set pref_file [file join $settings_dir "preference.json"]
            set prov_file [file join $data_dir "providers.json"]

            if {[file exists $prov_file]} {
                set fh [open $prov_file r]
                fconfigure $fh -encoding utf-8
                set json [read $fh]; close $fh
                catch { set providers_data [::llm_ui::logic::json_parse $json] }
            }

            if {[file exists $pref_file]} {
                set fh [open $pref_file r]
                fconfigure $fh -encoding utf-8
                set json [read $fh]; close $fh
                if {![catch {set d [::llm_ui::logic::json_parse $json]}]} {
                    if {[dict exists $d default_prompt]} { set default_prompt [dict get $d default_prompt] }
                    if {[dict exists $d system_prompt]} { set system_prompt [dict get $d system_prompt] }
                    if {[dict exists $d use_streaming]} { set ::llm_ui::use_streaming [dict get $d use_streaming] }
                    if {[dict exists $d lastchat]} { set lastchat [dict get $d lastchat] }

                    if {[dict exists $d providers_keys]} {
                        set keys [dict get $d providers_keys]
                        set new_p {}
                        foreach p $providers_data {
                            set name [dict get $p name]
                            if {[dict exists $keys $name]} {
                                dict set p api_key [dict get $keys $name]
                            }
                            lappend new_p $p
                        }
                        set providers_data $new_p
                    }
                }
            }
        }

        method SavePreferences {args} {
            set settings_dir "settings"
            set data_dir "data"
            if {![file isdirectory $settings_dir]} { file mkdir $settings_dir }
            if {![file isdirectory $data_dir]} { file mkdir $data_dir }

            set pref_file [file join $settings_dir "preference.json"]
            set prov_file [file join $data_dir "providers.json"]
            
            set d {}
            if {[file exists $pref_file]} {
                set fh [open $pref_file r]
                fconfigure $fh -encoding utf-8
                set json [read $fh]; close $fh
                catch {set d [::llm_ui::logic::json_parse $json]}
            }
            foreach {k v} $args { dict set d $k $v }
            
            set p_list_clean {}
            set p_keys {}
            foreach p $providers_data {
                set name [dict get $p name]
                set key [dict get $p api_key]
                dict set p_keys $name $key
                set p_clean $p
                if {[dict exists $p_clean api_key]} { dict unset p_clean api_key }
                lappend p_list_clean [::llm_ui::logic::json_gen_dict $p_clean]
            }
            set prov_json_str "\[[join $p_list_clean ,]\]"
            set fh [open $prov_file w]
            fconfigure $fh -encoding utf-8
            puts $fh $prov_json_str; close $fh

            dict set d providers_keys [::llm_ui::logic::json_gen_dict $p_keys]

            set lc_provider $current_p_name
            if {$lc_provider eq "" && [dict exists $d lastchat provider]} { set lc_provider [dict get $d lastchat provider] }
            set lc_model ""
            if {[info exists cb_m] && [winfo exists $cb_m]} { set lc_model [$cb_m get] }
            if {$lc_model eq "" && [dict exists $d lastchat model]} { set lc_model [dict get $d lastchat model] }

            set lc_key ""
            set p_idx [my FindProviderIdx $lc_provider]
            if {$p_idx != -1} { set lc_key [dict get [lindex $providers_data $p_idx] api_key] }

            dict set d lastchat [::llm_ui::logic::json_gen_dict [list provider $lc_provider model $lc_model api_key $lc_key]]

            set fh [open $pref_file w]
            fconfigure $fh -encoding utf-8
            puts $fh [::llm_ui::logic::json_gen_dict $d]; close $fh
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
            ttk::label $f.lstream -text [::llm_ui::logic::mc "Use Streaming"]
            grid $f.lstream -row $row -column 0 -sticky e -padx 5 -pady 5
            set cb_stream [ttk::checkbutton $f.cbstream -variable ::llm_ui::use_streaming]
            grid $f.cbstream -row $row -column 1 -sticky w -padx 5 -pady 5
            incr row

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

            ttk::button $f.btn_add_p -text [::llm_ui::logic::mc "Add provider"] -command [list [self] AddProvider]
            grid $f.btn_add_p -row $row -column 2 -padx 5 -pady 5
            incr row

            ttk::label $f.lk -text [::llm_ui::logic::mc "API Key"]
            set e_k [ttk::entry $f.ek -show "*"]
            grid $f.lk -row $row -column 0 -sticky e -padx 5 -pady 5
            grid $e_k -row $row -column 1 -sticky ew -padx 5 -pady 5

            ttk::button $f.btn_key -text [::llm_ui::logic::mc "Change API Key"] -command [list [self] ChangeKey]
            grid $f.btn_key -row $row -column 2 -padx 5 -pady 5
            incr row

            ttk::label $f.lm -text [::llm_ui::logic::mc "Model"]
            grid $f.lm -row $row -column 0 -sticky e -padx 5 -pady 5
            set cb_m [ttk::combobox $f.cbm -state readonly]
            grid $cb_m -row $row -column 1 -sticky ew -padx 5 -pady 5
            bind $cb_m <<ComboboxSelected>> [list [self] OnModelSelected %W]

            ttk::button $f.btn_refresh -text [::llm_ui::logic::mc "Refresh Models"] -command [list [self] RefreshModels]
            grid $f.btn_refresh -row $row -column 2 -padx 5 -pady 5
            incr row

            ttk::label $f.ldp -text [::llm_ui::logic::mc "Default Prompt"]
            grid $f.ldp -row $row -column 0 -sticky ne -padx 5 -pady 5
            set def_p_frame [ttk::frame $f.dpf]
            grid $def_p_frame -row $row -column 1 -columnspan 2 -sticky nsew -padx 5 -pady 5
            set def_p_text [text $def_p_frame.txt -height 3 -wrap word]
            pack $def_p_text -fill both -expand yes
            $def_p_text insert 1.0 $default_prompt
            incr row

            ttk::label $f.lsp -text [::llm_ui::logic::mc "System Prompt"]
            grid $f.lsp -row $row -column 0 -sticky ne -padx 5 -pady 5
            set sys_p_frame [ttk::frame $f.spf]
            grid $sys_p_frame -row $row -column 1 -columnspan 2 -sticky nsew -padx 5 -pady 5
            set sys_p_text [text $sys_p_frame.txt -height 3 -wrap word]
            pack $sys_p_text -fill both -expand yes
            $sys_p_text insert 1.0 $system_prompt
            incr row

            ttk::button $f.btn_save -text [::llm_ui::logic::mc "Save all settings"] -command [list [self] SaveAllSettings]
            grid $f.btn_save -row $row -column 1 -columnspan 2 -sticky e -padx 5 -pady 5

            grid columnconfigure $f 1 -weight 1
            grid rowconfigure $f [expr {$row-1}] -weight 1
            grid rowconfigure $f [expr {$row-2}] -weight 1

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
            $f.lstream configure -text [::llm_ui::logic::mc "Use Streaming"]
            $f.llang configure -text [::llm_ui::logic::mc "Language"]
            $f.lp configure -text [::llm_ui::logic::mc "Provider"]
            $f.btn_add_p configure -text [::llm_ui::logic::mc "Add provider"]
            $f.lk configure -text [::llm_ui::logic::mc "API Key"]
            $f.btn_key configure -text [::llm_ui::logic::mc "Change API Key"]
            $f.lm configure -text [::llm_ui::logic::mc "Model"]
            $f.btn_refresh configure -text [::llm_ui::logic::mc "Refresh Models"]
            $f.ldp configure -text [::llm_ui::logic::mc "Default Prompt"]
            $f.lsp configure -text [::llm_ui::logic::mc "System Prompt"]
            $f.btn_save configure -text [::llm_ui::logic::mc "Save all settings"]
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

            if {$key ne ""} {
                $w.config.ek configure -state readonly
            } else {
                $w.config.ek configure -state normal
            }

            set sp $system_prompt
            if {$sp eq ""} { set sp $default_prompt }

            $chatW configure -provider $current_p_name -base_url $url -api_key $key -system_prompt $sp -stream $::llm_ui::use_streaming
            my RefreshModels
        }

        method ChangeKey {} {
            $w.config.ek configure -state normal
            focus $w.config.ek
        }

        method AddProvider {} {
            set top .add_provider_popup
            if {[winfo exists $top]} { destroy $top }
            toplevel $top
            wm title $top [::llm_ui::logic::mc "Add Provider"]
            wm transient $top .

            set f [ttk::frame $top.f]
            pack $f -padx 10 -pady 10 -fill both -expand yes

            ttk::label $f.ln -text [::llm_ui::logic::mc "Provider Name"]
            set en [ttk::entry $f.en]
            grid $f.ln -row 0 -column 0 -sticky e -padx 5 -pady 5
            grid $en -row 0 -column 1 -sticky ew -padx 5 -pady 5

            ttk::label $f.lu -text [::llm_ui::logic::mc "Base URL"]
            set eu [ttk::entry $f.eu]
            grid $f.lu -row 1 -column 0 -sticky e -padx 5 -pady 5
            grid $eu -row 1 -column 1 -sticky ew -padx 5 -pady 5

            ttk::label $f.lk -text [::llm_ui::logic::mc "API Key"]
            set ek [ttk::entry $f.ek -show "*"]
            grid $f.lk -row 2 -column 0 -sticky e -padx 5 -pady 5
            grid $ek -row 2 -column 1 -sticky ew -padx 5 -pady 5

            set bf [ttk::frame $f.bf]
            grid $bf -row 3 -column 0 -columnspan 2 -sticky e -padx 5 -pady 5

            ttk::button $bf.cancel -text [::llm_ui::logic::mc "Cancel"] -command [list destroy $top]
            ttk::button $bf.ok -text [::llm_ui::logic::mc "OK"] -command [list [self] TestAndAddProvider $top $en $eu $ek]
            pack $bf.cancel $bf.ok -side left -padx 5

            grid columnconfigure $f 1 -weight 1
        }

        method TestAndAddProvider {top en eu ek} {
            set name [string trim [$en get]]
            set url [string trim [$eu get]]
            set key [string trim [$ek get]]

            if {$name eq "" || $url eq ""} {
                ::ttk::messagebox::show $top [::llm_ui::logic::mc "Add Provider Error"] [::llm_ui::logic::mc "Invalid input."] "error"
                return
            }

            $top.f.bf.ok configure -state disabled
            $top.f.bf.cancel configure -state disabled

            set test_url "$url/models"
            set headers [list \
                "Authorization" "Bearer [string trim $key]" \
                "Accept" "application/json" \
                "User-Agent" "OpenAI/Python 1.51.2" \
            ]

            if {[catch {
                set token [http::geturl $test_url -headers $headers -type "application/json" -timeout 10000]
                set ncode [http::ncode $token]
                set res [encoding convertfrom utf-8 [http::data $token]]
                http::cleanup $token

                if {$ncode != 200} {
                    error "HTTP $ncode: $res"
                }

                set ids [::llm_ui::logic::extract_ids $res "id"]

                set new_p [list name $name base_url $url api_key $key models $ids]
                lappend providers_data $new_p
                my SavePreferences

                set p_names {}
                foreach p $providers_data { foreach {k v} $p { if {$k eq "name"} { lappend p_names $v; break } } }
                $cb_p configure -values $p_names
                $cb_p set $name
                my OnProviderSelected $cb_p

                destroy $top
            } err]} {
                $top.f.bf.ok configure -state normal
                $top.f.bf.cancel configure -state normal
                ::ttk::messagebox::show $top [::llm_ui::logic::mc "Add Provider Error"] "[::llm_ui::logic::mc "Test connection failed."]\n$err" "error"
            }
        }

        method SaveAllSettings {} {
            set idx [$cb_p current]
            if {$idx != -1} {
                set key [$w.config.ek get]
                set p [lindex $providers_data $idx]
                set new_p {}
                foreach {k v} $p { if {$k eq "api_key"} { lappend new_p $k $key } else { lappend new_p $k $v } }
                set providers_data [lreplace $providers_data $idx $idx $new_p]
                $chatW configure -api_key $key
            }

            set default_prompt [string trim [$def_p_text get 1.0 end]]
            set system_prompt [string trim [$sys_p_text get 1.0 end]]
            
            set sp $system_prompt
            if {$sp eq ""} { set sp $default_prompt }
            $chatW configure -stream $::llm_ui::use_streaming
            $chatW configure -system_prompt $sp

            my SavePreferences default_prompt $default_prompt system_prompt $system_prompt use_streaming $::llm_ui::use_streaming
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
            set headers [list \
                "Authorization" "Bearer [string trim [$chatW cget -api_key]]" \
                "Accept" "application/json" \
                "User-Agent" "OpenAI/Python 1.51.2" \
            ]
            if {[catch {http::geturl $url -headers $headers -type "application/json" -timeout 10000} token]} {
                set err_msg "Failed to fetch models: $token"
                my UpdateModelList {}
                ::ttk::messagebox::show $w [::llm_ui::logic::mc "Fetch Error"] $err_msg "error"
                return
            }
            set res [encoding convertfrom utf-8 [http::data $token]]; http::cleanup $token
            set ids [::llm_ui::logic::extract_ids $res "id"]
            set p_idx [my FindProviderIdx $current_p_name]
            if {$p_idx != -1} {
                set p [lindex $providers_data $p_idx]
                set m_list {}
                foreach id $ids { lappend m_list $id }
                set new_p {}
                foreach {k v} $p { if {$k eq "models"} { lappend new_p $k $m_list } else { lappend new_p $k $v } }
                set providers_data [lreplace $providers_data $p_idx $p_idx $new_p]
                my SavePreferences
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
            } else {
                $cb_m set ""
                $chatW configure -model ""
                my SavePreferences
            }
        }

        method OnModelSelected {w_cb} {
            set model [$w_cb get]
            $chatW configure -model $model
            my SavePreferences
        }
        export OnProviderSelected ChangeKey RefreshModels OnModelSelected OnLanguageSelected SaveAllSettings UpdateTranslations SavePreferences AddProvider TestAndAddProvider
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
