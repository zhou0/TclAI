namespace eval ::json {
    proc parse {json} {
        set json [string map {
            "{" " dict create "
            "}" " "
            "[" " list "
            "]" " "
            ":" " "
            "," " "
            "\"" " "
        } $json]
        return [subst $json]
    }
}
package provide json 1.0
