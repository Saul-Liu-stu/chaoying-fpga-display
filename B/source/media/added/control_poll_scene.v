`timescale 1ns/1ps
module control_poll_scene #(parameter POLL_CYCLES=100000,RETRY_CYCLES=2500000)(
 input wire clk,rst,enable,grant,
 output wire request,transaction_idle,
 output reg send,output reg [111:0] send_info,input wire busy,
 input wire available,input wire [111:0] recv_info,output reg take,
 output reg auto_play,output reg [2:0] navigation,
 input wire [1:0] view_mode,input wire confirm_ready,
 input wire [15:0] available_mask,output reg [4:0] prefetch_pic,rendered_pic,output reg [1:0] rendered_mode,output reg mode_select,controls_ready,input wire navigation_ready,input wire navigation_busy,
 input wire [15:0] health_word,missing_images,input wire spectrum_select,
 output reg [15:0] health_ack,
 input wire [15:0] source_dimension,output reg [4:0] dimension_cursor);
 reg [1:0] state;reg [31:0] poll_id,seen_revision;
 localparam integer TIMER_BITS=$clog2((POLL_CYCLES>RETRY_CYCLES?POLL_CYCLES:RETRY_CYCLES)+1);
 reg [TIMER_BITS-1:0] timer;
 assign request=state!=0;assign transaction_idle=state==0;
 wire reply_good=recv_info[111:104]==8'h88 && recv_info[103:97]==0 &&
   recv_info[95:64]==poll_id && recv_info[19:4]==0 && recv_info[2:0]<=4;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=0;timer<=0;poll_id<=0;seen_revision<=0;send<=0;send_info<=0;take<=0;auto_play<=1;navigation<=0;prefetch_pic<=0;rendered_pic<=0;rendered_mode<=3;mode_select<=0;controls_ready<=0;health_ack<=0;dimension_cursor<=0;end
  else begin
   send<=0;take<=0;navigation<=0;
   case(state)
    0:if(!enable)timer<=0;else if(timer>=POLL_CYCLES-1)begin
     poll_id<=poll_id+1'b1;state<=1;timer<=0;
     send_info<={8'd8,(poll_id[1:0]==3?2'b11:2'b10),(poll_id[1:0]==3?dimension_cursor[0]:poll_id[0]),spectrum_select,navigation_busy,confirm_ready,view_mode,poll_id+32'd1,seen_revision,available_mask,(poll_id[1:0]==3?source_dimension:poll_id[0]?missing_images:health_word)};
    end else timer<=timer+1'b1;
    1:if(grant && !busy)begin send<=1;state<=2;timer<=0;end
    2:begin
     if(timer<RETRY_CYCLES)timer<=timer+1'b1;
     if(available && !take)begin
      take<=1;
      if(reply_good)begin
       if(send_info[103:102]==2'b10 && !send_info[101])health_ack<=send_info[15:0];
       if(send_info[103:102]==2'b11)dimension_cursor<=dimension_cursor+1'b1;
       mode_select<=recv_info[3];controls_ready<=1;auto_play<=recv_info[96];prefetch_pic<=recv_info[31:27];rendered_mode<=recv_info[26:25];rendered_pic<=recv_info[24:20];
       if(recv_info[63:32]!=seen_revision && (recv_info[2:0]==0 || navigation_ready))begin
        seen_revision<=recv_info[63:32];navigation<=recv_info[2:0];
       end
       state<=3;
      end
     end else if(timer>=RETRY_CYCLES)state<=1;
    end
    3:if(!send && !busy)begin state<=0;timer<=0;end
   endcase
  end
 end
endmodule
