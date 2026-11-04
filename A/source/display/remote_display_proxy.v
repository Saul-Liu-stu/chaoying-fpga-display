`timescale 1ns/1ps
module remote_display_proxy #(parameter integer CLK_FREQ_HZ=100_000_000)(
    input wire r5_frame_valid,input wire [117:0] r5_frame_pose,output wire [117:0] r5_pose,
    input wire write_ready,
    output wire [20:0] write_rect_first,write_rect_length,
    output wire [10:0] write_rect_width,
    output wire [11:0] write_rect_jump,
    input wire write_done_valid,presented_identity_valid,frame_transfer_fault,
    input wire [31:0] write_done_identity,presented_identity,
    output wire [31:0] write_identity,display_identity,frame_authorizations,
    input wire clk,rst,key_next,key_auto,key_prev,mode_select,settings_block,
    output wire [31:0] debug_observe,
    output wire [3:0] state_code,
    input wire [15:0] bmp_width,bmp_height,
    output wire display_valid,
    input wire read_active_buf_async,read_active_valid_async,write_finish_toggle,play_started_async,
    input wire presented_bank_async,presented_valid_async,
    output wire [1:0] write_buf_idx,disp_buf_idx,
    output wire write_req,
    input wire write_req_ack,
    output wire write_en,
    output wire [31:0] write_data,
    output wire SD_nCS,SD_DCLK,SD_MOSI,
    output wire caption_we,
    output wire [9:0] caption_address,
    output wire [23:0] caption_glyph,
    input wire caption_request_toggle,caption_cancel_toggle,caption_request_expired,
    input wire [55:0] caption_request_payload,
    output wire caption_response_toggle,caption_response_good,caption_font_bad,
    output wire caption_map_we,
    output wire [6:0] caption_map_address,
    output wire [4:0] caption_map_slot,
    output wire [31:0] caption_response_mask,
    output wire caption_active,caption_bank,
    output wire [1:0] caption_banks,
    input wire caption_commit_ready,
    output wire [1:0] caption_role,
    output wire [6:0] caption_count,
    output wire [95:0] caption_source_key,
    input wire sys_clk,sys_rst,net_clk,net_rst,
    input wire hard_rst,hard_sys_rst,hard_net_rst,output wire soft_reset,
    input wire rx_clk,rx_ctl,input wire [3:0] rxd,
    output wire tx_clk,tx_ctl,output wire [3:0] txd,inout wire mdio,mdc,
    input wire SD_MISO,
    input wire audio_pixel_clk,audio_pixel_rst,tone_tick,
    input wire [23:0] tone_left,tone_right,
    output wire pcm_tick,output wire [23:0] pcm_left,pcm_right,output wire [1:0] pcm_mode,
    output wire [15:0] media_health,missing_images,output wire spectrum_select,
    output wire dimension_update,output wire [4:0] dimension_picture,output wire [21:0] dimension_size,
    output wire ui_style_we,output wire [11:0] ui_style_address,output wire [7:0] ui_style_byte,
    output wire ui_style_valid,output wire [119:0] ui_style_palette,output wire ui_style_failed
);

 wire rx_logic_clk,rx_rst;wire rx_async_request=rst || sys_rst;
 EG_LOGIC_BUFG rx_clock_buffer(.i(rx_clk),.o(rx_logic_clk));
 link_reset rx_reset(rx_logic_clk,rx_async_request,rx_rst);
 wire ready,link_up,mdc_value;wire [15:0] phy_fault,phy_status;
 assign mdc=mdc_value?1'bz:1'b0;
 link_phy_setup #(.BOARD_ID(1)) u_phy(sys_clk,sys_rst,mdio,mdc_value,ready,link_up,phy_fault,phy_status);
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg [2:0] tx_enable_sync,rx_enable_sync,app_enable_sync;
 always @(posedge net_clk or posedge net_rst)if(net_rst)tx_enable_sync<=0;else tx_enable_sync<={tx_enable_sync[1:0],ready && link_up};
 always @(posedge rx_logic_clk or posedge rx_rst)if(rx_rst)rx_enable_sync<=0;else rx_enable_sync<={rx_enable_sync[1:0],ready && link_up};
 always @(posedge clk or posedge rst)if(rst)app_enable_sync<=0;else app_enable_sync<={app_enable_sync[1:0],ready && link_up};
 wire [7:0] tx_byte,rx_byte,raw_byte;wire tx_valid,rx_valid,rx_error,raw_valid,raw_error,tap;
 link_rgmii u_io(net_clk,net_rst,tx_byte,tx_valid,rx_logic_clk,rx_rst,rxd,rx_ctl,tx_clk,txd,tx_ctl,raw_byte,raw_valid,raw_error,tap);
 link_rx_pipeline rx_tuple(rx_logic_clk,rx_rst,raw_byte,raw_valid,raw_error,rx_byte,rx_valid,rx_error);
 wire host_send,busy,host_mem_we,available,host_take;wire [111:0] host_info,recv_info;wire [8:0] mem_addr,read_addr;wire [7:0] mem_byte,read_byte;
 wire rec_send,rec_take,rec_block,rec_freeze,rec_accepted,rec_complete,rec_exhausted,rec_request,rec_isolated;
 wire [111:0] rec_info,control_info;wire control_available;wire [15:0] epoch;
 wire hard_rx_rst;link_reset u_rx_hard_reset(rx_logic_clk,hard_rst || hard_sys_rst,hard_rx_rst);
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg [15:0] tx_epoch_s0,tx_epoch_s1,tx_epoch_s2,rx_epoch_s0,rx_epoch_s1,rx_epoch_s2;
 always @(posedge net_clk or posedge hard_net_rst)if(hard_net_rst)begin tx_epoch_s0<=0;tx_epoch_s1<=0;tx_epoch_s2<=0;end
  else begin tx_epoch_s0<=epoch;tx_epoch_s1<=tx_epoch_s0;tx_epoch_s2<=tx_epoch_s1;end
 always @(posedge rx_logic_clk or posedge hard_rx_rst)if(hard_rx_rst)begin rx_epoch_s0<=0;rx_epoch_s1<=0;rx_epoch_s2<=0;end
  else begin rx_epoch_s0<=epoch;rx_epoch_s1<=rx_epoch_s0;rx_epoch_s2<=rx_epoch_s1;end
 sector_wire_avpipe #(.BOARD_ID(1)) u_wire(
  .app_clk(clk),.app_rst(rst),.tx_clk(net_clk),.tx_rst(net_rst),.rx_clk(rx_logic_clk),.rx_rst(rx_rst),
  .tx_enable(tx_enable_sync[2]),.rx_enable(rx_enable_sync[2]),.tx_epoch(tx_epoch_s2),.rx_epoch(rx_epoch_s2),
  .control_available(control_available),.control_info(control_info),.control_take(rec_take),
  .send(rec_send || host_send),.send_info(rec_send?rec_info:host_info),.busy(busy),
  .mem_we(host_mem_we),.mem_addr(mem_addr),.mem_byte(mem_byte),
  .available(available),.recv_info(recv_info),.take(host_take || (available && rec_freeze)),.read_addr(read_addr),.read_byte(read_byte),
  .tx_byte(tx_byte),.tx_valid(tx_valid),.rx_byte(rx_byte),.rx_valid(rx_valid),.rx_error(rx_error));
 restart_master #(.QUIET_CYCLES(16),.RETRY_CYCLES(CLK_FREQ_HZ/5),.HOLD_CYCLES(CLK_FREQ_HZ/25)) u_recovery(
  .clk(clk),.hard_reset(hard_rst),.trigger(rec_request),.busy(busy),.available(control_available),.app_tx_activity(host_mem_we || host_send),
  .recv_info(control_info),
  .send(rec_send),.send_info(rec_info),.take(rec_take),.block_app(rec_block),.freeze_rx(rec_freeze),.soft_reset(soft_reset),
  .accepted(rec_accepted),.complete(rec_complete),.exhausted(rec_exhausted),.epoch(epoch));
 wire [31:0] frames;
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg [2:0] settings_block_sync;
 always @(posedge clk or posedge rst)
  if(rst)settings_block_sync<=0;else settings_block_sync<={settings_block_sync[1:0],settings_block};
 wire next_press,prev_press,short_press,chord_press,confirm_short,select_confirm_ready;
 lights_direct_keys #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_keys(
  .clk(clk),.rst(rst || settings_block_sync[2]),.previous(key_prev),.next(key_next),.confirm(key_auto),
  .prev_press(prev_press),.next_press(next_press),.confirm_press(short_press),
  .held_previous(),.held_next(),.held_confirm());
 assign chord_press=1'b0;
 assign confirm_short=short_press && select_confirm_ready;
 wire mode_held;
 lights_scene_button #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(20)) u_mode(
  .clk(clk),.rst(rst),.button_in(mode_select),.pressed(mode_held));
 reg mode_effective;
 reg [2:0] mode_warmup;
 always @(posedge clk or posedge rst)begin
  if(rst)begin mode_effective<=0;mode_warmup<=0;end
  else begin
   mode_warmup<={mode_warmup[1:0],1'b1};
   if(mode_warmup[2] && !settings_block_sync[2])mode_effective<=!mode_held;
  end
 end
 wire [1:0] wav_command;wire wav_flush,wav_run,wav_clear,wav_valid,wav_flush_done,wav_sample_ready,wav_underflow;
 wire [15:0] wav_sample;wire [12:0] wav_sample_room;wire [7:0] wav_error;
 wire [23:0] pcm_left_raw,pcm_right_raw;wire [1:0] pcm_mode_raw;
 lights_r6_pcm_bridge #(.BANK_BITS(11),.BANK_COUNT(3)) u_wav_pcm(.sd_clk(clk),.sd_rst(rst),.pixel_clk(audio_pixel_clk),.pixel_rst(audio_pixel_rst),
  .command_mode(wav_command),.flush_toggle(wav_flush),.run_sd(wav_run),.clear_sd(wav_clear),.flush_done(wav_flush_done),
  .sample_valid(wav_valid),.sample_data(wav_sample),.sample_ready(wav_sample_ready),.sample_room(wav_sample_room),
  .tick(tone_tick),.tone_left(tone_left),.tone_right(tone_right),.audio_valid(pcm_tick),.audio_left(pcm_left_raw),.audio_right(pcm_right_raw),.underflow(wav_underflow),.active_mode(pcm_mode_raw));
 (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [2:0] recovery_mute_sync;
 always @(posedge audio_pixel_clk or posedge audio_pixel_rst)if(audio_pixel_rst)recovery_mute_sync<=0;
  else recovery_mute_sync<={recovery_mute_sync[1:0],rec_isolated};
 assign pcm_left=recovery_mute_sync[2]?24'd0:pcm_left_raw;
 assign pcm_right=recovery_mute_sync[2]?24'd0:pcm_right_raw;
 assign pcm_mode=recovery_mute_sync[2]?2'd0:pcm_mode_raw;
 wire [20:0] text_lengths;wire [2:0] text_ready;wire [1:0] remote_mode;
 wire [31:0] caption_candidate_identity;
 display_host_app #(.PCM_PREFILL(6144),.NORMAL_HOLD_CYCLES(CLK_FREQ_HZ),.APP_CLK_HZ(CLK_FREQ_HZ)) u_host(clk,rst,app_enable_sync[2],host_send,host_info,busy || rec_block,host_mem_we,mem_addr,mem_byte,available && !rec_freeze,recv_info,host_take,read_addr,read_byte,
  SD_nCS,SD_DCLK,SD_MOSI,SD_MISO,write_req,write_req_ack,write_ready,write_en,write_data,write_identity,display_identity,display_valid,
  write_done_valid,write_done_identity,r5_frame_valid,r5_frame_pose,frame_transfer_fault,state_code,frames,next_press,prev_press,short_press,chord_press,confirm_short,mode_effective,select_confirm_ready,
 caption_request_toggle,caption_cancel_toggle,caption_request_expired,caption_request_payload,
 caption_response_toggle,caption_response_good,caption_font_bad,caption_response_mask,
 caption_we,caption_address,caption_glyph,caption_map_we,caption_map_address,caption_map_slot,text_lengths,text_ready,r5_pose,caption_commit_ready,remote_mode,wav_command,wav_flush,wav_run,wav_clear,wav_valid,wav_sample,
 wav_flush_done,wav_sample_ready,wav_sample_room,wav_error,caption_candidate_identity,media_health,missing_images,spectrum_select,dimension_update,dimension_picture,dimension_size,ui_style_we,ui_style_address,ui_style_byte,ui_style_valid,ui_style_palette,ui_style_failed,hard_rst,rec_accepted,rec_complete,rec_request,rec_isolated);
 assign write_buf_idx=write_identity[1:0];assign disp_buf_idx=display_identity[1:0];
 wire canvas_write=write_identity[30:29]==1 && write_identity[2];
 wire tile_write=canvas_write && write_identity[28:24]!=0;
 wire [9:0] tile_x=write_identity[28:24]==4?10'd36:write_identity[28:24]==7?10'd232:10'd428;
 reg [20:0] normal_first;
 always @*case(write_identity[1:0])
  0:normal_first=21'd306560;1:normal_first=21'd613760;2:normal_first=21'd920960;default:normal_first=21'd1228160;
 endcase
 assign write_rect_first=tile_write?21'd1417600+tile_x:canvas_write?21'd1535360:normal_first;
 assign write_rect_length=tile_write?21'd23232:21'd307200;
 assign write_rect_width=tile_write?11'd176:11'd640;
 assign write_rect_jump=tile_write?12'd815:12'd1279;

 reg [31:0] actual_shown;
 always @(posedge clk or posedge rst)if(rst)actual_shown<=0;else if(r5_frame_valid)actual_shown<=r5_frame_pose[117:86];
 reg select_armed;
 always @(posedge clk or posedge rst)if(rst)select_armed<=0;
  else if(!display_valid || display_identity[30:29]!=1)select_armed<=0;
  else if(remote_mode==1)select_armed<=1;
 wire [31:0] page_target=r5_pose[53:22];
 wire prewarming=select_armed && display_identity[30:29]==1 && remote_mode==2;
 wire [31:0] caption_view=page_target[31] && page_target[30:29]==2?page_target:
  display_identity[30:29]==2?display_identity:
  prewarming?{1'b1,2'd2,display_identity[28:3],1'b0,display_identity[1:0]}:display_identity;
 assign caption_role=caption_view[28:24]<=6?0:caption_view[28:24]<=9?1:2;
 assign caption_active=display_valid && caption_view[30:29]==2 && text_ready[caption_role] && !caption_font_bad && !(media_health[15] && (media_health[14] || media_health[11+caption_role]));
 assign caption_count=text_lengths[caption_role*7 +: 7];
 assign caption_bank=caption_view[0];assign caption_banks=2'b11;
 wire shown_role=actual_shown[31] && actual_shown[30:29]==2 &&
  (caption_role==0?actual_shown[28:24]>=4 && actual_shown[28:24]<=6:caption_role==1?actual_shown[28:24]>=7 && actual_shown[28:24]<=9:actual_shown[28:24]>=10 && actual_shown[28:24]<=12);
 wire prepared_role=caption_candidate_identity[31] && caption_candidate_identity[30:29]==2 &&
  (caption_role==0?caption_candidate_identity[28:24]>=4 && caption_candidate_identity[28:24]<=6:caption_role==1?caption_candidate_identity[28:24]>=7 && caption_candidate_identity[28:24]<=9:caption_candidate_identity[28:24]>=10 && caption_candidate_identity[28:24]<=12);
 assign frame_authorizations={caption_active && prepared_role,caption_active && shown_role,
  caption_active && prepared_role?{caption_candidate_identity[28:16],caption_candidate_identity[1:0]}:15'd0,
  caption_active && shown_role?{actual_shown[28:16],actual_shown[1:0]}:15'd0};
 assign caption_source_key={caption_candidate_identity,caption_view,actual_shown};assign debug_observe=0;
endmodule
