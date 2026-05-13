import re

with open('lib/llm_ui/llm_ui.tcl', 'r') as f:
    content = f.read()

new_method = """        method CopyAsImage {txt} {
            set filetypes [list \
                [list [::llm_ui::logic::mc "PNG Files"] ".png"] \
                [list [::llm_ui::logic::mc "PostScript Files"] ".ps"] \
                [list [::llm_ui::logic::mc "All Files"] "*"] \
            ]
            set filename [tk_getSaveFile -defaultextension ".png" -filetypes $filetypes]
            if {$filename eq ""} return

            set temp_top .temp_render
            if {[catch {
                if {[winfo exists $temp_top]} { destroy $temp_top }
                toplevel $temp_top
                wm title $temp_top [::llm_ui::logic::mc "Rendering Answer..."]

                set c [canvas $temp_top.c -bg white -highlightthickness 0]
                set tid [$c create text 10 10 -text $txt -anchor nw -width 600 -font {Helvetica 12}]
                set bbox [$c bbox $tid]
                set cw [expr {[lindex $bbox 2] + 20}]
                set ch [expr {[lindex $bbox 3] + 20}]
                $c configure -width $cw -height $ch
                pack $c

                update idletasks

                if {[string match -nocase "*.ps" $filename]} {
                    $c postscript -file $filename
                } else {
                    # Attempt PNG export
                    if {[catch {
                        # Modern Tk with Img package
                        package require Img
                        set img [image create photo -format window -data $c]
                        $img write $filename -format png
                        image delete $img
                    } err]} {
                        # Fallback for some Tk 8.6 environments that might support 'copy' from window
                        if {[catch {
                            set img [image create photo]
                            $img copy $c
                            $img write $filename -format png
                            image delete $img
                        } err2]} {
                             error [::llm_ui::logic::mc "Exporting PNG requires the 'Img' package. Please save as PostScript (.ps) instead."]
                        }
                    }
                }
                destroy $temp_top
            } err]} {
                if {[winfo exists $temp_top]} { destroy $temp_top }
                ::ttk::messagebox::show $w [::llm_ui::logic::mc "Export Error"] $err "error"
            }
        }"""

# Find the existing CopyAsImage method and replace it
# The previous step replaced it with a multi-line method, so let's match the start/end
pattern = r'        method CopyAsImage \{txt\} \{.*?        \}'
content = re.sub(pattern, new_method, content, flags=re.DOTALL)

with open('lib/llm_ui/llm_ui.tcl', 'w') as f:
    f.write(content)
