import re

filename = 'lib/llm_ui/llm_ui.tcl'
with open(filename, 'r') as f:
    content = f.read()

# Replace the inner part of the catch block to include debug info and better mapping
old_block = r"""                    # Attempt PNG export
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
                    }"""

new_block = r"""                    # Attempt PNG export
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

if old_block in content:
    content = content.replace(old_block, new_block)
    with open(filename, 'w') as f:
        f.write(content)
    print("Updated CopyAsImage with debug info and update")
else:
    print("Could not find old_block")
