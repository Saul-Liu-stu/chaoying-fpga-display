`timescale 1ns/1ps
module lights_r5_frame_present #(parameter integer FRAME_PIXELS=307200)(
 input wire clk,rst,de,vs,frame_enabled,active_valid,
 input wire [117:0] active_pose,input wire active_epoch,
 output reg frame_pulse,output wire [117:0] frame_pose,output reg presented_valid
);
 localparam integer BITS=$clog2(FRAME_PIXELS+1);
 reg [BITS-1:0] pixels;
 reg bad,vs_old;
 reg locked_epoch;
 assign frame_pose=active_pose;
 always @(posedge clk or posedge rst) begin
  if(rst) begin pixels<=0;bad<=0;vs_old<=0;locked_epoch<=0;frame_pulse<=0;presented_valid<=0;end
  else begin
   vs_old<=vs;frame_pulse<=0;
   if(vs_old && !vs) begin pixels<=0;bad<=0;end
   else if(de) begin
    if(pixels==0) locked_epoch<=active_epoch;
    if(!frame_enabled || !active_valid || pixels>=FRAME_PIXELS || (pixels!=0 && locked_epoch!=active_epoch)) bad<=1;
    if(pixels<FRAME_PIXELS) pixels<=pixels+1'b1;
    if(pixels==FRAME_PIXELS-1 && !bad && frame_enabled && active_valid &&
       (FRAME_PIXELS==1 || locked_epoch==active_epoch)) begin
     frame_pulse<=1;presented_valid<=1;
    end
   end
  end
 end
endmodule
