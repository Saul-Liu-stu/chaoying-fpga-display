`timescale 1ns/1ps
module wav_sd_arbiter(
 input wire clk,rst,sd_ready,
 input wire net_start,input wire [31:0] net_lba,input wire net_idle,
 output wire net_guard_idle,net_done,input wire [8:0] net_address,
 input wire wav_request,wav_release,input wire [31:0] wav_lba,
 output reg wav_grant,output wire wav_done,input wire [8:0] wav_address,
 input wire guard_idle,guard_done,output reg start,output reg [31:0] lba,
 output wire [8:0] address);
 reg [1:0] owner;reg completed;
 assign net_guard_idle=sd_ready && guard_idle && owner==0 && !wav_request;
 assign net_done=owner==1 && guard_done;
 assign wav_done=owner==2 && guard_done;
 assign address=owner==2?wav_address:net_address;
 always @(posedge clk or posedge rst)begin
  if(rst)begin owner<=0;completed<=0;start<=0;lba<=0;wav_grant<=0;end
  else begin
   start<=0;wav_grant<=0;
   case(owner)
    0:if(sd_ready && guard_idle)begin
     if(net_start)begin owner<=1;completed<=0;lba<=net_lba;start<=1;end
     else if(wav_request)begin owner<=2;completed<=0;lba<=wav_lba;start<=1;wav_grant<=1;end
    end
    1:begin
     if(guard_done)completed<=1;
     if(completed && net_idle && !net_start)begin owner<=0;completed<=0;end
    end
    2:if(wav_release)begin owner<=0;completed<=0;end
   endcase
  end
 end
endmodule
