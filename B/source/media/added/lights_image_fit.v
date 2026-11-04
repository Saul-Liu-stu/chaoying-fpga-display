`timescale 1ns/1ps
module lights_image_fit(input wire clk,rst,start,
 input wire [10:0] source_width,source_height,target_width,target_height,
 input wire [23:0] background,input wire source_valid,input wire [23:0] source_pixel,
 output wire source_ready,output reg output_valid,output reg [23:0] output_pixel,
 input wire output_ready,output reg done,output reg busy);
 localparam IDLE=0,SIZE=1,DIVSIZE=2,XS=3,XWAIT=4,YS=5,YWAIT=6,ROW=7,LOAD=8,
 PIX=9,READ0=10,READ1=11,CAPTURE=12,HORIZONTAL=13,VERTICAL=14,CHANNEL=15,SEND=16,ADVANCE=17,DRAIN=18,HSUM=19,VSUM=20,ROW_PREP=21,NATIVE=22;
 reg [4:0] state;
 reg [10:0] sw,sh,tw,th,dw,dh,ox,oy_bottom,x,y,ix,in_row,loaded_rows;
 reg [10:0] sw_last,sh_last;
 reg [10:0] sw_before_last,sh_before_last;
 reg last_input_column,last_source_row,last_needed_row,native_last;
 reg [10:0] x_end,y_end,x_image_last,y_image_last,tw_last,th_last;
 reg [23:0] bg;
 reg width_limited;
 wire [21:0] width_cross={11'd0,tw}*{11'd0,sh};
 wire [21:0] height_cross={11'd0,th}*{11'd0,sw};
 reg div_start;reg [31:0] div_num;reg [15:0] div_den;
 wire div_done;wire [31:0] div_q;wire [15:0] div_r;
 lights_fit_divider divider(clk,rst,div_start,div_num,div_den,div_done,div_q,div_r);
 reg [18:0] xq,yq,xstep,ystep;
 reg [10:0] xr,yr,xrem,yrem,xd,yd;
 wire [11:0] xsum={1'b0,xr}+{1'b0,xrem},ysum={1'b0,yr}+{1'b0,yrem};
 wire [10:0] x0=xq[18:8];wire [10:0] x1=x0==sw_last ? x0 : x0+1'b1;
 wire [10:0] y0=yq[18:8];wire [10:0] y1_raw=y0==sh_last ? y0 : y0+1'b1;reg [10:0] y1;
 wire [7:0] fx=xq[7:0],fy=yq[7:0];
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [23:0] row0[0:2047],row1[0:2047];
 reg [10:0] ra;reg [23:0] r0,r1,c00,c10,c01,c11;
 wire row_read=state==READ0 || state==CAPTURE;
 always @(posedge clk) begin
  if(row_read) begin r0<=row0[ra];r1<=row1[ra];end
  if(source_valid && source_ready) begin
   if(in_row[0]) row1[ix]<=source_pixel;else row0[ix]<=source_pixel;
  end
 end
 assign source_ready=state==LOAD || state==DRAIN ||
     (state==NATIVE && !native_last && (!output_valid || output_ready));
 reg [1:0] channel;reg [15:0] h0,h1;reg [24:0] v;
 reg [8:0] xwa,xwb,ywa,ywb;
 reg [15:0] hp00,hp10,hp01,hp11;reg [23:0] vp0,vp1;
 wire [7:0] a=c00[channel*8 +: 8],b=c10[channel*8 +: 8],c=c01[channel*8 +: 8],d=c11[channel*8 +: 8];
 wire image_y=y>=oy_bottom && y<y_end;
 wire image_x=x>=ox && x<x_end;
 reg [18:0] next_xq,next_yq;
 reg [10:0] next_xr,next_yr;
 reg send_last_column,send_last_row,send_advance_x,send_advance_y;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   next_xq<=0;next_yq<=0;next_xr<=0;next_yr<=0;
   send_last_column<=0;send_last_row<=0;send_advance_x<=0;send_advance_y<=0;
  end else begin
   if(state==PIX) begin
    send_last_column<=x==tw_last;send_last_row<=y==th_last;
    send_advance_x<=image_y && image_x && x<x_image_last;
    send_advance_y<=image_y && y<y_image_last;
   end
   next_xq<=xq+xstep+(xsum>=xd);next_xr<=xsum>=xd ? xsum-xd : xsum;
   next_yq<=yq+ystep+(ysum>=yd);next_yr<=ysum>=yd ? ysum-yd : ysum;
  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   state<=IDLE;busy<=0;done<=0;output_valid<=0;output_pixel<=0;
   sw<=0;sh<=0;sw_last<=0;sh_last<=0;tw<=0;th<=0;dw<=0;dh<=0;ox<=0;oy_bottom<=0;x<=0;y<=0;ix<=0;in_row<=0;loaded_rows<=0;bg<=0;
   sw_before_last<=0;sh_before_last<=0;last_input_column<=0;last_source_row<=0;last_needed_row<=0;native_last<=0;
   x_end<=0;y_end<=0;x_image_last<=0;y_image_last<=0;tw_last<=0;th_last<=0;
   width_limited<=0;div_start<=0;div_num<=0;div_den<=1;xq<=0;yq<=0;xstep<=0;ystep<=0;
   xr<=0;yr<=0;xrem<=0;yrem<=0;y1<=0;xd<=1;yd<=1;ra<=0;c00<=0;c10<=0;c01<=0;c11<=0;channel<=0;h0<=0;h1<=0;v<=0;
   xwa<=256;xwb<=0;ywa<=256;ywb<=0;hp00<=0;hp10<=0;hp01<=0;hp11<=0;vp0<=0;vp1<=0;
  end else begin
   done<=0;div_start<=0;
   case(state)
    IDLE: if(start) begin
     sw<=source_width;sh<=source_height;tw<=target_width;th<=target_height;bg<=background;
     sw_last<=source_width-11'd1;sh_last<=source_height-11'd1;
     sw_before_last<=source_width-11'd2;sh_before_last<=source_height-11'd2;
     last_input_column<=source_width==1;last_source_row<=source_height==1;
     tw_last<=target_width-1'b1;th_last<=target_height-1'b1;
     x<=0;y<=0;ix<=0;in_row<=0;loaded_rows<=0;busy<=1;native_last<=0;
     state<=source_width==target_width && source_height==target_height ? NATIVE : SIZE;
    end
    NATIVE:begin
     if(output_valid && output_ready)begin
      output_valid<=0;
      if(native_last)begin busy<=0;done<=1;state<=IDLE;end
     end
     if(source_valid && source_ready)begin
      output_pixel<=source_pixel;output_valid<=1;
      if(ix==tw_last)begin
       ix<=0;
       if(in_row==th_last)native_last<=1;else in_row<=in_row+1'b1;
      end else ix<=ix+1'b1;
     end
    end
    SIZE: begin
     width_limited<=width_cross<=height_cross;div_start<=1;
     if(width_cross<=height_cross) begin dw<=tw;div_num<=sh*tw;div_den<=sw;end
     else begin dh<=th;div_num<=sw*th;div_den<=sh;end
     state<=DIVSIZE;
    end
    DIVSIZE: if(div_done) begin
     if(width_limited) begin dh<=div_q==0 ? 11'd1 : div_q[10:0];end
     else begin dw<=div_q==0 ? 11'd1 : div_q[10:0];end
     state<=XS;
    end
    XS: begin
     ox<=(tw-dw)>>1;oy_bottom<=th-dh-((th-dh)>>1);
     xd<=dw>1 ? dw-1'b1 : 11'd1;
     xq<=dw==1 ? ((sw-1'b1)<<7) : 19'd0;
     xr<=dw>1 ? ((dw-1'b1)>>1) : 11'd0;
     div_num<=(sw-1'b1)<<8;div_den<=dw>1 ? dw-1'b1 : 16'd1;div_start<=1;state<=XWAIT;
    end
    XWAIT: if(div_done) begin
     x_end<=ox+dw;y_end<=oy_bottom+dh;
     x_image_last<=ox+dw-1'b1;y_image_last<=oy_bottom+dh-1'b1;
     xstep<=div_q[18:0];xrem<=div_r[10:0];state<=YS;end
    YS: begin
     yd<=dh>1 ? dh-1'b1 : 11'd1;
     yq<=dh==1 ? ((sh-1'b1)<<7) : 19'd0;
     yr<=dh>1 ? ((dh-1'b1)>>1) : 11'd0;
     div_num<=(sh-1'b1)<<8;div_den<=dh>1 ? dh-1'b1 : 16'd1;div_start<=1;state<=YWAIT;
    end
    YWAIT: if(div_done) begin ystep<=div_q[18:0];yrem<=div_r[10:0];state<=ROW_PREP;end
    ROW_PREP: begin y1<=y1_raw;state<=ROW;end
    ROW: begin
     last_needed_row<=in_row=={1'b0,y1};
     ywa<=9'd256-{1'b0,fy};ywb<={1'b0,fy};
     xq<=dw==1 ? ((sw-1'b1)<<7) : 19'd0;xr<=dw>1 ? ((dw-1'b1)>>1) : 11'd0;
     if(image_y && loaded_rows<={1'b0,y1}) state<=LOAD;else state<=PIX;
    end
    LOAD: if(source_valid) begin
     if(last_input_column) begin
      ix<=0;in_row<=in_row+1'b1;loaded_rows<=in_row+1'b1;
      last_input_column<=sw_last==0;
      last_source_row<=in_row=={1'b0,sh_before_last};
      last_needed_row<=in_row+11'd1=={1'b0,y1};
      if(last_needed_row) state<=PIX;
     end else begin ix<=ix+1'b1;last_input_column<=ix=={1'b0,sw_before_last};end
    end
    PIX: if(image_y && image_x) begin ra<=x0;xwa<=9'd256-{1'b0,fx};xwb<={1'b0,fx};state<=READ0;end
     else begin output_pixel<=bg;output_valid<=1;state<=SEND;end
    READ0: state<=READ1;
    READ1: begin c00<=y0[0] ? r1:r0;c01<=y1[0] ? r1:r0;ra<=x1;state<=CAPTURE;end
    CAPTURE: begin channel<=0;state<=HORIZONTAL;end
    HORIZONTAL: begin
     c10<=y0[0] ? r1:r0;c11<=y1[0] ? r1:r0;state<=VERTICAL;
    end
    VERTICAL: begin hp00<=a*xwa;hp10<=b*xwb;hp01<=c*xwa;hp11<=d*xwb;state<=HSUM;end
    HSUM: begin h0<=hp00+hp10;h1<=hp01+hp11;state<=CHANNEL;end
    CHANNEL: begin vp0<=h0*ywa;vp1<=h1*ywb;state<=VSUM;end
    VSUM: begin v<={1'b0,vp0}+{1'b0,vp1}+25'd32768;state<=ADVANCE;end
    ADVANCE: begin
     output_pixel[channel*8 +: 8]<=v[23:16];
     if(channel==2) begin output_valid<=1;state<=SEND;end
     else begin channel<=channel+1'b1;state<=VERTICAL;end
    end
    SEND: if(output_valid && output_ready) begin
     output_valid<=0;
     if(send_last_column) begin
      x<=0;
      if(send_last_row) begin
       if(loaded_rows<sh) state<=DRAIN;else begin done<=1;busy<=0;state<=IDLE;end
      end
      else begin
       y<=y+1'b1;
       if(send_advance_y) begin
        yq<=next_yq;yr<=next_yr;
       end
       state<=ROW_PREP;
      end
     end else begin
      x<=x+1'b1;
      if(send_advance_x) begin
       xq<=next_xq;xr<=next_xr;
      end
      state<=PIX;
     end
    end
    DRAIN: if(source_valid) begin
     if(last_input_column) begin
      ix<=0;in_row<=in_row+1'b1;loaded_rows<=in_row+1'b1;
      last_input_column<=sw_last==0;
      last_source_row<=in_row=={1'b0,sh_before_last};
      if(last_source_row) begin done<=1;busy<=0;state<=IDLE;end
     end else begin ix<=ix+1'b1;last_input_column<=ix=={1'b0,sw_before_last};end
    end
    default: state<=IDLE;
   endcase
  end
 end
endmodule
