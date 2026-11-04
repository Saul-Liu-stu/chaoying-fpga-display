`timescale 1ns/1ps
module pcm_packet_receiver #(
 parameter integer PREFILL_SAMPLES=2048
)(input wire clk,rst,available,input wire [111:0] recv_info,output reg take,
 output reg [8:0] read_addr,input wire [7:0] read_byte,
 output reg send,output reg [111:0] send_info,input wire busy,output wire transaction_idle,
 output reg [1:0] command_mode,output reg flush_toggle,run_pcm,clear_pcm,
 input wire flush_done,output reg sample_valid,output reg [15:0] sample,
 input wire sample_ready,input wire [12:0] sample_room,output reg [7:0] error_code);
 localparam IDLE=0,FLUSH_WAIT=1,CLEAR=2,CREDIT=3,ADDR=4,WAIT_BYTE=5,USE=6,PUSH=7,REPLY=8,DRAIN=9;
 reg [3:0] state;reg [111:0] packet;reg [31:0] epoch,expected;
 reg epoch_valid,nack;reg [8:0] position;reg [7:0] low_byte;reg [4:0] prefilled;
 wire [11:0] reported_sample_room=(sample_room>13'd4095) ? 12'hfff : sample_room[11:0];
 assign transaction_idle=state==IDLE;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;packet<=0;epoch<=0;expected<=0;epoch_valid<=0;nack<=0;position<=0;low_byte<=0;prefilled<=0;
   take<=0;read_addr<=0;send<=0;send_info<=0;command_mode<=0;flush_toggle<=0;run_pcm<=0;clear_pcm<=0;sample_valid<=0;sample<=0;error_code<=0;end
  else begin
   take<=0;send<=0;clear_pcm<=0;sample_valid<=0;
   case(state)
    IDLE:if(available && !take)begin
     take<=1;packet<=recv_info;nack<=0;
     if(recv_info[111:104]!=14 || recv_info[103:100]!=0 || recv_info[31:0]!=0)begin nack<=1;state<=REPLY;end
     else if(recv_info[99])begin
      nack<=!epoch_valid || recv_info[95:64]!=epoch || recv_info[98:97]!=command_mode;
      state<=REPLY;
     end else if(!recv_info[96])begin
      if(epoch_valid && recv_info[95:64]==epoch)state<=REPLY;
      else begin epoch<=recv_info[95:64];epoch_valid<=1;expected<=0;prefilled<=0;run_pcm<=0;
       command_mode<=recv_info[98:97];flush_toggle<=!flush_toggle;state<=FLUSH_WAIT;end
     end else if(!epoch_valid || recv_info[95:64]!=epoch || recv_info[98:97]!=command_mode)begin nack<=1;state<=REPLY;end
     else if(recv_info[63:32]==expected)state<=CREDIT;
     else if(expected!=0 && recv_info[63:32]==expected-1'b1)state<=REPLY;
     else begin nack<=1;state<=REPLY;end
    end
    FLUSH_WAIT:if(flush_done)begin clear_pcm<=1;state<=CLEAR;end
    CLEAR:state<=REPLY;
    CREDIT:if(flush_done && sample_room>=256)begin position<=0;state<=ADDR;end
    ADDR:begin read_addr<=position;state<=WAIT_BYTE;end
    WAIT_BYTE:state<=USE;
    USE:if(!position[0])begin low_byte<=read_byte;position<=position+1'b1;state<=ADDR;end
     else if(sample_ready)begin sample<={read_byte,low_byte};sample_valid<=1;state<=PUSH;end
    PUSH:begin
     if(position==511)begin
      expected<=expected+1'b1;
      if(prefilled<PREFILL_SAMPLES/256)prefilled<=prefilled+1'b1;
      if(prefilled>=PREFILL_SAMPLES/256-1)run_pcm<=command_mode!=0;
      state<=REPLY;
     end else begin position<=position+1'b1;state<=ADDR;end
    end
    REPLY:if(!busy)begin send_info<={8'h8e,nack,packet[102:32],20'd0,reported_sample_room};send<=1;state<=DRAIN;end
    DRAIN:if(!busy && !send)state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
