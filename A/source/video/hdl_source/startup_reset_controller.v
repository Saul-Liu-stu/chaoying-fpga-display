`timescale 1ns/1ps

module startup_reset_controller #(
    parameter integer BOOT_HOLD_BITS = 16,
    parameter integer LOCK_HOLD_BITS = 5
)(
    input wire ref_clk,
    input wire rst_n,
    input wire soft_reset,
    input wire sys_locked,
    input wire video_locked,
    input wire audio_locked,
    input wire sd_clk,
    input wire mem_clk,
    input wire net_clk,
    input wire pixel_clk,
    input wire audio_clk,
    output wire pll_reset,
    output wire reset_request,
    output wire rst_ref,
    output wire rst_sd,
    output wire rst_mem,
    output wire rst_net,
    output wire rst_video,
    output wire rst_audio,
    output wire rst_sd_hard,rst_mem_hard,rst_net_hard,rst_ref_hard
);
    wire rst_button_ref;
    reset_release_sync u_button_reset (
        .clk(ref_clk), .async_reset(!rst_n), .rst(rst_button_ref)
    );
    reg [BOOT_HOLD_BITS-1:0] boot_count = {BOOT_HOLD_BITS{1'b0}};
    always @(posedge ref_clk or posedge rst_button_ref) begin
        if (rst_button_ref)
            boot_count <= {BOOT_HOLD_BITS{1'b0}};
        else if (!(&boot_count))
            boot_count <= boot_count + 1'b1;
    end

    wire pll_reset_request = !rst_n || !(&boot_count);
    reset_release_sync u_pll_reset (
        .clk(ref_clk), .async_reset(pll_reset_request), .rst(pll_reset)
    );

    wire not_locked = pll_reset || !sys_locked || !video_locked || !audio_locked;
    reg [LOCK_HOLD_BITS-1:0] lock_count = {LOCK_HOLD_BITS{1'b0}};
    reg locks_ready = 1'b0;
    wire rst_lock_check;
    reset_release_sync u_lock_check_reset (
        .clk(ref_clk), .async_reset(not_locked), .rst(rst_lock_check)
    );
    always @(posedge ref_clk or posedge rst_lock_check) begin
        if (rst_lock_check) begin
            lock_count <= {LOCK_HOLD_BITS{1'b0}};
            locks_ready <= 1'b0;
        end else if (!locks_ready) begin
            if (&lock_count)
                locks_ready <= 1'b1;
            else
                lock_count <= lock_count + 1'b1;
        end
    end

    wire hard_reset_request = not_locked || !locks_ready;
    assign reset_request = hard_reset_request || soft_reset;
    reset_release_sync u_hard_sd (.clk(sd_clk),.async_reset(hard_reset_request),.rst(rst_sd_hard));
    reset_release_sync u_hard_mem (.clk(mem_clk),.async_reset(hard_reset_request),.rst(rst_mem_hard));
    reset_release_sync u_hard_net (.clk(net_clk),.async_reset(hard_reset_request),.rst(rst_net_hard));
    reset_release_sync u_hard_ref (.clk(ref_clk),.async_reset(hard_reset_request),.rst(rst_ref_hard));
    reset_release_sync u_ref_reset (
        .clk(ref_clk), .async_reset(reset_request), .rst(rst_ref)
    );
    reset_release_sync u_sd_reset (
        .clk(sd_clk), .async_reset(reset_request), .rst(rst_sd)
    );
    reset_release_sync u_mem_reset (
        .clk(mem_clk), .async_reset(reset_request), .rst(rst_mem)
    );
    reset_release_sync u_net_reset (
        .clk(net_clk), .async_reset(reset_request), .rst(rst_net)
    );
    reset_release_sync u_video_reset (
        .clk(pixel_clk), .async_reset(reset_request), .rst(rst_video)
    );
    reset_release_sync u_audio_reset (
        .clk(audio_clk), .async_reset(reset_request), .rst(rst_audio)
    );
endmodule

module reset_release_sync (
    input wire clk,
    input wire async_reset,
    output wire rst
);
    (* syn_preserve = 1 *) reg [2:0] release_pipe = 3'b111;
    always @(posedge clk or posedge async_reset) begin
        if (async_reset)
            release_pipe <= 3'b111;
        else
            release_pipe <= {release_pipe[1:0], 1'b0};
    end
    assign rst = release_pipe[2];
endmodule
