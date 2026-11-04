`timescale 1ns/1ps
module sector_wire_avpipe #(parameter [7:0] BOARD_ID=1)(
 input wire app_clk,app_rst,tx_clk,tx_rst,rx_clk,rx_rst,
 input wire tx_enable,rx_enable,
 input wire [15:0] tx_epoch,rx_epoch,
 output reg control_available,output reg [111:0] control_info,input wire control_take,
 input wire send,input wire [111:0] send_info,output wire busy,
 input wire mem_we,input wire [8:0] mem_addr,input wire [7:0] mem_byte,
 output wire available,output reg [111:0] recv_info,input wire take,
 input wire [8:0] read_addr,output reg [7:0] read_byte,
 output reg [7:0] tx_byte,output reg tx_valid,
 input wire [7:0] rx_byte,input wire rx_valid,rx_error);

 reg [7:0] rx_data_q;
 reg rx_valid_q,rx_error_q;
 always @(posedge rx_clk or posedge rx_rst)begin
  if(rx_rst)begin rx_data_q<=0;rx_valid_q<=0;rx_error_q<=0;end
  else begin rx_data_q<=rx_byte;rx_valid_q<=rx_valid;rx_error_q<=rx_error;end
 end
 localparam [7:0] PEER=(BOARD_ID==1)?2:1;
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [7:0] send_ram[0:511];
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [7:0] recv_ram[0:511];
 reg send_request,send_ack,recv_request,recv_ack;
 reg [111:0] send_hold,recv_hold;
 reg control_request,control_ack;reg [111:0] control_hold;
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg [2:0] control_req_sync,control_ack_sync;
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg [2:0] send_ack_sync,send_req_sync,recv_ack_sync,recv_req_sync;
 assign busy=send_request!=send_ack_sync[2];
 reg delivered;
 assign available=delivered;
 always @(posedge app_clk) begin
  if(mem_we && !busy)send_ram[mem_addr]<=mem_byte;
  read_byte<=recv_ram[read_addr];
 end
 always @(posedge app_clk or posedge app_rst)begin
  if(app_rst)begin send_request<=0;send_hold<=0;send_ack_sync<=0;recv_req_sync<=0;recv_ack<=0;recv_info<=0;delivered<=0;
   control_req_sync<=0;control_ack<=0;control_available<=0;control_info<=0;end
  else begin
   send_ack_sync<={send_ack_sync[1:0],send_ack};
   recv_req_sync<={recv_req_sync[1:0],recv_request};
   control_req_sync<={control_req_sync[1:0],control_request};
   if(!control_available && control_req_sync[2]!=control_ack)begin control_info<=control_hold;control_available<=1;end
   if(control_available && control_take)begin control_ack<=control_req_sync[2];control_available<=0;end
   if(send && !busy)begin send_hold<=send_info;send_request<=!send_request;end
   if(!delivered && recv_req_sync[2]!=recv_ack)begin recv_info<=recv_hold;delivered<=1;end
   if(take && available)begin recv_ack<=recv_req_sync[2];delivered<=0;end
  end
 end
 function [31:0] crc_byte(input [31:0] c,input [7:0] d);
  reg [31:0] t;integer k;
  begin t=c;for(k=0;k<8;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hedb88320:32'd0);crc_byte=t;end
 endfunction
 reg [1:0] tx_state;reg [9:0] tx_pos;reg [3:0] gap;
 reg [111:0] tx_info;reg [31:0] tx_crc;reg [7:0] ram_q;
 wire [8:0] ram_addr=(tx_pos>=34 && tx_pos<=545)?tx_pos-10'd34:9'd0;
 wire ram_read=tx_state==2 && tx_pos>=34 && tx_pos<=545;
 always @(posedge tx_clk)if(ram_read)ram_q<=send_ram[ram_addr];
 function [7:0] header_byte(input [9:0] n,input [111:0] m,input [7:0] payload);
  begin case(n)
   0,6:header_byte=8'h02;1,7:header_byte=8'h4c;2,8:header_byte=8'h49;
   3,9:header_byte=8'h47;4,10:header_byte=8'h48;5:header_byte=PEER;11:header_byte=BOARD_ID;
   12:header_byte=8'h88;13:header_byte=8'hb6;
   14:header_byte=8'h4c;15:header_byte=8'h53;16:header_byte=8'h44;17:header_byte=8'h31;
   18:header_byte=1;19:header_byte=m[111:104];20:header_byte=m[103:96];
   21:header_byte=tx_epoch[15:8];22:header_byte=tx_epoch[7:0];
   23:header_byte=m[95:88];24:header_byte=m[87:80];25:header_byte=m[79:72];26:header_byte=m[71:64];
   27:header_byte=m[63:56];28:header_byte=m[55:48];29:header_byte=m[47:40];30:header_byte=m[39:32];
   31:header_byte=m[31:24];32:header_byte=m[23:16];33:header_byte=m[15:8];34:header_byte=m[7:0];
   default:header_byte=payload;
  endcase end
 endfunction
 wire control_frame=tx_info[111:104]==8'd17 || tx_info[111:104]==8'h91;
 wire [7:0] body=header_byte(tx_pos,tx_info,control_frame?8'd0:ram_q);
 reg crc_body_valid;
 wire [31:0] crc_step=crc_byte(tx_crc,tx_byte);
 always @(posedge tx_clk or posedge tx_rst)begin
  if(tx_rst)begin send_req_sync<=0;send_ack<=0;tx_state<=0;tx_pos<=0;gap<=0;tx_crc<=0;tx_info<=0;tx_byte<=0;tx_valid<=0;crc_body_valid<=0;end
  else begin
   send_req_sync<={send_req_sync[1:0],send_request};tx_byte<=0;tx_valid<=0;
   crc_body_valid<=tx_state==2;
   if(crc_body_valid)tx_crc<=crc_step;
   case(tx_state)
    0:if(gap!=0)gap<=gap-1'b1;
      else if(tx_enable && send_req_sync[2]!=send_ack)begin tx_info<=send_hold;tx_state<=1;tx_pos<=0;end
    1:begin
     tx_valid<=1;tx_byte<=(tx_pos==7)?8'hd5:8'h55;
     if(tx_pos==7)begin tx_state<=2;tx_pos<=0;tx_crc<=32'hffffffff;end else tx_pos<=tx_pos+1'b1;
    end
    2:begin
     tx_valid<=1;tx_byte<=body;
     if(tx_pos==546)begin tx_state<=3;tx_pos<=0;end else tx_pos<=tx_pos+1'b1;
    end
    3:begin
     tx_valid<=1;
     case(tx_pos[1:0])0:tx_byte<=~crc_step[7:0];1:tx_byte<=~tx_crc[15:8];2:tx_byte<=~tx_crc[23:16];3:tx_byte<=~tx_crc[31:24];endcase
     if(tx_pos==3)begin tx_state<=0;gap<=12;send_ack<=send_req_sync[2];end else tx_pos<=tx_pos+1'b1;
    end
   endcase
  end
 end
 reg active,frame_bad,owns_slot;reg commit_pending,epoch_bad;reg [3:0] preamble;reg [9:0] rx_pos;
 reg [31:0] rx_crc;reg [15:0] work_epoch;reg [111:0] work_info;
 function header_ok(input [9:0] n,input [7:0] d);
  begin case(n)
   0,6:header_ok=d==8'h02;1,7:header_ok=d==8'h4c;2,8:header_ok=d==8'h49;
   3,9:header_ok=d==8'h47;4,10:header_ok=d==8'h48;5:header_ok=d==BOARD_ID;11:header_ok=d==PEER;
   12:header_ok=d==8'h88;13:header_ok=d==8'hb6;
   14:header_ok=d==8'h4c;15:header_ok=d==8'h53;16:header_ok=d==8'h44;17:header_ok=d==8'h31;
   18:header_ok=d==1;
   default:header_ok=1;
  endcase end
 endfunction
 always @(posedge rx_clk)begin
  if(active && owns_slot && rx_valid_q && rx_pos>=35 && rx_pos<=546)recv_ram[rx_pos-10'd35]<=rx_data_q;
 end
 always @(posedge rx_clk or posedge rx_rst)begin
  if(rx_rst)begin recv_ack_sync<=0;recv_request<=0;recv_hold<=0;active<=0;frame_bad<=0;owns_slot<=0;commit_pending<=0;preamble<=0;rx_pos<=0;rx_crc<=0;work_info<=0;
   epoch_bad<=0;work_epoch<=0;
   control_request<=0;control_hold<=0;control_ack_sync<=0;end
  else begin
   recv_ack_sync<={recv_ack_sync[1:0],recv_ack};
   control_ack_sync<={control_ack_sync[1:0],control_ack};
   commit_pending<=0;
   if(commit_pending)begin recv_hold<=work_info;recv_request<=!recv_request;end
   if(!rx_enable)begin active<=0;preamble<=0;end
   else if(!active)begin
    if(!rx_valid_q || rx_error_q)preamble<=0;
    else if(rx_data_q==8'h55)begin if(preamble<7)preamble<=preamble+1'b1;end
    else begin
     preamble<=0;
     if(rx_data_q==8'hd5 && preamble!=0)begin
      active<=1;frame_bad<=0;epoch_bad<=0;work_epoch<=0;rx_pos<=0;rx_crc<=32'hffffffff;work_info<=0;
      owns_slot<=recv_request==recv_ack_sync[2];
     end
    end
   end else if(rx_valid_q)begin
    rx_crc<=crc_byte(rx_crc,rx_data_q);frame_bad<=frame_bad || rx_error_q || !header_ok(rx_pos,rx_data_q);
    if(rx_pos<1023)rx_pos<=rx_pos+1'b1;else frame_bad<=1;
    case(rx_pos)
     19:work_info[111:104]<=rx_data_q;20:work_info[103:96]<=rx_data_q;
     21,22:begin
       work_epoch<={work_epoch[7:0],rx_data_q};
       if(work_info[111:104]!=8'd17 && work_info[111:104]!=8'h91)case(rx_pos)
        21:if(rx_data_q!=rx_epoch[15:8])epoch_bad<=1;
        22:if(rx_data_q!=rx_epoch[7:0])epoch_bad<=1;
       endcase
     end
     23,24,25,26:work_info[95:64]<={work_info[87:64],rx_data_q};
     27,28,29,30:work_info[63:32]<={work_info[55:32],rx_data_q};
     31,32,33,34:work_info[31:0]<={work_info[23:0],rx_data_q};
    endcase
   end else begin
    active<=0;preamble<=0;
    commit_pending<=owns_slot && !frame_bad && !epoch_bad && work_info[111:104]!=8'd17 && work_info[111:104]!=8'h91 && rx_pos==551 && rx_crc==32'hdebb20e3;
    if(!frame_bad && (work_info[111:104]==8'd17 || work_info[111:104]==8'h91) &&
       rx_pos==551 && rx_crc==32'hdebb20e3 && control_request==control_ack_sync[2])begin
      control_hold<=work_info;control_request<=!control_request;
    end
   end
  end
 end
endmodule
