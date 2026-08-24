version 18.0
clear all
set more off
set varabbrev off

display as result "TEXPDF_STATA_SMOKE_BEGIN"
display as text "stata_version=" c(stata_version)
display as text "stata_edition=" c(edition_real)
display as text "stata_os=" c(os)
display as text "stata_machine_type=" c(machine_type)
assert c(stata_version) >= 18

mata:
assert(sum((1, 2, 3)) == 6)
end

display as result "TEXPDF STATA MATA SMOKE PASS"
