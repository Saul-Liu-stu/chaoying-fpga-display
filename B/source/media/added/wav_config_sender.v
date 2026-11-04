`timescale 1ns/1ps
module wav_config_sender #(parameter RETRY_CYCLES=2500000)(
 input wire clk,rst,mounted,input wire [511:0] config_data,
 output wire request,input wire grant,output reg done,
 output reg send,output reg [111:0] send_info,input wire busy,
 output reg mem_we,output reg [8:0] mem_addr,output reg [7:0] mem_byte,
 input wire available,input wire [111:0] recv_info,output reg take);
 localparam IDLE=0,COPY=1,HEADER=2,SEND=3,WAIT_ACK=4,FINISHED=5;
 reg [2:0] state;reg [8:0] pos;reg [31:0] crc;reg [21:0] timer;
 reg [511:0] held;
 wire [7:0] value=pos<64?held[pos[5:0]*8+:8]:8'd0;
 assign request=state!=IDLE && state!=FINISHED;
 function [31:0] crc_byte(input [31:0] c,input [7:0] d);
  reg [31:0] t;integer k;begin t=c;for(k=0;k<8;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hedb88320:32'd0);crc_byte=t;end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;held<=0;pos<=0;crc<=0;timer<=0;done<=0;send<=0;send_info<=0;mem_we<=0;mem_addr<=0;mem_byte<=0;take<=0;end
  else begin
   send<=0;mem_we<=0;take<=0;
   case(state)
    IDLE:if(mounted)begin held<=config_data;pos<=0;crc<=32'hffffffff;state<=COPY;end
    COPY:if(grant && !busy)begin
     mem_we<=1;mem_addr<=pos;mem_byte<=value;crc<=crc_byte(crc,value);
     if(pos==511)state<=HEADER;else pos<=pos+1'b1;
    end
    HEADER:begin send_info<={8'd13,8'd1,32'd1,32'd0,~crc};state<=SEND;end
    SEND:if(grant && !busy)begin send<=1;timer<=0;state<=WAIT_ACK;end
    WAIT_ACK:begin
     if(timer<RETRY_CYCLES)timer<=timer+1'b1;
     if(available && !take)begin
      take<=1;
      if(recv_info=={8'h8d,send_info[103:0]})begin done<=1;timer<=0;state<=FINISHED;end
     end else if(timer>=RETRY_CYCLES)state<=SEND;
    end
    FINISHED:if(timer>=RETRY_CYCLES)begin
     timer<=0;pos<=0;crc<=32'hffffffff;state<=COPY;
    end else timer<=timer+1'b1;
   endcase
  end
 end
endmodule
