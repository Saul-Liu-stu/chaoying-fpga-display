`timescale 1ns/1ps
module lights_playback_control #(
    parameter integer CLK_FREQ_HZ=100_000_000,
    parameter integer AUTO_PLAY_MS=5000,
    parameter integer WRITE_FINISH_TIMEOUT=1_500_000_000,
    parameter integer EXTERNAL_COMMANDS=0
)(
    input wire clk,rst,
    input wire command_valid,
    input wire [3:0] command_index,
    output wire command_ready,play_started,
    output reg publish_pulse,
    input wire next_press,prev_press,auto_short,
    input wire catalog_ready,
    input wire [4:0] image_count,
    input wire source_idle,source_success,
    input wire [7:0] source_error,
    input wire write_finish_toggle,
    input wire read_active_buf_async,read_active_valid_async,
    input wire play_started_async, // persistent pixel-domain first full frame indication
    output reg load_start,
    output reg [3:0] load_index,
    output reg [1:0] write_buf_idx,disp_buf_idx,
    output reg display_valid,
    output reg auto_play_en,load_busy,source_done_seen,
    output wire write_finish_pulse,
    output reg fault_locked,
    output reg [7:0] error_code
);
    localparam integer AUTO_CYCLES=(CLK_FREQ_HZ/1000)*AUTO_PLAY_MS;
    (* syn_preserve=1 *) reg [2:0] read_active_buf_sync,read_active_valid_sync,wrfin_tgl_sync;
    (* syn_preserve=1 *) reg [2:0] play_started_sync;
    reg first_image_committed,write_done_seen,nav_req_pending,nav_req_is_prev;
    reg [3:0] img_idx;
    reg [1:0] pending_buf_idx;
    reg [31:0] auto_cnt,write_timer;
    wire buffer_available=!display_valid ||
        (read_active_valid_sync[2] && read_active_buf_sync[2]==disp_buf_idx[0]);
    wire manual_next=next_press && catalog_ready && display_valid && image_count>1;
    wire manual_prev=prev_press && catalog_ready && display_valid && image_count>1;
    wire manual_req=manual_next || manual_prev;
    wire manual_is_prev=manual_prev && !manual_next;
    wire auto_tick=auto_cnt>=AUTO_CYCLES-1;
    wire [3:0] next_idx=({1'b0,img_idx}+5'd1>=image_count) ? 4'd0 : img_idx+1'b1;
    wire [3:0] prev_idx=img_idx==0 ? image_count-1'b1 : img_idx-1'b1;
    wire [1:0] next_bank=!display_valid ? 2'd0 : {1'b0,~disp_buf_idx[0]};
    assign write_finish_pulse=wrfin_tgl_sync[2]^wrfin_tgl_sync[1];
    always @(posedge clk or posedge rst) begin
        if(rst) begin read_active_buf_sync<=0; read_active_valid_sync<=0; wrfin_tgl_sync<=0; play_started_sync<=0; end
        else begin
            read_active_buf_sync<={read_active_buf_sync[1:0],read_active_buf_async};
            read_active_valid_sync<={read_active_valid_sync[1:0],read_active_valid_async};
            wrfin_tgl_sync<={wrfin_tgl_sync[1:0],write_finish_toggle};
            play_started_sync<={play_started_sync[1:0],play_started_async};
        end
    end
    assign command_ready=catalog_ready && source_idle && !load_busy && buffer_available && !fault_locked;
    assign play_started=play_started_sync[2];
    generate if(EXTERNAL_COMMANDS) begin : g_commands
        always @(posedge clk or posedge rst) begin
            if(rst) begin
                load_start<=0; load_index<=0; write_buf_idx<=0; disp_buf_idx<=0;
                display_valid<=0; auto_play_en<=0; load_busy<=0; source_done_seen<=0;
                fault_locked<=0; error_code<=0; write_done_seen<=0;
                pending_buf_idx<=0; write_timer<=0; publish_pulse<=0;
                first_image_committed<=0; nav_req_pending<=0; nav_req_is_prev<=0;
                img_idx<=0; auto_cnt<=0;
            end else begin
                load_start<=0; publish_pulse<=0;
                if(source_error!=0 && !fault_locked) begin error_code<=source_error; fault_locked<=1; end
                else if(!fault_locked) begin
                    if(load_busy) begin
                        write_timer<=write_timer+1'b1;
                        if(source_success) source_done_seen<=1;
                        if(write_finish_pulse) write_done_seen<=1;
                        if((source_done_seen || source_success) && (write_done_seen || write_finish_pulse)) begin
                            load_busy<=0; source_done_seen<=0; write_done_seen<=0;
                            disp_buf_idx<=pending_buf_idx; display_valid<=1;
                            write_timer<=0; publish_pulse<=1;
                        end else if(write_timer>=WRITE_FINISH_TIMEOUT-1) begin error_code<=8'h42; fault_locked<=1; end
                    end else begin
                        write_timer<=0;
                        if(command_valid && command_ready) begin
                            load_index<=command_index; pending_buf_idx<=next_bank; write_buf_idx<=next_bank;
                            load_start<=1; load_busy<=1; source_done_seen<=0; write_done_seen<=0;
                        end
                    end
                end
            end
        end
    end else begin : g_navigation
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            publish_pulse<=0;
            load_start<=0; load_index<=0; write_buf_idx<=0; disp_buf_idx<=0;
            display_valid<=0; auto_play_en<=1; load_busy<=0; source_done_seen<=0;
            fault_locked<=0; error_code<=0; first_image_committed<=0; write_done_seen<=0;
            nav_req_pending<=0; nav_req_is_prev<=0; img_idx<=0; pending_buf_idx<=0;
            auto_cnt<=0; write_timer<=0;
        end else begin
            load_start<=0; publish_pulse<=0;
            if(source_error!=0 && !fault_locked) begin
                error_code<=source_error; fault_locked<=1; auto_cnt<=0;
            end else if(!fault_locked) begin
                if(load_busy) begin
                    write_timer<=write_timer+1'b1;
                    if(source_success) source_done_seen<=1;
                    if(write_finish_pulse) write_done_seen<=1;
                    if((source_done_seen || source_success) && (write_done_seen || write_finish_pulse)) begin
                        load_busy<=0; source_done_seen<=0; write_done_seen<=0;
                        disp_buf_idx<=pending_buf_idx; img_idx<=load_index;
                        publish_pulse<=1; display_valid<=1; first_image_committed<=1; write_timer<=0;
                    end else if(write_timer>=WRITE_FINISH_TIMEOUT-1) begin
                        error_code<=8'h42; fault_locked<=1; auto_cnt<=0;
                    end
                end else write_timer<=0;
                if(auto_short && catalog_ready && image_count>1) begin auto_play_en<=~auto_play_en; auto_cnt<=0; end
                else if(catalog_ready && auto_play_en && display_valid && !load_busy && buffer_available &&
                    first_image_committed && play_started_sync[2] && image_count>1) begin
                    if(auto_tick) auto_cnt<=0; else auto_cnt<=auto_cnt+1'b1;
                end else auto_cnt<=0;

                if(catalog_ready && source_idle && !load_busy && !first_image_committed && image_count!=0) begin
                    load_index<=0; pending_buf_idx<=0; write_buf_idx<=0;
                    load_start<=1; load_busy<=1; source_done_seen<=0; write_done_seen<=0;
                    nav_req_pending<=0; nav_req_is_prev<=0; auto_cnt<=0; write_timer<=0;
                end else if(source_idle && !load_busy && buffer_available && manual_req) begin
                    load_index<=manual_is_prev ? prev_idx : next_idx;
                    pending_buf_idx<=next_bank; write_buf_idx<=next_bank;
                    load_start<=1; load_busy<=1; source_done_seen<=0; write_done_seen<=0;
                    nav_req_pending<=0; nav_req_is_prev<=0; auto_cnt<=0; write_timer<=0;
                end else if(source_idle && !load_busy && buffer_available && nav_req_pending && display_valid && image_count>1) begin
                    load_index<=nav_req_is_prev ? prev_idx : next_idx;
                    pending_buf_idx<=next_bank; write_buf_idx<=next_bank;
                    load_start<=1; load_busy<=1; source_done_seen<=0; write_done_seen<=0;
                    nav_req_pending<=0; nav_req_is_prev<=0; auto_cnt<=0; write_timer<=0;
                end else if(catalog_ready && source_idle && display_valid && !load_busy && buffer_available &&
                    auto_play_en && play_started_sync[2] && auto_tick && !manual_req && !nav_req_pending && image_count>1) begin
                    load_index<=next_idx; pending_buf_idx<=next_bank; write_buf_idx<=next_bank;
                    load_start<=1; load_busy<=1; source_done_seen<=0; write_done_seen<=0;
                    auto_cnt<=0; write_timer<=0;
                end
                if(manual_req && (load_busy || !source_idle || !buffer_available)) begin
                    nav_req_pending<=1; nav_req_is_prev<=manual_is_prev;
                end
            end
        end
    end
    end endgenerate
endmodule
