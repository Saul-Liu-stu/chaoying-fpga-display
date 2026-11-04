`timescale 1ns/1ps
module lights_select_overlay #(parameter TF_STYLE=0)(
 input wire clk,rst,hs,vs,de,input wire [23:0] rgb,input wire [31:0] identity,input wire identity_valid,
 output reg out_hs,out_vs,out_de,output reg [23:0] out_rgb,output reg [31:0] out_identity,output reg out_identity_valid,
 input wire style_clk,style_we,input wire [11:0] style_address,input wire [7:0] style_byte,
 input wire style_valid_sd,input wire [119:0] style_palette_sd);
 reg [9:0] x;reg [8:0] y;reg de_old,vs_old;
 wire select_frame=identity_valid && identity[31] && identity[2] && identity[30:29]==1;
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg [2:0] style_sync;
 (* syn_preserve=1,syn_keep=1 *) reg [119:0] style_palette_pixel;
 reg style_active;
 always @(posedge clk or posedge rst)begin
  if(rst)begin style_sync<=0;style_active<=0;style_palette_pixel<=120'he4deecf6f1e840384dd9a441d9a441;end
  else begin
   style_sync<={style_sync[1:0],TF_STYLE?style_valid_sd:1'b0};
   if(vs_old && !vs && style_sync[2] && !style_active)begin style_palette_pixel<=style_palette_sd;style_active<=1;end
  end
 end
 wire [23:0] page_top=style_palette_pixel[119:96],page_bg=style_palette_pixel[95:72],ink=style_palette_pixel[71:48];
 wire [23:0] focus_color=style_palette_pixel[47:24],flow_base=style_palette_pixel[23:0];
 wire title_area=x>=160 && x<480 && y>=40 && y<72;
 reg name_area;reg [9:0] name_x;reg [10:0] name_offset;
 always @*begin
  name_area=0;name_x=0;name_offset=0;
  if(y>=318 && y<342)begin
   if(x>=36 && x<212)begin name_area=1;name_x=x-36;name_offset=0;end
   else if(x>=232 && x<408)begin name_area=1;name_x=x-232;name_offset=528;end
   else if(x>=428 && x<604)begin name_area=1;name_x=x-428;name_offset=1056;end
  end
 end
 wire [8:0] title_x=x-10'd160;wire [4:0] title_y=y-9'd40;
 wire [4:0] name_y=y-9'd318;
 wire [11:0] ui_address=title_area?({7'd0,title_y}<<5)+({7'd0,title_y}<<3)+{6'd0,title_x[8:3]}:
  12'd1280+{1'd0,name_offset}+({7'd0,name_y}<<4)+({7'd0,name_y}<<2)+({7'd0,name_y}<<1)+{5'd0,name_x[9:3]};
 wire ui_text_read=TF_STYLE && style_active && select_frame && de && (title_area || name_area);
 wire [2:0] ui_bit=title_area?3'd7-title_x[2:0]:3'd7-name_x[2:0];wire [7:0] ui_byte;
 generate if(TF_STYLE)begin:g_ui_bitmap
  (* ram_style="block",syn_ramstyle="block_ram" *) reg [7:0] bitmap[0:3071];reg [7:0] q;
  always @(posedge style_clk)if(style_we && !style_valid_sd && style_address<2864)bitmap[style_address]<=style_byte;
  always @(posedge clk)if(ui_text_read)q<=bitmap[ui_address];
  assign ui_byte=q;
 end else begin:g_no_ui_bitmap
  assign ui_byte=0;
 end endgenerate
 wire [9:0] fallback_x=x-10'd250;wire [8:0] fallback_y=y-9'd40;reg [34:0] fallback_row;
 always @*begin
  case(fallback_y[4:2])
   0:fallback_row=35'b11110011111010001011110011111000001;
   1,2:fallback_row=35'b00001000100010001000001000100000001;
   3:fallback_row=35'b01110000100011111011101000100000001;
   4,5:fallback_row=35'b10000000100010001010001000100000001;
   6:fallback_row=35'b01111000100010001011110011111011111;
   default:fallback_row=0;
  endcase
 end
 wire fallback_dot=!style_active && select_frame && de && x>=250 && x<390 && y>=40 && y<68 && fallback_row[fallback_x[7:2]];
 reg select_seen,focus_seen;reg [4:0] focus_pic;reg [6:0] breathe_phase;reg [8:0] flow_phase;reg [3:0] anim_frames;
 wire [3:0] breathe_level=breathe_phase[6]?~breathe_phase[5:2]:breathe_phase[5:2];
 function [7:0] lighten(input [7:0] c,input [3:0] a);
  reg [11:0] t;begin t=(8'd255-c)*a;lighten=c+(t>>6);end
 endfunction
 wire [23:0] glow_rgb={lighten(focus_color[23:16],breathe_level),lighten(focus_color[15:8],breathe_level),lighten(focus_color[7:0],breathe_level)};
 reg [9:0] focus_left,focus_right,focus_center;
 always @*begin
  case(identity[28:24])
   4:begin focus_left=33;focus_right=214;focus_center=124;end
   7:begin focus_left=229;focus_right=410;focus_center=320;end
   default:begin focus_left=425;focus_right=606;focus_center=516;end
  endcase
 end
 wire border=select_frame && de && y>=161 && y<299 && x>=focus_left && x<=focus_right && (x<focus_left+3 || x>focus_right-3 || y<164 || y>=296);
 wire [3:0] gap=anim_frames<8?4'd8-anim_frames:4'd0;
 wire [9:0] left=focus_left-{6'd0,gap},right=focus_right+{6'd0,gap};
 wire [8:0] top=9'd161-{5'd0,gap},bottom=9'd298+{5'd0,gap};
 wire corner=select_frame && de && anim_frames<12 && x>=left && x<=right && y>=top && y<=bottom &&
  (x<left+2 || x>right-2 || y<top+2 || y>bottom-2) && (x<left+12 || x>right-12) && (y<top+12 || y>bottom-12);
 wire [3:0] marker_half=9'd315-y;
 wire marker=select_frame && de && y>=309 && y<=315 && x>=focus_center-marker_half && x<=focus_center+marker_half;
 wire flow_window=select_frame && de && x>=160 && x<480 && y>=346 && y<378;
 wire [9:0] flow_x=flow_window?x:10'd0;wire [8:0] flow_y=flow_window?y:9'd0;
 function [2:0] triangle(input [6:0] p);begin triangle=p[6]?~p[5:3]:p[5:3];end endfunction
 function [1:0] glint(input [7:0] p,input [8:0] cy,input [9:0] xx,input [8:0] yy);
  reg [9:0] cx,dx;reg [8:0] dy;begin
   cx=10'd192+{2'd0,p};dx=xx>cx?xx-cx:cx-xx;dy=yy>cy?yy-cy:cy-yy;glint=0;
   if(p>=4 && p<=251 && dx<=5 && dy<=3)glint=1;
   if(p>=12 && p<=243 && dx<=3 && dy<=2)glint=2;
   if(p>=20 && p<=235 && dx<=1 && dy<=1)glint=3;
  end
 endfunction
 wire [1:0] g0=glint(flow_phase[8:1],9'd354+triangle(flow_phase[6:0]),flow_x,flow_y);
 wire [1:0] g1=glint(flow_phase[8:1]+8'd64,9'd360-triangle(flow_phase[6:0]+7'd32),flow_x,flow_y);
 wire [1:0] g2=glint(flow_phase[8:1]+8'd128,9'd352+triangle(flow_phase[6:0]+7'd64),flow_x,flow_y);
 wire [1:0] g3=glint(flow_phase[8:1]+8'd192,9'd362-triangle(flow_phase[6:0]+7'd96),flow_x,flow_y);
 wire [1:0] ga=g0>g1?g0:g1,gb=g2>g3?g2:g3,level=ga>gb?ga:gb;
 wire flow_dot=flow_window && (level!=0 || y==358);
 function [7:0] blend(input [7:0] c,b,input [1:0] l);
  reg [10:0] total;begin
   case(l)
    3:total={3'd0,c};2:total=({3'd0,c}+{3'd0,b})>>1;
    1:total=({3'd0,c}+({3'd0,b}<<1)+{3'd0,b})>>2;
    default:total=({3'd0,c}+({3'd0,b}<<3)-{3'd0,b})>>3;
   endcase
   blend=total[7:0];
  end
 endfunction
 wire [23:0] flow_rgb={blend(flow_base[23:16],page_bg[23:16],level),blend(flow_base[15:8],page_bg[15:8],level),blend(flow_base[7:0],page_bg[7:0],level)};
 wire thumbnail=de && y>=164 && y<296 && ((x>=36 && x<212)||(x>=232 && x<408)||(x>=428 && x<604));
 reg hs1,vs1,de1,valid1,effect1,title1,ui_text1,flow1;reg [2:0] ui_bit1;reg [23:0] rgb1,glow1,ink1,flow_rgb1;reg [31:0] identity1;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   x<=0;y<=0;de_old<=0;vs_old<=0;select_seen<=0;focus_seen<=0;focus_pic<=0;breathe_phase<=0;flow_phase<=0;anim_frames<=12;
   hs1<=0;vs1<=0;de1<=0;valid1<=0;effect1<=0;title1<=0;ui_text1<=0;flow1<=0;ui_bit1<=0;rgb1<=0;glow1<=0;ink1<=0;flow_rgb1<=0;identity1<=0;
   out_hs<=0;out_vs<=0;out_de<=0;out_rgb<=0;out_identity<=0;out_identity_valid<=0;
  end else begin
   de_old<=de;vs_old<=vs;
   if(vs_old && !vs)begin
    x<=0;y<=0;select_seen<=0;
    if(select_seen)begin breathe_phase<=breathe_phase+1'b1;flow_phase<=flow_phase+1'b1;if(anim_frames<12)anim_frames<=anim_frames+1'b1;end
    else begin breathe_phase<=0;flow_phase<=0;anim_frames<=12;focus_seen<=0;end
   end else begin if(de)x<=x==639?10'd0:x+1'b1;else x<=0;if(de_old && !de)y<=y+1'b1;end
   if(de && select_frame)begin select_seen<=1;if(!focus_seen || focus_pic!=identity[28:24])begin focus_seen<=1;focus_pic<=identity[28:24];anim_frames<=0;end end
   hs1<=hs;vs1<=vs;de1<=de;identity1<=identity;valid1<=identity_valid;
   rgb1<=style_active && select_frame && !thumbnail?(y<128?page_top:page_bg):rgb;
   effect1<=border || corner || marker;glow1<=glow_rgb;ink1<=ink;title1<=fallback_dot;
   ui_text1<=ui_text_read;ui_bit1<=ui_bit;flow1<=flow_dot;flow_rgb1<=flow_rgb;
   out_hs<=hs1;out_vs<=vs1;out_de<=de1;out_identity<=identity1;out_identity_valid<=valid1;
   out_rgb<=effect1?glow1:(title1 || (ui_text1 && ui_byte[ui_bit1]))?ink1:flow1?flow_rgb1:rgb1;
  end
 end
endmodule
