set root [file dirname [file normalize [info script]]]
file mkdir [file join $root verification]
cd [file join $root verification]
import_device eagle_s20.db -package EG4S20BG256
import_db [file join $root BOARD_B BOARD_B_Runs phy_1 BOARD_B_pr.db]
clear_sdc -user
read_sdc [file join $root source/media/timing.sdc]
read_sdc [file join $root source/recovery/b_cdc.sdc]
update_timing -mode final
report_timing_summary -file independent_audit.timing -ep_num 100 -path_num 1
report_timing_status -file independent_audit.ts
report_timing_exception -file independent_audit.exceptions
check_timing -verbose -file timing_checks.txt
report_timing_ignored -file ignored.timing -ep_num 100 -path_num 1
report_route_status -drc
write_verilog routed.v
puts "BOARD_B_AUDIT_FINISHED"
exit
