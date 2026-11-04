`timescale 1ns/1ps
module frame_sender_scene #(parameter FRAME_PIXELS=307200,TILE_PIXELS=23232,RETRY_CYCLES=2500000,DATA_RETRY_CYCLES=RETRY_CYCLES)(
 input wire clk,rst,begin_frame,input wire [4:0] picture,
 input wire write_req,output reg write_ack,
 input wire pixel_valid,input wire [23:0] pixel,output wire pixel_ready,
 input wire source_done,output reg frame_done,output wire request,output wire transaction_waiting,input wire grant,
 output reg send,output reg [111:0] send_info,input wire busy,
 output reg mem_we,output reg [8:0] mem_addr,output reg [7:0] mem_byte,
 input wire available,input wire [111:0] recv_info,output reg take,
 input wire [2:0] operation,input wire [31:0] begin_aux,output reg cache_hit);
 localparam IDLE=0,BEGIN=1,SEND=2,WAIT_ACK=3,FILL=4,GREEN=5,BLUE=6,COPY_PRIME=7,COPY=8,DATA=9,END_FRAME=10;
 reg [3:0] state;reg [7:0] kind;reg [4:0] pic;reg [2:0] op;reg [31:0] pixel_limit,transfer_limit,aux;
 reg [31:0] frame_id,offset,total,crc,packet_crc;reg [21:0] timer;
 reg [6:0] packet_pixels;reg [8:0] byte_pos,copy_pos;reg [15:0] tail;
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [7:0] payload[0:511];
 reg [7:0] payload_q;
 wire [8:0] copy_addr=(state==COPY)?copy_pos+9'd1:9'd0;
 wire capture=state==FILL && (pixel_valid || total>=pixel_limit);
 wire byte_we=capture || state==GREEN || state==BLUE;
 wire [7:0] next_byte=capture?(total<pixel_limit?pixel[23:16]:8'd0):state==GREEN?tail[15:8]:tail[7:0];
 always @(posedge clk)begin
  payload_q<=payload[copy_addr];
  if(byte_we)payload[byte_pos]<=next_byte;
 end
 function [31:0] crc_byte(input [31:0] c,input [7:0] d);
  reg [31:0] t;integer k;begin t=c;for(k=0;k<8;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hedb88320:32'd0);crc_byte=t;end
 endfunction
 assign pixel_ready=state==FILL && total<pixel_limit;
 assign transaction_waiting=state==WAIT_ACK;
 wire presentation_wait=state==WAIT_ACK && (kind==7 || (kind==5 && (op==3 || op==6 || op==7)));
 assign request=state==BEGIN || state==SEND || (state==WAIT_ACK && !presentation_wait) || state==COPY_PRIME || state==COPY || state==DATA || (state==END_FRAME && source_done);
 wire [21:0] retry_limit=(kind==6)?DATA_RETRY_CYCLES:RETRY_CYCLES;
 wire ack_match=recv_info[111:104]==(kind|8'h80) && recv_info[103:97]==0 &&
  (!recv_info[96] || (kind==5 && op==7)) &&
  recv_info[95:0]==send_info[95:0];
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   cache_hit<=0;state<=IDLE;kind<=0;pic<=0;op<=0;pixel_limit<=0;transfer_limit<=0;aux<=0;frame_id<=0;offset<=0;total<=0;crc<=0;packet_crc<=0;timer<=0;
   packet_pixels<=0;byte_pos<=0;copy_pos<=0;tail<=0;write_ack<=0;frame_done<=0;
   send<=0;send_info<=0;mem_we<=0;mem_addr<=0;mem_byte<=0;take<=0;
  end else begin
   send<=0;mem_we<=0;take<=0;frame_done<=0;
   if(!write_req)write_ack<=0;
   if(byte_we)begin crc<=crc_byte(crc,next_byte);packet_crc<=crc_byte(packet_crc,next_byte);end
   case(state)
    IDLE:if(begin_frame)begin
     cache_hit<=0;
     frame_id<=frame_id+1'b1;pic<=picture;op<=operation;aux<=begin_aux;pixel_limit<=operation==2?TILE_PIXELS:FRAME_PIXELS;transfer_limit<=operation==2?((TILE_PIXELS+127)/128)*128:FRAME_PIXELS;offset<=0;total<=0;byte_pos<=0;packet_pixels<=0;
     crc<=32'hffffffff;packet_crc<=32'hffffffff;state<=BEGIN;
    end
    BEGIN:if(grant && !busy)begin kind<=5;send_info<={8'd5,op,pic,frame_id,aux,32'd0};state<=SEND;end
    DATA:if(grant && !busy)begin kind<=6;send_info<={8'd6,8'd0,frame_id,offset,~packet_crc};state<=SEND;end
    END_FRAME:if(source_done && grant && !busy)begin kind<=7;send_info<={8'd7,8'd0,frame_id,total,~crc};state<=SEND;end
    SEND:if(grant && !busy)begin send<=1;timer<=0;state<=WAIT_ACK;end
    WAIT_ACK:begin
     if(timer<retry_limit)timer<=timer+1'b1;
     if(available && !take)begin
      take<=1;
      if(ack_match)case(kind)
       5:if(op==3 || op==6 || op==7)begin cache_hit<=op==7 && recv_info[96];frame_done<=1;state<=IDLE;end else begin write_ack<=1;state<=FILL;end
       6:begin
        if(total==transfer_limit)state<=END_FRAME;
        else begin offset<=offset+128;byte_pos<=0;packet_pixels<=0;packet_crc<=32'hffffffff;state<=FILL;end
       end
       7:begin frame_done<=1;state<=IDLE;end
      endcase
     end else if(timer>=retry_limit)state<=SEND;
    end
    FILL:if(pixel_valid || total>=pixel_limit)begin tail<=total<pixel_limit?pixel[15:0]:16'd0;byte_pos<=byte_pos+1'b1;state<=GREEN;end
    GREEN:begin byte_pos<=byte_pos+1'b1;state<=BLUE;end
    BLUE:begin
     byte_pos<=byte_pos+1'b1;total<=total+1'b1;packet_pixels<=packet_pixels+1'b1;
     if(packet_pixels==127)begin copy_pos<=0;state<=COPY_PRIME;end else state<=FILL;
    end
    COPY_PRIME:if(grant && !busy)state<=COPY;
    COPY:begin
     mem_we<=1;mem_addr<=copy_pos;mem_byte<=copy_pos<384?payload_q:8'd0;
     if(copy_pos==511)state<=DATA;else copy_pos<=copy_pos+1'b1;
    end
   endcase
  end
 end
endmodule
