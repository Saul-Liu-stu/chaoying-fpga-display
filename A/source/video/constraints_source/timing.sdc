

create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

derive_clocks

rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {net_clk_125} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
rename_clock -name {sdram_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[3]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]


set_false_path -from [get_clocks {audio_mclk}] -to [get_regs {u_I2S_receiver/S_i2s_bclk_1d u_I2S_receiver/S_i2s_lrck_1d u_I2S_receiver/S_i2s_dout_1d}]



set_false_path -through [get_nets {u_startup_reset/reset_request}]

create_clock -name rx_clock -period 8 -waveform {0 4} [get_ports rx_clk]
set_input_delay -clock rx_clock -max 2.6 [get_ports {rxd[*] rx_ctl}]
set_input_delay -clock rx_clock -min 1.0 [get_ports {rxd[*] rx_ctl}]
set_input_delay -clock rx_clock -clock_fall -add_delay -max 2.6 [get_ports {rxd[*] rx_ctl}]
set_input_delay -clock rx_clock -clock_fall -add_delay -min 1.0 [get_ports {rxd[*] rx_ctl}]
create_generated_clock -name phy_capture -source [get_pins {sys_pll_m0/pll_inst.clkc[1]}] -master_clock net_clk_125 -edges {1 2 3} -edge_shift {2 2 2} [get_ports tx_clk]
set_output_delay -clock phy_capture -max 1.0 [get_ports {txd[*] tx_ctl}]
set_output_delay -clock phy_capture -min -1.0 [get_ports {txd[*] tx_ctl}]
set_output_delay -clock phy_capture -clock_fall -add_delay -max 1.0 [get_ports {txd[*] tx_ctl}]
set_output_delay -clock phy_capture -clock_fall -add_delay -min -1.0 [get_ports {txd[*] tx_ctl}]

set_false_path -to [get_regs {sd_card_bmp_m0/u_wav_pcm/release_s1[*] sd_card_bmp_m0/u_wav_pcm/ack_s1 sd_card_bmp_m0/u_wav_pcm/publish_s1[*] sd_card_bmp_m0/u_wav_pcm/flush_s1 sd_card_bmp_m0/u_wav_pcm/run_s1}]
set_max_delay 20 -datapath_only -from [get_regs {sd_card_bmp_m0/u_host/u_pcm_receiver/command_mode[*]}] -to [get_regs {sd_card_bmp_m0/u_wav_pcm/selected_mode[*]}]
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_host/u_pcm_receiver/command_mode[*]}] -to [get_regs {sd_card_bmp_m0/u_wav_pcm/selected_mode[*]}]
set_max_delay 7.5 -datapath_only -from [get_regs {sd_card_bmp_m0/u_wire/send_request}] -to [get_regs {sd_card_bmp_m0/u_wire/send_req_sync[0]}]
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_wire/send_request}] -to [get_regs {sd_card_bmp_m0/u_wire/send_req_sync[0]}]
set_max_delay 7.5 -datapath_only -from [get_regs {sd_card_bmp_m0/u_wire/send_ack}] -to [get_regs {sd_card_bmp_m0/u_wire/send_ack_sync[0]}]
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_wire/send_ack}] -to [get_regs {sd_card_bmp_m0/u_wire/send_ack_sync[0]}]
set_max_delay 7.5 -datapath_only -from [get_regs {sd_card_bmp_m0/u_wire/recv_request}] -to [get_regs {sd_card_bmp_m0/u_wire/recv_req_sync[0]}]
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_wire/recv_request}] -to [get_regs {sd_card_bmp_m0/u_wire/recv_req_sync[0]}]
set_max_delay 7.5 -datapath_only -from [get_regs {sd_card_bmp_m0/u_wire/recv_ack}] -to [get_regs {sd_card_bmp_m0/u_wire/recv_ack_sync[0]}]
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_wire/recv_ack}] -to [get_regs {sd_card_bmp_m0/u_wire/recv_ack_sync[0]}]
set_max_delay 20 -datapath_only -from [get_regs {sd_card_bmp_m0/u_wire/send_hold[*]}] -to [get_regs {sd_card_bmp_m0/u_wire/tx_info[*]}]
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_wire/send_hold[*]}] -to [get_regs {sd_card_bmp_m0/u_wire/tx_info[*]}]
set_max_delay 20 -datapath_only -from [get_regs {sd_card_bmp_m0/u_wire/recv_hold[*]}] -to [get_regs {sd_card_bmp_m0/u_wire/recv_info[*]}]
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_wire/recv_hold[*]}] -to [get_regs {sd_card_bmp_m0/u_wire/recv_info[*]}]
set_false_path -to [get_regs {sd_card_bmp_m0/tx_enable_sync[0] sd_card_bmp_m0/rx_enable_sync[0] sd_card_bmp_m0/app_enable_sync[0]}]
set_false_path -through [get_nets {sd_card_bmp_m0/rx_async_request}]
set_false_path -from [get_ports mdio]
set_max_delay 20 -to [get_ports {mdio mdc}]

set_false_path -from [get_ports {sw_caption}]
set_false_path -from [get_ports {sw_scope}]

set_false_path -from [get_ports {sw_settings}]
set_false_path -to [get_regs {sd_card_bmp_m0/settings_block_sync[0]}]

set_false_path -from [get_ports {key1 key2 key3 sw_mode}]

set_max_delay 30 -datapath_only -from [get_regs {u_media_diagnostics/request_toggle}] -to [get_regs {u_media_diagnostics/request_sync[0]}]
set_false_path -hold -from [get_regs {u_media_diagnostics/request_toggle}] -to [get_regs {u_media_diagnostics/request_sync[0]}]
set_max_delay 7.5 -datapath_only -from [get_regs {u_media_diagnostics/ack_toggle}] -to [get_regs {u_media_diagnostics/ack_sync[0]}]
set_false_path -hold -from [get_regs {u_media_diagnostics/ack_toggle}] -to [get_regs {u_media_diagnostics/ack_sync[0]}]
set_max_delay 20 -datapath_only -from [get_regs {u_media_diagnostics/payload_hold[*]}] -to [get_regs {u_media_diagnostics/payload_sample[*]}]
set_false_path -hold -from [get_regs {u_media_diagnostics/payload_hold[*]}] -to [get_regs {u_media_diagnostics/payload_sample[*]}]
