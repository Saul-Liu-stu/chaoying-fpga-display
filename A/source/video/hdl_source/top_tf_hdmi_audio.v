
module top(
    input wire rx_clk,rx_ctl,input wire [3:0] rxd,
    output wire tx_clk,tx_ctl,output wire [3:0] txd,inout wire mdio,mdc,
    input                       clk,
    input                       rst_n,
    input wire sw_caption,sw_scope,sw_settings,sw_mode, // onboard SW1=C8 / SW2=C7, high=show
    input                       key1,           // physical KEY2=B2: previous/minus
    input                       key3, // physical KEY3=B1: confirm/play/back
    input                       key2,           // physical KEY4=C1: next/plus

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter integer ENABLE_DIAGNOSTIC_DISPLAY = 0;

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter [20:0] FRAME_PIXELS  = 21'd307200;   // 640*480
parameter [20:0] BUF0_ADDR     = 21'd0;
parameter [20:0] BUF1_ADDR     = FRAME_PIXELS;
parameter [20:0] BUF2_ADDR     = 2*FRAME_PIXELS;
parameter [20:0] BUF3_ADDR     = 3*FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire net_clk_125;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;
wire        display_enable;
wire audio_play_started;
wire presented_bank,presented_valid,presented_pulse;
wire [31:0] write_identity_sd,display_identity_sd,active_read_identity_mem,active_write_identity_mem;
wire [20:0] write_rect_first_sd,write_rect_length_sd;
wire [10:0] write_rect_width_sd;wire [11:0] write_rect_jump_sd;wire sd_write_ready;
wire ui_hs,ui_vs,ui_de,ui_identity_valid;
wire ui_style_we_sd,ui_style_valid_sd,ui_style_failed_sd;wire [11:0] ui_style_address_sd;wire [7:0] ui_style_byte_sd;wire [119:0] ui_style_palette_sd;
wire [15:0] media_health_sd,missing_images_sd;wire spectrum_select_sd;
wire [23:0] error_rgb;wire error_active;
wire [32:0] media_diagnostics_pixel;
wire [23:0] spectrum_rgb;wire spectrum_active,spectrum_selected;
wire fft_valid;wire [159:0] fft_bars;
wire [23:0] select_rgb,scope_rgb;wire scope_active;wire [1:0] audio_mode;
wire caption_visible,scope_visible;
wire settings_open,settings_active;wire [1:0] settings_item;
wire [3:0] settings_brightness,settings_contrast,settings_volume;
wire [23:0] adjusted_picture,settings_rgb;
wire raw_audio_valid;wire [23:0] raw_audio_left,raw_audio_right;wire [1:0] raw_audio_mode;
wire [23:0] ui_rgb;wire [31:0] ui_identity;
reg [31:0] caption_identity1,caption_identity2,caption_identity3;
reg [2:0] caption_identity_valid;
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) begin caption_identity1<=0;caption_identity2<=0;caption_identity3<=0;caption_identity_valid<=0;end
    else begin caption_identity1<=actual_identity_pixel;caption_identity2<=caption_identity1;caption_identity3<=caption_identity2;
        caption_identity_valid<={caption_identity_valid[1:0],actual_identity_valid_pixel};end
end
wire [31:0] requested_identity_pixel,actual_identity_pixel;
wire [117:0] pose_sd,desired_pose_pixel,active_pose_mem,frame_pose_pixel,frame_pose_sd;
wire r5_frame_valid_sd,region_identity_valid;
wire [31:0] region_identity_pixel;
reg [117:0] requested_pose_hold,actual_pose_hold,sent_display_pose;
reg actual_pose_epoch;
wire [31:0] write_done_identity_sd,presented_identity_sd,frame_authorizations_sd,frame_authorizations_pixel;
wire write_done_valid_sd,presented_identity_valid_sd,actual_identity_valid_pixel;
wire frame_read_underflow,frame_write_overflow;
wire video_startup_ready;

wire [31:0] debug_sd_observe;
wire debug_hdmi_locked;
wire [19:0] debug_digits;
wire [6:0] debug_seg0, debug_seg1, debug_seg2, debug_seg3, debug_seg4;
wire [3:0]  state_code;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire [1:0] active_read_index_mem;
wire active_read_valid_mem;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

wire        audio_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire tone_tick;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

wire sys_pll_lock;
wire video_pll_lock;
wire pll_reset;
wire reset_request;
wire soft_recovery_reset,hard_rst_sd,hard_rst_mem,hard_rst_net,hard_rst_ref;
wire rst_ref;
wire rst_sd;
wire rst_mem;
wire rst_net;
wire rst_video;
wire rst_audio;
startup_reset_controller u_startup_reset (
    .ref_clk(clk), .rst_n(rst_n), .soft_reset(soft_recovery_reset),
    .sys_locked(sys_pll_lock), .video_locked(video_pll_lock),
    .audio_locked(audio_pll_lock),
    .sd_clk(sd_card_clk), .mem_clk(ext_mem_clk), .net_clk(net_clk_125),
    .pixel_clk(video_clk), .audio_clk(audio_mclk),
    .pll_reset(pll_reset), .reset_request(reset_request),
    .rst_ref(rst_ref), .rst_sd(rst_sd), .rst_mem(rst_mem), .rst_net(rst_net),
    .rst_video(rst_video), .rst_audio(rst_audio),
    .rst_sd_hard(hard_rst_sd),.rst_mem_hard(hard_rst_mem),.rst_net_hard(hard_rst_net),.rst_ref_hard(hard_rst_ref)
);

sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (net_clk_125),
    .clk2_out   (ext_mem_clk),
    .clk3_out   (ext_mem_clk_sft),
    .reset      (pll_reset),
    .extlock    (sys_pll_lock)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (pll_reset),
    .extlock    (video_pll_lock)
);

PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (pll_reset),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

wire display_mailbox_ready,desired_identity_valid_pixel;
wire [31:0] desired_identity_pixel=desired_pose_pixel[117:86];
(* syn_preserve=1, syn_keep=1 *) reg [31:0] write_identity_hold_sd;
(* syn_preserve=1, syn_keep=1 *) reg [20:0] write_first_hold_sd;
reg [20:0] write_length_hold_sd;
(* syn_preserve=1, syn_keep=1 *) reg [10:0] write_width_hold_sd;
(* syn_preserve=1, syn_keep=1 *) reg [11:0] write_jump_hold_sd;
(* syn_preserve=1 *) reg [2:0] frame_identity_ack_sync,read_fault_sync;
reg [31:0] requested_identity_hold,actual_identity_hold;
reg identity_ack_seen,actual_identity_valid;
assign requested_identity_pixel=requested_pose_hold[117:86];
assign actual_identity_pixel=region_identity_pixel;
assign actual_identity_valid_pixel=region_identity_valid;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if(rst_sd) begin sent_display_pose<=0;read_fault_sync[2:1]<=0;write_identity_hold_sd<=0;
        write_first_hold_sd<=0;write_length_hold_sd<=0;write_width_hold_sd<=0;write_jump_hold_sd<=0;end
    else begin
        write_identity_hold_sd<=write_identity_sd;
        write_first_hold_sd<=write_rect_first_sd;write_length_hold_sd<=write_rect_length_sd;
        write_width_hold_sd<=write_rect_width_sd;write_jump_hold_sd<=write_rect_jump_sd;
        read_fault_sync[2:1]<=read_fault_sync[1:0];
        if(display_mailbox_ready && pose_sd[117]) sent_display_pose<=pose_sd;
    end
end
always @(negedge sd_card_clk or posedge rst_sd) begin
    if(rst_sd) read_fault_sync[0]<=0;
    else read_fault_sync[0]<=frame_read_underflow;
end
lights_r4_frame_mailbox #(.WIDTH(118),.SOURCE_ACK_FALLING(1)) u_display_identity_bridge(
    .source_clk(sd_card_clk),.source_rst(rst_sd),.source_ready(display_mailbox_ready),
    .source_valid(pose_sd[117] && pose_sd!=sent_display_pose),.source_data(pose_sd),
    .target_clk(video_clk),.target_rst(rst_video),.target_ready(1'b1),
    .target_valid(desired_identity_valid_pixel),.target_data(desired_pose_pixel));
always @(posedge video_clk or posedge rst_video) begin
    if(rst_video) begin frame_identity_ack_sync<=0;requested_identity_hold<=0;actual_identity_hold<=0;requested_pose_hold<=0;actual_pose_hold<=0;actual_pose_epoch<=0;identity_ack_seen<=0;actual_identity_valid<=0;end
    else begin
        frame_identity_ack_sync<={frame_identity_ack_sync[1:0],video_read_req_ack};
        if(!video_read_req && !frame_identity_ack_sync[2]) requested_pose_hold<=desired_pose_pixel;
        if(frame_identity_ack_sync[2] && !identity_ack_seen) begin
            actual_pose_hold<=requested_pose_hold;actual_pose_epoch<=~actual_pose_epoch;
            actual_identity_valid<=requested_pose_hold[117];identity_ack_seen<=1;
        end
        if(!frame_identity_ack_sync[2]) identity_ack_seen<=0;
    end
