`timescale 1ns/1ps
module lights_control_hints(input wire clk,rst,vs,de,frame_enabled,menu_open,
 input wire [1:0] mode,item,output reg out_active,output reg [23:0] out_rgb);
 reg [9:0] x;reg [8:0] y;reg vs_old;reg [1:0] frame_mode;
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=0;vs_old<=0;frame_mode<=0;end
  else begin vs_old<=vs;
   if(vs_old && !vs)begin x<=0;y<=0;frame_mode<=mode;end
   else if(de)begin if(x==639)begin x<=0;y<=y==479?0:y+1'b1;end else x<=x+1'b1;end
  end
 end
 function [34:0] shape;input [7:0] ch;begin case(ch)
 8'd75:shape=35'b10001100101010011000101001001010001;
 8'd50:shape=35'b01110100010000100010001000100011111;
 8'd51:shape=35'b11110000010000101110000010000111110;
 8'd52:shape=35'b00010001100101010010111110001000010;
 8'd80:shape=35'b11110100011000111110100001000010000;
 8'd82:shape=35'b11110100011000111110101001001010001;
 8'd69:shape=35'b11111100001000011110100001000011111;
 8'd86:shape=35'b10001100011000110001100010101000100;
 8'd83:shape=35'b01111100001000001110000010000111110;
 8'd84:shape=35'b11111001000010000100001000010000100;
 8'd65:shape=35'b01110100011000111111100011000110001;
 8'd78:shape=35'b10001110011010110011100011000110001;
 8'd88:shape=35'b10001100010101000100010101000110001;
 8'd66:shape=35'b11110100011000111110100011000111110;
 8'd67:shape=35'b01111100001000010000100001000001111;
 8'd73:shape=35'b11111001000010000100001000010011111;
 8'd77:shape=35'b10001110111010110101100011000110001;
 8'd76:shape=35'b10000100001000010000100001000011111;
 8'd43:shape=35'b00000001000010011111001000010000000;
 8'd45:shape=35'b00000000000000011111000000000000000;
 default:shape=0;endcase end endfunction
 reg [223:0] message;
 always @*begin
  if(menu_open)message=item==3?224'h4b322043414e43454c202020202020204b3420524553455420202020:224'h4b32202d202020204b33204954454d20204b34202b20202020202020;
  else message=frame_mode==1?224'h4b322050524556204b33205354415254204b34204e45585420202020:224'h4b322050524556204b33204241434b20204b34204e45585420202020;
 end
 wire [9:0] relative_x=x-10'd8;
 wire [4:0] index=relative_x[8:4];
 wire [2:0] col=relative_x[3:1];
 wire [8:0] relative_y=y-9'd2;
 wire [2:0] row=relative_y[3:1];
 wire [7:0] ch=message[223-index*8 -: 8];
 wire [34:0] bits=shape(ch);
 wire active=de && frame_enabled && (menu_open || frame_mode==1 || frame_mode==2) && x>=8 && x<456 && y>=2 && y<16;
 reg active_q,pixel_q;
 always @(posedge clk or posedge rst)begin
  if(rst)begin active_q<=0;pixel_q<=0;out_active<=0;out_rgb<=0;end
  else begin
   active_q<=active;pixel_q<=col<5 && bits[34-row*5-col];
   out_active<=active_q;out_rgb<=pixel_q?24'h403222:24'hF8F3EB;
  end
 end
endmodule
