`timescale 1ns/1ps
module link_mdio #(parameter HALF_PERIOD=25)(
 input wire clk,rst,start,rd,input wire [4:0] phy,regnum,input wire [15:0] wrdata,
 inout wire mdio,output reg mdc,output reg busy,done,ack_error,output reg [15:0] result);
 reg [7:0] divider;reg [5:0] bitno;reg [63:0] shift;reg is_read;
 reg mdio_meta,mdio_sync;
 wire driving=busy && (!is_read || bitno<46);
 assign mdio=driving && !shift[63] ? 1'b0 : 1'bz;
 always @(posedge clk or posedge rst)begin
  if(rst)begin mdio_meta<=1;mdio_sync<=1;end else begin mdio_meta<=mdio;mdio_sync<=mdio_meta;end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin divider<=0;bitno<=0;shift<=~64'd0;is_read<=0;mdc<=0;busy<=0;done<=0;ack_error<=0;result<=0;end
  else begin done<=0;
   if(!busy)begin mdc<=0;divider<=0;
    if(start)begin busy<=1;bitno<=0;is_read<=rd;result<=0;ack_error<=0;
     shift<={32'hffffffff,2'b01,(rd?2'b10:2'b01),phy,regnum,2'b10,wrdata};end
   end else if(divider==HALF_PERIOD-1)begin divider<=0;mdc<=!mdc;
    if(!mdc)begin
     if(is_read && bitno==47)ack_error<=mdio_sync;
     if(is_read && bitno>=48)result<={result[14:0],mdio_sync};
    end else if(bitno==63)begin busy<=0;done<=1;end
    else begin bitno<=bitno+1'b1;shift<={shift[62:0],1'b1};end
   end else divider<=divider+1'b1;
  end
 end
endmodule

module link_phy_setup #(parameter BOARD_ID=1,parameter POWER_WAIT=10000000,parameter POLL_WAIT=5000000,parameter RESET_WAIT=50000,parameter MDIO_HALF=25)(
 input wire clk,rst,inout wire mdio,output wire mdc,
 output reg ready,link_up,output reg [15:0] fault,output reg [15:0] phy_status);
 reg start,rd,waiting;reg [4:0] regnum;reg [15:0] wrdata,delay_word;
 wire busy,done,ack_error;wire [15:0] result;
 reg [3:0] step;reg [23:0] wait_count;reg [7:0] reset_tries;
 link_mdio #(.HALF_PERIOD(MDIO_HALF)) bus(clk,rst,start,rd,5'd1,regnum,wrdata,mdio,mdc,busy,done,ack_error,result);
 always @(posedge clk or posedge rst)begin
  if(rst)begin start<=0;rd<=0;waiting<=0;regnum<=0;wrdata<=0;delay_word<=0;
   step<=0;wait_count<=POWER_WAIT;reset_tries<=0;ready<=0;link_up<=0;fault<=0;phy_status<=0;end
  else begin start<=0;
   if(wait_count!=0)wait_count<=wait_count-1'b1;
   else if(!waiting && !busy && fault==0)begin
    start<=1;waiting<=1;rd<=0;
    case(step)
     0:begin regnum<=0;wrdata<=16'h9140;end
     1:begin regnum<=0;rd<=1;end
     2:begin regnum<=2;rd<=1;end
     3:begin regnum<=3;rd<=1;end
     4:begin regnum<=31;wrdata<=7;end
     5:begin regnum<=30;wrdata<=16'h00a4;end
     6:begin regnum<=28;rd<=1;end
     7:begin regnum<=28;wrdata<=delay_word|16'h3800;end
     8:begin regnum<=28;rd<=1;end
     9:begin regnum<=31;wrdata<=0;end
     10:begin regnum<=4;wrdata<=16'h0001;end
     11:begin regnum<=9;wrdata<=(BOARD_ID==1)?16'h1a00:16'h1200;end
     12:begin regnum<=0;wrdata<=16'h1340;end // External 1000/full AN; explicitly clear local loopback
     13:begin regnum<=0;rd<=1;end // Verify local loopback disabled before enabling traffic
     default:begin regnum<=17;rd<=1;end
    endcase
   end
   if(waiting && done)begin
    waiting<=0;
    if(ack_error)begin fault<=16'he001;link_up<=0;end
    else case(step)
     0:begin step<=1;wait_count<=RESET_WAIT;end
     1:if(result[15])begin wait_count<=RESET_WAIT;reset_tries<=reset_tries+1'b1;if(reset_tries==200)fault<=16'he004;end else step<=2;
     2:if(result!=16'h001c)fault<=16'he002;else step<=3;
     3:if(result[15:4]!=12'hc91)fault<=16'he003;else step<=4;
     6:begin delay_word<=result;step<=7;end
     8:if((result&16'h3800)!=16'h3800)fault<=16'he005;else step<=9;
     12:begin step<=13;wait_count<=POLL_WAIT;end
     13:begin
      if((result & 16'hfd40)==16'h1140)begin ready<=1;link_up<=0;step<=14;end
      else begin fault<=16'he006;ready<=0;link_up<=0;end
     end
     14:begin
      phy_status<=result;wait_count<=POLL_WAIT;
      link_up<=result[15:14]==2'b10 && result[13] && result[11] && result[10];
     end
     default:step<=step+1'b1;
    endcase
   end
  end
 end
endmodule