end
lights_frame_mailbox u_write_completion_bridge(
    .source_clk(ext_mem_clk),.source_rst(rst_mem),.source_valid(frame_write_finish),
    .source_data(active_write_identity_mem),.source_ready(),
    .target_clk(sd_card_clk),.target_rst(rst_sd),.target_ready(1'b1),
    .target_valid(write_done_valid_sd),.target_data(write_done_identity_sd));
lights_r4_frame_mailbox #(.WIDTH(118),.TARGET_FIRST_FALLING(1),.TARGET_SAMPLE_FALLING(1)) u_presented_identity_bridge(
    .source_clk(video_clk),.source_rst(rst_video),.source_valid(presented_pulse),
    .source_data(frame_pose_pixel),.source_ready(),
    .target_clk(sd_card_clk),.target_rst(rst_sd),.target_ready(1'b1),
    .target_valid(r5_frame_valid_sd),.target_data(frame_pose_sd));

wire caption_we,caption_active_sd,caption_bank_sd,caption_enable_pixel,caption_bank_pixel;
wire read_bank_pixel,read_valid_pixel,caption_boundary,caption_commit;
wire [1:0] caption_banks_sd,caption_banks_pixel;
wire [6:0] caption_count_sd,caption_count_pixel;
wire [1:0] caption_role_sd,caption_role_pixel;
wire caption_commit_ready,caption_bridge_ready;
wire [44:0] caption_credit;
wire [95:0] caption_source_key;
(* syn_preserve=1, syn_keep=1 *) reg [95:0] caption_key_stage;
wire [44:0] caption_live={frame_authorizations_sd,caption_active_sd,
    caption_active_sd ? caption_role_sd : 2'd0,
    caption_active_sd ? caption_count_sd : 7'd0,
    caption_active_sd ? caption_bank_sd : 1'b0,
    caption_active_sd ? caption_banks_sd : 2'd0};
(* syn_preserve=1, syn_keep=1 *) reg [44:0] caption_stage;
always @(posedge sd_card_clk or posedge rst_sd) begin
    if(rst_sd) begin caption_stage<=0;caption_key_stage<=0;end
    else begin caption_stage<=caption_live;caption_key_stage<=caption_source_key;end
end
assign caption_commit_ready=caption_bridge_ready && caption_credit==caption_stage && caption_key_stage==caption_source_key;
wire [9:0] caption_address;
wire [7:0] caption_generation;
wire caption_request_toggle,caption_cancel_toggle,caption_response_toggle,caption_response_good,caption_font_bad;
wire [55:0] caption_request_payload,caption_sd_payload;
wire caption_sd_request,caption_request_expired;
(* syn_preserve=1 *) reg caption_cancel_first_sd;
always @(negedge sd_card_clk or posedge rst_sd)
 if(rst_sd)caption_cancel_first_sd<=0;else caption_cancel_first_sd<=caption_cancel_toggle;
lights_r4_font_request_bridge u_font_request_bridge(
    .pixel_clk(video_clk),.pixel_rst(rst_video),.request_toggle(caption_request_toggle),
    .cancel_toggle(caption_cancel_toggle),.request_payload(caption_request_payload),
    .sd_clk(sd_card_clk),.sd_rst(rst_sd),.sd_request_toggle(caption_sd_request),
    .sd_request_expired(caption_request_expired),.sd_request_payload(caption_sd_payload));
wire caption_map_we;
wire [6:0] caption_map_address;
wire [4:0] caption_map_slot;
wire [31:0] caption_response_mask;
wire [23:0] caption_glyph;
wire caption_hs,caption_vs,caption_de;
wire [23:0] caption_rgb;
wire dimension_update_sd;wire [4:0] dimension_picture_sd;wire [21:0] dimension_size_sd;

remote_display_proxy #(.CLK_FREQ_HZ(50_000_000)) sd_card_bmp_m0(
    .dimension_update(dimension_update_sd),.dimension_picture(dimension_picture_sd),.dimension_size(dimension_size_sd),
    .sys_clk(clk),.sys_rst(rst_ref),.net_clk(net_clk_125),.net_rst(rst_net),
    .hard_rst(hard_rst_sd),.hard_sys_rst(hard_rst_ref),.hard_net_rst(hard_rst_net),.soft_reset(soft_recovery_reset),
    .rx_clk(rx_clk),.rx_ctl(rx_ctl),.rxd(rxd),.tx_clk(tx_clk),.tx_ctl(tx_ctl),.txd(txd),.mdio(mdio),.mdc(mdc),
    .write_ready(sd_write_ready),.write_rect_first(write_rect_first_sd),.write_rect_length(write_rect_length_sd),
    .write_rect_width(write_rect_width_sd),.write_rect_jump(write_rect_jump_sd),
    .write_done_valid(write_done_valid_sd),.write_done_identity(write_done_identity_sd),
    .presented_identity_valid(1'b0),.presented_identity(32'd0),
    .r5_frame_valid(r5_frame_valid_sd),.r5_frame_pose(frame_pose_sd),.r5_pose(pose_sd),
    .frame_transfer_fault(read_fault_sync[2] || frame_write_overflow),
    .write_identity(write_identity_sd),.display_identity(display_identity_sd),.frame_authorizations(frame_authorizations_sd),
    .clk               (sd_card_clk),
    .rst               (rst_sd),
    .settings_block(settings_open),
    .key_next          (key1),
    .key_auto          (key3),
    .key_prev(key2),.mode_select(sw_mode),
    .debug_observe     (debug_sd_observe),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .caption_we(caption_we),.caption_address(caption_address),.caption_glyph(caption_glyph),
    .caption_active(caption_active_sd),.caption_bank(caption_bank_sd),
    .caption_banks(caption_banks_sd),.caption_commit_ready(caption_commit_ready),.caption_source_key(caption_source_key),
    .caption_request_toggle(caption_sd_request),.caption_cancel_toggle(caption_cancel_first_sd),.caption_request_expired(caption_request_expired),
    .caption_request_payload(caption_sd_payload),.caption_response_toggle(caption_response_toggle),
    .caption_response_good(caption_response_good),.caption_font_bad(caption_font_bad),
    .caption_map_we(caption_map_we),.caption_map_address(caption_map_address),.caption_map_slot(caption_map_slot),.caption_response_mask(caption_response_mask),
    .caption_role(caption_role_sd),.caption_count(caption_count_sd),

    .read_active_buf_async(active_read_index_mem[0]),
    .read_active_valid_async(active_read_valid_mem),
    .play_started_async (audio_play_started),
    .presented_bank_async(presented_bank),
    .presented_valid_async(presented_valid),
    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso),
    .audio_pixel_clk(video_clk),.audio_pixel_rst(rst_video),.tone_tick(tone_tick),.tone_left(24'd0),.tone_right(24'd0), // quiet 48kHz placeholder until WAV PCM is ready
    .ui_style_we(ui_style_we_sd),.ui_style_address(ui_style_address_sd),.ui_style_byte(ui_style_byte_sd),.ui_style_valid(ui_style_valid_sd),.ui_style_palette(ui_style_palette_sd),.ui_style_failed(ui_style_failed_sd),
    .media_health(media_health_sd),.missing_images(missing_images_sd),.spectrum_select(spectrum_select_sd),
    .pcm_tick(raw_audio_valid),.pcm_left(raw_audio_left),.pcm_right(raw_audio_right),.pcm_mode(raw_audio_mode)
);

(* syn_preserve = 1 *) reg [3:0] debug_state_sample0, debug_state_sample1, debug_state_sample2;
always @(posedge clk or posedge rst_ref) begin
    if (rst_ref) begin
        debug_state_sample0 <= 0;
        debug_state_sample1 <= 0;
        debug_state_sample2 <= 0;
    end else begin
        debug_state_sample0 <= state_code;
        debug_state_sample1 <= debug_state_sample0;
        debug_state_sample2 <= debug_state_sample1;
    end
