package require http
# No tls registered yet
if {[catch {http::geturl HTTPS://example.com} err]} {
    puts "Error with HTTPS: $err"
}
if {[catch {http::geturl https://example.com} err]} {
    puts "Error with https: $err"
}

catch {package require tls}
if {[info commands ::tls::socket] ne ""} {
    http::register https 443 [list ::tls::socket -autoservername 1]
    puts "Registered https"
}

if {[catch {http::geturl https://example.com} err]} {
    puts "Error with https after register: $err"
} else {
    puts "Success with https after register"
}

if {[catch {http::geturl HTTPS://example.com} err]} {
    puts "Error with HTTPS after register: $err"
} else {
    puts "Success with HTTPS after register"
}
