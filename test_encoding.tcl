set chunk "\xe6\x88\x91\xe6\x98\xaf" ;# "我是" in UTF-8
puts "Default read behavior (simulated): $chunk"
set decoded [encoding convertfrom utf-8 $chunk]
puts "Decoded with utf-8: $decoded"

# Test SSE parsing with binary vs characters
proc parse_sse_simple {data buffer_var} {
    upvar 1 $buffer_var buffer
    append buffer $data
    if {[regexp "\n" $buffer]} {
        # ... simplified ...
    }
}
