set_max_delay 7.5 -datapath_only -from [get_regs {sd_card_bmp_m0/u_host/u_ui_style/style_valid}] -to [get_regs {u_select_overlay/style_sync[0]}]
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_host/u_ui_style/style_valid}] -to [get_regs {u_select_overlay/style_sync[0]}]
set_max_delay 30.0 -datapath_only -from [get_regs {sd_card_bmp_m0/u_host/u_ui_style/style_palette[*]}] -to [get_regs {u_select_overlay/style_palette_pixel[*]}]
set_false_path -hold -from [get_regs {sd_card_bmp_m0/u_host/u_ui_style/style_palette[*]}] -to [get_regs {u_select_overlay/style_palette_pixel[*]}]
