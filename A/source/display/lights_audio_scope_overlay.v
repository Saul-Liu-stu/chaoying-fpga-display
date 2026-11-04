`timescale 1ns/1ps
module lights_audio_scope_overlay(
 input wire clk,rst,hs,vs,de,frame_enabled,
 input wire [23:0] rgb,
 input wire [31:0] identity,input wire identity_valid,
 input wire pcm_valid,input wire [23:0] pcm_left,input wire [1:0] pcm_mode,
 output reg out_hs,out_vs,out_de,output reg [23:0] out_rgb,
 output reg [31:0] out_identity,output reg out_identity_valid,out_active
);
 localparam [23:0] CREAM=24'hF8F3EB,GOLD=24'hD9A441,
   TEXT=24'h40384D,GUIDE=24'hE0D4C3,
   SAGE=24'h7F8D6B,LILAC=24'hAA91B3,CORAL=24'hDC7C52;
 reg [9:0] x,y;
 reg vs_old;
 wire frame_edge=vs_old && !vs;
 always @(posedge clk or posedge rst) begin
  if(rst)begin x<=0;y<=0;vs_old<=0;end
  else begin
   vs_old<=vs;
   if(frame_edge)begin x<=0;y<=0;end
   else if(de)begin
    if(x==639)begin x<=0;y<=(y==479)?0:y+1'b1;end
    else x<=x+1'b1;
   end
  end
 end

 function [4:0] sample_row;
  input [23:0] pcm;
  reg signed [5:0] amplitude;
  begin
   amplitude=$signed(pcm[23:18]);
   if(amplitude>6'sd10)sample_row=0;
   else if(amplitude < -6'sd10)sample_row=20;
   else sample_row=6'sd10-amplitude;
  end
 endfunction

 (* ram_style="block" *) reg [4:0] wave_mem[0:511];
 reg read_bank,write_bank,wave_valid,snapshot_ready,capturing;
 reg [7:0] write_index,trigger_wait;
 reg previous_negative;
 wire trigger=previous_negative && !pcm_left[23] || trigger_wait==8'd255;
 wire take_sample=!rst && !snapshot_ready && pcm_valid && (capturing || trigger);
 always @(posedge clk)begin
  if(take_sample)wave_mem[{write_bank,write_index}]<=sample_row(pcm_left);
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   read_bank<=0;write_bank<=1;wave_valid<=0;snapshot_ready<=0;
   capturing<=0;write_index<=0;trigger_wait<=0;previous_negative<=0;
  end else begin
   if(pcm_valid)previous_negative<=pcm_left[23];
   if(frame_edge && snapshot_ready)begin
    read_bank<=write_bank;write_bank<=~write_bank;wave_valid<=1;
    snapshot_ready<=0;capturing<=0;write_index<=0;trigger_wait<=0;
   end else if(!snapshot_ready && pcm_valid)begin
    if(capturing || trigger)begin
     if(write_index==183)begin snapshot_ready<=1;capturing<=0;end
     else begin write_index<=write_index+1'b1;capturing<=1;end
    end else trigger_wait<=trigger_wait+1'b1;
   end
  end
 end

 function [70:0] title_row;
  input [2:0] row;
  input [1:0] mode;
  begin
   case({mode,row})
    5'd0:title_row=71'b10000011111001110010001011111001111000000011111001110010001011111000000;
    5'd1:title_row=71'b10000000100010001010001000100010000000000000100010001011001010000000000;
    5'd2:title_row=71'b10000000100010000010001000100010000000000000100010001011001010000000000;
    5'd3:title_row=71'b10000000100010111011111000100001110000000000100010001010101011110000000;
    5'd4:title_row=71'b10000000100010001010001000100000001000000000100010001010011010000000000;
    5'd5:title_row=71'b10000000100010001010001000100000001000000000100010001010011010000000000;
    5'd6:title_row=71'b11111011111001110010001000100011110000000000100001110010001011111000000;
    5'd8:title_row=71'b10000011111001110010001011111001111000000010001001110010001000100000000;
    5'd9:title_row=71'b10000000100010001010001000100010000000000010001010001010001001100000000;
    5'd10:title_row=71'b10000000100010000010001000100010000000000010001010001010001000100000000;
    5'd11:title_row=71'b10000000100010111011111000100001110000000010101011111010001000100000000;
    5'd12:title_row=71'b10000000100010001010001000100000001000000010101010001001010000100000000;
    5'd13:title_row=71'b10000000100010001010001000100000001000000011011010001001010000100000000;
    5'd14:title_row=71'b11111011111001110010001000100011110000000010001010001000100001110000000;
    5'd16:title_row=71'b10000011111001110010001011111001111000000010001001110010001001110000000;
    5'd17:title_row=71'b10000000100010001010001000100010000000000010001010001010001010001000000;
    5'd18:title_row=71'b10000000100010000010001000100010000000000010001010001010001000001000000;
    5'd19:title_row=71'b10000000100010111011111000100001110000000010101011111010001000010000000;
    5'd20:title_row=71'b10000000100010001010001000100000001000000010101010001001010000100000000;
    5'd21:title_row=71'b10000000100010001010001000100000001000000011011010001001010001000000000;
    5'd22:title_row=71'b11111011111001110010001000100011110000000010001010001000100011111000000;
    5'd24:title_row=71'b10000011111001110010001011111001111000000010001001110010001011110000000;
    5'd25:title_row=71'b10000000100010001010001000100010000000000010001010001010001000001000000;
    5'd26:title_row=71'b10000000100010000010001000100010000000000010001010001010001000001000000;
    5'd27:title_row=71'b10000000100010111011111000100001110000000010101011111010001001110000000;
    5'd28:title_row=71'b10000000100010001010001000100000001000000010101010001001010000001000000;
    5'd29:title_row=71'b10000000100010001010001000100000001000000011011010001001010000001000000;
    5'd30:title_row=71'b11111011111001110010001000100011110000000010001010001000100011110000000;
    default:title_row=71'd0;
   endcase
  end
 endfunction
 wire [9:0] render_x=frame_enabled?x:10'd0;
 wire [9:0] render_y=frame_enabled?y:10'd0;
 wire card_y=(render_y>=396 && render_y<=439);
 wire [2:0] inset=(render_y==396 || render_y==439)?5:
                       (render_y==397 || render_y==438)?3:
                       (render_y==398 || render_y==437)?2:
                       (render_y==399 || render_y==436)?1:0;
 wire card=card_y && render_x>=408+inset && render_x<=615-inset;
 wire border=card && (render_y==396 || render_y==439 || render_x==408+inset || render_x==615-inset);
 wire text_area=(render_x>=426 && render_x<=496 && render_y>=401 && render_y<=407);
 wire [70:0] title_bits=title_row(render_y-401,pcm_mode);
 wire title=text_area && title_bits[70-(render_x-426)];
 wire dot=(render_x>=417 && render_x<=420 && render_y>=402 && render_y<=405) &&
          !((render_x==417 || render_x==420) && (render_y==402 || render_y==405));
 wire graph=(render_x>=420 && render_x<=603 && render_y>=415 && render_y<=435);
 wire enabled=de && frame_enabled;
 wire [4:0] graph_row=render_y-415;
 wire [7:0] read_index=render_x-420;
 wire [23:0] color=pcm_mode==1?SAGE:pcm_mode==2?LILAC:pcm_mode==3?CORAL:GOLD;
 wire wave_read=graph && enabled;
 reg [4:0] wave_q,previous_q;
 always @(posedge clk)begin
  if(wave_read)begin
   wave_q<=wave_mem[{read_bank,read_index}];
   previous_q<=wave_q;
  end
 end
 reg hs_q,vs_q,de_q,identity_valid_q,card_q,border_q,title_q,dot_q;
 reg graph_q,first_q,guide_q,wave_valid_q;
 reg [4:0] row_q;
 reg [23:0] rgb_q,color_q;
 reg [31:0] identity_q;
 wire trace=wave_valid_q && graph_q &&
   (first_q ? row_q==wave_q :
    (wave_q<=previous_q ? row_q>=wave_q && row_q<=previous_q :
                         row_q>=previous_q && row_q<=wave_q));
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   hs_q<=0;vs_q<=0;de_q<=0;rgb_q<=0;identity_q<=0;identity_valid_q<=0;
   card_q<=0;border_q<=0;title_q<=0;dot_q<=0;graph_q<=0;first_q<=0;
   guide_q<=0;wave_valid_q<=0;row_q<=0;color_q<=GOLD;
   out_hs<=0;out_vs<=0;out_de<=0;out_rgb<=0;out_identity<=0;out_identity_valid<=0;out_active<=0;
  end else begin
   hs_q<=hs;vs_q<=vs;de_q<=de;rgb_q<=rgb;identity_q<=identity;identity_valid_q<=identity_valid;
   card_q<=enabled && card;
   if(enabled)begin
    border_q<=border;title_q<=title;dot_q<=dot;
    graph_q<=graph;first_q<=render_x==420;guide_q<=render_y==425 && !render_x[2];
    row_q<=graph_row;wave_valid_q<=wave_valid;color_q<=color;
   end
   out_hs<=hs_q;out_vs<=vs_q;out_de<=de_q;
   out_identity<=identity_q;out_identity_valid<=identity_valid_q;out_active<=card_q;
   out_rgb<=rgb_q;
   if(card_q)begin
    if(border_q || dot_q)out_rgb<=GOLD;
    else if(title_q)out_rgb<=TEXT;
    else if(trace)out_rgb<=color_q;
    else if(graph_q && guide_q)out_rgb<=GUIDE;
    else out_rgb<=CREAM;
   end
  end
 end
endmodule
