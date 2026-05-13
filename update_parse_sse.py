import re

filename = 'lib/llm_ui/llm_logic.tcl'
with open(filename, 'r') as f:
    content = f.read()

old_block = """            set line [string range $buffer 0 $end]
            set buffer [string range $buffer [expr {$end + 1}] end]
            set line [string trim $line]"""

new_block = """            set line [string range $buffer 0 $end]
            set buffer [string range $buffer [expr {$end + 1}] end]
            # Handle potential UTF-8 mojibake by explicitly converting from utf-8
            set line [encoding convertfrom utf-8 $line]
            set line [string trim $line]"""

if old_block in content:
    content = content.replace(old_block, new_block)
    with open(filename, 'w') as f:
        f.write(content)
    print("Updated parse_sse in lib/llm_ui/llm_logic.tcl")
else:
    print("Could not find target block in parse_sse")
