`timescale 1ns/1ps
module media_scene_app #(parameter TARGET_WIDTH=640,TARGET_HEIGHT=480,TILE_WIDTH=176,TILE_HEIGHT=132,
 CLK_FREQ_HZ=50000000,AUTO_PLAY_MS=1000,EXPLAIN_MS=2500,POLL_CYCLES=100000)(
 input wire clk,rst,enable,output wire send,output wire [111:0] send_info,input wire busy,
 output wire mem_we,output wire [8:0] mem_addr,output wire [7:0] mem_byte,
 input wire available,input wire [111:0] recv_info,output wire take,
 output wire [8:0] read_addr,input wire [7:0] read_byte,output wire [15:0] status,output reg [31:0] decoded_frames,input wire spectrum_select);
 localparam WAIT=0,SOURCE_START=1,SOURCE_WAIT=2,BG_START=3,BG_SEND=4,TILE_QUERY=5,TILE_START=6,TILE_WAIT=7,SHOW_START=8,SHOW_WAIT=9,PUBLISH=10,BLOCK=11,PF_MAP=12,PF_START=13,PF_WAIT=14,PROBE_WAIT=15,LOAD_START=16;
 reg [4:0] pf_pic,pf_cursor,last_prefetch;reg [3:0] pf_index;reg manual_pending,normal_sync_armed;wire [4:0] prefetch_pic,rendered_pic;wire [1:0] rendered_mode;
 reg [1:0] pf_mode;
 reg need_prepare;reg [31:0] prepare_mark;wire [31:0] prepared_serial;wire [55:0] prepared_payload;
 localparam F_IDLE=0,F_PREP=1,F_SEND=2,F_WAIT=3,F_FALLBACK=4,F_PUBLISH=5,F_BLOCK=6;
 reg [2:0] foreground_state;reg fast_start,fast_sync,reprobe_after_background;
 wire fast_idle,fast_request,fast_waiting,fast_send,fast_take,fast_done,fast_hit;wire [111:0] fast_info;
 wire foreground_idle=foreground_state==F_IDLE;
 reg [4:0] state;reg mount_good,passed,bad_frame,canvas_built,cancelled,canvas_prefilling;
 reg [2:0] owner;reg [1:0] cmd_mode,tile;reg [4:0] cmd_pic;reg [3:0] cmd_index,load_index;
 reg load_start,bg_begin,show_begin,bg_request,raw_seen,fit_seen,frame_seen;
 reg [2:0] upload_op;reg [18:0] bg_count;reg [10:0] bg_x,bg_y;
 wire sd_ready,sd_read,sd_valid,sd_end;wire [31:0] sd_lba,transfers;wire [7:0] sd_byte;
 wire [3:0] remote_fault;wire csend,cwe,ctake,client_idle;wire [111:0] cinfo;wire [8:0] caddr,craddr;wire [7:0] cbyte;
 wire fsend,fwe,ftake,frame_request,frame_waiting,frame_done,cache_hit;wire [111:0] finfo;wire [8:0] faddr;wire [7:0] fbyte;
 wire mode_select,controls_ready,scene_navigation_ready;
 wire psend,ptake,poll_request,poll_idle,auto_snapshot;wire [111:0] pinfo;wire [2:0] gesture;
 wire cap_request,cap_idle,cap_send,cap_take,cap_we;wire [111:0] cap_info;wire [8:0] cap_addr;wire [7:0] cap_byte;
 wire wav_request,wav_done,wav_send,wav_take,wav_we;wire [111:0] wav_info;wire [8:0] wav_address;wire [7:0] wav_byte;
  wire fast_kind=recv_info[111:104]==8'h8f;
  wire wav_kind=recv_info[111:104]==8'h8e;
  wire cap_kind=recv_info[111:104]>=8'h89 && recv_info[111:104]<=8'h8c;
 wire client_kind=recv_info[111:104]==2 || recv_info[111:104]==4;
 wire frame_kind=recv_info[111:104]>=8'h85 && recv_info[111:104]<=8'h87;
 wire control_kind=recv_info[111:104]==8'h88;
 wire ui_reply_kind=recv_info[111:104]==8'h90;
 wire ui_request,ui_send,ui_take,ui_mem_we,ui_block_valid,ui_block_done,ui_block_good,ui_block_read,ui_done,ui_valid,ui_failed;
 wire [111:0] ui_info;wire [8:0] ui_mem_addr,ui_block_addr;wire [7:0] ui_mem_byte,ui_block_byte;
 wire [2:0] ui_block_index;wire [31:0] ui_file_crc,ui_block_crc;
 wire ui_found,ui_duplicate;wire [31:0] ui_cluster,ui_size;
 wire ui_sector_request,ui_sector_release,ui_sector_grant,ui_sector_done;
 wire [31:0] ui_sector_lba;wire [8:0] ui_buffer_addr;wire [7:0] ui_buffer_byte;
 wire shared_font_request,shared_font_release,shared_font_grant,shared_font_done;
 wire [31:0] shared_font_lba;wire [8:0] shared_font_address;wire [7:0] shared_font_byte;
 wire [119:0] ui_palette;
 wire drop=available && ((!client_kind && !frame_kind && !control_kind && !cap_kind && !wav_kind && !fast_kind && !ui_reply_kind) || (client_kind && client_idle) || (frame_kind && !frame_waiting) || (control_kind && !poll_request) || (cap_kind && !cap_request) || (fast_kind && !fast_waiting) || (ui_reply_kind && !ui_request));
 assign send=owner==1?csend:owner==2?fsend:owner==3?psend:owner==4?cap_send:owner==5?wav_send:owner==6?fast_send:owner==7?ui_send:1'b0;assign send_info=owner==1?cinfo:owner==2?finfo:owner==4?cap_info:owner==5?wav_info:owner==6?fast_info:owner==7?ui_info:pinfo;
 assign mem_we=owner==1?cwe:owner==2?fwe:owner==4?cap_we:owner==5?wav_we:owner==7?ui_mem_we:1'b0;assign mem_addr=owner==1?caddr:owner==4?cap_addr:owner==5?wav_address:owner==7?ui_mem_addr:faddr;assign mem_byte=owner==1?cbyte:owner==4?cap_byte:owner==5?wav_byte:owner==7?ui_mem_byte:fbyte;
 assign take=ui_take || fast_take || ctake || ftake || ptake || cap_take || wav_take || (available && wav_kind && !wav_request) || drop;assign read_addr=craddr;
 always @(posedge clk or posedge rst)begin
  if(rst)owner<=1;else case(owner)
   0:if(wav_request)owner<=5;else if(poll_request)owner<=3;else if(fast_request)owner<=6;else if(frame_request)owner<=2;else if(!client_idle || sd_read)owner<=1;else if(cap_request)owner<=4;else if(ui_request)owner<=7;
   1:if(client_idle && !busy)owner<=0;
   2:if(!frame_request && !busy)owner<=0;
   3:if(poll_idle && !busy && !psend)owner<=0;
   4:if(!cap_request && !busy && !cap_send)owner<=0;
    5:if(!wav_request && !busy && !wav_send)owner<=0;
   6:if(!fast_request && !busy && !fast_send)owner<=0;
   7:if(!ui_request && !busy && !ui_send)owner<=0;
  endcase
 end
 remote_sd_client u_remote(clk,rst,enable,passed,csend,cinfo,busy || owner!=1,cwe,caddr,cbyte,
  available && client_kind && !client_idle,recv_info,ctake,craddr,read_byte,
  sd_ready,sd_read && (owner==1 || (owner==0 && !frame_request)),sd_lba,sd_byte,sd_valid,sd_end,remote_fault,transfers,client_idle);
 wire idle,catalog_ready,source_success,media_write_req,image_begin,opened,raw_valid,media_fault,font_found,font_duplicate;
 wire [4:0] image_count,source_number;wire [15:0] catalog_mask;wire [7:0] error_code;wire [3:0] media_state;
 wire [10:0] sw,sh;wire [23:0] raw_pixel,fit_pixel;wire [2:0] caption_ready;wire [20:0] caption_lengths;wire [23:0] caption_errors;
 reg [21:0] source_dimensions[0:15];reg [15:0] dimensions_valid;
 wire [4:0] dimension_cursor;
 wire [3:0] dimension_slot=dimension_cursor[4:1];
 wire [21:0] dimension_size=dimensions_valid[dimension_slot]?source_dimensions[dimension_slot]:22'd0;
 wire [4:0] dimension_picture={1'b0,dimension_slot}+5'd1;
 wire [15:0] dimension_word={dimension_picture,dimension_cursor[0]?dimension_size[10:0]:dimension_size[21:11]};
 always @(posedge clk)if(image_begin && source_number>=1 && source_number<=16)source_dimensions[source_number-1'b1]<={sw,sh};
 always @(posedge clk or posedge rst)
  if(rst)dimensions_valid<=0;
  else if(image_begin && source_number>=1 && source_number<=16)dimensions_valid[source_number-1'b1]<=1;
 wire fit_ready,fit_valid,fit_done,pixel_ready,write_ack,normal_ready,query_valid;
 wire [15:0] available_mask;wire [4:0] normal_count,scene_query;wire [3:0] query_index;
 wire [1:0] requested_mode,shown_mode;wire command_valid,command_ready,select_cancel,scene_auto,confirm_ready,shown_valid;
 wire [3:0] command_index;wire [4:0] shown_pic;
 wire explain_prefetch=shown_mode==2 && requested_mode==2 && rendered_mode==2 && rendered_pic==shown_pic &&
   prefetch_pic!=shown_pic && prefetch_pic>=(shown_pic<=6?5'd4:shown_pic<=9?5'd7:5'd10) && prefetch_pic<=(shown_pic<=6?5'd6:shown_pic<=9?5'd9:5'd12);
 wire normal_prefetch_due=scene_auto && shown_mode==0 && requested_mode==0 &&
   prefetch_pic!=0 && prefetch_pic!=last_prefetch && !manual_pending;
 wire background_dwell=(state==PF_MAP || state==PF_START || state==PF_WAIT) ||
   (canvas_prefilling && (state==BG_START || state==BG_SEND || state==TILE_QUERY || state==TILE_START || state==TILE_WAIT));
 wire tile_phase=state==TILE_QUERY || state==TILE_START || state==TILE_WAIT;
 wire [4:0] tile_pic=tile==0?5'd4:tile==1?5'd7:5'd10;
 wire tile_query_valid;wire [3:0] tile_query_index;
 wire font_bad;
 wire [2:0] wav_found,wav_duplicate;
 wire bgm_found,bgm_duplicate;wire [31:0] bgm_cluster,bgm_size;wire background_context;reg bgm_failed;
 wire [1:0] wav_command;
 wire [7:0] wav_error;wire wav_run;
 reg audio_preflight_done;reg [1:0] probe_audio,probe_slot;reg [1:0] probe_state;
 wire wav_player_idle;
 always @(posedge clk or posedge rst)begin
  if(rst)begin audio_preflight_done<=0;probe_audio<=0;probe_slot<=1;probe_state<=0;end
  else if(!audio_preflight_done)case(probe_state)
   0:if(catalog_ready)begin probe_audio<=1;probe_slot<=1;probe_state<=1;end
   1:if(wav_command==probe_slot && (wav_run || wav_error!=0))begin probe_audio<=0;probe_state<=2;end
   2:if(wav_command==0 && wav_player_idle)begin
    if(probe_slot==3)audio_preflight_done<=1;
    else begin probe_slot<=probe_slot+1'b1;probe_audio<=probe_slot+1'b1;probe_state<=1;end
   end
  endcase
 end
 wire [2:0] font_invalid_roles;
 wire font_unusable=!font_found || font_duplicate || font_bad;
 wire [2:0] disabled_captions=~caption_ready | font_invalid_roles | {3{font_unusable}};
 wire [1:0] command_role=cmd_pic<=6?2'd0:cmd_pic<=9?2'd1:2'd2;
 wire [15:0] health_ack;
 wire caption_downgrade_acked=health_ack[15] && (health_ack[14] || health_ack[11+command_role]);
 wire caption_dispatch_ready=cmd_mode!=2 || !disabled_captions[command_role] || caption_downgrade_acked;
 reg [2:0] failed_audio;reg wav_error_seen;
 wire [2:0] disabled_audio=~wav_found | wav_duplicate | failed_audio;
 wire [15:0] health_word={normal_ready && audio_preflight_done,font_unusable,disabled_captions,disabled_audio,
   (media_fault || remote_fault!=0 || bad_frame),error_code[3:0],2'd0,(bgm_duplicate || bgm_failed)};
 always @(posedge clk or posedge rst)begin
  if(rst)begin failed_audio<=0;wav_error_seen<=0;bgm_failed<=0;end
  else if(wav_error==0)wav_error_seen<=0;
  else if(!wav_error_seen)begin
   wav_error_seen<=1;
   if(wav_command!=0)begin
    if(background_context)bgm_failed<=1;else failed_audio[wav_command-1'b1]<=1;end
  end
 end
 wire [2:0] product_mask={available_mask[9],available_mask[6],available_mask[3]};
 lights_scene_catalog u_catalog(clk,rst,catalog_ready,catalog_mask,normal_ready,available_mask,normal_count,4'd0,,,scene_query,query_valid,query_index,tile_pic,tile_query_valid,tile_query_index);
 reg [31:0] published_identity,presented_identity;reg publish_pulse,presented_valid;reg [7:0] scene_generation;reg [2:0] present_delay;
 assign command_ready=mount_good && foreground_idle && (state==WAIT || background_dwell) && !bad_frame && !media_fault && remote_fault==0;
 wire normal_pause=shown_mode==0 && requested_mode==0 && scene_auto!=auto_snapshot && gesture!=4;
 lights_scene_control #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.AUTO_PLAY_MS(AUTO_PLAY_MS),.EXPLAIN_MS(EXPLAIN_MS),.CAPTION_SYNC(0),.FRAME_IDENTITY(1),.R4(1),.R5(1),.BACKGROUND_DWELL(1),.DIRECT_CONTROLS(1)) u_scene(
  .clk(clk),.rst(rst),.catalog_ready(normal_ready),.normal_advance(normal_sync_armed && shown_valid && shown_mode==0 && requested_mode==0 && rendered_mode==0 && rendered_pic!=shown_pic),.available_mask(available_mask),.normal_count(normal_count),
  .next_press(gesture==1),.prev_press(gesture==2),.short_press(normal_pause || gesture==3),.chord_press(gesture==4),.confirm_short(gesture==3 && shown_mode==1),
  .published_identity(published_identity),.presented_identity(presented_identity),.presented_identity_valid(presented_valid),
  .requested_mode(requested_mode),.foreground_claim(),.foreground_present_wait(),.select_cancel(select_cancel),.shown_identity(),
  .caption_commit_ready(1'b1),.caption_banks(),.command_ready(command_ready),.publish_pulse(publish_pulse),.published_bank(1'b0),
  .fault_locked(bad_frame || media_fault || remote_fault!=0),.play_started(passed),.presented_bank_async(1'b0),.presented_valid_async(1'b0),
  .command_valid(command_valid),.command_index(command_index),.query_number(scene_query),.query_valid(query_valid),.query_load_index(query_index),
  .auto_play_en(scene_auto),.shown_mode(shown_mode),.shown_pic(shown_pic),.shown_valid(shown_valid),.shown_bank(),.explain_active(),.no_product_hint(),.confirm_ready(confirm_ready),.background_dwell(background_dwell),.direct_mode_enable(controls_ready),.direct_mode_select(mode_select),.normal_primary_pic(rendered_pic),.navigation_ready(scene_navigation_ready));
 cached_show_sender u_cached_show(.clk(clk),.rst(rst),.start(fast_start),.mode(cmd_mode),.picture(cmd_pic),.sync_only(fast_sync),
  .idle(fast_idle),.request(fast_request),.waiting(fast_waiting),.grant(owner==6),.send(fast_send),.send_info(fast_info),.busy(busy || owner!=6),
  .available(available && fast_kind && fast_waiting),.recv_info(recv_info),.take(fast_take),.done(fast_done),.hit(fast_hit));
 control_poll_scene #(.POLL_CYCLES(POLL_CYCLES)) u_controls(clk,rst,enable && (normal_ready || media_fault || remote_fault!=0),owner==3,
  poll_request,poll_idle,psend,pinfo,busy || owner!=3,available && control_kind && poll_request,recv_info,ptake,auto_snapshot,gesture,requested_mode,confirm_ready,available_mask,prefetch_pic,rendered_pic,rendered_mode,mode_select,controls_ready,scene_navigation_ready && (shown_mode!=0 || (rendered_mode==0 && rendered_pic==shown_pic)),manual_pending,health_word,normal_ready?~catalog_mask:16'd0,spectrum_select,health_ack,dimension_word,dimension_cursor);
 wire [10:0] target_w=upload_op==2?TILE_WIDTH:TARGET_WIDTH,target_h=upload_op==2?TILE_HEIGHT:TARGET_HEIGHT;
 lights_image_fit u_fit(.clk(clk),.rst(rst),.start(image_begin),.source_width(sw),.source_height(sh),.target_width(target_w),.target_height(target_h),
  .background(upload_op==2?24'hf6f1e8:24'h18202a),.source_valid(raw_valid),.source_pixel(raw_pixel),.source_ready(fit_ready),
  .output_valid(fit_valid),.output_pixel(fit_pixel),.output_ready(pixel_ready && upload_op!=1),.done(fit_done),.busy());
 wire bg_valid=state==BG_SEND && bg_count<TARGET_WIDTH*TARGET_HEIGHT;
 wire [23:0] bg_pixel=bg_y<(TARGET_HEIGHT*128/480)?24'he4deec:24'hf6f1e8;
 frame_sender_scene #(.FRAME_PIXELS(TARGET_WIDTH*TARGET_HEIGHT),.TILE_PIXELS(TILE_WIDTH*TILE_HEIGHT),.DATA_RETRY_CYCLES(50000)) u_sender(
  clk,rst,image_begin || bg_begin || show_begin,upload_op==1?5'd0:(upload_op==3 || upload_op==6 || upload_op==7)?cmd_pic:source_number,
  media_write_req || bg_request,write_ack,upload_op==1?bg_valid:fit_valid,upload_op==1?bg_pixel:fit_pixel,pixel_ready,
  upload_op==1?bg_count==TARGET_WIDTH*TARGET_HEIGHT:raw_seen && fit_seen,
  frame_done,frame_request,frame_waiting,owner==2,fsend,finfo,busy || owner!=2,fwe,faddr,fbyte,available && frame_kind && frame_waiting,recv_info,ftake,upload_op,
  upload_op==7?{30'd0,cmd_mode}:upload_op==5?{30'd0,pf_mode}:{29'd0,product_mask},cache_hit);
 wire font_ce,font_request_toggle,font_cancel_toggle,font_response_toggle,font_response_good,font_we,font_map_we;
 wire [55:0] font_payload;wire [31:0] font_mask;wire [9:0] font_address;wire [23:0] font_row;wire [6:0] font_map_address;wire [4:0] font_map_slot;
 caption_client #(.POLL_CYCLES(POLL_CYCLES)) u_caption(clk,rst,enable && mount_good,owner==4,cap_request,cap_idle,cap_send,cap_info,busy || owner!=4,cap_we,cap_addr,cap_byte,
 available && cap_kind && cap_request,recv_info,cap_take,caption_lengths,caption_ready & ~font_invalid_roles,font_request_toggle,font_cancel_toggle,font_payload,font_ce,
 font_response_toggle,font_response_good,font_bad,font_mask,font_we,font_address,font_row,font_map_we,font_map_address,font_map_slot,prepared_serial,prepared_payload);
    wire text_we,font_request,font_release,font_chain_fault,font_grant,font_sector_done;
    wire [7:0] text_address,font_buffer_byte;
    wire [15:0] text_point;
    wire [8:0] font_buffer_addr,file_byte_index;
    wire [31:0] font_lba,font_cluster,font_size,font_fat_base,font_data_base,font_max_cluster;
    wire [32:0] font_volume_end;
    wire [3:0] font_cluster_shift;
    wire file_ready,file_unavailable,file_idle,file_done,file_good,file_byte_valid,file_start,file_cancel;
    reg file_idle_q;
    always @(posedge clk or posedge rst) begin
        if(rst) file_idle_q<=0;
        else file_idle_q<=file_idle;
    end
    wire cache_file_idle=file_idle_q;
    wire [7:0] file_byte;
    wire [31:0] file_offset;
    wire [9:0] file_length;
    wire anchor_we,anchor_read;wire [2:0] anchor_write_address,anchor_read_address;
    wire [27:0] anchor_write_data,anchor_read_data;
    lights_font_file u_font_file(
        .anchor_we(anchor_we),.anchor_read(anchor_read),.anchor_write_address(anchor_write_address),
        .anchor_read_address(anchor_read_address),.anchor_write_data(anchor_write_data),.anchor_read_data(anchor_read_data),
        .clk(clk),.rst(rst),.mounted(catalog_ready),.found(font_found),.duplicate(font_duplicate),
        .first_cluster(font_cluster),.file_size(font_size),.fat_base(font_fat_base),.data_base(font_data_base),
        .max_cluster(font_max_cluster),.volume_end(font_volume_end),.cluster_shift(font_cluster_shift),
        .ready(file_ready),.unavailable(file_unavailable),.chain_fault(font_chain_fault),
        .start(file_start),.cancel(file_cancel),.offset(file_offset),.length(file_length),
        .idle(file_idle),.done(file_done),.good(file_good),.byte_valid(file_byte_valid),
        .byte_index(file_byte_index),.byte_data(file_byte),.byte_ready(1'b1),
        .sector_request(font_request),.sector_lba(font_lba),.sector_grant(font_grant),.sector_done(font_sector_done),
        .sector_release(font_release),.buffer_addr(font_buffer_addr),.buffer_byte(font_buffer_byte));
    lights_font_cache_ce #(.WAIT_CYCLES(CLK_FREQ_HZ*16)) u_font_cache(.clock_enable(font_ce),
        .anchor_we(anchor_we),.anchor_read(anchor_read),.anchor_write_address(anchor_write_address),
        .anchor_read_address(anchor_read_address),.anchor_write_data(anchor_write_data),.anchor_read_data(anchor_read_data),
        .clk(clk),.rst(rst),.mounted(catalog_ready),.text_we(text_we),.text_address(text_address),.text_point(text_point),
        .text_ready(caption_ready),.text_lengths(caption_lengths),.file_ready(file_ready),
        .file_unavailable(file_unavailable || media_fault),.file_idle(cache_file_idle),.file_done(file_done),.file_good(file_good),
        .file_byte_valid(file_byte_valid),.file_byte_index(file_byte_index),.file_byte(file_byte),.file_size(font_size),
        .file_start(file_start),.file_cancel(file_cancel),.file_offset(file_offset),.file_length(file_length),
        .request_toggle(font_request_toggle),.cancel_toggle(font_cancel_toggle),.request_expired(1'b0),.request_payload(font_payload),
        .response_toggle(font_response_toggle),.response_good(font_response_good),.font_bad(font_bad),.invalid_roles(font_invalid_roles),
        .map_cache_we(font_map_we),.map_cache_address(font_map_address),.map_cache_slot(font_map_slot),.response_mask(font_mask),
        .cache_we(font_we),.cache_address(font_address),.cache_row(font_row));
 wire [95:0] wav_clusters,wav_sizes;
 wire wav_flush,wav_clear,wav_flush_done,wav_valid,wav_ready,wav_restart;
 wire [15:0] wav_sample;wire [10:0] wav_room;
 wire wav_sector_request,wav_sector_release,wav_sector_grant,wav_sector_done;wire [31:0] wav_sector_lba;
 wire [8:0] wav_buffer_addr;wire [7:0] wav_buffer_byte;
 wire [1:0] audio_selection;
 lights_background_audio_context u_background_audio(
  .clk(clk),.rst(rst),.preflight_done(audio_preflight_done),.probe_audio(probe_audio),
  .requested_mode(requested_mode),.rendered_mode(rendered_mode),.rendered_pic(rendered_pic),
  .normal_ready(normal_ready),.background_available(bgm_found && !bgm_duplicate && !bgm_failed),
  .command_mode(wav_command),.player_idle(wav_player_idle),.transport_idle(!wav_request),
  .selection(audio_selection),.background_context(background_context));
 wire [2:0] playing_found={wav_found[2:1],background_context?bgm_found:wav_found[0]};
 wire [2:0] playing_duplicate={wav_duplicate[2:1],background_context?bgm_duplicate:wav_duplicate[0]};
 wire [95:0] playing_clusters={wav_clusters[95:32],background_context?bgm_cluster:wav_clusters[31:0]};
 wire [95:0] playing_sizes={wav_sizes[95:32],background_context?bgm_size:wav_sizes[31:0]};
 lights_r6_wav_player u_wav_player(.clk(clk),.rst(rst || wav_restart),.mounted(catalog_ready),.selection(audio_selection),
  .found(playing_found),.duplicate(playing_duplicate),.clusters(playing_clusters),.sizes(playing_sizes),
  .fat_base(font_fat_base),.data_base(font_data_base),.max_cluster(font_max_cluster),.volume_end(font_volume_end),.cluster_shift(font_cluster_shift),
  .command_mode(wav_command),.flush_toggle(wav_flush),.flush_done(audio_preflight_done?wav_flush_done:1'b1),.clear_pcm(wav_clear),.run_pcm(wav_run),.player_idle(wav_player_idle),
  .pcm_valid(wav_valid),.pcm_data(wav_sample),.pcm_ready(audio_preflight_done && wav_ready),.pcm_room(audio_preflight_done?wav_room:11'd0),
  .sector_request(wav_sector_request),.sector_release(wav_sector_release),.sector_lba(wav_sector_lba),.sector_grant(wav_sector_grant),.sector_done(wav_sector_done),
  .buffer_addr(wav_buffer_addr),.buffer_byte(wav_buffer_byte),.error_code(wav_error));
 pcm_packet_sender u_pcm_sender(.clk(clk),.rst(rst || !audio_preflight_done),.command_mode(wav_command),.flush_toggle(wav_flush),.clear_pcm(wav_clear),.flush_done(wav_flush_done),
  .sample_valid(audio_preflight_done && wav_valid),.sample(wav_sample),.sample_ready(wav_ready),.sample_room(wav_room),
  .request(wav_request),.grant(owner==5),.send(wav_send),.send_info(wav_info),.busy(busy || owner!=5),.mem_we(wav_we),.mem_addr(wav_address),.mem_byte(wav_byte),
  .available(available && wav_kind && owner==5),.recv_info(recv_info),.take(wav_take),.restart_player(wav_restart));
  lights_fat32_media #(.RECOVER_ASSETS(1),.MEDIA_SNAPSHOT(1),.FAST_FILE_STREAM(1),.FAT_SECTOR_CACHE(1),.UI_STYLE(1),.SHARED_SERVICE(1),.WAV_FILES(1),.MAX_IMAGES(16),.VARIABLE_BMP(1),.CAPTIONS(1),.TF_FONT(1)) u_media(
  .clk(clk),.rst(rst),.sd_init_done(sd_ready),.bmp_width(16'd640),.bmp_height(16'd480),.idle(idle),.catalog_ready(catalog_ready),.image_count(image_count),.catalog_mask(catalog_mask),
  .error_code(error_code),.fault_present(media_fault),.state_code(media_state),.load_start(load_start),.load_index(load_index),.source_number(source_number),.source_success(source_success),
  .write_req(media_write_req),.write_req_ack(write_ack),.image_begin(image_begin),.image_stream_open(opened),.source_width(sw),.source_height(sh),.pixel_ready(fit_ready),.pixel_valid(raw_valid),.pixel(raw_pixel),
  .sd_read(sd_read),.sd_lba(sd_lba),.sd_byte(sd_byte),.sd_valid(sd_valid),.sd_end(sd_end),.caption_we(text_we),.caption_address(text_address),.caption_glyph(text_point),.caption_ready(caption_ready),.caption_lengths(caption_lengths),.caption_errors(caption_errors),
  .font_request(shared_font_request),.font_release(shared_font_release),.font_chain_fault(1'b0),.font_lba(shared_font_lba),.font_buffer_addr(shared_font_address),.font_grant(shared_font_grant),.font_sector_done(shared_font_done),.font_buffer_byte(shared_font_byte),.font_found(font_found),.font_duplicate(font_duplicate),
  .font_cluster(font_cluster),.font_size(font_size),.font_fat_base(font_fat_base),.font_data_base(font_data_base),.font_max_cluster(font_max_cluster),.font_volume_end(font_volume_end),.font_cluster_shift(font_cluster_shift),
  .wav_found(wav_found),.wav_duplicate(wav_duplicate),.wav_clusters(wav_clusters),.wav_sizes(wav_sizes),
  .bgm_found(bgm_found),.bgm_duplicate(bgm_duplicate),.bgm_cluster(bgm_cluster),.bgm_size(bgm_size),
  .ui_found(ui_found),.ui_duplicate(ui_duplicate),.ui_cluster(ui_cluster),.ui_size(ui_size),
   .service_request(wav_sector_request),.service_release(wav_sector_release),.service_chain_fault(1'b0),.service_lba(wav_sector_lba),.service_buffer_addr(wav_buffer_addr),.service_grant(wav_sector_grant),.service_done(wav_sector_done),.service_buffer_byte(wav_buffer_byte));

 assign font_buffer_byte=shared_font_byte;assign ui_buffer_byte=shared_font_byte;
 ui_font_sector_mux u_ui_font_mux(.clk(clk),.rst(rst),.font_request(font_request),.font_release(font_release),.ui_request(ui_sector_request),.ui_release(ui_sector_release),
  .font_lba(font_lba),.ui_lba(ui_sector_lba),.font_address(font_buffer_addr),.ui_address(ui_buffer_addr),
  .request(shared_font_request),.out_release(shared_font_release),.lba(shared_font_lba),.address(shared_font_address),.grant(shared_font_grant),.sector_done(shared_font_done),
  .font_grant(font_grant),.font_done(font_sector_done),.ui_grant(ui_sector_grant),.ui_done(ui_sector_done));
 ui_style_reader u_ui_reader(.clk(clk),.rst(rst),.mounted(catalog_ready),.found(ui_found),.duplicate(ui_duplicate),.first_cluster(ui_cluster),.file_size(ui_size),
  .fat_base(font_fat_base),.data_base(font_data_base),.max_cluster(font_max_cluster),.volume_end(font_volume_end),.cluster_shift(font_cluster_shift),.sector_fault(remote_fault),
  .sector_request(ui_sector_request),.sector_lba(ui_sector_lba),.sector_grant(ui_sector_grant),.sector_done(ui_sector_done),.sector_release(ui_sector_release),.buffer_addr(ui_buffer_addr),.buffer_byte(ui_buffer_byte),
  .block_valid(ui_block_valid),.block_index(ui_block_index),.file_crc(ui_file_crc),.block_crc(ui_block_crc),.block_read_enable(ui_block_read),.block_address(ui_block_addr),.block_byte(ui_block_byte),
  .block_done(ui_block_done),.block_good(ui_block_good),.done(ui_done),.valid(ui_valid),.failed(ui_failed),.palette(ui_palette));
 ui_style_sender u_ui_sender(.clk(clk),.rst(rst),.block_valid(ui_block_valid),.block_index(ui_block_index),.file_crc(ui_file_crc),.block_crc(ui_block_crc),
  .block_address(ui_block_addr),.block_read_enable(ui_block_read),.block_byte(ui_block_byte),.request(ui_request),.grant(owner==7),.busy(busy || owner!=7),
  .send(ui_send),.send_info(ui_info),.mem_we(ui_mem_we),.mem_addr(ui_mem_addr),.mem_byte(ui_mem_byte),
  .available(available && ui_reply_kind && owner==7),.recv_info(recv_info),.take(ui_take),.done(ui_block_done),.good(ui_block_good));

 assign status=remote_fault!=0?16'd9:media_fault?{error_code,4'd0,4'd7}:bad_frame?16'd8:passed?16'd6:16'd4;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   foreground_state<=F_IDLE;fast_start<=0;fast_sync<=0;reprobe_after_background<=0;
   pf_mode<=0;need_prepare<=0;prepare_mark<=0;pf_pic<=0;pf_cursor<=0;pf_index<=0;last_prefetch<=0;manual_pending<=0;normal_sync_armed<=0;state<=WAIT;mount_good<=0;passed<=0;bad_frame<=0;canvas_built<=0;cancelled<=0;canvas_prefilling<=0;cmd_mode<=0;cmd_pic<=0;cmd_index<=0;tile<=0;
   load_start<=0;load_index<=0;bg_begin<=0;show_begin<=0;bg_request<=0;raw_seen<=0;fit_seen<=0;frame_seen<=0;upload_op<=0;bg_count<=0;bg_x<=0;bg_y<=0;
   published_identity<=0;presented_identity<=0;publish_pulse<=0;presented_valid<=0;scene_generation<=0;present_delay<=0;decoded_frames<=0;
  end else begin
   fast_start<=0;load_start<=0;bg_begin<=0;show_begin<=0;publish_pulse<=0;presented_valid<=0;
   if(state==WAIT && foreground_idle && shown_valid && shown_mode==0 && requested_mode==0 && rendered_mode==0 && rendered_pic==shown_pic)normal_sync_armed<=1;
   if(source_success)raw_seen<=1;if(fit_done)fit_seen<=1;if(frame_done)frame_seen<=1;
   if(bg_request && write_ack)bg_request<=0;
   if(bg_valid && pixel_ready)begin bg_count<=bg_count+1'b1;if(bg_x==TARGET_WIDTH-1)begin bg_x<=0;bg_y<=bg_y+1'b1;end else bg_x<=bg_x+1'b1;end
   if(present_delay!=0)begin present_delay<=present_delay-1'b1;if(present_delay==1)begin presented_valid<=1;presented_identity<=published_identity;end end
   if(cmd_mode==1 && select_cancel && state!=WAIT)cancelled<=1;
   if(!mount_good && normal_ready && idle)begin if(image_count==0)bad_frame<=1;else mount_good<=1;end
   if(!media_fault && !bad_frame && remote_fault==0)case(state)
    WAIT:if(foreground_idle && !(command_valid && command_ready) && mount_good && shown_valid &&
      shown_mode==0 && requested_mode==0 && rendered_mode==0 && rendered_pic==shown_pic && !manual_pending &&
      !normal_prefetch_due && (canvas_prefilling || (!canvas_built && last_prefetch!=0 && product_mask!=0)))begin
     if(canvas_prefilling)state<=TILE_QUERY;
     else begin canvas_prefilling<=1;cancelled<=0;state<=BG_START;end
    end else if(foreground_idle && !(command_valid && command_ready) && mount_good && shown_valid && ((shown_mode==0 && requested_mode==0) || explain_prefetch) &&
      prefetch_pic!=0 && prefetch_pic!=last_prefetch && !manual_pending)begin
     pf_mode<=shown_mode;pf_pic<=prefetch_pic;pf_cursor<=0;pf_index<=0;state<=PF_MAP;
    end
    SOURCE_START:if(cmd_mode==2 && disabled_captions[command_role])begin
      need_prepare<=0;
      if(caption_downgrade_acked && idle && owner==0 && poll_idle && !load_start)begin
       upload_op<=7;show_begin<=1;frame_seen<=0;state<=PROBE_WAIT;
      end
     end else if(idle && owner==0 && poll_idle && !load_start && (!need_prepare ||
       (prepared_serial!=prepare_mark && prepared_payload[47:46]==(cmd_pic<=6?2'd0:cmd_pic<=9?2'd1:2'd2) && prepared_payload[45:39]==0 && prepared_payload[38:32]!=0)))begin
      upload_op<=7;show_begin<=1;frame_seen<=0;state<=PROBE_WAIT;
     end
    PROBE_WAIT:if(frame_seen)begin
     if(cache_hit)state<=PUBLISH;else state<=LOAD_START;
    end
    LOAD_START:if(idle && owner==0 && poll_idle && !load_start)begin
      upload_op<=cmd_mode==2?3'd4:3'd0;
      load_start<=1;load_index<=cmd_index;raw_seen<=0;fit_seen<=0;frame_seen<=0;state<=SOURCE_WAIT;
     end
    SOURCE_WAIT:if(raw_seen && fit_seen && frame_seen)state<=PUBLISH;
    BG_START:if(owner==0 && poll_idle && idle)begin upload_op<=1;bg_begin<=1;bg_request<=1;bg_count<=0;bg_x<=0;bg_y<=0;frame_seen<=0;state<=BG_SEND;end
    BG_SEND:if(frame_seen)begin tile<=0;state<=!canvas_prefilling && cancelled?WAIT:TILE_QUERY;end
    TILE_QUERY:if(canvas_prefilling && ((foreground_state==F_FALLBACK && (cmd_mode!=1 || cancelled || select_cancel)) || normal_prefetch_due))state<=WAIT;
     else if(!canvas_prefilling && cancelled)state<=WAIT;else if(tile==3)begin
      canvas_built<=1;
      if(canvas_prefilling)begin canvas_prefilling<=0;state<=WAIT;end else state<=SHOW_START;
     end
     else if(!available_mask[tile_pic-1'b1])tile<=tile+1'b1;else state<=TILE_START;
    TILE_START:if(canvas_prefilling && ((foreground_state==F_FALLBACK && (cmd_mode!=1 || cancelled || select_cancel)) || normal_prefetch_due) && !load_start)state<=WAIT;
     else if(idle && owner==0 && poll_idle && !load_start)begin
     if(!tile_query_valid)bad_frame<=1;else begin upload_op<=2;load_index<=tile_query_index;load_start<=1;raw_seen<=0;fit_seen<=0;frame_seen<=0;state<=TILE_WAIT;end
    end
    TILE_WAIT:if(raw_seen && fit_seen && frame_seen)begin tile<=tile+1'b1;state<=!canvas_prefilling && cancelled?WAIT:TILE_QUERY;end
    SHOW_START:if(cancelled)state<=WAIT;else if(owner==0 && poll_idle && idle)begin upload_op<=cmd_mode==0?3'd6:3'd3;show_begin<=1;frame_seen<=0;state<=SHOW_WAIT;end
    SHOW_WAIT:if(frame_seen)state<=cancelled?WAIT:PUBLISH;
    PUBLISH:begin
     scene_generation<=scene_generation+1'b1;published_identity<={1'b1,cmd_mode,cmd_pic,scene_generation+8'd1,13'd0,cmd_mode==1,2'd0};publish_pulse<=1;present_delay<=3;
     manual_pending<=0;decoded_frames<=decoded_frames+1'b1;passed<=1;state<=BLOCK;
    end
    BLOCK:if(present_delay==0 && !presented_valid)state<=WAIT;
    PF_MAP:if(gesture!=0)state<=WAIT;else if(pf_cursor==pf_pic-1'b1)begin load_index<=pf_index;state<=PF_START;end
     else begin if(available_mask[pf_cursor])pf_index<=pf_index+1'b1;pf_cursor<=pf_cursor+1'b1;end
    PF_START:if(gesture!=0)state<=WAIT;else if(idle && owner==0 && poll_idle && !load_start)begin
     if(!available_mask[pf_pic-1'b1])state<=WAIT;else begin upload_op<=5;load_start<=1;raw_seen<=0;fit_seen<=0;frame_seen<=0;state<=PF_WAIT;end
    end
    PF_WAIT:if(raw_seen && fit_seen && frame_seen)begin last_prefetch<=pf_pic;state<=WAIT;end
   endcase
   if(!media_fault && !bad_frame && remote_fault==0)case(foreground_state)
    F_IDLE:if(command_valid && command_ready)begin
     need_prepare<=requested_mode==2 && shown_mode!=2;prepare_mark<=prepared_serial;
     normal_sync_armed<=0;cmd_mode<=requested_mode;cmd_pic<=scene_query;cmd_index<=command_index;cancelled<=0;last_prefetch<=0;
     fast_sync<=requested_mode==0 && !manual_pending && rendered_mode==0 && rendered_pic==scene_query;
     reprobe_after_background<=0;foreground_state<=F_PREP;
     if(state==PF_MAP || state==PF_START)begin load_start<=0;state<=WAIT;end
    end
    F_PREP:if(cmd_mode==2 && disabled_captions[command_role])begin
      need_prepare<=0;
      if(caption_downgrade_acked)foreground_state<=F_SEND;
     end
     else if(!need_prepare || (prepared_serial!=prepare_mark &&
       prepared_payload[47:46]==(cmd_pic<=6?2'd0:cmd_pic<=9?2'd1:2'd2) && prepared_payload[45:39]==0 && prepared_payload[38:32]!=0))foreground_state<=F_SEND;
    F_SEND:if(!caption_dispatch_ready)foreground_state<=F_PREP;
     else if(fast_idle)begin fast_start<=1;foreground_state<=F_WAIT;end
    F_WAIT:if(fast_done)begin
     if(fast_hit)foreground_state<=F_PUBLISH;
     else begin reprobe_after_background<=state==PF_WAIT || (canvas_prefilling && state!=WAIT);foreground_state<=F_FALLBACK;end
    end
    F_FALLBACK:if(state==WAIT && idle && fast_idle)begin
     if(cmd_mode==1 && (cancelled || select_cancel))foreground_state<=F_IDLE;
     else if(cmd_mode==1 && canvas_prefilling)state<=TILE_QUERY;
     else if(reprobe_after_background)begin reprobe_after_background<=0;foreground_state<=F_SEND;end
     else begin
      foreground_state<=F_IDLE;last_prefetch<=0;
      if(cmd_mode==1)begin canvas_built<=0;state<=BG_START;end
      else state<=LOAD_START;
     end
    end
    F_PUBLISH:begin
     scene_generation<=scene_generation+1'b1;published_identity<={1'b1,cmd_mode,cmd_pic,scene_generation+8'd1,13'd0,cmd_mode==1,2'd0};publish_pulse<=1;present_delay<=3;
     manual_pending<=0;decoded_frames<=decoded_frames+1'b1;passed<=1;foreground_state<=F_BLOCK;
    end
    F_BLOCK:if(present_delay==0 && !presented_valid)foreground_state<=F_IDLE;
   endcase
   if(gesture!=0)manual_pending<=1;
  end
 end
endmodule

module lights_background_audio_context(
 input wire clk,rst,preflight_done,input wire [1:0] probe_audio,requested_mode,rendered_mode,
 input wire [4:0] rendered_pic,input wire normal_ready,background_available,
 input wire [1:0] command_mode,input wire player_idle,transport_idle,
 output wire [1:0] selection,output reg background_context);
 reg [1:0] state;
 wire want_background=preflight_done && normal_ready && background_available &&
  requested_mode!=2 && rendered_mode!=2 && rendered_pic>=1 && rendered_pic<=16;
 wire [1:0] legacy_selection=requested_mode==2 && rendered_mode==2 && rendered_pic>=4 && rendered_pic<=12 ?
  (rendered_pic<=6?2'd1:rendered_pic<=9?2'd2:2'd3):2'd0;
 wire changing=background_context!=want_background;
 assign selection=!preflight_done?probe_audio:
  (state!=0 || changing)?2'd0:want_background?2'd1:legacy_selection;
 always @(posedge clk or posedge rst)begin
  if(rst)begin background_context<=0;state<=0;end
  else if(!preflight_done)begin background_context<=0;state<=0;end
  else case(state)
   0:if(changing)state<=1;
   1:if(command_mode==0 && player_idle && transport_idle)begin
      background_context<=want_background;state<=2;end
   2:state<=0;
   default:state<=0;
  endcase
 end
endmodule
