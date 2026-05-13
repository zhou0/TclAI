import re

filename = 'lib/llm_ui/llm_ui.tcl'
with open(filename, 'r') as f:
    content = f.read()

# Replace the whole PNG attempt part to be more robust
old_pattern = r'# Attempt PNG export.*?error "\[::llm_ui::logic::mc "Exporting PNG requires the \'Img\' package. Please save as PostScript \(.ps\) instead."\]\$debug_info"\s+\}\s+\}'

new_part = r"""                    # Attempt PNG export
                    set success 0
                    if {![catch {package require Img}]} {
                        # Map window to ensure window format works
                        wm deiconify $temp_top
                        update idletasks
                        if {![catch {
                            set img [image create photo -format window -data $c]
                            $img write $filename -format png
                            image delete $img
                            set success 1
                        } err]} {
                            # Success
                        }
                    }

                    if {!$success} {
                         error [::llm_ui::logic::mc "Exporting PNG requires the 'Img' package. Please save as PostScript (.ps) instead."]
                    }"""

# Actually I'll use a simpler replacement based on the current state
current_block = """                    # Attempt PNG export
                    if {[catch {
                        # Ensure window is mapped for 'window' format
                        update
                        # Modern Tk with Img package
                        package require Img
                        set img [image create photo -format window -data $c]
                        $img write $filename -format png
                        image delete $img
                    } err]} {
                        # Fallback for some Tk 8.6 environments that might support 'copy' from window
                        if {[catch {
                            set img [image create photo]
                            # Note: $img copy $c usually only works for other images, not canvases
                            # but we try it just in case of future Tk improvements
                            $img copy $c
                            $img write $filename -format png
                            image delete $img
                        } err2]} {
                             set debug_info " (Img: $err, Copy: $err2)"
                             error "[::llm_ui::logic::mc "Exporting PNG requires the 'Img' package. Please save as PostScript (.ps) instead."]$debug_info"
                        }
                    }"""

final_block = """                    # Attempt PNG export
                    set success 0
                    if {![catch {package require Img}]} {
                        # Map window and wait for it to be drawn for 'window' format to work
                        wm deiconify $temp_top
                        raise $temp_top
                        update idletasks
                        update

                        if {![catch {
                            set img [image create photo -format window -data $c]
                            $img write $filename -format png
                            image delete $img
                            set success 1
                        } err]} {
                            # Success
                        } else {
                            # Log error if Img is present but failed
                            puts "Img failed: $err"
                        }
                    }

                    if {!$success} {
                         error [::llm_ui::logic::mc "Exporting PNG requires the 'Img' package. Please save as PostScript (.ps) instead."]
                    }"""

if current_block in content:
    content = content.replace(current_block, final_block)
    with open(filename, 'w') as f:
        f.write(content)
    print("Improved CopyAsImage with deiconify and raise")
else:
    print("Could not find current_block")
