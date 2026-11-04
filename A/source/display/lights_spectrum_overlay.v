`timescale 1ns/1ps
module lights_spectrum_overlay(
 input wire clk,rst,vs,de,frame_enabled,select_spectrum,
 input wire [1:0] pcm_mode,input wire bars_valid,input wire [159:0] bars,
 output reg selected,output reg out_active,output reg [23:0] out_rgb
);
 reg [9:0] x,y;reg vs_old,pending_valid;reg [159:0] pending;
 reg [4:0] levels[0:31];integer i;
 wire frame_edge=vs_old && !vs;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   x<=0;y<=0;vs_old<=0;pending<=0;pending_valid<=0;selected<=0;
   for(i=0;i<32;i=i+1)levels[i]<=0;
  end else begin
   vs_old<=vs;
   if(bars_valid)begin pending<=bars;pending_valid<=1;end
   if(frame_edge)begin
    x<=0;y<=0;selected<=select_spectrum;
    if(pending_valid)begin
     for(i=0;i<32;i=i+1)levels[i]<=pending[i*5+:5];
     pending_valid<=bars_valid;
    end
   end else if(de)begin
    if(x==639)begin x<=0;y<=y==479?0:y+1'b1;end else x<=x+1'b1;
   end
  end
 end
 function [16:0] title_row;
  input [2:0] row;
  begin case(row)
   0:title_row=17'b11111011111011111;
   1:title_row=17'b10000010000000100;
   2:title_row=17'b10000010000000100;
   3:title_row=17'b11110011110000100;
   4:title_row=17'b10000010000000100;
   5:title_row=17'b10000010000000100;
   6:title_row=17'b10000010000000100;
   default:title_row=0;
  endcase end
 endfunction
 wire enabled=frame_enabled && selected && de;
 wire card_y=y>=396 && y<=439;
 wire [2:0] inset=(y==396 || y==439)?5:(y==397 || y==438)?3:(y==398 || y==437)?2:(y==399 || y==436)?1:0;
 wire card=enabled && card_y && x>=408+inset && x<=615-inset;
 wire border=y==396 || y==439 || x==408+inset || x==615-inset;
 wire [16:0] title_bits=title_row(y-401);
 wire title=x>=426 && x<443 && y>=401 && y<=407 && title_bits[16-(x-426)];
 wire graph=x>=416 && x<608 && y>=415 && y<=435;
 wire [7:0] column=x-416;
 reg [4:0] band;reg in_bar;integer k;
 always @*begin
  band=0;in_bar=0;
  for(k=0;k<32;k=k+1)if(column>=k*6 && column<k*6+4)begin band=k;in_bar=1;end
 end
 function [4:0] visible_height;
  input [4:0] h;
  begin visible_height=h<=1?h:h>=18?5'd20:h+5'd2;end
 endfunction
 wire [4:0] source_a=band<16?{1'b0,band[4:1]}:
                       band<24?band-5'd8:5'd16+((band-5'd24)<<1);
 wire [4:0] source_b=source_a+5'd1;
 wire [4:0] a=visible_height(levels[source_a]);
 wire [4:0] b=visible_height(levels[source_b]);
 wire [5:0] average_sum={1'b0,a}+{1'b0,b};
 wire [4:0] display_height=band<16 && band[0]?average_sum[5:1]:
                          band>=24?(a>b?a:b):a;
 wire bar=graph && in_bar && display_height!=0 && y>=436-display_height;
 wire guide=graph && (y==425 || y==435) && !x[2];
 reg card_q,border_q,title_q,bar_q,guide_q;reg [23:0] color_q;
 always @(posedge clk or posedge rst)begin
  if(rst)begin card_q<=0;border_q<=0;title_q<=0;bar_q<=0;guide_q<=0;color_q<=0;out_active<=0;out_rgb<=0;end
  else begin
   card_q<=card;
   if(card)begin border_q<=border;title_q<=title;bar_q<=bar;guide_q<=guide;
    color_q<=pcm_mode==1?24'h7f8d6b:pcm_mode==2?24'haa91b3:pcm_mode==3?24'hdc7c52:24'hd9a441;
   end
   out_active<=card_q;
   out_rgb<=border_q?24'hd9a441:title_q?24'h40384d:bar_q?color_q:guide_q?24'he0d4c3:24'hf8f3eb;
  end
 end
endmodule
