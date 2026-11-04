`timescale 1ns/1ps
module lights_volume(input wire clk,rst,in_valid,
 input wire [23:0] in_left,in_right,input wire [1:0] in_mode,
 input wire [3:0] volume,
 output reg out_valid,output reg [23:0] out_left,out_right,output reg [1:0] out_mode);
 reg [11:0] gain;
 reg signed [36:0] left_product,right_product;
 reg valid_q;reg [1:0] mode_q;
 function [11:0] gain_table;
  input [3:0] v;begin case(v)
   0:gain_table=0;1:gain_table=102;2:gain_table=205;3:gain_table=307;
   4:gain_table=410;5:gain_table=512;6:gain_table=614;7:gain_table=717;
   8:gain_table=819;9:gain_table=922;10:gain_table=1024;11:gain_table=1126;
   12:gain_table=1229;13:gain_table=1331;14:gain_table=1434;15:gain_table=1536;
  endcase end
 endfunction
 wire [11:0] target=gain_table(volume);
 function [23:0] saturate;
  input signed [36:0] product;
  reg signed [36:0] scaled;
  begin
   scaled=product>>>10;
   if(scaled>37'sd8388607)saturate=24'h7fffff;
   else if(scaled < -37'sd8388608)saturate=24'h800000;
   else saturate=scaled[23:0];
  end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin gain<=1024;left_product<=0;right_product<=0;valid_q<=0;mode_q<=0;
   out_valid<=0;out_left<=0;out_right<=0;out_mode<=0;end
  else begin
   valid_q<=in_valid;mode_q<=in_mode;
   if(in_valid)begin
    left_product<=$signed(in_left)*$signed({1'b0,gain});
    right_product<=$signed(in_right)*$signed({1'b0,gain});
    if(gain<target)gain<=target-gain<=4?target:gain+12'd4;
    else if(gain>target)gain<=gain-target<=4?target:gain-12'd4;
   end
   out_valid<=valid_q;out_mode<=mode_q;
   if(valid_q)begin out_left<=saturate(left_product);out_right<=saturate(right_product);end
  end
 end
endmodule
