import os

filename = 'lib/llm_ui/llm_logic.tcl'
with open(filename, 'r') as f:
    content = f.read()

# The specific one that shouldn't have been escaped if it was in braces
bad = 'regexp {^\\[^'
good = 'regexp {^[^'

content = content.replace(bad, good)

with open(filename, 'w') as f:
    f.write(content)
