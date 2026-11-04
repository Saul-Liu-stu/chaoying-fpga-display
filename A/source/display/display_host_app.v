`timescale 1ns/1ps
module display_host_app #(parameter FRAME_PIXELS=307200,TILE_PIXELS=23232,PCM_PREFILL=2048,NORMAL_HOLD_CYCLES=100000000,APP_CLK_HZ=100000000)(
 input wire clk,rst,enable,
 output wire send,output wire [111:0] send_info,input wire busy,
 output wire mem_we,output wire [8:0] mem_addr,output wire [7:0] mem_byte,
 input wire available,input wire [111:0] recv_info,output wire take,
 output wire [8:0] read_addr,input wire [7:0] read_byte,
 output wire sd_ncs,sd_dclk,sd_mosi,input wire sd_miso,
 output wire write_req,input wire write_req_ack,write_ready,
 output wire write_en,output wire [31:0] write_data,write_identity,display_identity,
 output wire display_valid,input wire write_done_valid,input wire [31:0] write_done_identity,
 input wire frame_valid,input wire [117:0] frame_pose,input wire transfer_fault,
 output wire [3:0] status,output wire [31:0] frames,
 input wire next_press,prev_press,short_press,chord_press,confirm_short,mode_select,
 output wire select_confirm_ready,
 input wire caption_request_toggle,caption_cancel_toggle,caption_request_expired,input wire [55:0] caption_payload,
 output wire caption_response_toggle,caption_response_good,caption_font_bad,output wire [31:0] caption_response_mask,
 output wire caption_we,output wire [9:0] caption_address,output wire [23:0] caption_glyph,
 output wire caption_map_we,output wire [6:0] caption_map_address,output wire [4:0] caption_map_slot,
 output wire [20:0] caption_lengths,output wire [2:0] caption_ready,
 output wire [117:0] scroll_pose,input wire caption_display_ready,output wire [1:0] remote_mode,
 output wire [1:0] wav_command,output wire wav_flush,wav_run,wav_clear,
 output wire wav_valid,output wire [15:0] wav_sample,
 input wire wav_flush_done,wav_sample_ready,input wire [12:0] wav_sample_room,
 output wire [7:0] wav_error,output wire [31:0] caption_candidate_identity,
 output wire [15:0] media_health,output reg [15:0] missing_images,output reg spectrum_select,
 output wire dimension_update,output wire [4:0] dimension_picture,output wire [21:0] dimension_size,
 output wire ui_style_we,output wire [11:0] ui_style_address,output wire [7:0] ui_style_byte,
 output wire ui_style_valid,output wire [119:0] ui_style_palette,output wire ui_style_failed,
 input wire hard_rst,restart_accepted,restart_complete,output wire restart_request,recovery_isolated);
 reg [15:0] remote_health;
 wire [31:0] publication,original_publication,cache_identity;
 wire [2:0] disabled_captions=media_health[13:11] | {3{media_health[14]}};
 wire [1:0] candidate_role=caption_candidate_identity[28:24]<=6?2'd0:caption_candidate_identity[28:24]<=9?2'd1:2'd2;
 wire [1:0] publication_role=publication[28:24]<=6?2'd0:publication[28:24]<=9?2'd1:2'd2;
 wire candidate_credit=caption_display_ready || (media_health[15] && disabled_captions[candidate_role]);
 wire publication_credit=caption_display_ready || (media_health[15] && disabled_captions[publication_role]);
 wire original_publication_valid,publication_valid;
 wire fast_send,fast_take,fast_reply,fast_publish,fast_confirmed,fast_candidate_valid,fast_lookup_enable;
 wire [111:0] fast_info;wire [31:0] fast_publication,fast_candidate_identity,fast_lookup_identity;
 wire [1:0] fast_lookup_mode;wire [4:0] fast_lookup_pic;wire [3:0] fast_held;wire [2:0] canvas_ready;
 wire [31:0] image_frames;reg [31:0] old_image_frames,total_frames,old_publication;reg select_fast;
 reg [31:0] publication_q;reg publication_valid_q;
 assign frames=total_frames;
 assign publication=select_fast?fast_publication:original_publication;
 assign publication_valid=select_fast?1'b1:original_publication_valid;
 assign caption_candidate_identity=fast_candidate_valid?fast_candidate_identity:write_identity;
 always @(posedge clk or posedge rst)begin
  if(rst)begin publication_q<=0;publication_valid_q<=0;end
  else begin
   publication_q<=publication;
   publication_valid_q<=publication_valid && (publication[30:29]!=2 || publication_credit);
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin old_image_frames<=0;total_frames<=0;old_publication<=0;select_fast<=0;end
  else begin
   old_image_frames<=image_frames;
   if(image_frames!=old_image_frames || fast_confirmed)total_frames<=total_frames+1'b1;
   if(original_publication_valid)old_publication<=original_publication;
   if(original_publication_valid && original_publication!=old_publication)select_fast<=0;
   if(fast_publish)select_fast<=1;
  end
 end
 wire [1:0] normal_style;wire allocate_ready,cache_commit,normal_auto;wire [1:0] allocate_bank;wire [15:0] normal_mask;wire [4:0] load_pic;wire [4:0] load_reply;wire navigation_pending;
 wire normal_fallback=normal_mask!=0 && (normal_mask & 16'hf007)==0;
 wire [1:0] lookup_mode;wire [4:0] lookup_pic;wire [31:0] lookup_identity;

 reg [2:0] owner;wire server_idle,image_idle,image_parked,image_reply;
 wire is_ui=recv_info[111:104]==16;wire ui_sel=owner==7 || (owner==0 && is_ui);
 wire ui_send,ui_take,ui_idle;wire [111:0] ui_info;wire [8:0] ui_read_address;
 wire is_fast=recv_info[111:104]==15;
 wire is_wav=recv_info[111:104]==14;wire wav_sel=owner==5 || (owner==0 && is_wav);
 wire config_send,config_take,config_idle;wire [111:0] config_info;wire [8:0] config_address;
 wire is_sector=recv_info[111:104]==1 || recv_info[111:104]==3;
 wire is_image=recv_info[111:104]>=5 && recv_info[111:104]<=7;
 wire is_caption=recv_info[111:104]>=9 && recv_info[111:104]<=12;
 wire cap_sel=owner==4 || (owner==0 && is_caption);
 wire cap_send,cap_take,cap_idle;wire [111:0] cap_info;wire [8:0] cap_raddr,frame_raddr;
 assign read_addr=owner==7?ui_read_address:owner==5?config_address:owner==4?cap_raddr:frame_raddr;
 wire is_control=recv_info[111:104]==8;
 wire control_sel=owner==3 || (owner==0 && is_control);
 wire csend,ctake,control_idle;wire [111:0] cinfo;
 wire sector_sel=owner==1 || (owner==0 && is_sector);
 wire image_sel=owner==2 || (owner==0 && is_image);
 wire ssend,swe,stake,fsend,ftake;wire [111:0] sinfo,finfo;wire [8:0] saddr;wire [7:0] sbyte;
 wire sd_ready,start,guard_idle,guard_done,sd_read,sd_valid,sd_end,sd_crc_bad;
 wire probe_sd_read,probe_idle,probe_done,probe_driver_reset,probe_reset,probe_start;
 wire [3:0] probe_fault;wire [31:0] probe_lba;
 wire [3:0] guard_fault,frame_fault;wire [31:0] lba,sd_lba;wire [8:0] buffer_addr;wire [7:0] buffer_byte,sd_byte;
 wire [15:0] server_status;wire [31:0] verified;
 assign send=owner==1?ssend:owner==2?fsend:owner==3?csend:owner==4?cap_send:owner==5?config_send:owner==6?fast_send:owner==7?ui_send:1'b0;
 assign send_info=owner==1?sinfo:owner==2?finfo:owner==4?cap_info:owner==5?config_info:owner==6?fast_info:owner==7?ui_info:cinfo;
 assign mem_we=owner==1 && swe;assign mem_addr=saddr;assign mem_byte=sbyte;
 assign take=ui_take || fast_take || stake || ftake || ctake || cap_take || config_take || (available && owner==0 && !is_sector && !is_image && !is_control && !is_caption && !is_wav && !is_fast && !is_ui);
 assign status=!enable?4'd3:frame_fault!=0?frame_fault:guard_fault!=0?4'd7:server_status==9?4'd9:!sd_ready?4'd2:frames!=0?4'd6:4'd4;
 reg [29:0] card_init_wait;reg card_init_failed;
 always @(posedge clk or posedge rst)begin
  if(rst)begin card_init_wait<=0;card_init_failed<=0;end
  else if(!enable || sd_ready)card_init_wait<=0;
  else if(card_init_wait==APP_CLK_HZ*10-1)card_init_failed<=1;
  else if(!card_init_failed)card_init_wait<=card_init_wait+1'b1;
 end
 wire local_media_fault=guard_fault!=0 || server_status==9 || frame_fault!=0 || transfer_fault || card_init_failed || recovery_isolated;
 assign media_health=remote_health | (local_media_fault?16'h0080:16'd0);
 always @(posedge clk or posedge rst)begin
  if(rst)begin remote_health<=0;missing_images<=0;spectrum_select<=0;end
  else if(available && control_sel && is_control && recv_info[103:102]==2'b10)begin
   spectrum_select<=recv_info[100];
   if(recv_info[101])missing_images<=recv_info[15:0];else remote_health<=recv_info[15:0];
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)owner<=0;
  else case(owner)
   0:if(fast_reply)owner<=6;else if(image_reply)owner<=2;else if(available)begin if(is_sector)owner<=1;else if(is_image)owner<=2;else if(is_control)owner<=3;else if(is_caption)owner<=4;else if(is_wav)owner<=5;else if(is_ui)owner<=7;end
   1:if(server_idle && !busy && !ssend)owner<=0;
   2:if((image_idle || image_parked) && !busy && !fsend)owner<=0;
   3:if(control_idle && !busy && !csend)owner<=0;
   4:if(cap_idle && !busy && !cap_send)owner<=0;
   5:if(config_idle && !busy && !config_send)owner<=0;
   6:if(!fast_reply && !busy && !fast_send)owner<=0;
   7:if(ui_idle && !busy && !ui_send)owner<=0;
  endcase
 end
 ui_style_receiver u_ui_style(.clk(clk),.rst(rst),.available(available && ui_sel && is_ui),.recv_info(recv_info),.take(ui_take),
  .read_addr(ui_read_address),.read_byte(read_byte),.send(ui_send),.send_info(ui_info),.busy(busy || owner!=7),.transaction_idle(ui_idle),
  .style_we(ui_style_we),.style_address(ui_style_address),.style_byte(ui_style_byte),.style_valid(ui_style_valid),.style_palette(ui_style_palette),.style_failed(ui_style_failed));
 control_host_scene u_controls(clk,rst,next_press,prev_press,short_press,chord_press,confirm_short,
  available && control_sel && is_control,recv_info,ctake,csend,cinfo,busy || owner!=3,control_idle,select_confirm_ready,load_reply,display_identity,normal_auto,remote_mode,normal_mask,mode_select,navigation_pending,normal_style,dimension_update,dimension_picture,dimension_size);
 tf_probe_supervisor #(.INIT_TIMEOUT(APP_CLK_HZ*10),.RETRY_DELAY(APP_CLK_HZ),.READ_TIMEOUT(APP_CLK_HZ/5*6)) u_probe_control(.clk(clk),.hard_reset(hard_rst),.monitor_enable(enable),.sd_ready(sd_ready),
  .normal_guard_fault(guard_fault),.probe_idle(probe_idle),.probe_done(probe_done),.probe_fault(probe_fault),
  .restart_accepted(restart_accepted),.restart_complete(restart_complete),.isolate(recovery_isolated),
  .driver_reset(probe_driver_reset),.probe_reset(probe_reset),.probe_start(probe_start),.restart_request(restart_request),
  .debug_state());
 sd_card_top u_sd(.clk(clk),.rst(rst || probe_driver_reset),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
  .sd_read_crc_bad(sd_crc_bad),.sd_init_done(sd_ready),.sd_sec_read(recovery_isolated?probe_sd_read:sd_read),.sd_sec_read_addr(recovery_isolated?probe_lba:sd_lba),
  .sd_sec_read_data(sd_byte),.sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
  .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
 lights_sector_guard #(.TIMEOUT_CYCLES(APP_CLK_HZ)) u_guard(.clk(clk),.rst(rst),.start(start && !recovery_isolated),.lba(lba),
  .idle(guard_idle),.done(guard_done),.fault(guard_fault),.buffer_addr(buffer_addr),.buffer_byte(buffer_byte),
  .sd_read(sd_read),.sd_lba(sd_lba),.sd_byte(sd_byte),.sd_valid(sd_valid && !recovery_isolated),.sd_end(sd_end && !recovery_isolated),.sd_crc_bad(sd_crc_bad));
 probe_sector_checker #(.TIMEOUT_CYCLES(APP_CLK_HZ)) u_probe_guard(.clk(clk),.rst(rst || probe_reset),.start(probe_start),
  .idle(probe_idle),.done(probe_done),.fault(probe_fault),.sd_read(probe_sd_read),.sd_lba(probe_lba),
  .sd_valid(sd_valid && recovery_isolated),.sd_end(sd_end && recovery_isolated),.sd_crc_bad(sd_crc_bad));
 pcm_packet_receiver #(.PREFILL_SAMPLES(PCM_PREFILL)) u_pcm_receiver(
  .clk(clk),.rst(rst),.available(available && wav_sel && is_wav),.recv_info(recv_info),.take(config_take),
  .read_addr(config_address),.read_byte(read_byte),.send(config_send),.send_info(config_info),.busy(busy || owner!=5),.transaction_idle(config_idle),
  .command_mode(wav_command),.flush_toggle(wav_flush),.run_pcm(wav_run),.clear_pcm(wav_clear),.flush_done(wav_flush_done),
  .sample_valid(wav_valid),.sample(wav_sample),.sample_ready(wav_sample_ready),.sample_room(wav_sample_room),.error_code(wav_error));
 sector_server #(.STALE_CYCLES(APP_CLK_HZ/2*3)) u_server(clk,rst,enable,sd_ready,ssend,sinfo,busy || owner!=1,swe,saddr,sbyte,
  available && sector_sel && is_sector,recv_info,stake,start,lba,guard_idle,guard_done,guard_fault,buffer_addr,buffer_byte,server_status,verified,server_idle);
 frame_receiver_scene #(.FRAME_PIXELS(FRAME_PIXELS),.TILE_PIXELS(TILE_PIXELS)) u_frame(clk,rst,available && image_sel && is_image,recv_info,ftake,frame_raddr,read_byte,
  fsend,finfo,busy || owner!=2,image_idle,image_parked,image_reply,write_req,write_req_ack,write_ready,write_en,write_data,
  write_identity,original_publication,original_publication_valid,write_done_valid,write_done_identity,frame_valid,frame_pose,transfer_fault,frame_fault,image_frames,
  allocate_ready,allocate_bank,display_identity,cache_commit,cache_identity,lookup_mode,lookup_pic,lookup_identity,canvas_ready,normal_fallback);
 scroll_cache #(.HOLD_CYCLES(NORMAL_HOLD_CYCLES)) u_scroll(clk,rst,publication_valid_q,publication_q,cache_commit,cache_identity,write_req,write_identity,
  frame_valid,frame_pose,normal_auto,next_press || prev_press || chord_press || navigation_pending,remote_mode,normal_mask,
  allocate_ready,allocate_bank,scroll_pose,display_identity,display_valid,load_pic,lookup_mode,lookup_pic,lookup_identity,fast_lookup_enable,fast_lookup_mode,fast_lookup_pic,fast_lookup_identity,fast_held,normal_style,load_reply);
cached_show_receiver u_cached_show(.clk(clk),.rst(rst),.available(available && is_fast),.recv_info(recv_info),.take(fast_take),
 .send(fast_send),.send_info(fast_info),.busy(busy || owner!=6),.reply_pending(fast_reply),
 .lookup_mode(fast_lookup_mode),.lookup_pic(fast_lookup_pic),.lookup_enable(fast_lookup_enable),.lookup_identity(fast_lookup_identity),
 .primary_identity(display_identity),.canvas_ready(canvas_ready),.held_banks(fast_held),.candidate_valid(fast_candidate_valid),.candidate_identity(fast_candidate_identity),
 .caption_ready(candidate_credit),.frame_valid(frame_valid),.frame_pose(frame_pose),.publish(fast_publish),.publication(fast_publication),.confirmed(fast_confirmed),.allow_normal_fallback(normal_fallback));
caption_host u_caption(clk,rst,available && cap_sel && is_caption,recv_info,cap_take,cap_send,cap_info,busy || owner!=4,cap_idle,cap_raddr,read_byte,
 caption_request_toggle,caption_cancel_toggle,caption_request_expired,caption_payload,
 caption_response_toggle,caption_response_good,caption_font_bad,caption_response_mask,
 caption_we,caption_address,caption_glyph,caption_map_we,caption_map_address,caption_map_slot,caption_lengths,caption_ready);
endmodule
