`timescale 1ns/1ps
module caption_client #(parameter POLL_CYCLES=1000000,RETRY_CYCLES=2500000)(
 input wire clk,rst,enable,grant,output wire request,idle,
 output reg send,output reg [111:0] send_info,input wire busy,
 output reg mem_we,output reg [8:0] mem_addr,output reg [7:0] mem_byte,
 input wire available,input wire [111:0] recv_info,output reg take,
 input wire [20:0] lengths,input wire [2:0] text_ready,
 output reg cache_request,cache_cancel,output reg [55:0] cache_payload,output wire cache_enable,
 input wire response_toggle,response_good,font_bad,input wire [31:0] response_mask,
 input wire cache_we,input wire [9:0] cache_address,input wire [23:0] cache_row,
 input wire map_we,input wire [6:0] map_address,input wire [4:0] map_slot,
 output reg [31:0] prepared_serial,output reg [55:0] prepared_payload);
 localparam IDLE=0,SEND=1,WAIT_ACK=2,CANCEL=3,FONT_WAIT=4,START=5,PRIME=6,FILL=7,DATA=8,COMMIT=9,DRAIN=10;
 reg [3:0] state;reg [31:0] timer,xid,dirty,upload_dirty,mask;reg [7:0] kind;reg good,bad;
 reg [2:0] packet,phase,delay;reg [8:0] pos;reg [9:0] row_addr;reg [23:0] row_q;reg [4:0] map_q;
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [23:0] rows[0:1023];
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [4:0] maps[0:127];
 assign cache_enable=state==IDLE || state==SEND && kind==9 || state==WAIT_ACK && kind==9 || state==CANCEL || state==FONT_WAIT || state==DRAIN;
 assign request=state==SEND || state==WAIT_ACK || state==START || state==PRIME || state==FILL || state==DATA || state==COMMIT;
 assign idle=state==IDLE;
 wire [6:0] map_index=cache_payload[45:39];
 wire map_valid=pos<64 && pos>=map_index && pos<cache_payload[38:32] && pos<map_index+8'd24;
 always @(posedge clk)begin
  if(cache_we && cache_enable)rows[cache_address]<=cache_row;
  if(map_we && cache_enable)maps[map_address]<=map_slot;
  if(state==PRIME || state==FILL)begin
   row_q<=rows[row_addr];map_q<=maps[{cache_request,pos[5:0]}];
  end
 end
 wire ack_id=recv_info[111:104]==(kind|8'h80) && recv_info[95:64]==xid;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=0;timer<=0;xid<=0;dirty<=0;upload_dirty<=0;mask<=0;kind<=0;good<=0;bad<=0;packet<=0;phase<=0;delay<=0;pos<=0;row_addr<=0;
   send<=0;send_info<=0;mem_we<=0;mem_addr<=0;mem_byte<=0;take<=0;cache_request<=0;cache_cancel<=0;cache_payload<=0;prepared_serial<=0;prepared_payload<=0;end
  else begin
   send<=0;mem_we<=0;take<=0;
   if(cache_we && cache_enable)dirty[cache_address/24]<=1;
   case(state)
    IDLE:if(!enable)timer<=0;else if(timer>=POLL_CYCLES-1)begin
     xid<=xid+1'b1;kind<=9;send_info<={8'd9,8'd0,xid+32'd1,40'd0,text_ready,lengths};timer<=0;state<=SEND;
    end else timer<=timer+1'b1;
    SEND:if(grant && !busy)begin send<=1;timer<=0;state<=WAIT_ACK;end
    WAIT_ACK:begin
     if(timer<RETRY_CYCLES)timer<=timer+1'b1;
     if(available && !take)begin
      take<=1;
      if(ack_id && (kind==9 || recv_info[63:0]==send_info[63:0]))begin
       if(kind==9)begin
        if(recv_info[96])begin cache_payload<=recv_info[55:0];cache_cancel<=recv_info[57];delay<=6;state<=CANCEL;end
        else state<=DRAIN;
       end else if(recv_info[103:96]!=0)state<=DRAIN;
       else if(kind==10)begin packet<=0;row_addr<=0;pos<=0;phase<=0;delay<=2;state<=good?PRIME:COMMIT;end
       else if(kind==11)begin
        if(packet==6)state<=COMMIT;else begin packet<=packet+1'b1;pos<=0;phase<=0;delay<=2;state<=PRIME;end
       end else begin
        if(good && !bad)begin prepared_serial<=prepared_serial+1'b1;prepared_payload<=cache_payload;end
        dirty<=dirty & ~upload_dirty;state<=DRAIN;
       end
      end
     end else if(timer>=RETRY_CYCLES)state<=SEND;
    end
    CANCEL:if(delay==0)begin cache_request<=!cache_request;state<=FONT_WAIT;end else delay<=delay-1'b1;
    FONT_WAIT:if(response_toggle==cache_request)begin good<=response_good;bad<=font_bad;mask<=response_mask;upload_dirty<=dirty;state<=START;end
    START:if(grant && !busy)begin kind<=10;send_info<={8'd10,6'd0,bad,good,xid,upload_dirty,mask};state<=SEND;end
    PRIME:if(delay!=0)delay<=delay-1'b1;else state<=FILL;
    FILL:if(grant && !busy)begin
     mem_we<=1;mem_addr<=pos;
     if(packet==6)mem_byte<=map_valid?{3'd0,map_q}:8'd0;
     else if(pos<384 && upload_dirty[row_addr/24])case(phase)
      0:mem_byte<=row_q[23:16];1:mem_byte<=row_q[15:8];default:mem_byte<=row_q[7:0];endcase
     else mem_byte<=0;
     if(pos==511)state<=DATA;
     else begin
      pos<=pos+1'b1;
      if(packet==6)begin delay<=1;state<=PRIME;end
      else if(pos<384)begin
       if(phase==2)begin phase<=0;row_addr<=row_addr+1'b1;delay<=1;state<=PRIME;end else phase<=phase+1'b1;
      end
     end
    end
    DATA:if(grant && !busy)begin kind<=11;send_info<={8'd11,8'd0,xid,29'd0,packet,32'd0};state<=SEND;end
    COMMIT:if(grant && !busy)begin kind<=12;send_info<={8'd12,8'd0,xid,64'd0};state<=SEND;end
    DRAIN:if(!busy && !send)begin state<=IDLE;timer<=0;end
   endcase
  end
 end
endmodule
