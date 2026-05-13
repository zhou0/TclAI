filename = 'lib/llm_ui/llm_ui.tcl'
with open(filename, 'r') as f:
    content = f.read()

old_block = """                    if {!$success} {
                         error [::llm_ui::logic::mc "Exporting PNG requires the 'Img' package. Please save as PostScript (.ps) instead."]
                    }"""

new_block = """                    if {!$success} {
                         if {[info exists err]} {
                             error "[::llm_ui::logic::mc "Exporting PNG requires the 'Img' package. Please save as PostScript (.ps) instead."]\n($err)"
                         } else {
                             error [::llm_ui::logic::mc "Exporting PNG requires the 'Img' package. Please save as PostScript (.ps) instead."]
                         }
                    }"""

if old_block in content:
    content = content.replace(old_block, new_block)
    with open(filename, 'w') as f:
        f.write(content)
    print("Added detailed error reporting to CopyAsImage")
else:
    print("Could not find old_block")
