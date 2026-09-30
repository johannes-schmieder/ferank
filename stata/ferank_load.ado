*! ferank native plugin loader 0.1.0 30sep2026
program define ferank_load, rclass
    version 18.0
    syntax , ACTION(string)

    local os `"`c(os)'"'
    local machine `"`c(machine_type)'"'
    if `"`os'"' == "Windows" {
        local plugin_name "ferank_windows.plugin"
    }
    else if `"`os'"' == "MacOSX" {
        local plugin_name "ferank_macos.plugin"
    }
    else if `"`os'"' == "Unix" & strmatch(`"`machine'"', "Mac*") {
        local plugin_name "ferank_macos.plugin"
    }
    else if `"`os'"' == "Unix" {
        local plugin_name "ferank_linux.plugin"
    }
    else {
        di as error "ferank does not recognize this operating system: `os' / `machine'"
        exit 9
    }

    capture quietly findfile `plugin_name'
    if _rc {
        di as error "ferank native plugin not found: `plugin_name'"
        exit 601
    }
    local plugin_file `"`r(fn)'"'
    capture program __ferank_plugin, plugin using(`"`plugin_file'"')
    if _rc != 0 & _rc != 110 exit _rc

    if `"`action'"' == "version" {
        plugin call __ferank_plugin, version
    }
    else if `"`action'"' == "selftest" {
        plugin call __ferank_plugin, selftest
    }
    else if `"`action'"' != "loadonly" {
        di as error "unknown ferank plugin action: `action'"
        exit 198
    }

    return local handle "__ferank_plugin"
    return local plugin_name "`plugin_name'"
    return local plugin_file `"`plugin_file'"'
end
