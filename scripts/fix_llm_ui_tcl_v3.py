with open('lib/llm_ui/llm_ui.tcl', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False
for i in range(len(lines)):
    if skip:
        if lines[i].strip() == '}':
            skip = False
        continue

    # Detect the duplicate closing block
    if i > 0 and lines[i].strip() == '}' and lines[i-1].strip() == '}' and (i+1 < len(lines) and lines[i+1].strip() == 'method ShowJSON {json} {'):
         # This is the extra '}' we want to keep one, but let's see.
         # Actually looking at the sed output:
         # 266:         }
         # 267:         }
         # 268:
         # 269:         method ShowJSON {json} {
         # The extra '}' is at line 267.
         pass

    new_lines.append(lines[i])

# Let's just do a specific string replacement for the duplicated end
content = "".join(new_lines)
bad_end = """            }
        }
        }"""
good_end = """            }
        }"""

content = content.replace(bad_end, good_end)

with open('lib/llm_ui/llm_ui.tcl', 'w') as f:
    f.write(content)