end
seg_decoder seg_decoder_m0(
    .bin_data          (debug_state_sample2),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (~rst_ref),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,seg_data_0}),
    .seg_data_1        ({1'b1,7'h40}),
    .seg_data_2        ({1'b1,7'h40}),
    .seg_data_3        ({1'b1,7'h40}),
    .seg_data_4        ({1'b1,7'h40}),
    .seg_data_5        ({1'b1,7'h08})
);

video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .frame_valid_async (desired_identity_pixel[31]),
    .startup_ready     (video_startup_ready),
    .display_enable    (display_enable),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_video),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

assign vout_data = display_enable ? vout_data_raw : 24'd0;

lights_r5_pixel_identity u_region_identity(
    .clk(video_clk),.rst(rst_video),.de(de),.vs(vs),.frame_enabled(display_enable),
    .pose(actual_pose_hold),.identity(region_identity_pixel),.identity_valid(region_identity_valid));
assign read_bank_pixel=actual_pose_hold[86];
assign read_valid_pixel=actual_identity_valid;
assign presented_bank=actual_pose_hold[86];
lights_r5_frame_present #(.FRAME_PIXELS(FRAME_PIXELS)) u_frame_present(
    .clk(video_clk),.rst(rst_video),.de(ui_de),.vs(ui_vs),.frame_enabled(display_enable),
    .active_valid(actual_identity_valid && !frame_read_underflow),.active_pose(actual_pose_hold),.active_epoch(actual_pose_epoch),
    .frame_pulse(presented_pulse),.frame_pose(frame_pose_pixel),.presented_valid(presented_valid));


frame_read_write #(
    .FRAME_IDENTITY   (1),
    .R4               (1),
    .R5               (1),
    .R5_BORDER        (1),
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .write_rect_first(write_first_hold_sd),.write_rect_width(write_width_hold_sd),.write_rect_jump(write_jump_hold_sd),.write_ready(sd_write_ready),
    .read_frame_identity(requested_identity_pixel),.write_frame_identity(write_identity_hold_sd),
    .read_pose(requested_pose_hold),.active_read_pose(active_pose_mem),
    .active_read_identity(active_read_identity_mem),.active_write_identity(active_write_identity_mem),
    .read_rst(rst_video),.write_rst(rst_sd),.read_underflow(frame_read_underflow),.write_overflow(frame_write_overflow),
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .active_read_index (active_read_index_mem),
    .active_read_valid (active_read_valid_mem),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (BUF3_ADDR),
    .read_addr_index   (requested_identity_pixel[1:0]), // stable request payload; atomically latched by memory
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en & display_enable),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (BUF3_ADDR),
    .write_addr_index  (write_buf_idx),
    .write_len         (write_length_hold_sd),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

wire audio_source_rst;
wire video_audio_rst;
media_start_controller #(.FRAME_PIXELS(FRAME_PIXELS),
    .PIXEL_FREQ_HZ(25_000_000), .STARTUP_SETTLE_MS(3000)) u_media_start (
    .pixel_clk(video_clk), .pixel_rst(rst_video),
    .audio_clk(audio_mclk), .audio_rst(rst_audio),
    .frame_enabled(display_enable), .video_de(ui_de), .video_vs(ui_vs),
    .video_link_locked(debug_hdmi_locked), .audio_packet_valid(acr_valid),
    .startup_ready(video_startup_ready),
    .play_started(audio_play_started),
    .audio_source_rst(audio_source_rst), .video_audio_rst(video_audio_rst)
);

lights_audio_tick_source u_hdmi_audio_tone_i2s_64fs (
 .I_mclk(audio_mclk),.I_rst(rst_audio),
 .O_i2s_BCLK(audio_i2s_bclk),.O_i2s_LRCK(audio_i2s_lrck)
);

lights_audio_tick_receiver u_I2S_receiver(
 .I_clk(video_clk),.I_rst(video_audio_rst),
 .I_i2s_BCLK(audio_i2s_bclk),.I_i2s_LRCK(audio_i2s_lrck),
 .O_audio_valid(tone_tick)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (video_audio_rst),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

lights_settings_control u_settings(.clk(video_clk),.rst(rst_video),.vs(vs),.sw_settings(sw_settings),
 .key1(key2),.key2(key1),.key3(key3),.menu_open(settings_open),.item(settings_item),
 .brightness(settings_brightness),.contrast(settings_contrast),.volume(settings_volume));
lights_picture_adjust u_picture_adjust(.rgb(vout_data),.brightness(settings_brightness),
 .contrast(settings_contrast),.adjusted(adjusted_picture));
lights_volume u_volume(.clk(video_clk),.rst(rst_video),.in_valid(raw_audio_valid),
 .in_left(raw_audio_left),.in_right(raw_audio_right),.in_mode(raw_audio_mode),.volume(settings_volume),
 .out_valid(audio_valid),.out_left(audio_left_data),.out_right(audio_right_data),.out_mode(audio_mode));

lights_overlay_switches u_overlay_switches(.clk(video_clk),.rst(rst_video),.vs(vs),
 .sw_caption(sw_caption),.sw_scope(sw_scope),.caption_visible(caption_visible),.scope_visible(scope_visible));

lights_r4_caption_bridge u_caption_bridge(
    .frame_authorizations(caption_stage[44:13]),.frame_authorizations_pixel(frame_authorizations_pixel),    .sd_clk(sd_card_clk),.sd_rst(rst_sd),.active(caption_stage[12]),
    .role(caption_stage[11:10]),.count(caption_stage[9:3]),.bank(caption_stage[2]),
    .allowed_banks(caption_stage[1:0]),.allowed_banks_pixel(caption_banks_pixel),.source_ready(caption_bridge_ready),.source_credit(caption_credit),
    .pixel_clk(video_clk),.pixel_rst(rst_video),.frame_boundary(caption_boundary),
    .enable_pixel(caption_enable_pixel),.bank_pixel(caption_bank_pixel),
    .role_pixel(caption_role_pixel),.count_pixel(caption_count_pixel),
    .generation_pixel(caption_generation),.commit_pixel(caption_commit));
lights_caption_overlay #(.BANK_AUTHORIZATION(1),.FRAME_IDENTITY(1)) u_caption_overlay(
    .read_frame_identity(actual_identity_pixel),.frame_authorizations(frame_authorizations_pixel),    .sd_clk(sd_card_clk),.cache_we(caption_we),.cache_address(caption_address),.cache_row(caption_glyph),
    .request_toggle(caption_request_toggle),.cancel_toggle(caption_cancel_toggle),.request_payload(caption_request_payload),
    .response_toggle(caption_response_toggle),.response_good(caption_response_good),.font_bad(caption_font_bad),
    .map_cache_we(caption_map_we),.map_cache_address(caption_map_address),.map_cache_slot(caption_map_slot),.response_mask(caption_response_mask),
    .clk(video_clk),.rst(rst_video),.hs(hs),.vs(vs),.de(de),.rgb(adjusted_picture),
    .frame_enabled(display_enable),.read_bank(read_bank_pixel),.read_valid(read_valid_pixel),
    .allowed_banks(caption_banks_pixel),
    .enable(caption_enable_pixel),.metadata_bank(caption_bank_pixel),.role(caption_role_pixel),
    .count(caption_count_pixel),.generation(caption_generation),.frame_boundary(caption_boundary),
    .visible(caption_visible),
    .out_hs(caption_hs),.out_vs(caption_vs),.out_de(caption_de),.out_rgb(caption_rgb));

