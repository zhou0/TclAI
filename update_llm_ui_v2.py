with open('lib/llm_ui/llm_ui.tcl', 'r') as f:
    content = f.read()

target = '            set url "$options(-base_url)/chat/completions"'
replacement = '            set url "$options(-base_url)/chat/completions"\n            if {[string match -nocase "https://*" $url] && ![::llm_ui::logic::is_https_available]} {\n                error [::llm_ui::logic::mc "HTTPS requires the \'tls\' package, which is not installed."]\n            }'

if target in content:
    content = content.replace(target, replacement)
    with open('lib/llm_ui/llm_ui.tcl', 'w') as f:
        f.write(content)
    print("Updated ChatWidget logic")
else:
    print("Could not find ChatWidget logic")
