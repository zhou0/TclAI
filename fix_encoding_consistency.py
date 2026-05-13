filename_logic = 'lib/llm_ui/llm_logic.tcl'
filename_ui = 'lib/llm_ui/llm_ui.tcl'

with open(filename_logic, 'r') as f:
    logic = f.read()

# Revert parse_sse to take raw data and we'll decode it in SSEHandler/elsewhere
# Or better: make sure we don't decode twice.

# Current SSEHandler decodes chunk then passes to parse_sse.
# parse_sse then decodes line again.
# This is bad! double decoding.

# Let's make SSEHandler pass raw chunk, and parse_sse handle decoding.

with open(filename_ui, 'r') as f:
    ui = f.read()

ui = ui.replace('append accumulated_data [encoding convertfrom utf-8 $chunk]', 'append accumulated_data $chunk')

with open(filename_ui, 'w') as f:
    f.write(ui)

print("Restored raw accumulated_data in SSEHandler")
