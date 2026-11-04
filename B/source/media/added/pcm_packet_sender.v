`timescale 1ns/1ps
module pcm_packet_sender #(parameter RETRY_CYCLES=250000,POLL_CYCLES=100000)(
 input wire clk,rst,input wire [1:0] command_mode,input wire flush_toggle,clear_pcm,
 output wire flush_done,input wire sample_valid,input wire [15:0] sample,
 output wire sample_ready,output wire [10:0] sample_room,
 output wire request,input wire grant,output reg send,output reg [111:0] send_info,input wire busy,
 output reg mem_we,output reg [8:0] mem_addr,output reg [7:0] mem_byte,
 input wire available,input wire [111:0] recv_info,output reg take,output reg restart_player);
 localparam FILL=0,FLUSH=1,PRIME=2,COPY=3,DATA=4,SEND=5,ACK=6,PARK=7,QUERY=8;
 reg [1:0] stream_mode;reg [3:0] state;reg acknowledged_flush,sent_flush,flush_packet,poll_packet;reg [11:0] credit;
 reg [31:0] epoch,sequence_id;reg [21:0] timer;
 reg [8:0] count,copy_pos;
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [15:0] samples[0:255];
 reg [15:0] sample_q;
 wire [8:0] next_copy=copy_pos+9'd1;
 wire [7:0] ram_addr=state==COPY?next_copy[8:1]:8'd0;
 assign flush_done=acknowledged_flush==flush_toggle;
 assign sample_ready=state==FILL && flush_done && count<256 && !clear_pcm;
 assign sample_room=sample_ready?11'd256-{2'd0,count}:11'd0;
 assign request=state!=FILL && state!=PARK;
 always @(posedge clk)begin
  sample_q<=samples[ram_addr];
  if(sample_valid && sample_ready)samples[count[7:0]]<=sample;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin stream_mode<=0;state<=FILL;acknowledged_flush<=0;sent_flush<=0;flush_packet<=0;poll_packet<=0;credit<=0;
   epoch<=0;sequence_id<=0;timer<=0;count<=0;copy_pos<=0;send<=0;send_info<=0;mem_we<=0;mem_addr<=0;mem_byte<=0;take<=0;restart_player<=0;end
  else begin
   send<=0;mem_we<=0;take<=0;restart_player<=0;
   case(state)
    FILL:if(!flush_done)begin count<=0;epoch<=epoch+1'b1;sequence_id<=0;state<=FLUSH;end
     else if(clear_pcm)count<=0;
     else if(sample_valid && sample_ready)begin count<=count+1'b1;if(count==255)begin copy_pos<=0;timer<=0;state<=credit>=256?PRIME:PARK;end end
    FLUSH:if(grant && !busy)begin
     sent_flush<=flush_toggle;stream_mode<=command_mode;flush_packet<=1;poll_packet<=0;
     send_info<={8'd14,5'd0,command_mode,1'b0,epoch,32'd0,32'd0};state<=SEND;
    end
    PRIME:if(grant && !busy)state<=COPY;
    COPY:begin
     mem_we<=1;mem_addr<=copy_pos;mem_byte<=copy_pos[0]?sample_q[15:8]:sample_q[7:0];
     if(copy_pos==511)state<=DATA;else copy_pos<=copy_pos+1'b1;
    end
    DATA:if(grant && !busy)begin flush_packet<=0;poll_packet<=0;
     send_info<={8'd14,5'd0,stream_mode,1'b1,epoch,sequence_id,32'd0};state<=SEND;
    end
    PARK:if(!flush_done)begin count<=0;state<=FILL;end
     else if(credit>=256)state<=PRIME;
     else if(timer>=POLL_CYCLES-1)begin timer<=0;state<=QUERY;end
     else timer<=timer+1'b1;
    QUERY:if(grant && !busy)begin flush_packet<=0;poll_packet<=1;
     send_info<={8'd14,4'd0,1'b1,stream_mode,1'b0,epoch,sequence_id,32'd0};state<=SEND;
    end
    SEND:if(grant && !busy)begin send<=1;timer<=0;state<=ACK;end
    ACK:begin
     if(timer<RETRY_CYCLES)timer<=timer+1'b1;
     if(available && !take)begin
      take<=1;
      if(recv_info[111:104]==8'h8e && recv_info[102:32]==send_info[102:32])begin
       if(recv_info[103])begin
        restart_player<=1;acknowledged_flush<=!flush_toggle;count<=0;state<=FILL;
       end else begin
        credit<=recv_info[11:0];
        if(poll_packet)begin timer<=0;state<=PARK;end
        else begin
         if(flush_packet)acknowledged_flush<=sent_flush;else sequence_id<=sequence_id+1'b1;
         count<=0;state<=FILL;
        end
       end
      end
     end else if(timer>=RETRY_CYCLES)state<=SEND;
    end
    default:state<=FILL;
   endcase
  end
 end
endmodule
