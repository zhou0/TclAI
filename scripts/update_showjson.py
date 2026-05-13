import re

filename = 'lib/llm_ui/llm_ui.tcl'
with open(filename, 'r') as f:
    content = f.read()

# Fix ShowJSON method: add localization and ensure UTF-8 decoding
old_showjson = r'        method ShowJSON \{json\} \{.*?            wm title \$top "Raw JSON Response".*?            \$txt insert 1.0 \[::llm_ui::logic::json_pretty \$json\].*?        \}'

new_showjson = """        method ShowJSON {json} {
            set top .json_popup
            if {[winfo exists $top]} { destroy $top }
            toplevel $top
            wm title $top [::llm_ui::logic::mc "Raw JSON Response"]
            wm geometry $top 600x400
            set txt [text $top.t -wrap none -font {Courier 10}]
            set sbx [ttk::scrollbar $top.sbx -orient horizontal -command [list $txt xview]]
            set sby [ttk::scrollbar $top.sby -orient vertical -command [list $txt yview]]
            $txt configure -xscrollcommand [list $sbx set] -yscrollcommand [list $sby set]

            grid $txt -row 0 -column 0 -sticky nsew
            grid $sby -row 0 -column 1 -sticky ns
            grid $sbx -row 1 -column 0 -sticky ew
            grid rowconfigure $top 0 -weight 1
            grid columnconfigure $top 0 -weight 1

            # Ensure the JSON is properly decoded from UTF-8 if it's still raw bytes
            if {[string is bytearray $json] || ![string is utf8 $json]} {
                set json [encoding convertfrom utf-8 $json]
            }

            $txt insert 1.0 [::llm_ui::logic::json_pretty $json]
            $txt configure -state disabled
        }"""

content = re.sub(old_showjson, new_showjson, content, flags=re.DOTALL)

# Fix SSEHandler to store decoded accumulated data or ensure it's handled
# In SSEHandler, append accumulated_data with decoded chunk or similar
# Actually, accumulated_data is used in APIComplete: set last_raw_json $accumulated_data
# Let's fix SSEHandler to append the decoded chunk to accumulated_data

old_sse_handler = """        method SSEHandler {sock token} {
            set chunk [read $sock]
            append accumulated_data $chunk"""

new_sse_handler = """        method SSEHandler {sock token} {
            set chunk [read $sock]
            append accumulated_data [encoding convertfrom utf-8 $chunk]"""

content = content.replace(old_sse_handler, new_sse_handler)

with open(filename, 'w') as f:
    f.write(content)
print("Updated ShowJSON and SSEHandler")
