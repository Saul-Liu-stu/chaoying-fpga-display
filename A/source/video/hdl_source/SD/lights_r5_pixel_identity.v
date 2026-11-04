`timescale 1ns/1ps
module lights_r5_pixel_identity(
 input wire clk,rst,de,vs,frame_enabled,input wire [117:0] pose,
 output reg [31:0] identity,output wire identity_valid
);
 reg [9:0] x;reg [8:0] y;reg de_old,vs_old;
 wire [31:0] a=pose[117:86],b=pose[85:54],c=pose[53:22];
 wire [1:0] effect=pose[11:10];
 wire [9:0] boundary=pose[9:0];
 wire [10:0] position={1'b0,x}+{1'b0,pose[21:12]};
 reg scroll;
 assign identity_valid=frame_enabled && identity[31];
 always @* begin
  identity=a;scroll=effect==1;
  if(effect==2 && x>=boundary) identity=b;
  if(effect==3) begin
   if(boundary[9] ? y<boundary[8:0] : y>=boundary[8:0]) identity=c;
   else scroll=a[30:29]==0;
  end
  if(scroll) begin
   if(position>=640 && position<648) identity=0;
   else if(position>=648) identity=b;
  end
  if(effect==2 && y>=452) identity=a;
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin x<=0;y<=0;de_old<=0;vs_old<=0;end
  else begin
   de_old<=de;vs_old<=vs;
   if(vs_old && !vs) begin x<=0;y<=0;end
   else begin
    if(de) x<=x==639 ? 10'd0:x+1'b1;else x<=0;
    if(de_old && !de) y<=y+1'b1;
   end
  end
 end
endmodule
