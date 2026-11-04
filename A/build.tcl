set root [file dirname [file normalize [info script]]]
cd [file join $root BOARD_A]
import_device eagle_s20.db -package EG4S20BG256
open_project BOARD_A.al
launch_runs syn_1 -jobs 6
wait_run syn_1 -quiet
launch_runs phy_1 -jobs 6
wait_run phy_1 -quiet
close_project
file mkdir [file join $root verification]
cd [file join $root verification]
import_db [file join $root BOARD_A BOARD_A_Runs phy_1 BOARD_A_pr.db]
clear_sdc -user
read_sdc [file join $root source/video/constraints_source/timing.sdc]
read_sdc [file join $root constraints/resolution_cdc.sdc]
read_sdc [file join $root constraints/ui_style_cdc.sdc]
read_sdc [file join $root source/recovery/a_cdc.sdc]
update_timing -mode final
report_timing_summary -file independent.timing -ep_num 100 -path_num 1
report_timing_status -file independent.ts
report_timing_exception -file independent.exceptions
report_route_status -drc
puts "BOARD_A_BUILD_AND_STA_FINISHED"
exit
