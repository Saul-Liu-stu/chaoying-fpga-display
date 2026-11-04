`timescale 1ns/1ps
module lights_r5_line_reader #(parameter integer NARROW_BORDER=1)(
 input wire mem_clk,rst,pixel_clk,pixel_rst,
 input wire init_done,refresh,busy,writer_busy,
 input wire read_req,input wire [117:0] read_pose,
 output reg read_req_ack,output reg [117:0] active_pose,
 output wire [31:0] active_identity,output wire active_valid,
 output reg read_finish,output wire reader_busy,read_urgent,
 output wire App_rd_en,output wire [20:0] App_rd_addr,
 input wire Sdr_rd_en,input wire [31:0] Sdr_rd_dout,
 input wire read_en,output wire [31:0] read_data,output reg underflow
);
 localparam [13:0] IDLE=13'h001,ACK=13'h002,ROW=13'h004,PLAN=13'h008,ADDRESS=13'h010,
                  SIZE=13'h020,WAIT_BUS=13'h040,SEND=13'h080,RETURN_DATA=13'h100,
                  DRAIN=13'h200,CONSTANT=13'h400,DONE_ROW=13'h800,COMPLETE=13'h1000,CLASSIFY=14'h2000;
 (* syn_encoding="onehot" *) reg [13:0] state;
 (* syn_preserve=1 *) reg [2:0] request_sync;
 (* syn_preserve=1 *) reg [117:0] pose_sample;
 (* syn_preserve=1 *) reg [2:0] consumed0_sync,consumed1_sync;
 reg ready0,ready1;
 reg consumed0,consumed1;
 (* syn_preserve=1 *) reg [2:0] ready0_sync,ready1_sync;
 reg [8:0] row;
 reg [20:0] row_base,address,row_address;
 reg [9:0] dest_x,source_x,span;
 reg [9:0] return_source_x;
 reg [31:0] source_id;
 reg constant_black;
 reg [1:0] head;
 reg [8:0] useful,physical,issued,returned;
 reg [3:0] drain;
 reg admitted,last_return_q;
 reg [8:0] keep_end,physical_last;
 reg [23:0] line0 [0:1023];
 reg [23:0] line1 [0:1023];
 reg [23:0] pixel0,pixel1;
 reg [9:0] pixel_x;
 reg [8:0] pixel_y;
 reg pixel_bank,pixel_good;
 wire [31:0] a=active_pose[117:86],b=active_pose[85:54],c=active_pose[53:22];
 wire [9:0] offset=active_pose[21:12],wipe_edge=active_pose[9:0];
 wire [1:0] effect=active_pose[11:10];
 wire bank_available=row[0] ? ready1==consumed1_sync[2] : ready0==consumed0_sync[2];
 wire pixel_ready=pixel_y[0] ? ready1_sync[2]!=consumed1 : ready0_sync[2]!=consumed0;
 assign active_identity=a;
 assign active_valid=a[31];
 assign App_rd_en=state==SEND && (admitted || (!writer_busy && !busy && !refresh));
 assign App_rd_addr=address;
 assign reader_busy=state==SEND || state==RETURN_DATA || state==DRAIN;
 assign read_urgent=(state==ROW && bank_available) || state==CLASSIFY || state==PLAN || state==ADDRESS ||
                    state==SIZE || state==WAIT_BUS || reader_busy || state==CONSTANT;
 assign read_data={pixel_good ? (pixel_bank ? pixel1 : pixel0) : 24'd0,8'd0};
 always @(negedge mem_clk or posedge rst) begin
  if(rst) begin request_sync[0]<=0;pose_sample<=0;consumed0_sync[0]<=0;consumed1_sync[0]<=0;end
  else begin request_sync[0]<=read_req;pose_sample<=read_pose;consumed0_sync[0]<=consumed0;consumed1_sync[0]<=consumed1;end
 end
 always @(posedge mem_clk or posedge rst) begin
  if(rst) begin request_sync[2:1]<=0;consumed0_sync[2:1]<=0;consumed1_sync[2:1]<=0;end
  else begin
   request_sync[2:1]<=request_sync[1:0];
   consumed0_sync[2:1]<=consumed0_sync[1:0];
   consumed1_sync[2:1]<=consumed1_sync[1:0];
  end
 end
 always @(posedge pixel_clk or posedge pixel_rst) begin
  if(pixel_rst) begin ready0_sync<=0;ready1_sync<=0;end
  else if(read_req) begin ready0_sync<=0;ready1_sync<=0;end
  else begin ready0_sync<={ready0_sync[1:0],ready0};ready1_sync<={ready1_sync[1:0],ready1};end
 end
 always @(posedge pixel_clk) if(read_en) begin pixel0<=line0[pixel_x];pixel1<=line1[pixel_x];end
 always @(posedge pixel_clk or posedge pixel_rst) begin
  if(pixel_rst) begin pixel_x<=0;pixel_y<=0;consumed0<=0;consumed1<=0;pixel_bank<=0;pixel_good<=0;underflow<=0;end
  else if(read_req) begin pixel_x<=0;pixel_y<=0;consumed0<=0;consumed1<=0;pixel_good<=0;end
  else if(read_en) begin
   pixel_bank<=pixel_y[0];pixel_good<=pixel_ready && pixel_y<480;
   if(!pixel_ready || pixel_y>=480) underflow<=1;
   if(pixel_x==639) begin
    pixel_x<=0;pixel_y<=pixel_y+1'b1;
    if(pixel_y[0]) consumed1<=ready1_sync[2];else consumed0<=ready0_sync[2];
   end else pixel_x<=pixel_x+1'b1;
  end
 end
 reg [31:0] plan_id;
 reg [9:0] plan_x,plan_span;
 reg plan_black;
 reg row_uses_c,row_scroll,row_border;
 wire row_select_c=effect==3 && (wipe_edge[9] ? row<wipe_edge[8:0] : row>=wipe_edge[8:0]);
 always @(posedge mem_clk or posedge rst) begin
  if(rst) begin row_uses_c<=0;row_scroll<=0;row_border<=0;end
  else if(state==ROW) begin
   row_uses_c<=row_select_c;
   row_scroll<=effect==1 || (effect==3 && !row_select_c && a[30:29]==0);
   row_border<=row<2 || row>=478;
  end
 end
 reg [10:0] k640,k648;
 reg [9:0] koff;
 reg wipe_short,offset_gt8;
 always @(posedge mem_clk or posedge rst) begin
  if(rst) begin k640<=11'd640;k648<=11'd648;koff<=0;wipe_short<=0;offset_gt8<=0;end
  else begin
   k640<={1'b0,offset}<=11'd640 ? 11'd640-{1'b0,offset} : 11'd0;
   k648<={1'b0,offset}<=11'd648 ? 11'd648-{1'b0,offset} : 11'd0;
   koff<=offset-10'd648;wipe_short<=wipe_edge<10'd640;offset_gt8<=offset>10'd8;
  end
 end
 reg scroll_a,scroll_black,wipe_b;
 always @(posedge mem_clk or posedge rst) begin
  if(rst) begin scroll_a<=0;scroll_black<=0;wipe_b<=0;end
  else if(state==CLASSIFY) begin
   scroll_a<={1'b0,dest_x}<k640;scroll_black<={1'b0,dest_x}<k648;
   wipe_b<=dest_x>=wipe_edge;
  end
 end
 wire [10:0] span_a=k640-{1'b0,dest_x},span_black=k648-{1'b0,dest_x};
 always @* begin
  plan_id=row_uses_c ? c:a;plan_x=dest_x;plan_span=10'd640-dest_x;plan_black=0;
  if(effect==2) begin
   if(wipe_b) plan_id=b;
   else if(wipe_short) plan_span=wipe_edge-dest_x;
  end
  if(row_scroll) begin
   if(scroll_a) begin
    plan_id=a;plan_x=dest_x+offset;plan_span=span_a[9:0];
   end else if(scroll_black) begin
    plan_black=1;plan_x=0;
    if(offset_gt8) plan_span=span_black[9:0];
   end else begin plan_id=b;plan_x=dest_x+koff;end
  end
 end
 function [20:0] base;
  input [31:0] id;
  begin base=id[2] && id[30:29]==1 ? 21'd1228800 :
       id[1:0]==0 ? 21'd0 : id[1:0]==1 ? 21'd307200 : id[1:0]==2 ? 21'd614400 : 21'd921600;end
 endfunction
 wire return_valid=(state==SEND || state==RETURN_DATA) && Sdr_rd_en;
 wire keep_word=return_valid && returned>=head && returned<keep_end;
 wire border=NARROW_BORDER && source_id[30:29]==0 &&
             (row_border || return_source_x<2 || return_source_x>=638);
 wire fill=keep_word || state==CONSTANT;
 wire [23:0] fill_data=state==CONSTANT ? 24'd0 : border ? 24'h202020 : Sdr_rd_dout[31:8];
 reg fill_q,fill_bank_q;reg [9:0] fill_x_q;reg [23:0] fill_data_q;
 always @(posedge mem_clk or posedge rst) begin
  if(rst) fill_q<=0;else fill_q<=fill;
 end
 always @(posedge mem_clk) begin
  fill_bank_q<=row[0];fill_x_q<=dest_x;fill_data_q<=fill_data;
  if(fill_q) begin
   if(fill_bank_q) line1[fill_x_q]<=fill_data_q;else line0[fill_x_q]<=fill_data_q;
  end
 end
 always @(posedge mem_clk or posedge rst) begin
  if(rst) begin last_return_q<=0;physical_last<=0;end
  else begin
   physical_last<=physical-1'b1;
   last_return_q<=return_valid && returned==physical_last;
  end
 end
 always @(posedge mem_clk or posedge rst) begin
  if(rst) begin
   state<=IDLE;read_req_ack<=0;active_pose<=0;read_finish<=0;ready0<=0;ready1<=0;
   row<=0;row_base<=0;address<=0;row_address<=0;dest_x<=0;source_x<=0;return_source_x<=0;span<=0;source_id<=0;constant_black<=0;admitted<=0;
   head<=0;useful<=0;physical<=0;issued<=0;returned<=0;drain<=0;keep_end<=0;
  end else begin
   read_finish<=0;
   if(keep_word) dest_x<=dest_x+1'b1;
   if(return_valid) begin returned<=returned+1'b1;return_source_x<=return_source_x+1'b1;end
   if(state==SIZE)issued<=0;
   else if(App_rd_en)issued<=issued+1'b1;
   case(state)
    IDLE,COMPLETE:if(request_sync[2] && init_done) begin
     active_pose<=pose_sample;read_req_ack<=1;ready0<=0;ready1<=0;
     row<=0;row_base<=0;dest_x<=0;state<=ACK;
    end
    ACK:if(!request_sync[2]) begin read_req_ack<=0;state<=ROW;end
    ROW:if(bank_available) begin dest_x<=0;state<=CLASSIFY;end
    CLASSIFY:state<=PLAN;
    PLAN:begin source_id<=plan_id;source_x<=plan_x;span<=plan_span;constant_black<=plan_black;state<=ADDRESS;end
    ADDRESS:begin
     if(constant_black) state<=CONSTANT;
     else begin
      row_address<=base(source_id)+row_base;head<=source_x[1:0];
      useful<=span>(9'd256-{7'd0,source_x[1:0]}) ? (9'd256-{7'd0,source_x[1:0]}) : span;
      state<=SIZE;
     end
    end
    SIZE:begin address<=row_address+{source_x[9:2],2'b00};return_source_x<={source_x[9:2],2'b00};physical<=({7'd0,head}+useful+9'd3)&9'h1fc;keep_end<={7'd0,head}+useful;returned<=0;admitted<=0;state<=WAIT_BUS;end
    WAIT_BUS:if(!writer_busy && !busy && !refresh) state<=SEND;
    SEND:if(App_rd_en) begin
     admitted<=1;address<=address+1'b1;
     if(issued==physical_last) state<=RETURN_DATA;
    end
    RETURN_DATA:if(last_return_q) begin drain<=0;state<=DRAIN;end
    DRAIN:if(drain==10 && !busy) begin state<=dest_x==640 ? DONE_ROW : CLASSIFY;end
          else if(drain<10) drain<=drain+1'b1;
    CONSTANT:begin
     dest_x<=dest_x+1'b1;span<=span-1'b1;
     if(span==1) state<=dest_x==639 ? DONE_ROW : CLASSIFY;
    end
    DONE_ROW:begin
     if(row[0]) ready1<=~ready1;else ready0<=~ready0;
     if(row==479) begin read_finish<=1;state<=COMPLETE;end
     else begin row<=row+1'b1;row_base<=row_base+21'd640;state<=ROW;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
