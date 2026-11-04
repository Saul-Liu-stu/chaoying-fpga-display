`timescale 1ns/1ps
module lights_frame_mailbox #(parameter integer WIDTH=32,TARGET_SAMPLE_FALLING=0)(
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
        if(source_rst) begin payload_hold<=0;request_toggle<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[1:0],ack_toggle};
            if(source_valid && source_ready) begin
                payload_hold<=source_data;request_toggle<=~request_toggle;
            end
        end
    end
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
        if(target_rst) begin request_sync<=0;ack_toggle<=0;target_valid<=0;target_data<=0;end
        else begin
            request_sync<={request_sync[1:0],request_toggle};
            if(!target_valid && request_sync[2]!=ack_toggle) begin
                target_data<=payload_sample;target_valid<=1;
            end else if(target_valid && target_ready) begin
                target_valid<=0;ack_toggle<=request_sync[2];
            end
        end
    end
endmodule
