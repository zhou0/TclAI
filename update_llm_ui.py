import re

with open('lib/llm_ui/llm_ui.tcl', 'r') as f:
    lines = f.readlines()

def add_https_check(content):
    check_code = """            if {[string match -nocase "https://*" $url] && ![::llm_ui::logic::is_https_available]} {
                error [::llm_ui::logic::mc "HTTPS requires the 'tls' package, which is not installed."]
            }
"""
    # Specifically for TestAndAddProvider
    content = content.replace('            set test_url "$url/models"', '            set test_url "$url/models"\n            if {[string match -nocase "https://*" $test_url] && ![::llm_ui::logic::is_https_available]} {\n                error [::llm_ui::logic::mc "HTTPS requires the \'tls\' package, which is not installed."]\n            }')

    # For FetchModels
    content = content.replace('            set url "$base_url/models"', '            set url "$base_url/models"\n            if {[string match -nocase "https://*" $url] && ![::llm_ui::logic::is_https_available]} {\n                error [::llm_ui::logic::mc "HTTPS requires the \'tls\' package, which is not installed."]\n            }')

    # For ChatWidget (sending message)
    # The URL is constructed as: set url "$base_url/chat/completions"
    content = content.replace('                    set url "$base_url/chat/completions"', '                    set url "$base_url/chat/completions"\n                    if {[string match -nocase "https://*" $url] && ![::llm_ui::logic::is_https_available]} {\n                        error [::llm_ui::logic::mc "HTTPS requires the \'tls\' package, which is not installed."]\n                    }')

    return content

new_content = add_https_check("".join(lines))

with open('lib/llm_ui/llm_ui.tcl', 'w') as f:
    f.write(new_content)
