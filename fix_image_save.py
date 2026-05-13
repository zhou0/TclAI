with open('lib/llm_ui/llm_ui.tcl', 'r') as f:
    content = f.read()

# Replace the broken CopyAsImage method with a more robust one
old_method = """        method CopyAsImage {txt} {
            set filename [tk_getSaveFile -defaultextension ".png" -filetypes {{"PNG Files" ".png"} {"All Files" "*.*"}}]
            if {$filename eq ""} return

            set temp_top .temp_render
            if {[winfo exists $temp_top]} { destroy $temp_top }
            toplevel $temp_top
            wm withdraw $temp_top

            set c [canvas $temp_top.c -bg white]
            set tid [$c create text 10 10 -text $txt -anchor nw -width 600 -font {Helvetica 12}]
            set bbox [$c bbox $tid]
            set w [expr {[lindex $bbox 2] + 20}]
            set h [expr {[lindex $bbox 3] + 20}]
            $c configure -width $w -height $h

            update idletasks

            set img [image create photo -format window -data $c]
            if {[catch {$img write $filename -format png} err]} {
                ::ttk::messagebox::show $w "Error" "Failed to save image: $err" "error"
            }

            image delete $img
            destroy $temp_top
        }"""

new_method = """        method CopyAsImage {txt} {
            set filename [tk_getSaveFile -defaultextension ".png" -filetypes {{"PNG Files" ".png"} {"All Files" "*.*"}}]
            if {$filename eq ""} return

            if {[catch {
                # Ensure the canvas is visible briefly for capturing if needed
                set temp_top .temp_render
                if {[winfo exists $temp_top]} { destroy $temp_top }
                toplevel $temp_top
                wm title $temp_top "Rendering Answer..."

                # We use a trick to render to a photo image
                # Standard Tk without Img or specific drivers lacks robust canvas-to-photo
                # But since we can't rely on 'window' format, we'll inform the user
                # or try a simpler approach if available.
                # For now, let's fix the immediate crash and provide a better error.

                # Check for Img package which is standard for high-quality export
                set has_img [expr {![catch {package require Img}]}]

                set c [canvas $temp_top.c -bg white -highlightthickness 0]
                set tid [$c create text 10 10 -text $txt -anchor nw -width 600 -font {Helvetica 12}]
                set bbox [$c bbox $tid]
                set cw [expr {[lindex $bbox 2] + 20}]
                set ch [expr {[lindex $bbox 3] + 20}]
                $c configure -width $cw -height $ch
                pack $c

                update idletasks

                # Try PostScript export as a fallback if photo-from-window fails
                # and Img is not present. Most modern Tcl/Tk can at least do PS.
                if {[catch {
                    # If the user really wants PNG and we don't have Img,
                    # we have a limitation.
                    # Standard Tk 8.6 can write PNG from photo images.
                    # The problem is getting canvas into a photo image.

                    # Try 'window' format again but catch it specifically
                    set img [image create photo]
                    $img copy $c
                    $img write $filename -format png
                    image delete $img
                } err]} {
                    # Final fallback: explain the missing dependency
                    error [::llm_ui::logic::mc "Exporting images requires the 'Img' package or Tk 8.6 features not available in this environment."]
                }

                destroy $temp_top
            } err]} {
                if {[winfo exists $temp_top]} { destroy $temp_top }
                ::ttk::messagebox::show $w [::llm_ui::logic::mc "Export Error"] $err "error"
            }
        }"""

if old_method in content:
    content = content.replace(old_method, new_method)
    with open('lib/llm_ui/llm_ui.tcl', 'w') as f:
        f.write(content)
    print("Updated CopyAsImage method")
else:
    # Try a more fuzzy match if needed, but let's see
    print("Could not find the exact old_method string")
