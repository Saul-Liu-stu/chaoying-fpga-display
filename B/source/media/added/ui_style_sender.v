`timescale 1ns/1ps
module ui_style_sender #(parameter RETRY_CYCLES=250000)(
 input wire clk,rst,block_valid,input wire [2:0] block_index,
 input wire [31:0] file_crc,block_crc,
 output wire [8:0] block_address,output wire block_read_enable,input wire [7:0] block_byte,
 output wire request,input wire grant,busy,
 output reg send,output reg [111:0] send_info,
 output reg mem_we,output reg [8:0] mem_addr,output reg [7:0] mem_byte,
 input wire available,input wire [111:0] recv_info,output reg take,
 output reg done,good);
 localparam IDLE=0,CLAIM=1,PRIME=2,COPY=3,SEND=4,WAIT_ACK=5,DRAIN=6;
 reg [2:0] state;reg [8:0] pos;reg [1:0] retries;
 localparam TIMER_BITS=RETRY_CYCLES>1?$clog2(RETRY_CYCLES):1;
 reg [TIMER_BITS-1:0] timer;
 assign request=state!=IDLE;
 assign block_address=state==COPY?pos+9'd1:9'd0;
 assign block_read_enable=state==PRIME || state==COPY;
 wire matching=recv_info[111:104]==8'h90 && recv_info[95:64]==file_crc && recv_info[63:32]=={20'd0,block_index,9'd0} && recv_info[31:0]==block_crc;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;pos<=0;retries<=0;timer<=0;send<=0;send_info<=0;mem_we<=0;mem_addr<=0;mem_byte<=0;take<=0;done<=0;good<=0;end
  else begin
   send<=0;mem_we<=0;take<=0;done<=0;
   case(state)
    IDLE:if(block_valid)begin state<=CLAIM;retries<=0;good<=0;end
    CLAIM:if(grant && !busy)begin pos<=0;state<=PRIME;end
    PRIME:state<=COPY;
    COPY:begin mem_we<=1;mem_addr<=pos;mem_byte<=block_byte;if(pos==511)state<=SEND;else pos<=pos+1'b1;end
    SEND:if(grant && !busy)begin send_info<={8'd16,{5'd0,block_index},file_crc,{20'd0,block_index,9'd0},block_crc};send<=1;timer<=0;state<=WAIT_ACK;end
    WAIT_ACK:begin
     if(available && !take)begin
      take<=1;
      if(matching)begin done<=1;good<=recv_info[103:96]==0;state<=DRAIN;end
     end else if(timer==RETRY_CYCLES-1)begin
      if(retries==3)begin done<=1;good<=0;state<=DRAIN;end
      else begin retries<=retries+1'b1;state<=SEND;end
     end else timer<=timer+1'b1;
    end
    DRAIN:if(!busy && !send)state<=IDLE;
   endcase
  end
 end
endmodule
