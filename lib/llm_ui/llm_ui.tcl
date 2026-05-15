package provide llm_ui 0.1

package require Tk
package require http
package require llm_ui::logic
package require ttk::messagebox

namespace eval ::llm_ui {
    variable providers_data {}
    variable use_streaming 1
    variable last_raw_json ""

    ::oo::class create ChatWidgetClass {
        variable w options messages history input last_assistant_marker sse_buffer accumulated_data last_raw_json

        constructor {path args} {
            set w $path
            set messages {}
            set last_assistant_marker ""
            set sse_buffer ""
            set accumulated_data ""
            set last_raw_json ""

            array set options {
                -base_url "https://api.deepseek.com"
                -model "deepseek-chat"
                -api_key ""
                -system_prompt "You are a helpful assistant."
                -stream 1
            }
            array set options $args

            ttk::frame $w

            set txt_frame [ttk::frame $w.f]
            pack $txt_frame -fill both -expand yes -padx 10 -pady 10

            set history [text $txt_frame.h -wrap word -state disabled -font {TkDefaultFont 11} -padx 10 -pady 10]
            set vsb [ttk::scrollbar $txt_frame.vsb -orient vertical -command [list $history yview]]
            $history configure -yscrollcommand [list $vsb set]

            pack $vsb -side right -fill y
            pack $history -side left -fill both -expand yes

            set input_frame [ttk::frame $w.i]
            pack $input_frame -fill x -padx 10 -pady 10

            set input [text $input_frame.t -height 3 -font {TkDefaultFont 11}]
            set send_btn [ttk::button $w.send -text [::llm_ui::logic::mc "Send"] -command [list [self] SendMessage]]

            pack $input -side left -fill x -expand yes
            pack $send_btn -side right -padx 5

            $history tag configure right_aligned -justify right
            my LoadHistory
        }

        method configure {args} {
            foreach {k v} $args {
                set options($k) $v
            }
        }

        method cget {k} { return $options($k) }

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
            set display_role [::llm_ui::logic::mc $role]
            if {$role eq "Assistant" && $msg eq "..."} {
                set last_assistant_marker [$history index "end - 1c"]
                $history insert end "$display_role: $msg\n\n"
            } else {
                $history insert end "$display_role: $msg\n"
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
            if {[string match -nocase "https://*" $url] && ![::llm_ui::logic::is_https_available]} {
                error [::llm_ui::logic::mc "HTTPS requires the 'tls' package, which is not installed."]
            }
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
                "Content-Type" "application/json" \
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
                    lassign [::llm_ui::logic::http_post $url $headers [encoding convertto utf-8 $body]] ncode data
                    set data [encoding convertfrom utf-8 $data]
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
                    set prefix "[::llm_ui::logic::mc "Assistant"]: "
                    set assistant_msg [string range [$history get $last_assistant_marker "end - 1c"] [string length $prefix] end]
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

        method UpdateLastHistory {msg} {
            $history configure -state normal
            if {$last_assistant_marker ne ""} {
                set end_idx [$history index "end - 1c"]
                $history delete $last_assistant_marker $end_idx
                set display_role [::llm_ui::logic::mc "Assistant"]
                $history insert $last_assistant_marker "$display_role: $msg\n"
                my AddMessageButtons $msg
            }
            $history configure -state disabled
            $history yview end
        }

        method AddMessageButtons {msg} {
            set btn_frame [ttk::frame $history.f[clock clicks]]
            set copy_btn [ttk::button $btn_frame.copy -text [::llm_ui::logic::mc "Copy Answer"] -style Toolbutton -command [list [self] CopyText $msg]]
            set img_btn [ttk::button $btn_frame.img -text [::llm_ui::logic::mc "Copy Answer as Image"] -style Toolbutton -command [list [self] CopyAsImage $msg]]
            set raw_btn [ttk::button $btn_frame.raw -text [::llm_ui::logic::mc "Show full response data"] -style Toolbutton -command [list [self] ShowJSON]]
            pack $copy_btn $img_btn $raw_btn -side left -padx 2

            $history configure -state normal
            $history window create end -window $btn_frame -align baseline
            $history tag add right_aligned [$history index "end - 1c"] end
            $history insert end "\n\n"
            $history configure -state disabled
        }

        method ShowJSON {} {
            set win .json_viewer[clock clicks]
            toplevel $win
            wm title $win [::llm_ui::logic::mc "Raw JSON Response"]
            wm geometry $win 600x400

            set txt [text $win.t -wrap none -font {TkFixedFont 10}]
            set vsb [ttk::scrollbar $win.vsb -orient vertical -command [list $win.t yview]]
            set hsb [ttk::scrollbar $win.hsb -orient horizontal -command [list $win.t xview]]
            $win.t configure -yscrollcommand [list $vsb set] -xscrollcommand [list $hsb set]

            grid $win.t -row 0 -column 0 -sticky nsew
            grid $vsb -row 0 -column 1 -sticky ns
            grid $hsb -row 1 -column 0 -sticky ew
            grid rowconfigure $win 0 -weight 1
            grid columnconfigure $win 0 -weight 1

            $win.t insert end "[::llm_ui::logic::mc "Raw JSON Data"]:\n\n"
            $win.t insert end [::llm_ui::logic::json_pretty $last_raw_json]
            $win.t configure -state disabled
        }

        method CopyText {txt} {
            clipboard clear
            clipboard append $txt
        }

        method CopyAsImage {txt} {
            set filetypes [list \
                [list [::llm_ui::logic::mc "PNG Files"] ".png"] \
                [list [::llm_ui::logic::mc "PostScript Files"] ".ps"] \
                [list [::llm_ui::logic::mc "All Files"] "*"] \
            ]
            set filename [tk_getSaveFile -defaultextension ".png" -filetypes $filetypes]
            if {$filename eq ""} return

            set render_win .render[clock clicks]
            toplevel $render_win
            wm title $render_win [::llm_ui::logic::mc "Rendering Answer..."]

            set c [canvas $render_win.c -bg white -highlightthickness 0]
            pack $c -fill both -expand yes

            set t_id [$c create text 10 10 -text $txt -width 600 -anchor nw -font {TkDefaultFont 11} -fill black]
            set bbox [$c bbox $t_id]
            set w [expr {[lindex $bbox 2] + 20}]
            set h [expr {[lindex $bbox 3] + 20}]
            $c configure -width $w -height $h

            update

            if {[string match "*.ps" $filename]} {
                $c postscript -file $filename
            } else {
                if {[catch {package require Img} err]} {
                    ::ttk::messagebox::show $render_win [::llm_ui::logic::mc "Export Error"] [::llm_ui::logic::mc "Exporting PNG requires the 'Img' package. Please save as PostScript (.ps) instead."] "error"
                } else {
                    wm deiconify $render_win
                    raise $render_win
                    update
                    set img [image create photo -format window -data $render_win]
                    $img write $filename -format png
                    image delete $img
                }
            }
            destroy $render_win
        }

        method LoadHistory {} {
            variable script_dir
            set history_file [file join [file dirname [info script]] data history.json]
            if {[file exists $history_file]} {
                set fh [open $history_file r]
                set json [read $fh]
                close $fh
                if {![catch {set messages [::llm_ui::logic::json_parse $json]}]} {
                    foreach m $messages {
                        my AppendHistory [dict get $m role] [dict get $m content]
                    }
                }
            }
        }

        method SaveHistory {} {
            set history_dir [file join [file dirname [info script]] data]
            file mkdir $history_dir
            set history_file [file join $history_dir history.json]
            set fh [open $history_file w]
            puts -nonewline $fh [::llm_ui::logic::json_gen_val $messages]
            close $fh
        }

        export SSEHandler APIComplete CallAPI AppendHistory UpdateLastHistory AppendAssistantContent AddMessageButtons
        export configure cget SendMessage UpdateTranslations ShowJSON CopyText CopyAsImage AddMessageButtons
    }

    ::oo::class create SettingsWidgetClass {
        variable w chatW providers_data current_p_name cb_p cb_m ent_key txt_prompt ent_base_url

        constructor {path chat_widget args} {
            set w $path
            set chatW $chat_widget
            set providers_data {}
            set current_p_name ""

            ttk::frame $w
            
            set f [ttk::labelframe $w.p -text [::llm_ui::logic::mc "Provider"] -padding 10]
            pack $f -fill x -padx 10 -pady 5
            
            set row 0
            grid [ttk::label $f.lp -text "[::llm_ui::logic::mc "Provider"]:"] -row $row -column 0 -sticky w
            set cb_p [ttk::combobox $f.cp -state readonly]
            grid $cb_p -row $row -column 1 -sticky ew -padx 5
            grid [ttk::button $f.ap -text "+" -width 3 -command [list [self] AddProvider]] -row $row -column 2

            incr row
            grid [ttk::label $f.lm -text "[::llm_ui::logic::mc "Model"]:"] -row $row -column 0 -sticky w
            set cb_m [ttk::combobox $f.cm -state readonly]
            grid $cb_m -row $row -column 1 -sticky ew -padx 5
            grid [ttk::button $f.rm -text [::llm_ui::logic::mc "Refresh Models"] -command [list [self] RefreshModels]] -row $row -column 2

            incr row
            grid [ttk::label $f.lk -text "[::llm_ui::logic::mc "API Key"]:"] -row $row -column 0 -sticky w
            set ent_key [ttk::entry $f.ek -show "*"]
            grid $ent_key -row $row -column 1 -sticky ew -padx 5
            grid [ttk::button $f.ck -text [::llm_ui::logic::mc "Change API Key"] -command [list [self] ChangeKey]] -row $row -column 2

            incr row
            grid [ttk::label $f.lb -text "[::llm_ui::logic::mc "Base URL"]:"] -row $row -column 0 -sticky w
            set ent_base_url [ttk::entry $f.eb]
            grid $ent_base_url -row $row -column 1 -sticky ew -padx 5

            grid columnconfigure $f 1 -weight 1

            set fs [ttk::labelframe $w.s -text [::llm_ui::logic::mc "System Prompt"] -padding 10]
            pack $fs -fill both -expand yes -padx 10 -pady 5

            set txt_prompt [text $fs.t -height 5 -font {TkDefaultFont 11}]
            pack $txt_prompt -fill both -expand yes

            set fl [ttk::frame $w.l -padding 10]
            pack $fl -fill x -padx 10

            grid [ttk::label $fl.ll -text "[::llm_ui::logic::mc "Language"]:"] -row 0 -column 0 -sticky w
            set cb_l [ttk::combobox $fl.cl -state readonly -values {English Simplified_Chinese Traditional_Chinese}]
            grid $cb_l -row 0 -column 1 -sticky ew -padx 5

            set cur_lang [::msgcat::mclocale]
            switch -glob -- $cur_lang {
                zh_cn* { $cb_l current 1 }
                zh_tw* - zh_hk* { $cb_l current 2 }
                default { $cb_l current 0 }
            }

            set fs_check [ttk::frame $w.check -padding 10]
            pack $fs_check -fill x -padx 10
            set check_stream [ttk::checkbutton $fs_check.stream -text [::llm_ui::logic::mc "Use Streaming"] -variable ::llm_ui::use_streaming]
            pack $check_stream -side left

            set fb [ttk::frame $w.b -padding 10]
            pack $fb -fill x -padx 10 -pady 5
            pack [ttk::button $fb.s -text [::llm_ui::logic::mc "Save all settings"] -command [list [self] SaveAllSettings]] -side right

            bind $cb_p <<ComboboxSelected>> [list [self] OnProviderSelected %W]
            bind $cb_m <<ComboboxSelected>> [list [self] OnModelSelected %W]
            bind $cb_l <<ComboboxSelected>> [list [self] OnLanguageSelected %W]

            my LoadPreferences
        }

        method OnProviderSelected {w} {
            set current_p_name [$w get]
            foreach p $providers_data {
                if {[dict get $p name] eq $current_p_name} {
                    $cb_m configure -values [dict get $p models]
                    $ent_key delete 0 end
                    $ent_key insert 0 [dict get $p api_key]
                    $ent_base_url delete 0 end
                    $ent_base_url insert 0 [dict get $p base_url]
                    if {[llength [dict get $p models]] > 0} {
                        $cb_m current 0
                        my OnModelSelected $cb_m
                    }
                    $chatW configure -base_url [dict get $p base_url] -api_key [dict get $p api_key]
                    break
                }
            }
        }

        method OnModelSelected {w} {
            $chatW configure -model [$w get]
        }

        method OnLanguageSelected {w} {
            set lang [$w get]
            set locale "en"
            if {$lang eq "Simplified_Chinese"} { set locale "zh_cn" }
            if {$lang eq "Traditional_Chinese"} { set locale "zh_tw" }
            ::msgcat::mclocale $locale
            ::llm_ui::logic::mcload_msgs
            event generate . <<LanguageChanged>>
            my UpdateTranslations
        }

        method UpdateTranslations {} {
            $w.p configure -text [::llm_ui::logic::mc "Provider"]
            $w.p.lp configure -text "[::llm_ui::logic::mc "Provider"]:"
            $w.p.rm configure -text [::llm_ui::logic::mc "Refresh Models"]
            $w.p.lk configure -text "[::llm_ui::logic::mc "API Key"]:"
            $w.p.ck configure -text [::llm_ui::logic::mc "Change API Key"]
            $w.p.lb configure -text "[::llm_ui::logic::mc "Base URL"]:"
            $w.s configure -text [::llm_ui::logic::mc "System Prompt"]
            $w.l.ll configure -text "[::llm_ui::logic::mc "Language"]:"
            $w.b.s configure -text [::llm_ui::logic::mc "Save all settings"]
            $w.check.stream configure -text [::llm_ui::logic::mc "Use Streaming"]
            $chatW UpdateTranslations
        }

        method ChangeKey {} {
            set new_key [string trim [$ent_key get]]
            set p_idx [my FindProviderIdx $current_p_name]
            if {$p_idx != -1} {
                set p [lindex $providers_data $p_idx]
                dict set p api_key $new_key
                set providers_data [lreplace $providers_data $p_idx $p_idx $p]
                $chatW configure -api_key $new_key
                my SavePreferences
            }
        }

        method FindProviderIdx {name} {
            set i 0
            foreach p $providers_data {
                if {[dict get $p name] eq $name} { return $i }
                incr i
            }
            return -1
        }

        method RefreshModels {} {
            set url "[$chatW cget -base_url]"
            if {$url eq ""} {
                ::ttk::messagebox::show $w [::llm_ui::logic::mc "Fetch Error"] [::llm_ui::logic::mc "Error: Base URL is empty."] "error"
                return
            }
            my FetchModels $url
        }

        method AddProvider {} {
            set top .add_provider_popup
            if {[winfo exists $top]} { destroy $top }
            toplevel $top
            wm title $top [::llm_ui::logic::mc "Add Provider"]
            wm geometry $top 400x250

            set f [ttk::frame $top.f -padding 20]
            pack $f -fill both -expand yes

            grid [ttk::label $f.ln -text "[::llm_ui::logic::mc "Provider Name"]:"] -row 0 -column 0 -sticky w
            set en [ttk::entry $f.en]
            grid $en -row 0 -column 1 -sticky ew -pady 5

            grid [ttk::label $f.lu -text "[::llm_ui::logic::mc "Base URL"]:"] -row 1 -column 0 -sticky w
            set eu [ttk::entry $f.eu]
            grid $eu -row 1 -column 1 -sticky ew -pady 5

            grid [ttk::label $f.lk -text "[::llm_ui::logic::mc "API Key"]:"] -row 2 -column 0 -sticky w
            set ek [ttk::entry $f.ek -show "*"]
            grid $ek -row 2 -column 1 -sticky ew -pady 5

            set bf [ttk::frame $f.bf]
            grid $bf -row 3 -column 0 -columnspan 2 -pady 20

            ttk::button $bf.ok -text [::llm_ui::logic::mc "OK"] -command [list [self] TestAndAddProvider $top $en $eu $ek]
            ttk::button $bf.cancel -text [::llm_ui::logic::mc "Cancel"] -command [list destroy $top]
            pack $bf.ok $bf.cancel -side left -padx 5

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
            if {[string match -nocase "https://*" $test_url] && ![::llm_ui::logic::is_https_available]} {
                error [::llm_ui::logic::mc "HTTPS requires the 'tls' package, which is not installed."]
            }
            set headers [list \
                "Authorization" "Bearer [string trim $key]" \
                "Accept" "application/json" \
                "User-Agent" "OpenAI/Python 1.51.2" \
            ]

            if {[catch {
                lassign [::llm_ui::logic::http_get $test_url $headers] ncode res
                set res [encoding convertfrom utf-8 $res]

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
                set p_name [$cb_p get]
                set p_idx [my FindProviderIdx $p_name]
                if {$p_idx != -1} {
                    set p [lindex $providers_data $p_idx]
                    dict set p api_key [string trim [$ent_key get]]
                    dict set p base_url [string trim [$ent_base_url get]]
                    set providers_data [lreplace $providers_data $p_idx $p_idx $p]
                }
            }
            $chatW configure -system_prompt [$txt_prompt get 1.0 end-1c]
            $chatW configure -stream $::llm_ui::use_streaming
            my SavePreferences
        }

        method LoadPreferences {} {
            set settings_dir [file join [file dirname [info script]] settings]
            set pref_file [file join $settings_dir preference.json]
            if {[file exists $pref_file]} {
                set fh [open $pref_file r]
                set json [read $fh]
                close $fh
                if {![catch {set d [::llm_ui::logic::json_parse $json]}]} {
                    if {[dict exists $d providers]} {
                        set providers_data [dict get $d providers]
                        set p_names {}
                        foreach p $providers_data {
                            lappend p_names [dict get $p name]
                        }
                        $cb_p configure -values $p_names
                        if {[llength $p_names] > 0} {
                            $cb_p current 0
                            my OnProviderSelected $cb_p
                        }
                    }
                    if {[dict exists $d system_prompt]} {
                        $txt_prompt insert 1.0 [dict get $d system_prompt]
                        $chatW configure -system_prompt [dict get $d system_prompt]
                    }
                    if {[dict exists $d use_streaming]} {
                        set ::llm_ui::use_streaming [dict get $d use_streaming]
                        $chatW configure -stream $::llm_ui::use_streaming
                    }
                }
            }
        }

        method SavePreferences {} {
            set settings_dir [file join [file dirname [info script]] settings]
            file mkdir $settings_dir
            set pref_file [file join $settings_dir preference.json]

            set lang "en"
            set cur_lang [::msgcat::mclocale]
            if {[string match "zh_cn*" $cur_lang]} { set lang "zh_cn" }
            if {[string match "zh_tw*" $cur_lang] || [string match "zh_hk*" $cur_lang]} { set lang "zh_tw" }

            set d [list \
                providers $providers_data \
                system_prompt [$txt_prompt get 1.0 end-1c] \
                language $lang \
                use_streaming $::llm_ui::use_streaming \
            ]
            set fh [open $pref_file w]
            puts -nonewline $fh [::llm_ui::logic::json_gen_val $d]
            close $fh
        }

        method UpdateModelList {ids} {
            $cb_m configure -values $ids
            if {[llength $ids] > 0} {
                $cb_m current 0
                my OnModelSelected $cb_m
            }
        }

        method FetchModels {base_url} {
            set url "$base_url/models"
            if {[string match -nocase "https://*" $url] && ![::llm_ui::logic::is_https_available]} {
                error [::llm_ui::logic::mc "HTTPS requires the 'tls' package, which is not installed."]
            }
            set headers [list \
                "Authorization" "Bearer [string trim [$chatW cget -api_key]]" \
                "Accept" "application/json" \
                "User-Agent" "OpenAI/Python 1.51.2" \
            ]
            if {[catch {
                lassign [::llm_ui::logic::http_get $url $headers] ncode res
                set res [encoding convertfrom utf-8 $res]
                if {$ncode != 200} {
                    error "HTTP $ncode: $res"
                }
                set ids [::llm_ui::logic::extract_ids $res "id"]
                set p_idx [my FindProviderIdx $current_p_name]
                if {$p_idx != -1} {
                    set p [lindex $providers_data $p_idx]
                    dict set p models $ids
                    set providers_data [lreplace $providers_data $p_idx $p_idx $p]
                    my SavePreferences
                }
                my UpdateModelList $ids
            } err]} {
                set err_msg "Failed to fetch models: $err"
                my UpdateModelList {}
                ::ttk::messagebox::show $w [::llm_ui::logic::mc "Fetch Error"] $err_msg "error"
            }
        }

        export OnProviderSelected ChangeKey RefreshModels OnModelSelected OnLanguageSelected SaveAllSettings UpdateTranslations SavePreferences AddProvider TestAndAddProvider
    }

    proc ChatWidget {path args} {
        return [ChatWidgetClass create ::${path}:obj $path {*}$args]
    }

    proc SettingsWidget {path chat_widget args} {
        return [SettingsWidgetClass create ::${path}:obj $path $chat_widget {*}$args]
    }
}
