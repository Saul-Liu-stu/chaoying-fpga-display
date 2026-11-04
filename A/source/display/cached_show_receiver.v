`timescale 1ns/1ps
module cached_show_receiver(
 input wire clk,rst,available,input wire [111:0] recv_info,output reg take,
 output reg send,output reg [111:0] send_info,input wire busy,output wire reply_pending,
 output reg [1:0] lookup_mode,output reg [4:0] lookup_pic,output wire lookup_enable,
 input wire [31:0] lookup_identity,primary_identity,input wire [2:0] canvas_ready,
 output wire [3:0] held_banks,output reg candidate_valid,output reg [31:0] candidate_identity,
 input wire caption_ready,frame_valid,input wire [117:0] frame_pose,
 output reg publish,output reg [31:0] publication,output reg confirmed,input wire allow_normal_fallback);
 localparam IDLE=0,LOOKUP=1,SETTLE=2,ADOPT=3,CAPTION=4,PRESENT=5,SCROLL=6,REPLY=7,DRAIN=8;
 reg [3:0] state;reg [111:0] packet;reg last_valid,hit;
 reg [7:0] generation;
 wire normal_pic=(recv_info[100:96]>=1 && recv_info[100:96]<=3) ||
                  (recv_info[100:96]>=13 && recv_info[100:96]<=16) ||
                  (allow_normal_fallback && recv_info[100:96]>=4 && recv_info[100:96]<=12);
 wire explain_pic=recv_info[100:96]>=4 && recv_info[100:96]<=12;
 wire select_pic=recv_info[100:96]==4 || recv_info[100:96]==7 || recv_info[100:96]==10;
 wire legal=recv_info[111:104]==15 && recv_info[63:0]==0 &&
   (recv_info[102:101]==0 ? normal_pic :
    !recv_info[103] && (recv_info[102:101]==1 ? select_pic : recv_info[102:101]==2 && explain_pic));
 wire [1:0] canvas_slot=lookup_pic==4?0:lookup_pic==7?1:2;
 wire can_adopt=lookup_mode==1?canvas_ready[canvas_slot]:lookup_identity[31];
 wire [31:0] proposed={1'b1,lookup_mode,lookup_pic,generation+8'd1,13'd0,lookup_mode==1,lookup_mode==1?2'd0:lookup_identity[1:0]};
 assign reply_pending=state==REPLY;
 assign lookup_enable=state==LOOKUP || state==SETTLE || state==ADOPT;
 assign held_banks=candidate_valid && state!=IDLE && !candidate_identity[2] ? 4'b1<<candidate_identity[1:0] : 4'd0;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;packet<=0;last_valid<=0;hit<=0;generation<=0;
   take<=0;send<=0;send_info<=0;lookup_mode<=0;lookup_pic<=0;candidate_valid<=0;candidate_identity<=0;publish<=0;publication<=0;confirmed<=0;end
  else begin
   take<=0;send<=0;publish<=0;confirmed<=0;
   if(state!=IDLE && available && !take && recv_info==packet)take<=1;
   case(state)
    IDLE:if(available && !take)begin
     take<=1;
     if(last_valid && recv_info==packet)state<=REPLY;
     else begin
      packet<=recv_info;last_valid<=1;hit<=0;candidate_valid<=0;
      if(!legal)state<=REPLY;
      else if(recv_info[103])state<=SCROLL;
      else begin lookup_mode<=recv_info[102:101];lookup_pic<=recv_info[100:96];state<=LOOKUP;end
     end
    end
    LOOKUP:state<=SETTLE;
    SETTLE:state<=ADOPT;
    ADOPT:if(!can_adopt)state<=REPLY;else begin
     generation<=generation+8'd1;candidate_valid<=1;
     candidate_identity<=proposed==primary_identity?proposed^32'h00010000:proposed;
     state<=CAPTION;
    end
    CAPTION:if(lookup_mode!=2 || caption_ready)begin
     publication<=candidate_identity;publish<=1;state<=PRESENT;
    end
    PRESENT:if(frame_valid && frame_pose[117:86]==candidate_identity)begin hit<=1;confirmed<=1;state<=REPLY;end
    SCROLL:if(!primary_identity[31] || primary_identity[30:29]!=0 || primary_identity[28:24]!=packet[100:96])state<=REPLY;
     else if(frame_valid && frame_pose[117] && frame_pose[116:115]==0 && frame_pose[114:110]==packet[100:96])begin hit<=1;confirmed<=1;state<=REPLY;end
    REPLY:if(!busy)begin send_info<={8'h8f,7'd0,hit,packet[95:64],64'd0};send<=1;state<=DRAIN;end
    DRAIN:if(!send && !busy)state<=IDLE;
   endcase
  end
 end
endmodule
