import os

def fix_file(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()

    new_lines = []
    changed = False
    for line in lines:
        if r'\\[^' in line:
            new_line = line.replace(r'\\[^', r'\[^')
            new_lines.append(new_line)
            changed = True
        else:
            new_lines.append(line)

    if changed:
        with open(filename, 'w') as f:
            f.writelines(new_lines)
        print(f"Fixed {filename}")
    else:
        print(f"No changes for {filename}")

fix_file('lib/llm_ui/llm_ui.tcl')
