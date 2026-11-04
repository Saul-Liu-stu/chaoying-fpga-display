set_false_path -to [get_regs {u_link/tx_epoch_s0[*] u_link/rx_epoch_s0[*] u_link/u_wire/control_req_sync[0] u_link/u_wire/control_ack_sync[0]}]
set_max_delay 20 -datapath_only -from [get_regs {u_link/u_wire/control_hold[*]}] -to [get_regs {u_link/u_wire/control_info[*]}]
set_false_path -hold -from [get_regs {u_link/u_wire/control_hold[*]}] -to [get_regs {u_link/u_wire/control_info[*]}]
set_false_path -through [get_nets {u_link/recovery_reset_request}]
