import os

files = ['lib/llm_ui/llm_logic.tcl', 'lib/llm_ui/llm_ui.tcl']

for filename in files:
    with open(filename, 'r') as f:
        content = f.read()

    # Replace [^ with \[^
    new_content = content.replace('[^', '\\[^')

    if new_content != content:
        with open(filename, 'w') as f:
            f.write(new_content)
        print(f"Fixed square braces in {filename}")
    else:
        print(f"No square braces to fix in {filename}")
