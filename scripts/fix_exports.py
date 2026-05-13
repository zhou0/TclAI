import re

with open('lib/llm_ui/llm_ui.tcl', 'r') as f:
    content = f.read()

# Find ChatWidgetClass definition and add exports
pattern = r'(::oo::class create ChatWidgetClass \{.*?)(export configure)'
replacement = r'\1export SSEHandler APIComplete CallAPI AppendHistory UpdateLastHistory AppendAssistantContent AddMessageButtons\n        \2'

if 'export SSEHandler' not in content:
    content = re.sub(pattern, replacement, content, flags=re.DOTALL)

with open('lib/llm_ui/llm_ui.tcl', 'w') as f:
    f.write(content)
