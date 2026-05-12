import sys

with open('lib/llm_ui/llm_logic.tcl', 'r') as f:
    content = f.read()

old_block = """    if {[info commands ::tls::socket] ne ""} {
        http::register https 443 [list ::tls::socket -autoservername 1]
    }"""

new_block = """    if {[info commands ::tls::socket] ne ""} {
        http::register https 443 [list ::tls::socket -autoservername 1]
        http::register HTTPS 443 [list ::tls::socket -autoservername 1]
    }

    proc is_https_available {} {
        return [expr {[info commands ::tls::socket] ne ""}]
    }"""

if old_block in content:
    new_content = content.replace(old_block, new_block)
    with open('lib/llm_ui/llm_logic.tcl', 'w') as f:
        f.write(new_content)
    print("Successfully updated lib/llm_ui/llm_logic.tcl")
else:
    print("Could not find the target block in lib/llm_ui/llm_logic.tcl")
    sys.exit(1)
