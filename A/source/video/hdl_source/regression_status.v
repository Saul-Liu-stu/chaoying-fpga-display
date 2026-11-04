`timescale 1ns/1ps
module regression_status(
    input wire ref_clk,rst_ref,sd_clk,rst_sd,pixel_clk,rst_pixel,
    input wire [31:0] sd_observe,
    input wire axis_valid,axis_ready,video_locked,display_enable,play_started,
    output wire [19:0] digits
);
    reg finish_seen,request_seen,source_busy_seen;
    always @(posedge sd_clk or posedge rst_sd) begin
        if(rst_sd) begin finish_seen<=0;request_seen<=0;source_busy_seen<=0;end
        else if(sd_observe[8]) begin finish_seen<=0;request_seen<=0;source_busy_seen<=0;end
        else begin
            if(sd_observe[9] && sd_observe[6]) finish_seen<=1;
            if(sd_observe[9] && sd_observe[7]) request_seen<=1;
            if(sd_observe[9] && !sd_observe[5]) source_busy_seen<=1;
        end
    end
    reg ready_violation,picture_seen;
    always @(posedge pixel_clk or posedge rst_pixel) begin
        if(rst_pixel) begin ready_violation<=0;picture_seen<=0;end
        else begin
            if(axis_valid && !axis_ready) ready_violation<=1;
            if(axis_valid && display_enable) picture_seen<=1;
        end
    end
    wire [3:0] pixel_status={ready_violation,video_locked,picture_seen,play_started};
    wire [3:0] load_status={finish_seen,request_seen,source_busy_seen,sd_observe[4]};
    (* syn_preserve=1 *) reg [20:0] sample0,sample1,sample2;
    always @(posedge ref_clk or posedge rst_ref) begin
        if(rst_ref) begin sample0<=0;sample1<=0;sample2<=0;end
        else begin
            sample0<={sd_observe[31:24],sd_observe[23:19],pixel_status,load_status};
            sample1<=sample0;sample2<=sample1;
        end
    end
    wire [4:0] count=sample2[12:8];
    wire [3:0] tens=count>=10 ? 4'd1 : 4'd0;
    wire [3:0] units=count>=10 ? count-5'd10 : count[3:0];
    assign digits=sample2[20:13]!=0 ? {4'he,sample2[20:13],sample2[7:0]} :
        {4'ha,tens,units,sample2[7:0]};
endmodule
