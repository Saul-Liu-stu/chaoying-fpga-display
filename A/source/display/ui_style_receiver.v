`timescale 1ns/1ps
module ui_style_receiver(
 input wire clk,rst,available,input wire [111:0] recv_info,output reg take,
 output wire [8:0] read_addr,input wire [7:0] read_byte,
 output reg send,output reg [111:0] send_info,input wire busy,
 output wire transaction_idle,output reg style_we,output reg [11:0] style_address,
 output reg [7:0] style_byte,output reg style_valid,output reg [119:0] style_palette,
 output reg style_failed);
 localparam IDLE=0,PRIME=1,COPY=2,CHECK=3,ACK=4,DRAIN=5;
 reg [2:0] state,next_block,block_index;reg [8:0] pos;
 reg [31:0] file_id,ack_file_id,packet_crc,chunk_crc,file_crc,header_crc,last_chunk_crc;
 reg [7:0] ack_status;reg header_good,aborted;
 wire [11:0] file_position={block_index,pos};
 assign read_addr=state==COPY?pos+9'd1:9'd0;
 assign transaction_idle=state==IDLE;
 function [31:0] crc_byte(input [31:0] c,input [7:0] d);
  reg [31:0] t;integer k;begin t=c;for(k=0;k<8;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hedb88320:32'd0);crc_byte=t;end
 endfunction
 function header_byte_good(input [11:0] a,input [7:0] d);
  begin case(a)
   0:header_byte_good=d==8'h55;1:header_byte_good=d==8'h49;2:header_byte_good=d==8'h53;3:header_byte_good=d==8'h31;
   4,5:header_byte_good=d==1;6:header_byte_good=d==64;9:header_byte_good=d==12;12:header_byte_good=d==48;13:header_byte_good=d==11;
   16,17,18,20,21,22,24,25,26,28,29,30,32,33,34,35,36,37,38:header_byte_good=1;
   default:header_byte_good=a>=64 && a<2928?1:d==0;
  endcase end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;next_block<=0;block_index<=0;pos<=0;file_id<=0;ack_file_id<=0;packet_crc<=0;chunk_crc<=0;file_crc<=0;header_crc<=0;last_chunk_crc<=0;
   ack_status<=0;header_good<=1;aborted<=0;take<=0;send<=0;send_info<=0;
   style_we<=0;style_address<=0;style_byte<=0;style_valid<=0;style_palette<=0;style_failed<=0;
  end else begin
   take<=0;send<=0;style_we<=0;
   case(state)
    IDLE:if(available && !take)begin
     ack_file_id<=recv_info[95:64];packet_crc<=recv_info[31:0];block_index<=recv_info[98:96];ack_status<=1;
     if(recv_info[111:104]!=16 || recv_info[103:99]!=0 || recv_info[98:96]>5 || recv_info[63:32]!={20'd0,recv_info[98:96],9'd0})begin take<=1;state<=ACK;end
     else if(next_block!=0 && recv_info[98:96]==next_block-1'b1 && recv_info[95:64]==file_id && recv_info[31:0]==last_chunk_crc)begin ack_status<=0;take<=1;state<=ACK;end
     else if(aborted || style_valid || recv_info[98:96]!=next_block || (next_block!=0 && recv_info[95:64]!=file_id))begin take<=1;state<=ACK;end
     else begin
      pos<=0;chunk_crc<=32'hffffffff;state<=PRIME;
      if(next_block==0)begin file_id<=recv_info[95:64];file_crc<=32'hffffffff;header_good<=1;header_crc<=0;end
     end
    end
    PRIME:state<=COPY;
    COPY:begin
     chunk_crc<=crc_byte(chunk_crc,read_byte);
     if(file_position<32 || file_position>=36)file_crc<=crc_byte(file_crc,read_byte);
     if(!header_byte_good(file_position,read_byte))header_good<=0;
     if(file_position>=64 && file_position<2928)begin style_we<=1;style_address<=file_position-12'd64;style_byte<=read_byte;end
     case(file_position)
      16:style_palette[119:112]<=read_byte;17:style_palette[111:104]<=read_byte;18:style_palette[103:96]<=read_byte;
      20:style_palette[95:88]<=read_byte;21:style_palette[87:80]<=read_byte;22:style_palette[79:72]<=read_byte;
      24:style_palette[71:64]<=read_byte;25:style_palette[63:56]<=read_byte;26:style_palette[55:48]<=read_byte;
      28:style_palette[47:40]<=read_byte;29:style_palette[39:32]<=read_byte;30:style_palette[31:24]<=read_byte;
      32:header_crc[7:0]<=read_byte;33:header_crc[15:8]<=read_byte;34:header_crc[23:16]<=read_byte;35:header_crc[31:24]<=read_byte;
      36:style_palette[23:16]<=read_byte;37:style_palette[15:8]<=read_byte;38:style_palette[7:0]<=read_byte;
     endcase
     if(pos==511)state<=CHECK;else pos<=pos+1'b1;
    end
    CHECK:begin
     take<=1;state<=ACK;ack_status<=1;
     if(~chunk_crc!=packet_crc || !header_good || header_crc!=file_id || (block_index==5 && ~file_crc!=file_id))begin aborted<=1;style_failed<=1;end
     else begin
      ack_status<=0;next_block<=next_block+1'b1;last_chunk_crc<=packet_crc;
      if(block_index==5)begin style_valid<=1;end
     end
    end
    ACK:if(!busy)begin send_info<={8'h90,ack_status,ack_file_id,{20'd0,block_index,9'd0},packet_crc};send<=1;state<=DRAIN;end
    DRAIN:if(!busy && !send)state<=IDLE;
   endcase
  end
 end
endmodule
