`timescale 1ns/1ps
module cached_show_sender #(parameter RETRY_CYCLES=250000)(
 input wire clk,rst,start,input wire [1:0] mode,input wire [4:0] picture,input wire sync_only,
 output wire idle,request,waiting,input wire grant,
 output reg send,output reg [111:0] send_info,input wire busy,
 input wire available,input wire [111:0] recv_info,output reg take,done,hit);
 reg [1:0] state;reg [31:0] xid;reg [21:0] timer;
 assign idle=state==0;assign request=state==1;assign waiting=state==2;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=0;xid<=0;timer<=0;send<=0;send_info<=0;take<=0;done<=0;hit<=0;end
  else begin
   send<=0;take<=0;done<=0;
   case(state)
    0:if(start)begin xid<=xid+1'b1;send_info<={8'd15,sync_only,mode,picture,xid+32'd1,64'd0};hit<=0;state<=1;end
    1:if(grant && !busy)begin send<=1;timer<=0;state<=2;end
    2:begin
     if(timer<RETRY_CYCLES)timer<=timer+1'b1;
     if(available && !take)begin
      take<=1;
      if(recv_info[111:104]==8'h8f && recv_info[103:97]==0 && recv_info[95:64]==xid && recv_info[63:0]==0)begin hit<=recv_info[96];state<=3;end
     end else if(timer>=RETRY_CYCLES)state<=1;
    end
    3:begin done<=1;state<=0;end
   endcase
  end
 end
endmodule
