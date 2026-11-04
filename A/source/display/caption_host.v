`timescale 1ns/1ps
module caption_host(
 input wire clk,rst,available,input wire [111:0] recv_info,output reg take,
 output reg send,output reg [111:0] send_info,input wire busy,output wire idle,
 output reg [8:0] read_addr,input wire [7:0] read_byte,
 input wire request_toggle,cancel_toggle,expired,input wire [55:0] payload,
 output reg response_toggle,response_good,font_bad,output reg [31:0] response_mask,
 output reg cache_we,output reg [9:0] cache_address,output reg [23:0] cache_row,
 output reg map_we,output reg [6:0] map_address,output reg [4:0] map_slot,
 output reg [20:0] lengths,output reg [2:0] text_ready);
 localparam IDLE=0,ACK=1,WAIT_TX=2,PRIME=3,RED=4,GREEN=5,BLUE=6,ROW=7,MAP=8;
 reg [3:0] state;reg [31:0] query_id,job_id,dirty,mask;reg [63:0] snapshot;
 reg [55:0] completed_payload;reg [2:0] expected;reg active,completed,good,bad,token;
 reg [9:0] row_index;reg [4:0] slot,row;reg [6:0] pixel;reg [8:0] pos;
 reg [23:0] rgb;
 wire [63:0] raw_current={5'd0,expired,cancel_toggle,request_toggle,payload};
 reg [63:0] current;
 always @(posedge clk or posedge rst)if(rst)current<=0;else current<=raw_current;
 wire current_job=current==snapshot && !current[58];
 wire pending=!current[58] && (current[56]!=response_toggle || current[55:0]!=completed_payload);
 assign idle=state==IDLE;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=0;take<=0;send<=0;send_info<=0;read_addr<=0;query_id<=0;job_id<=0;dirty<=0;mask<=0;snapshot<=0;
   completed_payload<=0;expected<=0;active<=0;completed<=0;good<=0;bad<=0;token<=0;row_index<=0;slot<=0;row<=0;pixel<=0;pos<=0;rgb<=0;
   response_toggle<=0;response_good<=0;font_bad<=0;response_mask<=0;cache_we<=0;cache_address<=0;cache_row<=0;map_we<=0;map_address<=0;map_slot<=0;lengths<=0;text_ready<=0;end
  else begin
   take<=0;send<=0;cache_we<=0;map_we<=0;
   case(state)
    IDLE:if(available && !take)begin
     send_info<={recv_info[111:104]|8'h80,8'd0,recv_info[95:0]};
     case(recv_info[111:104])
      9:begin
       take<=1;lengths<=recv_info[20:0];text_ready<=recv_info[23:21];
       if(recv_info[95:64]!=query_id)begin query_id<=recv_info[95:64];snapshot<=current;end
       send_info<={8'h89,7'd0,pending,recv_info[95:64],recv_info[95:64]==query_id?snapshot:current};state<=ACK;
      end
      10:begin
       take<=1;
       if(completed && recv_info[95:64]==job_id)state<=ACK;
       else if(active && recv_info[95:64]==job_id)state<=ACK;
       else if(recv_info[95:64]!=query_id || !current_job)begin send_info[103:96]<=1;state<=ACK;end
       else begin job_id<=recv_info[95:64];active<=1;completed<=0;expected<=0;dirty<=recv_info[63:32];mask<=recv_info[31:0];
        good<=recv_info[96];bad<=recv_info[97];token<=snapshot[56];row_index<=0;slot<=0;row<=0;state<=ACK;end
      end
      11:begin
       if(!active || recv_info[95:64]!=job_id || recv_info[63:32]>6 || !good)begin take<=1;send_info[103:96]<=1;state<=ACK;end
       else if(recv_info[63:32]<expected)begin take<=1;state<=ACK;end
       else if(recv_info[63:32]!=expected)begin take<=1;send_info[103:96]<=1;state<=ACK;end
       else begin read_addr<=0;pixel<=0;pos<=0;state<=PRIME;end
      end
      12:begin
       take<=1;
       if(completed && recv_info[95:64]==job_id)state<=ACK;
       else if(active && recv_info[95:64]==job_id && expected==(good?7:0) && current_job)begin
        response_good<=good;response_mask<=mask;font_bad<=bad;response_toggle<=token;completed_payload<=snapshot[55:0];
        completed<=1;active<=0;state<=ACK;
       end else begin active<=0;send_info[103:96]<=1;state<=ACK;end
      end
      default:begin take<=1;state<=ACK;end
     endcase
    end
    PRIME:begin read_addr<=pos+1;state<=expected==6?MAP:RED;end
    RED:begin rgb[23:16]<=read_byte;read_addr<=pos+2;state<=GREEN;end
    GREEN:begin rgb[15:8]<=read_byte;state<=BLUE;end
    BLUE:begin rgb[7:0]<=read_byte;state<=ROW;end
    ROW:begin
     if(current_job && dirty[slot])begin cache_we<=1;cache_address<=row_index;cache_row<=rgb;end
     row_index<=row_index+1'b1;if(row==23)begin row<=0;slot<=slot+1'b1;end else row<=row+1'b1;
     if(pixel==127)begin expected<=expected+1'b1;take<=1;state<=ACK;end
     else begin pixel<=pixel+1'b1;pos<=pos+3;read_addr<=pos+3;state<=PRIME;end
    end
    MAP:begin
     if(current_job)begin map_we<=1;map_address<={token,pos[5:0]};map_slot<=read_byte[4:0];end
     if(pos==63)begin expected<=7;take<=1;state<=ACK;end
     else begin pos<=pos+1'b1;read_addr<=pos+2;end
    end
    ACK:if(!busy)begin send<=1;state<=WAIT_TX;end
    WAIT_TX:if(!send && !busy)state<=IDLE;
   endcase
  end
 end
endmodule
