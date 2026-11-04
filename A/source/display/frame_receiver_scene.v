`timescale 1ns/1ps
module frame_receiver_scene #(parameter FRAME_PIXELS=307200,TILE_PIXELS=23232)(
 input wire clk,rst,available,input wire [111:0] recv_info,output reg take,
 output reg [8:0] read_addr,input wire [7:0] read_byte,
 output reg send,output reg [111:0] send_info,input wire busy,
 output wire transaction_idle,
 output wire transaction_parked,reply_pending,
 output reg write_req,input wire write_req_ack,write_ready,
 output wire write_en,output wire [31:0] write_data,
 output reg [31:0] write_identity,output reg [31:0] display_identity,output reg display_valid,
 input wire write_done_valid,input wire [31:0] write_done_identity,
 input wire frame_valid,input wire [117:0] frame_pose,input wire transfer_fault,
 output reg [3:0] fault,output reg [31:0] frames,
 input wire allocate_ready,input wire [1:0] allocate_bank,input wire [31:0] normal_identity,
 output reg cache_commit,output reg [31:0] cache_identity,
 output reg [1:0] lookup_mode,output reg [4:0] lookup_pic,input wire [31:0] lookup_identity,output wire [2:0] canvas_ready,input wire allow_normal_fallback);
 localparam IDLE=0,WAIT_ACK_HI=1,WAIT_ACK_LO=2,SCAN_PRIME=3,SCAN=4,
  EMIT_PRIME=5,RED=6,GREEN=7,BLUE=8,PIXEL=9,ACK=10,WAIT_TX=11,WAIT_WRITE=12,WAIT_PRESENT=13,CHECK=14,WAIT_SCROLL=15,LOOKUP_WAIT=16,LOOKUP_ADOPT=17,METADATA=18;
 function integer count_width(input integer n);
  begin count_width=0;while(n>0)begin count_width=count_width+1;n=n>>1;end
   if(count_width==0)count_width=1;end
 endfunction
 localparam TILE_TRANSFER=((TILE_PIXELS+127)/128)*128;
 localparam MAX_TRANSFER=FRAME_PIXELS>TILE_TRANSFER?FRAME_PIXELS:TILE_TRANSFER;
 localparam COUNT_BITS=count_width(MAX_TRANSFER+127);
 reg [COUNT_BITS-1:0] expected_offset,last_offset,in_offset,real_pixels,transfer_pixels;
 reg [4:0] state;reg [31:0] frame_id,last_crc,frame_crc,candidate_crc,packet_crc,in_crc;
 reg [2:0] operation,canvas_expected,canvas_received;reg canvas_background;reg [7:0] emit_limit;
 reg [4:0] normal_pic;reg [7:0] in_kind,generation;reg active,write_finished,packet_seen,end_complete;
 reg probe_hit;
 reg duplicate_data_ok,new_data_ok,end_data_ok;
 always @(posedge clk or posedge rst)begin
  if(rst)begin duplicate_data_ok<=0;new_data_ok<=0;end_data_ok<=0;end
  else if(state==IDLE && available && !take)begin
   duplicate_data_ok<=packet_seen && recv_info[63:32]==last_offset && recv_info[31:0]==last_crc;
   new_data_ok<=recv_info[63:32]==expected_offset && expected_offset<transfer_pixels;
   end_data_ok<=recv_info[63:32]==transfer_pixels && recv_info[31:0]==~frame_crc;
  end
 end
 wire normal_picture=(recv_info[100:96]>=1 && recv_info[100:96]<=3) ||
  (recv_info[100:96]>=13 && recv_info[100:96]<=16) ||
  (allow_normal_fallback && recv_info[100:96]>=4 && recv_info[100:96]<=12);
 reg [8:0] pos;reg [23:0] rgb;reg [6:0] pixel_number;
 (* ASYNC_REG="TRUE" *) reg [2:0] ack_sync;
 assign canvas_ready=canvas_background && canvas_expected!=0 && (canvas_received&canvas_expected)==canvas_expected ? canvas_expected : 3'd0;
 assign transaction_idle=state==IDLE;
 assign transaction_parked=state==WAIT_WRITE || state==WAIT_PRESENT || state==WAIT_SCROLL;
 assign reply_pending=state==ACK;
 wire parked_duplicate=transaction_parked && available && !take &&
   recv_info[111:104]==in_kind && recv_info[95:0]==send_info[95:0];
 assign write_en=state==PIXEL && write_ready && pixel_number<emit_limit && fault==0;
 assign write_data={rgb,8'd0};
 function [31:0] crc_byte(input [31:0] c,input [7:0] d);
  reg [31:0] t;integer k;begin t=c;for(k=0;k<8;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hedb88320:32'd0);crc_byte=t;end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   lookup_mode<=0;lookup_pic<=0;probe_hit<=0;cache_commit<=0;cache_identity<=0;normal_pic<=0;state<=IDLE;take<=0;read_addr<=0;send<=0;send_info<=0;write_req<=0;
   write_identity<=0;display_identity<=0;display_valid<=0;fault<=0;frames<=0;frame_id<=0;expected_offset<=0;
   last_offset<=0;last_crc<=0;frame_crc<=0;candidate_crc<=0;packet_crc<=0;in_crc<=0;in_offset<=0;in_kind<=0;
   generation<=0;operation<=0;canvas_expected<=0;canvas_received<=0;canvas_background<=0;real_pixels<=0;transfer_pixels<=0;emit_limit<=0;active<=0;write_finished<=0;packet_seen<=0;end_complete<=0;pos<=0;rgb<=0;pixel_number<=0;ack_sync<=0;
  end else begin
   take<=parked_duplicate;send<=0;cache_commit<=0;ack_sync<={ack_sync[1:0],write_req_ack};
   if(transfer_fault)fault<=7;
   if(write_done_valid && write_done_identity==write_identity)write_finished<=1;
   if(state==RED)rgb[23:16]<=read_byte;
   if(state==GREEN)rgb[15:8]<=read_byte;
   if(state==BLUE)rgb[7:0]<=read_byte;
   if(fault==0 && state==IDLE && available && !take &&
      recv_info[111:104]==6 && active && recv_info[95:64]==frame_id &&
      recv_info[63:32]==expected_offset && expected_offset<transfer_pixels)begin
    pos<=0;read_addr<=0;packet_crc<=32'hffffffff;candidate_crc<=frame_crc;
    emit_limit<=real_pixels-expected_offset>=128?8'd128:real_pixels-expected_offset;
   end
   if(fault==0)case(state)
    IDLE:if(available && !take)state<=METADATA;
    METADATA:if(available && !take)begin
     state<=IDLE;
     in_kind<=recv_info[111:104];in_crc<=recv_info[31:0];in_offset<=recv_info[63:32];
     send_info<={recv_info[111:104]|8'h80,8'd0,recv_info[95:0]};
     if(recv_info[111:104]==5)begin
      if(!active && !(end_complete && recv_info[95:64]==frame_id) &&
        (recv_info[103:101]==0 || recv_info[103:101]==4 || recv_info[103:101]==5) && !allocate_ready)begin state<=METADATA;end
      else begin take<=1;
      if((active || end_complete) && recv_info[95:64]==frame_id)begin
       send_info[96]<=operation==7 && probe_hit;state<=ACK;
      end
      else if(!active)begin
       if((recv_info[103:101]==7 && (recv_info[63:34]!=0 || recv_info[31:0]!=0 ||
           !(recv_info[33:32]==0 && normal_picture ||
             recv_info[33:32]==2 && recv_info[100:96]>=4 && recv_info[100:96]<=12))) ||
          (recv_info[103:101]==5 && (recv_info[63:34]!=0 || recv_info[31:0]!=0 ||
           !(recv_info[33:32]==0 && normal_picture ||
             recv_info[33:32]==2 && recv_info[100:96]>=4 && recv_info[100:96]<=12))) ||
          (recv_info[103:101]==1 && recv_info[34:32]==0) ||
          (recv_info[103:101]==2 && (!canvas_background ||
             !(recv_info[100:96]==4 && canvas_expected[0] || recv_info[100:96]==7 && canvas_expected[1] || recv_info[100:96]==10 && canvas_expected[2]))) ||
          (recv_info[103:101]==3 && (!canvas_background || (canvas_received&canvas_expected)!=canvas_expected ||
             !(recv_info[100:96]==4 && canvas_expected[0] || recv_info[100:96]==7 && canvas_expected[1] || recv_info[100:96]==10 && canvas_expected[2]))))fault<=8;
       else begin
        frame_id<=recv_info[95:64];generation<=generation+1'b1;operation<=recv_info[103:101];normal_pic<=recv_info[100:96];
        expected_offset<=0;frame_crc<=32'hffffffff;packet_seen<=0;write_finished<=0;end_complete<=0;active<=1;probe_hit<=0;
        real_pixels<=recv_info[103:101]==2?TILE_PIXELS:FRAME_PIXELS;
        transfer_pixels<=recv_info[103:101]==2?((TILE_PIXELS+127)/128)*128:FRAME_PIXELS;
        if(recv_info[103:101]==7)begin
         lookup_mode<=recv_info[33:32];lookup_pic<=recv_info[100:96];state<=LOOKUP_WAIT;
        end else if(recv_info[103:101]==6)state<=WAIT_SCROLL;
        else if(recv_info[103:101]==3)begin
         display_identity<={1'b1,2'd1,recv_info[100:96],generation+8'd1,13'd0,1'b1,2'd0};display_valid<=1;state<=WAIT_PRESENT;
        end else begin
         write_req<=1;state<=WAIT_ACK_HI;
         if(recv_info[103:101]==1 || recv_info[103:101]==2)
          write_identity<={1'b1,2'd1,recv_info[100:96],generation+8'd1,13'd0,1'b1,2'd0};
         else write_identity<={1'b1,(recv_info[103:101]==4 || recv_info[103:101]==5 && recv_info[33:32]==2?2'd2:2'd0),recv_info[100:96],generation+8'd1,14'd0,allocate_bank};
         if(recv_info[103:101]==1)begin canvas_expected<=recv_info[34:32];canvas_received<=0;canvas_background<=0;end
        end
       end
      end else fault<=8;
      end
     end else if(recv_info[95:64]!=frame_id)take<=1;
     else if(recv_info[111:104]==6 && active)begin
      if(duplicate_data_ok)begin take<=1;state<=ACK;end
      else if(new_data_ok)begin
       state<=SCAN_PRIME;
      end else begin take<=1;fault<=8;end
     end else if(recv_info[111:104]==7)begin
      take<=1;
      if(end_complete && end_data_ok)state<=ACK;
      else if(active && expected_offset==transfer_pixels && end_data_ok)state<=WAIT_WRITE;
      else fault<=9;
     end else take<=1;
    end
    WAIT_ACK_HI:if(ack_sync[2])begin write_req<=0;state<=WAIT_ACK_LO;end
    LOOKUP_WAIT:state<=LOOKUP_ADOPT;
    LOOKUP_ADOPT:begin
     probe_hit<=lookup_identity[31];send_info[96]<=lookup_identity[31];
     if(lookup_identity[31])begin
      write_identity<={1'b1,lookup_mode,lookup_pic,generation,14'd0,lookup_identity[1:0]};
      display_identity<={1'b1,lookup_mode,lookup_pic,generation,14'd0,lookup_identity[1:0]};
      display_valid<=1;state<=WAIT_PRESENT;
     end else begin end_complete<=1;active<=0;state<=ACK;end
    end
    WAIT_ACK_LO:if(!ack_sync[2])state<=ACK;
    SCAN_PRIME:begin read_addr<=1;state<=SCAN;end
    SCAN:begin
     packet_crc<=crc_byte(packet_crc,read_byte);candidate_crc<=crc_byte(candidate_crc,read_byte);
     if(pos==383)state<=CHECK;
     else begin pos<=pos+1'b1;read_addr<=pos+9'd2;end
    end
    CHECK:if(~packet_crc!=in_crc)begin fault<=9;take<=1;end
      else begin frame_crc<=candidate_crc;pos<=0;read_addr<=0;pixel_number<=0;state<=EMIT_PRIME;end
    EMIT_PRIME:begin read_addr<=pos+9'd1;state<=RED;end
    RED:begin read_addr<=pos+9'd2;state<=GREEN;end
    GREEN:begin state<=BLUE;end
    BLUE:begin state<=PIXEL;end
    PIXEL:if(pixel_number>=emit_limit || write_ready)begin
     if(pixel_number>=emit_limit && rgb!=0)fault<=9;
     if(pixel_number==127)begin
      expected_offset<=expected_offset+128;last_offset<=in_offset;last_crc<=in_crc;packet_seen<=1;take<=1;state<=ACK;
     end else begin
      pixel_number<=pixel_number+1'b1;pos<=pos+9'd3;read_addr<=pos+9'd3;state<=EMIT_PRIME;
     end
    end
    ACK:if(!busy)begin send<=1;state<=WAIT_TX;end
    WAIT_TX:if(!send && !busy)state<=IDLE;
    WAIT_WRITE:if(write_finished)begin
     if(operation==5)begin cache_commit<=1;cache_identity<=write_identity;end_complete<=1;active<=0;state<=ACK;end
     else if(operation==1 || operation==2)begin
      if(operation==1)canvas_background<=1;
      else if(write_identity[28:24]==4)canvas_received[0]<=1;
      else if(write_identity[28:24]==7)canvas_received[1]<=1;
      else canvas_received[2]<=1;
      end_complete<=1;active<=0;state<=ACK;
     end else begin display_identity<=write_identity;display_valid<=1;state<=WAIT_PRESENT;end
    end
    WAIT_SCROLL:if(frame_valid && normal_identity[31] && normal_identity[30:29]==0 && normal_identity[28:24]==normal_pic && frame_pose[117:86]==normal_identity)begin
     end_complete<=1;active<=0;frames<=frames+1'b1;state<=ACK;
    end
    WAIT_PRESENT:if(frame_valid && frame_pose[117:86]==display_identity)begin
     end_complete<=1;active<=0;frames<=frames+1'b1;state<=ACK;
    end
   endcase
  end
 end
endmodule