lights_select_overlay #(.TF_STYLE(1)) u_select_overlay(
    .clk(video_clk),.rst(rst_video),.hs(caption_hs),.vs(caption_vs),.de(caption_de),.rgb(caption_rgb),
    .identity(caption_identity3),.identity_valid(caption_identity_valid[2]),
    .out_hs(ui_hs),.out_vs(ui_vs),.out_de(ui_de),.out_rgb(select_rgb),.out_identity(ui_identity),.out_identity_valid(ui_identity_valid),
    .style_clk(sd_card_clk),.style_we(ui_style_we_sd),.style_address(ui_style_address_sd),.style_byte(ui_style_byte_sd),.style_valid_sd(ui_style_valid_sd),.style_palette_sd(ui_style_palette_sd));

wire [1:0] visualization_mode=caption_identity_valid[2] && caption_identity3[31] &&
 caption_identity3[30:29]==2'd2 ? audio_mode : 2'd0;
lights_audio_scope_overlay u_audio_scope(
 .clk(video_clk),.rst(rst_video),.hs(caption_hs),.vs(caption_vs),.de(caption_de),.rgb(caption_rgb),
 .frame_enabled(display_enable && scope_visible && !spectrum_selected),.identity(caption_identity3),.identity_valid(caption_identity_valid[2]),
 .pcm_valid(audio_valid),.pcm_left(audio_left_data),.pcm_mode(visualization_mode),
 .out_hs(),.out_vs(),.out_de(),.out_rgb(scope_rgb),.out_identity(),.out_identity_valid(),.out_active(scope_active));
lights_settings_overlay u_settings_overlay(.clk(video_clk),.rst(rst_video),.vs(caption_vs),.de(caption_de),
 .source_clk(sd_card_clk),.source_rst(rst_sd),.dimension_update(dimension_update_sd),.dimension_picture(dimension_picture_sd),.dimension_size(dimension_size_sd),.view_identity(actual_pose_hold[117:86]),
 .frame_enabled(display_enable),.menu_open(settings_open),.item(settings_item),
 .brightness(settings_brightness),.contrast(settings_contrast),.volume(settings_volume),
 .out_active(settings_active),.out_rgb(settings_rgb));
wire [32:0] diagnostics_sd={spectrum_select_sd,media_health_sd,missing_images_sd};
reg [32:0] diagnostics_sent;
wire diagnostics_ready;
always @(posedge sd_card_clk or posedge rst_sd)
 if(rst_sd)diagnostics_sent<=0;
 else if(diagnostics_ready && diagnostics_sd!=diagnostics_sent)diagnostics_sent<=diagnostics_sd;
lights_frame_mailbox #(.WIDTH(33),.TARGET_SAMPLE_FALLING(1)) u_media_diagnostics(
 .source_clk(sd_card_clk),.source_rst(rst_sd),.source_valid(diagnostics_sd!=diagnostics_sent),
 .source_data(diagnostics_sd),.source_ready(diagnostics_ready),
 .target_clk(video_clk),.target_rst(rst_video),.target_ready(1'b1),
 .target_valid(),.target_data(media_diagnostics_pixel));
lights_media_error_overlay u_media_error(.clk(video_clk),.rst(rst_video),.vs(caption_vs),.de(caption_de),
 .health(media_diagnostics_pixel[31:16]),.missing_images(media_diagnostics_pixel[15:0]),
 .out_active(error_active),.out_rgb(error_rgb));
lights_fft512 u_fft(.clk(video_clk),.rst(rst_video),.pcm_valid(audio_valid),.pcm_sample(audio_left_data[23:8]),
 .bars_valid(fft_valid),.bars(fft_bars));
lights_spectrum_overlay u_spectrum(.clk(video_clk),.rst(rst_video),.vs(caption_vs),.de(caption_de),
 .frame_enabled(display_enable && scope_visible),.select_spectrum(media_diagnostics_pixel[32]),.pcm_mode(visualization_mode),
 .bars_valid(fft_valid),.bars(fft_bars),.selected(spectrum_selected),.out_active(spectrum_active),.out_rgb(spectrum_rgb));
