lappend auto_path [file join [file dirname [info script]] lib]
package require llm_ui::logic

set messages {
    {"role": "user", "content": "hello"}
}
set m_list {}
foreach m $messages {
    lappend m_list [::llm_ui::logic::json_gen_dict $m]
}
set messages_json "\[[join $m_list ,]\]"

set body_dict [list \
    model "test-model" \
    messages $messages_json \
]
set body [::llm_ui::logic::json_gen_dict $body_dict]
puts "Generated body: $body"
