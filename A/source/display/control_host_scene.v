`timescale 1ns/1ps
module control_host_scene(
 input wire clk,rst,next_press,prev_press,short_press,chord_press,confirm_short,
 input wire available,input wire [111:0] recv_info,output reg take,
 output reg send,output reg [111:0] send_info,input wire busy,
 output wire transaction_idle,select_confirm_ready,
 input wire [4:0] load_pic,input wire [31:0] primary_identity,
 output wire normal_auto,output wire [1:0] remote_mode,output reg [15:0] normal_mask,input wire mode_select,output wire navigation_pending,output reg [1:0] normal_style,
 output reg dimension_update,output reg [4:0] dimension_picture,output reg [21:0] dimension_size);
 reg [10:0] pending_width;reg [4:0] pending_picture;reg pending_dimension;
 wire dimension_page=recv_info[103:102]==2'b11;
 wire dimension_range=recv_info[15:11]>=1 && recv_info[15:11]<=16 && recv_info[10:0]>=1 && recv_info[10:0]<=1920;
 reg [1:0] state,reported_mode;reg reported_ready;
 reg mode_select_d,remote_navigation_busy;
 reg [31:0] revision,acknowledged;reg [2:0] navigation;wire auto_play=normal_style!=2;
 wire [2:0] gesture;
 reg [4:0] queue[0:7];reg [2:0] head,tail;reg [3:0] queued;
 wire mode_change=mode_select_d!=mode_select;
 wire push=gesture!=0 && queued<8 && !mode_change;
 wire pop=queued!=0 && revision==acknowledged && !mode_change;
 assign navigation_pending=queued!=0 || revision!=acknowledged || remote_navigation_busy;
 wire locked=navigation==4 && revision!=acknowledged;
 wire controls_aligned=mode_select?(reported_mode!=0):(reported_mode==0);
 assign gesture=!controls_aligned?3'd0:chord_press?3'd4:next_press?3'd1:prev_press?3'd2:
  (short_press && reported_mode!=0 && (reported_mode!=1 || confirm_short))?3'd3:3'd0;
 assign normal_auto=auto_play;assign remote_mode=reported_mode;
 assign transaction_idle=state==0;
 assign select_confirm_ready=reported_mode==1 && reported_ready;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=0;revision<=0;acknowledged<=0;navigation<=0;normal_style<=2'd2;
   head<=0;tail<=0;queued<=0;mode_select_d<=0;remote_navigation_busy<=0;normal_mask<=0;reported_mode<=0;reported_ready<=0;take<=0;send<=0;send_info<=0;
   pending_width<=0;pending_picture<=0;pending_dimension<=0;dimension_update<=0;dimension_picture<=0;dimension_size<=0;end
  else begin
   take<=0;send<=0;dimension_update<=0;
   if(short_press && controls_aligned && reported_mode==0 && !locked)normal_style<=normal_style==2?2'd0:normal_style+1'b1;
   mode_select_d<=mode_select;
   if(chord_press || (mode_select_d && !mode_select))normal_style<=0;
   if(mode_change)begin head<=0;tail<=0;queued<=0;revision<=revision+1'b1;navigation<=0;end
   else begin
    case({push,pop})2'b10:queued<=queued+1'b1;2'b01:queued<=queued-1'b1;default:;endcase
    if(push)begin queue[tail]<={mode_select?2'd1:2'd0,gesture};tail<=tail+1'b1;end
    if(pop)begin
     head<=head+1'b1;
     if(queue[head][4:3]==(mode_select?2'd1:2'd0))begin revision<=revision+1'b1;navigation<=queue[head][2:0];end
    end
   end
   case(state)
    0:if(available && !take)begin
     if(dimension_page)begin
      if(!recv_info[101])begin
       pending_width<=recv_info[10:0];pending_picture<=recv_info[15:11];pending_dimension<=dimension_range;
      end else if(dimension_range && pending_dimension && pending_picture==recv_info[15:11] && (pending_width<=1080 || recv_info[10:0]<=1080))begin
       dimension_update<=1;dimension_picture<=pending_picture;dimension_size<={pending_width,recv_info[10:0]};
      end
     end
     take<=1;remote_navigation_busy<=recv_info[99];normal_mask<=recv_info[31:16];reported_mode<=recv_info[97:96];reported_ready<=recv_info[98];acknowledged<=recv_info[63:32];
     send_info<={8'h88,7'd0,auto_play,recv_info[95:64],revision,load_pic,(primary_identity[31]?primary_identity[30:29]:2'd3),primary_identity[28:24],16'd0,mode_select,navigation};state<=1;
    end
    1:if(!busy)begin send<=1;state<=2;end
    2:if(!send && !busy)state<=0;
   endcase
  end
 end
endmodule