assign ui_rgb=error_active?error_rgb:settings_active?settings_rgb:
 (scope_visible && spectrum_selected && spectrum_active)?spectrum_rgb:
 (scope_visible && !spectrum_selected && scope_active)?scope_rgb:select_rgb;

video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_video),
    .I_vs          (ui_vs),
    .I_de          (ui_de),
    .I_rgb         (ui_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_video),
    .O_pulse (edid_trig)
);

hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_video),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (debug_hdmi_locked),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (reset_request),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);


generate
if (ENABLE_DIAGNOSTIC_DISPLAY) begin : g_diagnostic
regression_status_r4 u_regression_status (
    .ref_clk(clk), .rst_ref(rst_ref), .sd_clk(sd_card_clk), .rst_sd(rst_sd),
    .pixel_clk(video_clk), .rst_pixel(rst_video), .sd_observe(debug_sd_observe),
    .axis_valid(axis_s_valid), .axis_ready(axis_s_ready),
    .video_locked(debug_hdmi_locked), .display_enable(display_enable),
    .play_started(audio_play_started), .digits(debug_digits)
);
seg_decoder debug_decoder0 (.bin_data(debug_digits[19:16]), .seg_data(debug_seg0));
seg_decoder debug_decoder1 (.bin_data(debug_digits[15:12]), .seg_data(debug_seg1));
seg_decoder debug_decoder2 (.bin_data(debug_digits[11:8]), .seg_data(debug_seg2));
seg_decoder debug_decoder3 (.bin_data(debug_digits[7:4]), .seg_data(debug_seg3));
seg_decoder debug_decoder4 (.bin_data(debug_digits[3:0]), .seg_data(debug_seg4));
end else begin : g_no_diagnostic
    assign debug_digits = 20'd0;
    assign debug_seg0 = 7'b1111111;
    assign debug_seg1 = 7'b1111111;
    assign debug_seg2 = 7'b1111111;
    assign debug_seg3 = 7'b1111111;
    assign debug_seg4 = 7'b1111111;
end
endgenerate
endmodule

module lights_r4_caption_bridge(
 input wire sd_clk,sd_rst,active,input wire [1:0] role,input wire [6:0] count,
 input wire bank,input wire [1:0] allowed_banks,input wire [31:0] frame_authorizations,
 output wire source_ready,output wire [44:0] source_credit,input wire pixel_clk,pixel_rst,frame_boundary,
 output reg enable_pixel,bank_pixel,output reg [1:0] role_pixel,allowed_banks_pixel,
 output reg [6:0] count_pixel,output reg [7:0] generation_pixel,
 output reg [31:0] frame_authorizations_pixel,output reg commit_pixel);
 reg was_active;reg [7:0] generation,next_generation;
 (* syn_preserve=1 *) reg [52:0] desired_stage,payload_hold,credit_stamp;
 (* syn_preserve=1 *) reg request_toggle,ack_toggle;
 (* syn_preserve=1 *) reg [2:0] request_sync,ack_sync;
 reg payload_equal;
 wire [7:0] effective_generation=active && !was_active ? next_generation : generation;
 wire [52:0] current_desired={active ? frame_authorizations : 32'd0,effective_generation,active,
  active ? role : 2'd0,active ? count : 7'd0,active ? bank : 1'b0,active ? allowed_banks : 2'd0};
 assign source_credit={credit_stamp[52:21],credit_stamp[12:0]};
 assign source_ready=request_toggle==ack_sync[2] && payload_equal && credit_stamp[20:13]==effective_generation;
 always @(posedge sd_clk or posedge sd_rst) begin
  if(sd_rst) begin
   was_active<=0;generation<=0;next_generation<=1;desired_stage<=0;payload_hold<=0;
   credit_stamp<=0;payload_equal<=0;request_toggle<=0;ack_sync[2:1]<=0;
  end else begin
   was_active<=active;
   if(active && !was_active) begin generation<=next_generation;next_generation<=next_generation+1'b1;end
   desired_stage<=current_desired;
   payload_equal<=desired_stage==payload_hold;credit_stamp<=desired_stage;
   ack_sync[2:1]<=ack_sync[1:0];
   if(request_toggle==ack_sync[2] && !payload_equal) begin
    payload_hold<=desired_stage;request_toggle<=~request_toggle;
   end
  end
 end
 always @(negedge sd_clk or posedge sd_rst) begin
  if(sd_rst)ack_sync[0]<=0;else ack_sync[0]<=ack_toggle;
 end
 always @(posedge pixel_clk or posedge pixel_rst) begin
  if(pixel_rst) begin
   request_sync<=0;ack_toggle<=0;enable_pixel<=0;bank_pixel<=0;role_pixel<=0;
   allowed_banks_pixel<=0;count_pixel<=0;generation_pixel<=0;frame_authorizations_pixel<=0;commit_pixel<=0;
  end else begin
   request_sync<={request_sync[1:0],request_toggle};commit_pixel<=0;
   if(frame_boundary && request_sync[2]!=ack_toggle) begin
    {frame_authorizations_pixel,generation_pixel,enable_pixel,role_pixel,count_pixel,bank_pixel,allowed_banks_pixel}<=payload_hold;
    ack_toggle<=request_sync[2];commit_pixel<=1;
   end
  end
 end
endmodule

