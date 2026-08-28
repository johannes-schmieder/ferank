version 19.0
set more off
set varabbrev off

capture erase "windows-ci.status"
shell powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass ///
    -File "scripts/build_windows_x86_64.ps1"
confirm file "dist/ferank_windows.plugin"
copy "dist/ferank_windows.plugin" "stata/ferank_windows.plugin", replace

do "ci/stata_package_quick.do"

tempname status
file open `status' using "windows-ci.status", write text replace
file write `status' "WINDOWS_CI=PASS" _n
file close `status'
display as result "FERANK WINDOWS X86_64 QUALIFICATION PASS"
