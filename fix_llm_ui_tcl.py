with open('lib/llm_ui/llm_ui.tcl', 'r') as f:
    content = f.read()

# Find the end of the method we just added and remove the dangling code
target = '} err]} {\n                if {[winfo exists $temp_top]} { destroy $temp_top }\n                ::ttk::messagebox::show $w [::llm_ui::logic::mc "Export Error"] $err "error"\n            }\n        }'
dangling_start = ' err]} {\n                    # Final fallback'
dangling_end = 'destroy $temp_top\n'

# Find the position of target
idx = content.find(target)
if idx != -1:
    end_idx = idx + len(target)
    # Search for the next occurrences of 'destroy $temp_top\n' after end_idx
    d_idx = content.find(dangling_end, end_idx)
    if d_idx != -1:
        new_content = content[:end_idx] + content[d_idx + len(dangling_end):]
        with open('lib/llm_ui/llm_ui.tcl', 'w') as f:
            f.write(new_content)
        print("Removed dangling code")
else:
    print("Could not find target")
