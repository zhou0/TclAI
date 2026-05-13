filename = 'lib/llm_ui/llm_ui.tcl'
with open(filename, 'r') as f:
    content = f.read()

old_code = """            $txt insert 1.0 [::llm_ui::logic::json_pretty $json]"""
new_code = """            # Ensure the JSON is properly decoded from UTF-8 if it comes from raw accumulated_data
            if {[catch {set decoded [encoding convertfrom utf-8 $json]}]} {
                set decoded $json
            }
            $txt insert 1.0 [::llm_ui::logic::json_pretty $decoded]"""

content = content.replace(old_code, new_code)
with open(filename, 'w') as f:
    f.write(content)
print("Updated ShowJSON with safe decoding")
