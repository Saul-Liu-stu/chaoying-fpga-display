`timescale 1ns/1ps
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ=100_000_000,
    parameter integer MAX_IMAGES=4,
    parameter integer CAPTIONS=0,
    parameter integer FRAME_POOL=0,
    parameter integer R4=0,
    parameter integer R5=0,
    parameter integer LONG_PRESS_MS=800,
    parameter integer AUTO_PLAY_MS=5000
)(
    input wire r5_frame_valid,input wire [117:0] r5_frame_pose,output wire [117:0] r5_pose,
    input wire write_ready,
    output wire [20:0] write_rect_first,write_rect_length,
    output wire [10:0] write_rect_width,
    output wire [11:0] write_rect_jump,
    input wire write_done_valid,presented_identity_valid,frame_transfer_fault,
    input wire [31:0] write_done_identity,presented_identity,
    output wire [31:0] write_identity,display_identity,frame_authorizations,
    input wire clk,rst,key_next,key_auto,
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
    output wire [78:0] caption_source_key,
    input wire SD_MISO
);
    wire next_press,prev_press,short_press,chord_press,confirm_short,confirm_ready,sd_init_done;
    wire sd_read,sd_valid,sd_end;
    wire [31:0] sd_lba;
    wire [7:0] sd_byte;
    wire catalog_ready,source_idle,source_success,load_start;
    wire raw_success,raw_pixel_valid,raw_write_req,image_begin,image_stream_open;
    wire [23:0] raw_pixel;wire [10:0] source_width,source_height;wire fit_ready;
    wire page_owner,background_req,background_valid;wire [23:0] background_pixel;
    wire select_cancel;
    wire [4:0] image_count,source_number;
    wire [3:0] load_index,source_state;
    wire [7:0] source_error,control_error;
    wire source_fault_present;
    wire [15:0] catalog_mask,available_mask;
    wire normal_ready;
    wire [4:0] normal_count,query_number,shown_pic;
    wire [3:0] source_load_index,query_load_index,command_index;
    wire query_valid,command_valid,command_ready,publish_pulse,play_started;
    wire [2:0] caption_ready;
    wire [20:0] caption_lengths;
    wire [23:0] caption_errors;
    wire explain_active,shown_bank;
    wire [31:0] shown_identity,pool_prepared_identity;
    wire pool_prepared_valid;
    wire [1:0] requested_mode;
    wire foreground_claim;
    wire foreground_present_wait;
    wire [1:0] shown_mode;
    wire auto_play_en,load_busy,source_done_seen,write_finish_pulse,fault_locked;
    wire normal_advance,r5_presented_valid;
    wire [31:0] r5_presented_identity,cache_query_identity;
    wire [4:0] cache_query_pic;
    wire [3:0] extra_hold,hold_ack;
    wire [31:0] extra_generations;
    wire extra_changed;
    wire effective_presented_valid=R5 ? r5_presented_valid : presented_identity_valid;
    wire [31:0] effective_presented_identity=R5 ? r5_presented_identity : presented_identity;
    generate if(R5) begin : g_r5_motion
      lights_r5_motion u_motion(
       .clk(clk),.rst(rst),.published_valid(display_valid),.published_identity(display_identity),
       .auto_play(auto_play_en),.play_started(play_started),.foreground_claim(foreground_claim),.foreground_present_wait(foreground_present_wait),.fault_locked(fault_locked),
       .available_mask(available_mask),.query_pic(cache_query_pic),.query_identity(cache_query_identity),
       .hold_mask(extra_hold),.hold_generations(extra_generations),.hold_changed(extra_changed),.hold_ack(hold_ack),
       .frame_valid(r5_frame_valid),.frame_pose(r5_frame_pose),.pose(r5_pose),.transition_busy(),
       .normal_advance(normal_advance),.presented_pulse(r5_presented_valid),.presented_identity(r5_presented_identity));
    end else begin : g_no_motion
      assign normal_advance=0;assign r5_presented_valid=0;assign r5_presented_identity=0;
      assign r5_pose=0;assign cache_query_pic=0;assign extra_hold=0;assign extra_generations=0;assign extra_changed=0;
    end endgenerate
    wire shown_valid;
    wire [4:0] prepared_pic=pool_prepared_identity[28:24];
    wire entering_explain=R5 && pool_prepared_valid && pool_prepared_identity[30:29]==2 && shown_mode!=2;
    wire [4:0] caption_pic=entering_explain ? prepared_pic : shown_pic;
    wire caption_shown_valid=shown_valid && (!R5 || shown_mode==2);
    wire shown_role0=caption_pic<=6;
    wire shown_role1=caption_pic>6 && caption_pic<=9;
    wire shown_role2=caption_pic>9;
    wire target_role0=prepared_pic>=4 && prepared_pic<=6;
    wire target_role1=prepared_pic>=7 && prepared_pic<=9;
    wire target_role2=prepared_pic>=10 && prepared_pic<=12;
    wire same_role_prepared=pool_prepared_valid && pool_prepared_identity[30:29]==2 &&
        ((shown_role0 && target_role0) || (shown_role1 && target_role1) || (shown_role2 && target_role2));
    assign frame_authorizations={caption_active && same_role_prepared,caption_active && caption_shown_valid,
        (caption_active && same_role_prepared ? {pool_prepared_identity[28:16],pool_prepared_identity[1:0]} : 15'd0),
        (caption_active && caption_shown_valid ? {shown_identity[28:16],shown_identity[1:0]} : 15'd0)};
    assign caption_role=caption_pic<=6 ? 2'd0 : caption_pic<=9 ? 2'd1 : 2'd2;
    assign caption_active=(explain_active || entering_explain) && caption_ready[caption_role] && !caption_font_bad;
    assign caption_bank=entering_explain ? pool_prepared_identity[0] : shown_bank;
    assign caption_count=caption_lengths[caption_role*7 +: 7];
    assign caption_source_key={pool_prepared_identity,shown_identity,pool_prepared_valid,shown_valid,
        caption_active,caption_role,caption_count,caption_bank,caption_banks};
    wire no_product_hint;
    wire [23:0] pixel;
    wire playback_source_failed=source_fault_present || (normal_ready && normal_count==0) || (FRAME_POOL && frame_transfer_fault);
    wire [7:0] playback_source_error=source_fault_present ? source_error :
        (normal_ready && normal_count==0 ? 8'h43 : FRAME_POOL && frame_transfer_fault ? 8'h45 : 8'd0);
    wire [7:0] error_code=control_error!=0 ? control_error : source_fault_present ? source_error :
        no_product_hint ? 8'h44 : 8'd0;
    assign write_data={pixel,8'd0};
    assign state_code=source_state | {4{control_error!=0 || source_fault_present || no_product_hint}};
    assign source_load_index=load_index;
    lights_scene_catalog u_scene_catalog (
        .clk(clk),.rst(rst),.catalog_ready(catalog_ready),.catalog_mask(catalog_mask),
        .ready(normal_ready),.available_mask(available_mask),.normal_count(normal_count),
        .normal_index(4'd0),.normal_load_index(),.normal_number(),
        .query_number(query_number),.query_valid(query_valid),.query_load_index(query_load_index));
    lights_scene_keys #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.LONG_MS(LONG_PRESS_MS)) u_scene_keys(
        .clk(clk),.rst(rst),.key1(key_next),.key2(key_auto),
        .confirm_ready(confirm_ready),.confirm_short(confirm_short),
        .next_press(next_press),.prev_press(prev_press),.short_press(short_press),.chord_press(chord_press));
    lights_scene_control #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.AUTO_PLAY_MS(AUTO_PLAY_MS),.CAPTION_SYNC(CAPTIONS),.FRAME_IDENTITY(FRAME_POOL),.R4(R4),.R5(R5)) u_scene(
        .normal_advance(normal_advance),
        .published_identity(display_identity),.presented_identity(effective_presented_identity),
        .presented_identity_valid(effective_presented_valid),.requested_mode(requested_mode),.foreground_claim(foreground_claim),.foreground_present_wait(foreground_present_wait),.select_cancel(select_cancel),.shown_identity(shown_identity),
        .clk(clk),.rst(rst),.catalog_ready(normal_ready),.available_mask(available_mask),.normal_count(normal_count),
        .next_press(next_press),.prev_press(prev_press),.short_press(short_press),.chord_press(chord_press),.confirm_short(confirm_short),
        .caption_commit_ready(caption_commit_ready),.caption_banks(caption_banks),
        .command_ready(command_ready),.publish_pulse(publish_pulse),.published_bank(disp_buf_idx[0]),
        .fault_locked(fault_locked),.play_started(play_started),
        .presented_bank_async(presented_bank_async),.presented_valid_async(presented_valid_async),
        .command_valid(command_valid),.command_index(command_index),.query_number(query_number),
        .query_valid(query_valid),.query_load_index(query_load_index),
        .auto_play_en(auto_play_en),.shown_mode(shown_mode),.shown_pic(shown_pic),.shown_valid(shown_valid),
        .shown_bank(shown_bank),.explain_active(explain_active),
        .no_product_hint(no_product_hint),.confirm_ready(confirm_ready));
    generate if(FRAME_POOL) begin : g_four_pool
    reg accepted_command;reg [3:0] accepted_index;
    reg [4:0] accepted_pic;reg [1:0] accepted_mode;
    always @(posedge clk or posedge rst) begin
        if(rst) begin accepted_command<=0;accepted_index<=0;accepted_pic<=0;accepted_mode<=0;end
        else begin
            accepted_command<=command_valid && command_ready;
            if(command_valid && command_ready) begin accepted_index<=command_index;accepted_pic<=query_number;accepted_mode<=requested_mode;end
        end
    end
    if(R4) begin : g_r4
    lights_r4_backend #(.CAPTION_SYNC(CAPTIONS),.R5(R5)) u_backend(
        .extra_hold(extra_hold),.extra_generations(extra_generations),.extra_changed(extra_changed),.hold_ack_mask(hold_ack),
        .cache_query_pic(cache_query_pic),.cache_query_identity(cache_query_identity),
        .clk(clk),.rst(rst),.catalog_ready(normal_ready),.available_mask(available_mask),
        .accepted_command(accepted_command),.accepted_index(accepted_index),.accepted_pic(accepted_pic),.accepted_mode(accepted_mode),
        .requested_mode(requested_mode),.foreground_claim(foreground_claim),.select_cancel(select_cancel),.command_ready(command_ready),
        .view_valid(shown_valid),.view_pic(shown_pic),.view_mode(shown_mode),
        .source_idle(source_idle),.source_success(source_success),.source_number(source_number),.source_error(playback_source_error),.source_fault(playback_source_failed),
        .write_done_valid(write_done_valid),.write_done_identity(write_done_identity),
        .presented_valid(effective_presented_valid),.presented_identity(effective_presented_identity),.caption_commit_ready(caption_commit_ready),
        .load_start(load_start),.load_index(load_index),.write_buf_idx(write_buf_idx),.disp_buf_idx(disp_buf_idx),
        .write_identity(write_identity),.display_identity(display_identity),.prepared_identity(pool_prepared_identity),.prepared_valid(pool_prepared_valid),
        .display_valid(display_valid),.publish_pulse(publish_pulse),.load_busy(load_busy),.source_done_seen(source_done_seen),.write_finish_pulse(write_finish_pulse),
        .fault_locked(fault_locked),.error_code(control_error),.page_owner(page_owner),.background_req(background_req),.background_valid(background_valid),.background_pixel(background_pixel),
        .rect_first(write_rect_first),.rect_length(write_rect_length),.rect_width(write_rect_width),.rect_jump(write_rect_jump),.write_req_ack(write_req_ack),.write_ready(write_ready));
    end else begin : g_original
    lights_frame_pool #(.CAPTION_SYNC(CAPTIONS),.SOURCE_FAULT_INPUT(1)) u_pool(
        .clk(clk),.rst(rst),.catalog_ready(normal_ready),.available_mask(available_mask),
        .command_valid(accepted_command),.foreground_claim(foreground_claim),.command_index(accepted_index),.command_pic(accepted_pic),.command_mode(accepted_mode),
        .command_ready(command_ready),.view_valid(shown_valid),.view_pic(shown_pic),.view_mode(shown_mode),
        .source_idle(source_idle),.source_success(source_success),.source_number(source_number),.source_error(playback_source_error),
        .source_fault(playback_source_failed),
        .write_done_valid(write_done_valid),.write_done_identity(write_done_identity),
        .presented_valid(effective_presented_valid),.presented_identity(effective_presented_identity),.caption_commit_ready(caption_commit_ready),
        .extra_hold(4'd0),.extra_generations(32'd0),.extra_changed(1'b0),.hold_ack_mask(),
        .load_start(load_start),.load_index(load_index),.write_buf_idx(write_buf_idx),.disp_buf_idx(disp_buf_idx),
        .write_identity(write_identity),.display_identity(display_identity),.prepared_identity(pool_prepared_identity),.prepared_valid(pool_prepared_valid),
        .display_valid(display_valid),.publish_pulse(publish_pulse),.load_busy(load_busy),.source_done_seen(source_done_seen),
        .write_finish_pulse(write_finish_pulse),.fault_locked(fault_locked),.error_code(control_error),.valid_slots(),.protected_slots());
    end
        (* syn_preserve=1 *) reg [2:0] play_started_sync;
        if(R4) begin : g_start_phase
        always @(negedge clk or posedge rst) begin
            if(rst) play_started_sync[0]<=0;
            else play_started_sync[0]<=play_started_async;
        end
        always @(posedge clk or posedge rst) begin
            if(rst) play_started_sync[2:1]<=0;
            else play_started_sync[2:1]<=play_started_sync[1:0];
        end
        end else begin : g_start_original
        always @(posedge clk or posedge rst) begin
            if(rst) play_started_sync<=0;
            else play_started_sync<={play_started_sync[1:0],play_started_async};
        end
        end
        assign play_started=play_started_sync[2];
    end else begin : g_legacy_pool
        assign write_identity=0;assign display_identity=0;assign pool_prepared_identity=0;assign pool_prepared_valid=0;
    lights_playback_control #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.AUTO_PLAY_MS(AUTO_PLAY_MS),.EXTERNAL_COMMANDS(1)) u_playback(
        .clk(clk),.rst(rst),.next_press(1'b0),.prev_press(1'b0),.auto_short(1'b0),
        .command_valid(command_valid),.command_index(command_index),.command_ready(command_ready),
        .publish_pulse(publish_pulse),.play_started(play_started),
        .catalog_ready(normal_ready),.image_count(normal_count),.source_idle(source_idle),
        .source_success(source_success),.source_error(playback_source_error),.write_finish_toggle(write_finish_toggle),
        .read_active_buf_async(read_active_buf_async),.read_active_valid_async(read_active_valid_async),
        .play_started_async(play_started_async),
        .load_start(load_start),.load_index(load_index),.write_buf_idx(write_buf_idx),.disp_buf_idx(disp_buf_idx),
        .display_valid(display_valid),.auto_play_en(),.load_busy(load_busy),
        .source_done_seen(source_done_seen),.write_finish_pulse(write_finish_pulse),
        .fault_locked(fault_locked),.error_code(control_error));
    end endgenerate
    generate if(R4) begin : g_fit
        wire fit_valid,fit_done,fit_busy;wire [23:0] fit_pixel;
        reg opened,raw_seen,fit_seen,success_sent;
        reg success_pulse;
        lights_image_fit u_fit(.clk(clk),.rst(rst),.start(image_begin),.source_width(source_width),.source_height(source_height),
            .target_width(page_owner ? 11'd176 : 11'd640),.target_height(page_owner ? 11'd132 : 11'd480),
            .background(page_owner ? 24'hf6f1e8 : 24'h18202a),.source_valid(raw_pixel_valid),.source_pixel(raw_pixel),.source_ready(fit_ready),
            .output_valid(fit_valid),.output_pixel(fit_pixel),.output_ready(write_ready && opened),.done(fit_done),.busy(fit_busy));
        always @(posedge clk or posedge rst) begin
            if(rst) begin opened<=0;raw_seen<=0;fit_seen<=0;success_sent<=0;success_pulse<=0;end
            else begin
                success_pulse<=0;
                if(image_begin) begin opened<=0;raw_seen<=0;fit_seen<=0;success_sent<=0;end
                else begin
                    if(image_stream_open) opened<=1;
                    if(raw_success) raw_seen<=1;
                    if(fit_done) begin fit_seen<=1;opened<=0;end
                    if(!success_sent && (raw_seen || raw_success) && (fit_seen || fit_done)) begin success_pulse<=1;success_sent<=1;end
                end
            end
        end
        assign source_success=success_pulse;
        assign write_req=background_req || raw_write_req;
        assign write_en=write_ready && (background_valid || (fit_valid && opened));
        assign pixel=background_valid ? background_pixel : fit_pixel;
    end else begin : g_no_fit
        assign source_success=raw_success;assign fit_ready=1;
        assign write_en=raw_pixel_valid;assign pixel=raw_pixel;assign write_req=raw_write_req;
        assign page_owner=0;assign background_req=0;assign background_valid=0;assign background_pixel=0;
        assign write_rect_first=0;assign write_rect_length=307200;assign write_rect_width=640;assign write_rect_jump=1279;
    end endgenerate
    wire text_we,font_request,font_release,font_chain_fault,font_grant,font_sector_done,font_found,font_duplicate;
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
    wire cache_file_idle=R4 ? file_idle_q : file_idle;
    wire [7:0] file_byte;
    wire [31:0] file_offset;
    wire [9:0] file_length;
    wire anchor_we,anchor_read;wire [2:0] anchor_write_address,anchor_read_address;
    wire [27:0] anchor_write_data,anchor_read_data;
    lights_font_file u_font_file(
        .anchor_we(anchor_we),.anchor_read(anchor_read),.anchor_write_address(anchor_write_address),
        .anchor_read_address(anchor_read_address),.anchor_write_data(anchor_write_data),.anchor_read_data(anchor_read_data),
        .clk(clk),.rst(rst),.mounted(CAPTIONS && catalog_ready),.found(font_found),.duplicate(font_duplicate),
        .first_cluster(font_cluster),.file_size(font_size),.fat_base(font_fat_base),.data_base(font_data_base),
        .max_cluster(font_max_cluster),.volume_end(font_volume_end),.cluster_shift(font_cluster_shift),
        .ready(file_ready),.unavailable(file_unavailable),.chain_fault(font_chain_fault),
        .start(file_start),.cancel(file_cancel),.offset(file_offset),.length(file_length),
        .idle(file_idle),.done(file_done),.good(file_good),.byte_valid(file_byte_valid),
        .byte_index(file_byte_index),.byte_data(file_byte),.byte_ready(1'b1),
        .sector_request(font_request),.sector_lba(font_lba),.sector_grant(font_grant),.sector_done(font_sector_done),
        .sector_release(font_release),.buffer_addr(font_buffer_addr),.buffer_byte(font_buffer_byte));
    lights_font_cache u_font_cache(
        .anchor_we(anchor_we),.anchor_read(anchor_read),.anchor_write_address(anchor_write_address),
        .anchor_read_address(anchor_read_address),.anchor_write_data(anchor_write_data),.anchor_read_data(anchor_read_data),
        .clk(clk),.rst(rst),.mounted(catalog_ready),.text_we(text_we),.text_address(text_address),.text_point(text_point),
        .text_ready(caption_ready),.text_lengths(caption_lengths),.file_ready(file_ready),
        .file_unavailable(file_unavailable || source_fault_present),.file_idle(cache_file_idle),.file_done(file_done),.file_good(file_good),
        .file_byte_valid(file_byte_valid),.file_byte_index(file_byte_index),.file_byte(file_byte),.file_size(font_size),
        .file_start(file_start),.file_cancel(file_cancel),.file_offset(file_offset),.file_length(file_length),
        .request_toggle(caption_request_toggle),.cancel_toggle(caption_cancel_toggle),.request_expired(caption_request_expired),.request_payload(caption_request_payload),
        .response_toggle(caption_response_toggle),.response_good(caption_response_good),.font_bad(caption_font_bad),
        .map_cache_we(caption_map_we),.map_cache_address(caption_map_address),.map_cache_slot(caption_map_slot),.response_mask(caption_response_mask),
        .cache_we(caption_we),.cache_address(caption_address),.cache_row(caption_glyph));
    lights_fat32_media #(.MAX_IMAGES(MAX_IMAGES),.CAPTIONS(CAPTIONS),.TF_FONT(CAPTIONS),.VARIABLE_BMP(R4)) u_media(
        .clk(clk),.rst(rst),.sd_init_done(sd_init_done),.bmp_width(bmp_width),.bmp_height(bmp_height),
        .idle(source_idle),.catalog_ready(catalog_ready),.image_count(image_count),.catalog_mask(catalog_mask),
        .error_code(source_error),.fault_present(source_fault_present),.state_code(source_state),.load_start(load_start),.load_index(source_load_index),
        .source_number(source_number),.source_success(raw_success),.write_req(raw_write_req),.write_req_ack(write_req_ack),
        .caption_we(text_we),.caption_address(text_address),.caption_glyph(text_point),
        .caption_ready(caption_ready),.caption_lengths(caption_lengths),.caption_errors(caption_errors),
        .font_request(font_request),.font_release(font_release),.font_chain_fault(font_chain_fault),.font_lba(font_lba),
        .font_grant(font_grant),.font_sector_done(font_sector_done),.font_buffer_addr(font_buffer_addr),.font_buffer_byte(font_buffer_byte),
        .font_found(font_found),.font_duplicate(font_duplicate),.font_cluster(font_cluster),.font_size(font_size),
        .font_fat_base(font_fat_base),.font_data_base(font_data_base),.font_max_cluster(font_max_cluster),
        .font_volume_end(font_volume_end),.font_cluster_shift(font_cluster_shift),
        .service_request(1'b0),.service_release(1'b0),.service_chain_fault(1'b0),
        .service_lba(32'd0),.service_buffer_addr(9'd0),
        .image_begin(image_begin),.image_stream_open(image_stream_open),.source_width(source_width),.source_height(source_height),
        .pixel_ready(fit_ready),.pixel_valid(raw_pixel_valid),.pixel(raw_pixel),.sd_read(sd_read),.sd_lba(sd_lba),.sd_byte(sd_byte),.sd_valid(sd_valid),.sd_end(sd_end));
    sd_card_top sd_card_top_m0(
        .clk(clk),.rst(rst),.SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),
        .sd_init_done(sd_init_done),.sd_sec_read(sd_read),.sd_sec_read_addr(sd_lba),
        .sd_sec_read_data(sd_byte),.sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
        .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
        .sd_sec_write_data_req(),.sd_sec_write_end());
    assign debug_observe={error_code,image_count,source_number,catalog_ready,sd_init_done,
        display_valid,auto_play_en,load_busy,load_start,write_req,write_finish_pulse,
        source_idle,source_done_seen,fault_locked,shown_mode,shown_valid};
endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse,
    output wire button_stable_out
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

assign button_stable_out = button_stable;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule

module key_short_long_press #(
    parameter integer CLK_FREQ_HZ  = 100_000_000,
    parameter integer DEBOUNCE_MS  = 20,
    parameter integer LONG_PRESS_MS = 800
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,
    output reg  short_press_pulse,
    output reg  long_press_pulse
);

localparam integer LONG_PRESS_CYCLES = (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;

wire button_stable;
wire press_pulse_unused;
reg [31:0] hold_cnt;
reg        press_active;
reg        long_press_fired;

key_press_debounce #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .DEBOUNCE_MS(DEBOUNCE_MS)
) u_debounce (
    .clk              (clk),
    .rst              (rst),
    .button_in        (button_in),
    .press_pulse      (press_pulse_unused),
    .button_stable_out(button_stable)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        short_press_pulse <= 1'b0;
        long_press_pulse  <= 1'b0;
        hold_cnt          <= 32'd0;
        press_active      <= 1'b0;
        long_press_fired  <= 1'b0;
    end else begin
        short_press_pulse <= 1'b0;
        long_press_pulse  <= 1'b0;

        if (!button_stable) begin
            if (!press_active) begin
                press_active     <= 1'b1;
                long_press_fired <= 1'b0;
                if (LONG_PRESS_CYCLES <= 1) begin
                    hold_cnt         <= 32'd0;
                    long_press_pulse <= 1'b1;
                    long_press_fired <= 1'b1;
                end else begin
                    hold_cnt <= 32'd1;
                end
            end else if (!long_press_fired) begin
                if (hold_cnt >= (LONG_PRESS_CYCLES - 1)) begin
                    hold_cnt         <= hold_cnt;
                    long_press_pulse <= 1'b1;
                    long_press_fired <= 1'b1;
                end else begin
                    hold_cnt <= hold_cnt + 32'd1;
                end
            end
        end else begin
            if (press_active && !long_press_fired)
                short_press_pulse <= 1'b1;
            hold_cnt         <= 32'd0;
            press_active     <= 1'b0;
            long_press_fired <= 1'b0;
        end
    end
end

endmodule