module regression_status_r4(
 input wire ref_clk,rst_ref,sd_clk,rst_sd,pixel_clk,rst_pixel,
 input wire [31:0] sd_observe,input wire axis_valid,axis_ready,video_locked,display_enable,play_started,
 output wire [19:0] digits);
 reg finish_seen,request_seen,source_busy_seen;
 always @(posedge sd_clk or posedge rst_sd) begin
  if(rst_sd)begin finish_seen<=0;request_seen<=0;source_busy_seen<=0;end
  else if(sd_observe[8])begin finish_seen<=0;request_seen<=0;source_busy_seen<=0;end
  else begin
   if(sd_observe[9] && sd_observe[6])finish_seen<=1;
   if(sd_observe[9] && sd_observe[7])request_seen<=1;
   if(sd_observe[9] && !sd_observe[5])source_busy_seen<=1;
  end
 end
 reg ready_violation,picture_seen;
 always @(posedge pixel_clk or posedge rst_pixel) begin
  if(rst_pixel)begin ready_violation<=0;picture_seen<=0;end
  else begin
   if(axis_valid && !axis_ready)ready_violation<=1;
   if(axis_valid && display_enable)picture_seen<=1;
  end
 end
 (* syn_preserve=1 *) reg [20:0] sample0,sample1,sample2;
 always @(negedge ref_clk or posedge rst_ref) begin
  if(rst_ref)sample0<=0;
  else sample0<={sd_observe[31:24],sd_observe[23:19],ready_violation,video_locked,picture_seen,play_started,
   finish_seen,request_seen,source_busy_seen,sd_observe[4]};
 end
 always @(posedge ref_clk or posedge rst_ref) begin
  if(rst_ref)begin sample1<=0;sample2<=0;end
  else begin sample1<=sample0;sample2<=sample1;end
 end
 wire [4:0] count=sample2[12:8];
 wire [3:0] tens=count>=10 ? 4'd1 : 4'd0;
 wire [3:0] units=count>=10 ? count-5'd10 : count[3:0];
 assign digits=sample2[20:13]!=0 ? {4'he,sample2[20:13],sample2[7:0]} : {4'ha,tens,units,sample2[7:0]};
endmodule

