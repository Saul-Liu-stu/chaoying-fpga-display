`timescale 1ns/1ps
module lights_picture_adjust(input wire [23:0] rgb,
 input wire [3:0] brightness,contrast,output wire [23:0] adjusted);
 function [7:0] channel;
  input [7:0] value;
  input [3:0] b,c;
  reg signed [8:0] centered;
  reg signed [4:0] factor,bias_step;
  reg signed [13:0] product,bias,result;
  begin
   centered=$signed({1'b0,value})-9'sd128;
   factor=$signed({1'b0,c})+5'sd4;
   product=centered*factor;
   bias_step=$signed({1'b0,b})-5'sd4;
   bias=bias_step;bias=bias<<<3;
   result=(product>>>3)+14'sd128+bias;
   if(result<0)channel=0;
   else if(result>255)channel=255;
   else channel=result[7:0];
  end
 endfunction
 assign adjusted={channel(rgb[23:16],brightness,contrast),
                  channel(rgb[15:8],brightness,contrast),
                  channel(rgb[7:0],brightness,contrast)};
endmodule
