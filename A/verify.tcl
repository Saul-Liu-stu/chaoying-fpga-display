set root [file dirname [file normalize [info script]]]
file mkdir [file join $root verification]
cd [file join $root verification]
import_device eagle_s20.db -package EG4S20BG256
import_db [file join $root BOARD_A BOARD_A_Runs phy_1 BOARD_A_pr.db]
clear_sdc -user
read_sdc [file join $root source/video/constraints_source/timing.sdc]
read_sdc [file join $root constraints/resolution_cdc.sdc]
read_sdc [file join $root constraints/ui_style_cdc.sdc]
read_sdc [file join $root source/recovery/a_cdc.sdc]
update_timing -mode final
report_timing_summary -file independent_audit.timing -ep_num 100 -path_num 1
report_timing_status -file independent_audit.ts
report_timing_exception -file independent_audit.exceptions
check_timing -verbose -file timing_checks.txt
report_timing_ignored -file ignored.timing -ep_num 100 -path_num 1
report_route_status -drc
write_verilog routed.v
puts "BOARD_A_AUDIT_FINISHED"
exit
