`timescale 1ns/1ps
module sector_server #(parameter STALE_CYCLES=150000000)(
 input wire clk,rst,enable,sd_ready,
 output reg send,output reg [111:0] send_info,input wire busy,
 output reg mem_we,output reg [8:0] mem_addr,output reg [7:0] mem_byte,
 input wire available,input wire [111:0] recv_info,output reg take,
 output reg start,output reg [31:0] lba,input wire guard_idle,guard_done,input wire [3:0] guard_fault,
 output wire [8:0] buffer_addr,input wire [7:0] buffer_byte,
 output wire [15:0] status,output reg [31:0] verified,output wire transaction_idle);
 localparam IDLE=0,START=1,WAIT_SD=2,PRIME=3,COPY=4,SEND_DATA=5,WAIT_TX=6,SEND_CONFIRM=7;
 assign transaction_idle=state==IDLE;
 reg [3:0] state;reg [8:0] pos;reg [31:0] crc,cached_crc,xid,cached_xid,cached_lba;
 reg cached,checked,passed,bad_check;reg [27:0] stale;
 assign buffer_addr=(state==COPY)?pos+9'd1:9'd0;
 assign status=guard_fault!=0?16'd7:bad_check?16'd9:!sd_ready?16'd2:
               (passed && stale<STALE_CYCLES)?16'd6:16'd4;
 function [31:0] crc_byte(input [31:0] c,input [7:0] d);
  reg [31:0] t;integer k;
  begin t=c;for(k=0;k<8;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hedb88320:32'd0);crc_byte=t;end
 endfunction
 wire [31:0] next_crc=crc_byte(crc,buffer_byte);
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;pos<=0;crc<=0;cached_crc<=0;xid<=0;cached_xid<=0;cached_lba<=0;
   cached<=0;checked<=0;passed<=0;bad_check<=0;stale<=STALE_CYCLES;verified<=0;
   send<=0;send_info<=0;mem_we<=0;mem_addr<=0;mem_byte<=0;take<=0;start<=0;lba<=0;
  end else begin
   send<=0;mem_we<=0;take<=0;start<=0;
   if(stale<STALE_CYCLES)stale<=stale+1'b1;
   if(guard_fault==0 && !bad_check)case(state)
    IDLE:if(available && !take)begin
     take<=1;
     if(recv_info[111:104]==1 && recv_info[103:96]==0)begin
      xid<=recv_info[95:64];lba<=recv_info[63:32];
      if(!(cached && recv_info[95:64]==cached_xid && recv_info[63:32]==cached_lba))checked<=0;
      cached<=0;state<=START;
     end else if(recv_info[111:104]==3 && cached && recv_info[95:64]==cached_xid && recv_info[63:32]==cached_lba)begin
      if(recv_info[31:0]!=cached_crc)bad_check<=1;
      else begin
       if(!checked)verified<=verified+1'b1;
       checked<=1;stale<=0;if(recv_info[103:96]==1)passed<=1;
       state<=SEND_CONFIRM;
      end
     end
    end
    START:if(sd_ready && guard_idle)begin start<=1;state<=WAIT_SD;end
    WAIT_SD:if(guard_done)begin cached<=1;cached_xid<=xid;cached_lba<=lba;state<=PRIME;end
    PRIME:if(!busy)begin pos<=0;crc<=32'hffffffff;state<=COPY;end
    COPY:begin
     mem_we<=1;mem_addr<=pos;mem_byte<=buffer_byte;crc<=next_crc;
     if(pos==511)begin cached_crc<=~next_crc;state<=SEND_DATA;end else pos<=pos+1'b1;
    end
    SEND_DATA:if(!busy && enable)begin send_info<={8'd2,8'd0,xid,lba,cached_crc};send<=1;state<=WAIT_TX;end
    SEND_CONFIRM:if(!busy && enable)begin send_info<={8'd4,8'd0,cached_xid,cached_lba,cached_crc};send<=1;state<=WAIT_TX;end
    WAIT_TX:if(!send && !busy)state<=IDLE;
   endcase
  end
 end
endmodule

