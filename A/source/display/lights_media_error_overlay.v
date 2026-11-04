`timescale 1ns/1ps
module lights_media_error_overlay(
 input wire clk,rst,vs,de,input wire [15:0] health,missing_images,
 output reg out_active,output reg [23:0] out_rgb
);
 reg [9:0] x,y;reg vs_old;
 wire frame_edge=vs_old && !vs;
 reg [15:0] frame_health,frame_missing;
 reg [4:0] selected,scan,pending;
 reg searching,pending_valid;
 reg [10:0] offset;reg [6:0] dwell;
 wire catalog_valid=frame_health[15];
 wire no_images=catalog_valid && frame_missing==16'hffff;
 function issue;
  input [4:0] n;
  begin
   if(n<16)issue=catalog_valid && frame_missing[n];
   else if(n<19)issue=catalog_valid && !frame_health[14] && frame_health[11+n-16];
   else if(n<22)issue=catalog_valid && frame_health[8+n-19];
   else if(n==22)issue=catalog_valid && frame_health[14];
   else if(n==23)issue=frame_health[7];
   else issue=0;
  end
 endfunction
 function [5:0] message_length;
  input [4:0] n;
  begin
   if(n<16)message_length=35;
   else if(n<22)message_length=30;
   else if(n==22)message_length=36;
   else if(n==23)message_length=30;
   else message_length=34;
  end
 endfunction
 wire [4:0] message=no_images?5'd24:selected;
 wire enabled=no_images || issue(selected);
 wire [10:0] width_pixels={message_length(message),4'd0};
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=0;vs_old<=0;frame_health<=0;frame_missing<=0;selected<=31;scan<=0;pending<=0;searching<=1;pending_valid<=0;offset<=0;dwell<=0;end
  else begin
   vs_old<=vs;
   if(searching)begin
    if(issue(scan))begin pending<=scan;pending_valid<=1;searching<=0;end
    else scan<=scan>=23?0:scan+1'b1;
   end
   if(frame_edge)begin
    x<=0;y<=0;frame_health<=health;frame_missing<=missing_images;
    if(!enabled)begin
     offset<=0;dwell<=0;
     if(pending_valid)begin selected<=pending;pending_valid<=0;end
     else searching<=1;
    end else if(dwell<60)dwell<=dwell+1'b1;
    else if(width_pixels>608 && offset+608<width_pixels)offset<=offset+2;
    else if(dwell<120)dwell<=dwell+1'b1;
    else begin
     offset<=0;dwell<=0;scan<=selected>=23?0:selected+1'b1;selected<=31;searching<=1;
    end
   end else if(de)begin
    if(x==639)begin x<=0;y<=y==479?0:y+1'b1;end else x<=x+1'b1;
   end
  end
 end
 wire region=de && enabled && x>=16 && x<624 && y>=20 && y<44;
 wire [10:0] text_x={1'b0,x}-11'd16+offset;
 wire ink_area=region && y>=24 && y<40 && text_x<width_pixels;
 (* ram_style="block" *) reg [6:0] text_rom[0:2047];
 (* ram_style="block" *) reg [15:0] font_rom[0:2047];
 initial begin
  $readmemh("media_error_text.hex",text_rom);
  $readmemh("media_error_font.hex",font_rom);
 end
 reg [6:0] character;
 reg [15:0] glyph_row;
 reg [3:0] bit_stage;
 reg region_q,ink_q;
 reg [3:0] row_q;
 always @(posedge clk)begin
  if(region)character<=text_rom[{message,text_x[9:4]}];
  if(region_q)glyph_row<=font_rom[{character,row_q}];
 end
 reg [3:0] bit_q;
 reg region_qq,ink_qq;
 always @(posedge clk or posedge rst)begin
  if(rst)begin region_q<=0;ink_q<=0;row_q<=0;bit_q<=0;region_qq<=0;ink_qq<=0;bit_stage<=0;end
  else begin
   region_q<=region;ink_q<=ink_area;row_q<=y[3:0]-4'd8;bit_q<=text_x[3:0];
   region_qq<=region_q;ink_qq<=ink_q;bit_stage<=bit_q;
  end
 end
 always @*begin
  out_active=region_qq;
  out_rgb=ink_qq && glyph_row[15-bit_stage]?24'hfff4df:24'h802b30;
 end
endmodule
