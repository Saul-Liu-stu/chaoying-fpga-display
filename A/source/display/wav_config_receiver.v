`timescale 1ns/1ps
module wav_config_receiver(
 input wire clk,rst,available,input wire [111:0] recv_info,output reg take,
 output wire [8:0] read_addr,input wire [7:0] read_byte,
 output reg send,output reg [111:0] send_info,input wire busy,output wire idle,
 output reg mounted,output reg [511:0] config_data);
 localparam IDLE=0,PRIME=1,COPY=2,CHECK=3,ACK=4,DRAIN=5;
 reg [2:0] state;reg [8:0] pos;reg [31:0] crc,saved_crc;reg bad;
 reg [511:0] shadow;reg [111:0] header;
 assign idle=state==IDLE;
 assign read_addr=state==COPY?pos+9'd1:9'd0;
 function [31:0] crc_byte(input [31:0] c,input [7:0] d);
  reg [31:0] t;integer k;begin t=c;for(k=0;k<8;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hedb88320:32'd0);crc_byte=t;end
 endfunction
 wire fields_good=shadow[31:0]==32'h31564157 && shadow[63:56]==1 &&
  shadow[39:35]==0 && shadow[47:43]==0 && shadow[55:48]<=7 &&
  shadow[223:193]==0 && shadow[511:416]==0 &&
  shadow[95:64]<shadow[127:96] && shadow[159:128]>=2 &&
  {1'b0,shadow[127:96]}<shadow[192:160];
 reg fields_good_q;
 wire commit_good=!bad && ~crc==header[31:0] && fields_good_q && (!mounted || saved_crc==~crc);
 always @(posedge clk)begin
  fields_good_q<=fields_good;
  if(!rst && state==COPY && pos<64)shadow[pos[5:0]*8+:8]<=read_byte;
  if(!rst && state==CHECK && commit_good && !mounted)config_data<=shadow;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;pos<=0;crc<=0;saved_crc<=0;bad<=0;header<=0;mounted<=0;send<=0;send_info<=0;take<=0;end
  else begin
   send<=0;take<=0;
   case(state)
    IDLE:if(available && !take)begin
     take<=1;
     if(recv_info[111:96]==16'h0d01 && recv_info[95:32]==64'h0000000100000000)begin
      header<=recv_info;pos<=0;crc<=32'hffffffff;bad<=0;state<=PRIME;
     end
    end
    PRIME:state<=COPY;
    COPY:begin
     crc<=crc_byte(crc,read_byte);
     if(pos>=64 && read_byte!=0)bad<=1;
     if(pos==511)state<=CHECK;else pos<=pos+1'b1;
    end
    CHECK:begin
     if(commit_good)begin
      if(!mounted)begin mounted<=1;saved_crc<=~crc;end
      send_info<={8'h8d,header[103:0]};state<=ACK;
     end else state<=IDLE;
    end
    ACK:if(!busy)begin send<=1;state<=DRAIN;end
    DRAIN:if(!busy && !send)state<=IDLE;
   endcase
  end
 end
endmodule
