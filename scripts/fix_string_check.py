filename = 'lib/llm_ui/llm_ui.tcl'
with open(filename, 'r') as f:
    content = f.read()

# 'string is utf8' is not a standard Tcl command.
# And 'string is bytearray' is also not.
# We should probably just catch the encoding conversion or use a safer check.

old_block = """            # Ensure the JSON is properly decoded from UTF-8 if it's still raw bytes
            if {[string is bytearray $json] || ![string is utf8 $json]} {
                set json [encoding convertfrom utf-8 $json]
            }"""

new_block = """            # Ensure the JSON is properly decoded from UTF-8
            if {[catch {encoding convertto utf-8 $json} tmp]} {
                # If conversion to utf-8 fails or results in change, it might already be decoded.
                # In Tcl, internal strings are usually UTF-8.
                # If we suspect it is raw bytes, we convert it.
            }"""

# Actually, the safest way in Tcl to handle "maybe bytes maybe string" is tricky.
# But since I've fixed SSEHandler to append decoded data, and non-stream also decodes:
# set data [encoding convertfrom utf-8 [http::data $token]]
# accumulated_data should be fine.

# Let's just remove the redundant check and trust the incoming data is decoded.
# But I'll keep the mc for localization.

replacement = """            # The incoming json should already be decoded in SSEHandler or CallAPI
            # if {$json ne ""} { ... }"""

content = content.replace(old_block, "")

with open(filename, 'w') as f:
    f.write(content)
print("Cleaned up ShowJSON")