`timescale 1ns/1ps
module lights_r4_frame_mailbox #(parameter integer WIDTH=32,TARGET_SAMPLE_FALLING=0,SOURCE_ACK_FALLING=0,TARGET_FIRST_FALLING=0)(
    input wire source_clk,source_rst,source_valid,
    input wire [WIDTH-1:0] source_data,
    output wire source_ready,
    input wire target_clk,target_rst,target_ready,
    output reg target_valid,
    output reg [WIDTH-1:0] target_data
);
    (* syn_preserve=1 *) reg [WIDTH-1:0] payload_hold;
    (* syn_preserve=1 *) reg [WIDTH-1:0] payload_sample;
    (* syn_preserve=1 *) reg request_toggle,ack_toggle;
    (* syn_preserve=1 *) reg [2:0] request_sync,ack_sync;
    assign source_ready=request_toggle==ack_sync[2];
    always @(posedge source_clk or posedge source_rst) begin
        if(source_rst) begin payload_hold<=0;request_toggle<=0;ack_sync[2:1]<=0;if(!SOURCE_ACK_FALLING)ack_sync[0]<=0;end
        else begin
            ack_sync[2:1]<=ack_sync[1:0];if(!SOURCE_ACK_FALLING)ack_sync[0]<=ack_toggle;
            if(source_valid && source_ready) begin
                payload_hold<=source_data;request_toggle<=~request_toggle;
            end
        end
    end
    generate if(SOURCE_ACK_FALLING) begin : g_source_ack_phase
    always @(negedge source_clk or posedge source_rst)
      if(source_rst)ack_sync[0]<=0;else ack_sync[0]<=ack_toggle;
    end endgenerate
    generate if(TARGET_FIRST_FALLING) begin : g_target_request_phase
    always @(negedge target_clk or posedge target_rst)
      if(target_rst)request_sync[0]<=0;else request_sync[0]<=request_toggle;
    end endgenerate
    generate if(TARGET_SAMPLE_FALLING) begin : g_falling_sample
    always @(negedge target_clk or posedge target_rst) begin
        if(target_rst) payload_sample<=0;
        else payload_sample<=payload_hold;
    end
    end else begin : g_rising_sample
    always @(posedge target_clk or posedge target_rst) begin
        if(target_rst) payload_sample<=0;
        else payload_sample<=payload_hold;
    end
    end endgenerate
    always @(posedge target_clk or posedge target_rst) begin
        if(target_rst) begin request_sync[2:1]<=0;if(!TARGET_FIRST_FALLING)request_sync[0]<=0;ack_toggle<=0;target_valid<=0;target_data<=0;end
        else begin
            request_sync[2:1]<=request_sync[1:0];if(!TARGET_FIRST_FALLING)request_sync[0]<=request_toggle;
            if(!target_valid && request_sync[2]!=ack_toggle) begin
                target_data<=payload_sample;target_valid<=1;
            end else if(target_valid && target_ready) begin
                target_valid<=0;ack_toggle<=request_sync[2];
            end
        end
    end
endmodule

module lights_r4_font_request_bridge(
    input wire pixel_clk,pixel_rst,request_toggle,cancel_toggle,
    input wire [55:0] request_payload,
    input wire sd_clk,sd_rst,
    output reg sd_request_toggle,sd_request_expired,
    output reg [55:0] sd_request_payload
);
    reg [55:0] packet;
    reg token,epoch,request_seen,beat_toggle;
    reg [3:0] beat_data,send_index;
    reg [1:0] send_state;
    reg beat_ack;
    (* syn_preserve=1 *) reg [2:0] ack_sync,beat_sync,cancel_sync;
    reg beat_seen,receive_token,receive_epoch;
    reg [3:0] receive_index;
    reg [55:0] assembled;
    reg [3:0] captured;
    (* syn_preserve=1 *) reg [3:0] beat_data_phase;
    reg receive_pending;
    always @(posedge pixel_clk or posedge pixel_rst) begin
        if(pixel_rst) begin
            packet<=0;token<=0;epoch<=0;request_seen<=0;beat_toggle<=0;
            beat_data<=0;send_index<=0;send_state<=0;ack_sync<=0;
        end else begin
            ack_sync<={ack_sync[1:0],beat_ack};
            case(send_state)
                0:if(request_toggle!=request_seen) begin
                    packet<=request_payload;token<=request_toggle;epoch<=cancel_toggle;
                    request_seen<=request_toggle;send_index<=0;send_state<=1;
                end
                1:begin
                    beat_data<=send_index==0 ? {2'd0,epoch,token} : packet[3:0];
                    send_state<=2;
                end
                2:begin beat_toggle<=~beat_toggle;send_state<=3;end
                3:if(ack_sync[2]==beat_toggle) begin
                    if(send_index==14)send_state<=0;
                    else begin
                        if(send_index!=0)packet<=packet>>4;
                        send_index<=send_index+1'b1;send_state<=1;
                    end
                end
            endcase
        end
    end
    always @(negedge sd_clk or posedge sd_rst) begin
      if(sd_rst)begin beat_sync[0]<=0;cancel_sync[0]<=0;beat_data_phase<=0;end
      else begin beat_sync[0]<=beat_toggle;cancel_sync[0]<=cancel_toggle;beat_data_phase<=beat_data;end
    end
    integer lane;
    always @(posedge sd_clk or posedge sd_rst) begin
        if(sd_rst) assembled<=0;
        else if(receive_pending && receive_index!=0)
            for(lane=0;lane<14;lane=lane+1)
                if(receive_index==lane+1)assembled[lane*4 +: 4]<=captured;
    end
    always @(posedge sd_clk or posedge sd_rst) begin
        if(sd_rst) begin
            beat_ack<=0;beat_sync[2:1]<=0;cancel_sync[2:1]<=0;beat_seen<=0;
            receive_token<=0;receive_epoch<=0;receive_index<=0;captured<=0;receive_pending<=0;
            sd_request_toggle<=0;sd_request_expired<=0;sd_request_payload<=0;
        end else begin
            beat_sync[2:1]<=beat_sync[1:0];cancel_sync[2:1]<=cancel_sync[1:0];
            if(beat_sync[2]!=beat_seen && !receive_pending) begin
                beat_seen<=beat_sync[2];captured<=beat_data_phase;receive_pending<=1;
            end else if(receive_pending) begin
                receive_pending<=0;beat_ack<=beat_seen;
                if(receive_index==0) begin receive_token<=captured[0];receive_epoch<=captured[1];end
                if(receive_index==14)begin
                    sd_request_payload<={captured,assembled[51:0]};
                    sd_request_expired<=receive_epoch!=cancel_sync[2];
                    sd_request_toggle<=receive_token;receive_index<=0;
                end else receive_index<=receive_index+1'b1;
            end
        end
    end
endmodule


module lights_audio_tick_source(
 input wire I_mclk,I_rst,
 output reg O_i2s_BCLK,output reg O_i2s_LRCK
);
 reg [5:0] S_bit_cnt;
 always @(posedge I_mclk or posedge I_rst) begin
  if(I_rst) begin O_i2s_BCLK<=0;O_i2s_LRCK<=0;S_bit_cnt<=0;end
  else begin
   O_i2s_BCLK<=~O_i2s_BCLK;
   if(O_i2s_BCLK) begin
    if(S_bit_cnt==63) begin S_bit_cnt<=0;O_i2s_LRCK<=~O_i2s_LRCK;end
    else S_bit_cnt<=S_bit_cnt+1'b1;
   end
  end
 end
endmodule

module lights_audio_tick_receiver(
 input wire I_clk,I_rst,I_i2s_BCLK,I_i2s_LRCK,
 output reg O_audio_valid
);
 (* syn_preserve=1 *) reg S_i2s_bclk_1d,S_i2s_bclk_2d,S_i2s_bclk_3d;
 (* syn_preserve=1 *) reg S_i2s_lrck_1d,S_i2s_lrck_2d,S_i2s_lrck_3d;
 reg S_i2s_lrck_sync,S_right_data_valid;
 wire S_i2s_bclk_p_edge=~S_i2s_bclk_3d & S_i2s_bclk_2d;
 wire S_i2s_lrck_n_edge=~S_i2s_lrck_3d & S_i2s_lrck_sync;
 always @(posedge I_clk or posedge I_rst) begin
  if(I_rst) begin
   S_i2s_bclk_1d<=0;S_i2s_bclk_2d<=0;S_i2s_bclk_3d<=0;
   S_i2s_lrck_1d<=0;S_i2s_lrck_2d<=0;S_i2s_lrck_3d<=0;
   S_i2s_lrck_sync<=0;S_right_data_valid<=0;O_audio_valid<=0;
  end else begin
   S_i2s_bclk_1d<=I_i2s_BCLK;S_i2s_bclk_2d<=S_i2s_bclk_1d;S_i2s_bclk_3d<=S_i2s_bclk_2d;
   S_i2s_lrck_1d<=I_i2s_LRCK;S_i2s_lrck_2d<=S_i2s_lrck_1d;S_i2s_lrck_3d<=S_i2s_lrck_2d;
   if(S_i2s_bclk_p_edge) S_i2s_lrck_sync<=S_i2s_lrck_3d;
   S_right_data_valid<=S_i2s_bclk_p_edge && S_i2s_lrck_n_edge;
   O_audio_valid<=S_right_data_valid;
  end
 end
endmodule
