`timescale 1ns/1ps
module lights_select_page(input wire clk,rst,catalog_ready,input wire [15:0] available_mask,
 input wire command_valid,input wire [4:0] command_pic,output wire command_ready,
 input wire cancel,pool_load_busy,source_idle,source_success,
 input wire write_done_valid,input wire [31:0] write_done_identity,input wire source_fault,
 output reg owner,output reg load_start,output reg [3:0] load_index,
 output reg [31:0] write_identity,display_identity,output reg publish_pulse,
 output reg [20:0] rect_first,rect_length,output reg [10:0] rect_width,output reg [11:0] rect_jump,
 output reg background_req,input wire write_req_ack,output wire background_valid,
 output wire [23:0] background_pixel,input wire write_ready,
 output reg page_valid,output reg fault,output wire active);
 localparam IDLE=0,DRAIN=1,PREP=2,REQ=3,ACKLOW=4,FILL=5,BGWAIT=6,TILE=7,TILEWAIT=8,PUBLISH=9;
 reg [3:0] state;reg [1:0] tile;
 reg [4:0] focus;reg [7:0] serial,transaction;reg [3:0] compact[0:15];
 reg [4:0] map_cursor,map_count;reg mapped,cancelled,src_seen,wr_seen;
 reg [9:0] x,y;reg [18:0] count;reg [30:0] timer;reg timer_reset;
 always @(posedge clk or posedge rst) begin
  if(rst) timer<=0;
  else if(timer_reset || !active) timer<=0;
  else timer<=timer+1'b1;
 end
 (* syn_preserve=1 *) reg [2:0] ack_sync;
 wire write_match=write_done_valid && write_done_identity==write_identity;
 wire [4:0] tile_pic=tile==0 ? 5'd4 : tile==1 ? 5'd7 : 5'd10;
 wire [9:0] tile_x=tile==0 ? 10'd36 : tile==1 ? 10'd232 : 10'd428;
 assign command_ready=mapped && state==IDLE && !fault;
 assign active=state!=IDLE;
 assign background_valid=state==FILL;
 assign background_pixel=(479-y)>=352 ? 24'he4deec : 24'hf6f1e8;
 integer k;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   state<=IDLE;tile<=0;focus<=0;serial<=0;transaction<=0;map_cursor<=0;map_count<=0;mapped<=0;
   cancelled<=0;src_seen<=0;wr_seen<=0;x<=0;y<=0;count<=0;timer_reset<=0;ack_sync<=0;
   owner<=0;load_start<=0;load_index<=0;write_identity<=0;display_identity<=0;publish_pulse<=0;
   rect_first<=0;rect_length<=0;rect_width<=0;rect_jump<=0;background_req<=0;page_valid<=0;fault<=0;
   for(k=0;k<16;k=k+1) compact[k]<=0;
  end else begin
   ack_sync<={ack_sync[1:0],write_req_ack};load_start<=0;publish_pulse<=0;timer_reset<=0;
   if(catalog_ready && !mapped) begin
    if(map_cursor==16) mapped<=1;
    else begin compact[map_cursor[3:0]]<=map_count[3:0];map_cursor<=map_cursor+1'b1;if(available_mask[map_cursor[3:0]]) map_count<=map_count+1'b1;end
   end
   if(cancel && active) cancelled<=1;
   if(active) begin
    if(timer>=31'd1499999999 || source_fault) fault<=1;
   end
   if(!fault) case(state)
    IDLE: if(command_valid && command_ready && !cancel) begin
     focus<=command_pic;serial<=serial+1'b1;cancelled<=0;timer_reset<=1;
     state<=page_valid ? PUBLISH : DRAIN;
    end
    DRAIN: if(cancelled) state<=IDLE;
     else if(!pool_load_busy && source_idle) begin
      owner<=1;rect_first<=21'd1535360;rect_length<=21'd307200;rect_width<=640;rect_jump<=1279;
      transaction<=transaction+1'b1;write_identity<={1'b1,2'd1,5'd0,8'd1,transaction+8'd1,5'd0,1'b1,2'd0};
      state<=PREP;
     end
    PREP: if(cancelled) begin owner<=0;state<=IDLE;end
     else begin background_req<=1;state<=REQ;timer_reset<=1;end
    REQ: if(ack_sync[2]) begin background_req<=0;state<=ACKLOW;end
    ACKLOW: if(!ack_sync[2]) begin count<=0;x<=0;y<=0;wr_seen<=0;state<=FILL;end
    FILL: if(write_ready) begin
     count<=count+1'b1;
     if(x==639) begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
     if(count==307199) state<=BGWAIT;
    end
    BGWAIT: if(write_match) begin
     if(cancelled) begin owner<=0;state<=IDLE;end
     else begin tile<=0;state<=TILE;end
    end
    TILE: if(cancelled) begin owner<=0;state<=IDLE;end
     else if(tile==3) begin page_valid<=1;owner<=0;state<=PUBLISH;end
     else if(!available_mask[tile_pic-1'b1]) tile<=tile+1'b1;
     else if(source_idle) begin
      rect_first<=21'd1417600+tile_x;rect_length<=21'd23232;rect_width<=176;rect_jump<=815;
      transaction<=transaction+1'b1;write_identity<={1'b1,2'd1,tile_pic,8'd1,transaction+8'd1,5'd0,1'b1,2'd0};
      load_index<=compact[tile_pic-1'b1];state<=TILEWAIT;load_start<=1;src_seen<=0;wr_seen<=0;timer_reset<=1;
     end
    TILEWAIT: begin
     if(source_success) src_seen<=1;
     if(write_match) wr_seen<=1;
     if((src_seen || source_success) && (wr_seen || write_match)) begin tile<=tile+1'b1;state<=TILE;end
    end
    PUBLISH: begin
     if(!cancelled && !cancel) begin
      display_identity<={1'b1,2'd1,focus,8'd1,serial,5'd0,1'b1,2'd0};publish_pulse<=1;
     end
     state<=IDLE;
    end
    default: state<=IDLE;
   endcase
  end
 end
endmodule
