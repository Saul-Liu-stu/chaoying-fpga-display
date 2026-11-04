`timescale 1ns/1ps
module lights_settings_overlay(input wire clk,rst,vs,de,frame_enabled,menu_open,
 input wire [1:0] item,input wire [3:0] brightness,contrast,volume,
 output reg out_active,output reg [23:0] out_rgb,
 input wire source_clk,source_rst,dimension_update,input wire [4:0] dimension_picture,
 input wire [21:0] dimension_size,input wire [31:0] view_identity);
 wire resolution_valid;wire [15:0] resolution_width,resolution_height;
 lights_resolution_status u_resolution(.source_clk(source_clk),.source_rst(source_rst),
  .update(dimension_update),.picture(dimension_picture),.size(dimension_size),
  .clk(clk),.rst(rst),.vs(vs),.menu_open(menu_open),.view_identity(view_identity),
  .valid(resolution_valid),.width_bcd(resolution_width),.height_bcd(resolution_height));
 localparam [23:0] CREAM=24'hF8F3EB,GOLD=24'hC49A4A,TEXT=24'h403222,
  SAGE=24'h7F8D6B,EMPTY=24'hE4DDCF,SELECTED=24'hFBE7B4;
 reg [9:0] x;reg [8:0] y;reg vs_old;
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=0;vs_old<=0;end
  else begin
   vs_old<=vs;
   if(vs_old && !vs)begin x<=0;y<=0;end
   else if(de)begin
    if(x==639)begin x<=0;y<=y==479?0:y+1'b1;end else x<=x+1'b1;
   end
  end
 end
 function [5:0] text_char;
  input [2:0] line;input [3:0] index;
  begin case({line,index})
   7'd0:text_char=6'd1;
   7'd1:text_char=6'd2;
   7'd2:text_char=6'd3;
   7'd3:text_char=6'd4;
   7'd4:text_char=6'd5;
   7'd5:text_char=6'd6;
   7'd6:text_char=6'd7;
   7'd7:text_char=6'd8;
   7'd8:text_char=6'd9;
   7'd16:text_char=6'd10;
   7'd17:text_char=6'd11;
   7'd32:text_char=6'd12;
   7'd33:text_char=6'd13;
   7'd34:text_char=6'd11;
   7'd48:text_char=6'd14;
   7'd49:text_char=6'd15;
   7'd64:text_char=6'd16;
   7'd65:text_char=6'd17;
   7'd66:text_char=6'd18;
   7'd67:text_char=6'd19;
   7'd80:text_char=6'd33;
   7'd81:text_char=6'd34;
   7'd82:text_char=6'd35;
   default:text_char=0;
  endcase end
 endfunction
 wire render_enable=frame_enabled && menu_open;
 wire render_active=de && render_enable;
 wire [9:0] render_x=render_enable?x:10'd0;
 wire [8:0] render_y=render_enable?y:9'd0;
 reg [5:0] glyph;reg [3:0] row,col;
 reg [2:0] line;reg line_valid;
 reg [3:0] level,absolute_level,digit;
 always @*begin
  glyph=0;row=0;col=0;line=0;line_valid=0;level=4;absolute_level=0;digit=0;
  if(render_y>=30 && render_y<46)begin line=0;row=render_y-30;line_valid=1;end
  else if(render_y>=65 && render_y<81)begin line=1;row=render_y-65;line_valid=1;level=brightness;end
  else if(render_y>=95 && render_y<111)begin line=2;row=render_y-95;line_valid=1;level=contrast;end
  else if(render_y>=125 && render_y<141)begin line=3;row=render_y-125;line_valid=1;end
  else if(render_y>=169 && render_y<185)begin line=4;row=render_y-169;line_valid=1;end
  else if(render_y>=211 && render_y<227)begin line=5;row=render_y-211;line_valid=1;end
  if(line_valid && render_x>=444 && render_x<(line==0?588:line==4?508:492))begin
   glyph=text_char(line,(render_x-444)>>4);col=(render_x-444)&15;
  end
  if(line_valid && (line==1 || line==2))begin
   absolute_level=level>=4?level-4:4-level;
   if(render_x>=594 && render_x<602)begin
    glyph=level>4?6'd30:level<4?6'd31:6'd0;col=render_x-594;
   end else if(render_x>=602 && render_x<610)begin glyph=6'd20+absolute_level;col=render_x-602;end
  end
  if(line_valid && line==3 && render_x>=586 && render_x<618)begin
   if(render_x<594)begin glyph=volume>=10?6'd21:0;col=render_x-586;end
   else if(render_x<602)begin
    digit=volume>=10?volume-10:volume;
    glyph=volume==0?0:6'd20+digit;col=render_x-594;
   end else if(render_x<610)begin glyph=6'd20;col=render_x-602;end
   else begin glyph=6'd32;col=render_x-610;end
  end
  if(line_valid && line==5)begin
   if(render_x>=500 && render_x<532)begin
    col=(render_x-500)&7;
    case((render_x-500)>>3)
     0:begin digit=resolution_width[15:12];glyph=resolution_valid?(digit!=0?20+digit:0):31;end
     1:begin digit=resolution_width[11:8];glyph=resolution_valid?(|resolution_width[15:8]?20+digit:0):31;end
     2:begin digit=resolution_width[7:4];glyph=resolution_valid?(|resolution_width[15:4]?20+digit:0):31;end
     default:begin digit=resolution_width[3:0];glyph=resolution_valid?20+digit:31;end
    endcase
   end else if(render_x>=536 && render_x<544)begin glyph=36;col=render_x-536;end
   else if(render_x>=548 && render_x<580)begin
    col=(render_x-548)&7;
    case((render_x-548)>>3)
     0:begin digit=resolution_height[15:12];glyph=resolution_valid?(digit!=0?20+digit:0):31;end
     1:begin digit=resolution_height[11:8];glyph=resolution_valid?(|resolution_height[15:8]?20+digit:0):31;end
     2:begin digit=resolution_height[7:4];glyph=resolution_valid?(|resolution_height[15:4]?20+digit:0):31;end
     default:begin digit=resolution_height[3:0];glyph=resolution_valid?20+digit:31;end
    endcase
   end
  end
 end
 (* ram_style="block",rom_style="block" *) reg [15:0] font[0:1023];
    initial $readmemh("settings_font.hex",font);
 reg [15:0] font_q;
 wire font_read=render_active && glyph!=0;
 always @(posedge clk)if(font_read)font_q<=font[{glyph,row}];
 wire outer_edge=(render_y==9'd18 || render_y==9'd242);
 wire next_edge=(render_y==9'd19 || render_y==9'd241);
 wire [9:0] edge_left=outer_edge?10'd436:next_edge?10'd434:10'd432;
 wire [9:0] edge_right=outer_edge?10'd621:next_edge?10'd623:10'd625;
 wire card=render_y>=9'd18 && render_y<=9'd242 && render_x>=edge_left && render_x<=edge_right;
 wire border=card && (outer_edge || render_x==edge_left || render_x==edge_right ||
  (render_y==53 && render_x>=442 && render_x<=615) || (render_y==153 && render_x>=442 && render_x<=615) ||
  ((render_y==160 || render_y==192) && render_x>=442 && render_x<=518) || ((render_x==442 || render_x==518) && render_y>=160 && render_y<=192));
 wire selected=(item==0 && render_y>=61 && render_y<=84 || item==1 && render_y>=91 && render_y<=114 ||
                item==2 && render_y>=121 && render_y<=144) && render_x>=438 && render_x<=619 ||
                item==3 && render_x>442 && render_x<518 && render_y>160 && render_y<192;
 wire [6:0] bar_x=render_x-10'd502;
 wire level_x=render_x>=10'd502 && render_x<=10'd571 && bar_x[2:0]<=3'd5;
 wire brightness_row=render_y>=9'd70 && render_y<=9'd78;
 wire contrast_row=render_y>=9'd100 && render_y<=9'd108;
 wire level_bar=level_x && (brightness_row || contrast_row);
 wire level_filled=level_x && ((brightness_row && brightness>=bar_x[6:3]) ||
                                         (contrast_row && contrast>=bar_x[6:3]));
 wire [14:0] volume_hit,volume_filled;
 genvar j;
 generate for(j=0;j<15;j=j+1)begin:volume_segments
  localparam [9:0] LEFT=502+j*5,RIGHT=504+j*5;
  localparam [3:0] INDEX=j;
  assign volume_hit[j]=render_x>=LEFT && render_x<=RIGHT;
  assign volume_filled[j]=volume_hit[j] && volume>INDEX;
 end endgenerate
 wire volume_row=render_y>=9'd130 && render_y<=9'd138;
 wire bar=level_bar || (volume_row && |volume_hit);
 wire filled=level_filled || (volume_row && |volume_filled);
 wire boost=volume_row && |volume_hit[14:10];
 reg card_q,border_q,selected_q,bar_q,filled_q,boost_q,text_q;reg [3:0] col_q;
 always @(posedge clk or posedge rst)begin
  if(rst)begin card_q<=0;border_q<=0;selected_q<=0;bar_q<=0;filled_q<=0;boost_q<=0;text_q<=0;col_q<=0;
   out_active<=0;out_rgb<=0;end
  else begin
   card_q<=render_active && card;text_q<=font_read;
   if(render_active)begin
    border_q<=border;selected_q<=selected;bar_q<=bar;filled_q<=filled;boost_q<=boost;col_q<=col;
   end
   out_active<=card_q;out_rgb<=CREAM;
   if(card_q)begin
    if(border_q)out_rgb<=GOLD;
    else if(text_q && font_q[15-col_q])out_rgb<=TEXT;
    else if(bar_q)out_rgb<=filled_q?(boost_q?GOLD:SAGE):EMPTY;
    else if(selected_q)out_rgb<=SELECTED;
   end
  end
 end
endmodule

module lights_resolution_status(
 input wire source_clk,source_rst,update,input wire [4:0] picture,input wire [21:0] size,
 input wire clk,rst,vs,menu_open,input wire [31:0] view_identity,
 output wire valid,output reg [15:0] width_bcd,height_bcd);
 reg [26:0] pending,payload_hold;reg dirty,request_toggle;
 reg acknowledge;
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg [2:0] ack_sync,request_sync;
 always @(posedge source_clk or posedge source_rst)begin
  if(source_rst)begin pending<=0;payload_hold<=0;dirty<=0;request_toggle<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[1:0],acknowledge};
   if(dirty && ack_sync[2]==request_toggle)begin payload_hold<=pending;dirty<=0;request_toggle<=~request_toggle;end
   if(update)begin pending<={picture,size};dirty<=1;end
  end
 end
 reg [26:0] received_payload;reg received;
 reg [15:0] known;
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [21:0] dimensions[0:15];
 wire current_picture=view_identity[31] && (view_identity[30:29]==0 || view_identity[30:29]==2) && view_identity[28:24]>=1 && view_identity[28:24]<=16;
 reg [21:0] lookup_size;reg [4:0] lookup_picture;reg lookup_known;
 always @(posedge clk)begin
  if(received && received_payload[26:22]>=1 && received_payload[26:22]<=16)dimensions[received_payload[26:22]-1'b1]<=received_payload[21:0];
  if(menu_open && current_picture)lookup_size<=dimensions[view_identity[28:24]-1'b1];
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin request_sync<=0;acknowledge<=0;received_payload<=0;received<=0;known<=0;lookup_picture<=0;lookup_known<=0;end
  else begin
   request_sync<={request_sync[1:0],request_toggle};received<=0;
   if(request_sync[2]!=acknowledge)begin received_payload<=payload_hold;received<=1;acknowledge<=request_sync[2];end
   if(received && received_payload[26:22]>=1 && received_payload[26:22]<=16)known[received_payload[26:22]-1'b1]<=1;
   lookup_picture<=view_identity[28:24];lookup_known<=menu_open && current_picture && known[view_identity[28:24]-1'b1];
  end
 end
 function [15:0] corrected(input [15:0] value);
  integer j;begin corrected=value;for(j=0;j<4;j=j+1)if(value[j*4+:4]>=5)corrected[j*4+:4]=value[j*4+:4]+4'd3;end
 endfunction
 reg [10:0] binary_width,binary_height;reg [15:0] work_width,work_height,pending_width,pending_height;
 reg [4:0] working_picture,pending_picture,shown_picture;
 reg [21:0] last_size;reg [4:0] last_picture;
 reg [3:0] remaining;reg pending_valid,shown_valid,vs_old;
 wire [15:0] fixed_width=corrected(work_width),fixed_height=corrected(work_height);
 wire [15:0] next_width={fixed_width[14:0],binary_width[10]},next_height={fixed_height[14:0],binary_height[10]};
 assign valid=shown_valid && current_picture && shown_picture==view_identity[28:24];
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   binary_width<=0;binary_height<=0;work_width<=0;work_height<=0;pending_width<=0;pending_height<=0;
   working_picture<=0;pending_picture<=0;shown_picture<=0;last_size<=0;last_picture<=0;remaining<=0;pending_valid<=0;shown_valid<=0;vs_old<=0;width_bcd<=0;height_bcd<=0;
  end else begin
   vs_old<=vs;
   if(remaining!=0)begin
    work_width<=next_width;work_height<=next_height;binary_width<=binary_width<<1;binary_height<=binary_height<<1;remaining<=remaining-1'b1;
    if(remaining==1)begin pending_width<=next_width;pending_height<=next_height;pending_picture<=working_picture;pending_valid<=1;end
   end else if(lookup_known && lookup_picture==view_identity[28:24] && (last_picture!=lookup_picture || last_size!=lookup_size))begin
    binary_width<=lookup_size[21:11];binary_height<=lookup_size[10:0];work_width<=0;work_height<=0;
    working_picture<=lookup_picture;last_picture<=lookup_picture;last_size<=lookup_size;remaining<=11;
   end
   if(vs_old && !vs)begin
    shown_valid<=menu_open && pending_valid && current_picture && pending_picture==view_identity[28:24];
    if(menu_open && pending_valid && current_picture && pending_picture==view_identity[28:24])begin
     width_bcd<=pending_width;height_bcd<=pending_height;shown_picture<=pending_picture;
    end
   end
  end
 end
endmodule
