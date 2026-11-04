`timescale 1ns/1ps
module lights_r5_motion(
 input wire clk,rst,input wire published_valid,input wire [31:0] published_identity,
 input wire auto_play,play_started,foreground_claim,foreground_present_wait,fault_locked,
 input wire [15:0] available_mask,
 output reg [4:0] query_pic,input wire [31:0] query_identity,
 output reg [3:0] hold_mask,output reg [31:0] hold_generations,output reg hold_changed,input wire [3:0] hold_ack,
 input wire frame_valid,input wire [117:0] frame_pose,
 output wire [117:0] pose,output wire transition_busy,
 output wire normal_advance,output reg presented_pulse,output reg [31:0] presented_identity
);
 reg [31:0] a,b,c,published_seen;
 reg [9:0] scroll,boundary;
 reg [1:0] effect,h_mod;
 reg [4:0] wipe_step;
 reg [3:0] retire_mask;
 reg [31:0] retire_generations;
 reg [4:0] scan_pic,scan_left,scan_reference;
 reg scan_active,roll_commit_wait;
 reg leases_good;
 reg [1:0] lease_settle;
 reg [3:0] next_hold_mask;reg [31:0] next_hold_generations;
 reg frame_accept;
 assign pose={a,b,c,scroll,effect,boundary};
 assign transition_busy=effect==2 || effect==3;
 assign normal_advance=roll_commit_wait;
 wire next_eligible=scan_pic>=1 && scan_pic<=16 && available_mask[scan_pic-1'b1] &&
                    (scan_pic<=3 || scan_pic>=13);
 wire source_match=published_identity[31:16]==a[31:16] && published_identity[2:0]==a[2:0];
 wire returning_normal=effect==3 && c[31] && c[30:29]==0 && a[30:29]!=0;
 wire [4:0] normal_reference=returning_normal ? c[28:24] : a[28:24];
 wire rendered_pose_matches=frame_pose[117:86]==a && frame_pose[53:0]==pose[53:0] &&
      (frame_pose[85:54]==b || (effect==1 && scroll==0) || returning_normal);
 wire publish_event=published_valid && published_identity[31] && published_identity!=published_seen && !transition_busy;
 integer j;
 always @* begin
  next_hold_mask=retire_mask;next_hold_generations=retire_generations;
  for(integer k=0;k<4;k=k+1) begin
   if(a[31] && !a[2] && a[1:0]==k) begin next_hold_mask[k]=1;next_hold_generations[k*8 +: 8]=a[23:16];end
   if(b[31] && !b[2] && b[1:0]==k) begin next_hold_mask[k]=1;next_hold_generations[k*8 +: 8]=b[23:16];end
   if(c[31] && !c[2] && c[1:0]==k) begin next_hold_mask[k]=1;next_hold_generations[k*8 +: 8]=c[23:16];end
  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin hold_mask<=0;hold_generations<=0;hold_changed<=0;end
  else begin
   hold_mask<=next_hold_mask;hold_generations<=next_hold_generations;
   hold_changed<=next_hold_mask!=hold_mask || next_hold_generations!=hold_generations;
  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   a<=0;b<=0;c<=0;published_seen<=0;scroll<=0;boundary<=0;effect<=0;h_mod<=0;wipe_step<=0;
   retire_mask<=0;retire_generations<=0;query_pic<=0;scan_pic<=0;scan_left<=0;scan_reference<=0;
   scan_active<=0;roll_commit_wait<=0;leases_good<=0;lease_settle<=2;presented_pulse<=0;presented_identity<=0;frame_accept<=0;
  end else begin
   presented_pulse<=0;
   frame_accept<=!fault_locked && frame_valid && rendered_pose_matches && leases_good && a[31] && !publish_event;
   if(lease_settle!=0) lease_settle<=lease_settle-1'b1;
   leases_good<=lease_settle==0 && hold_ack==hold_mask;
   if(!fault_locked) begin
    if(!frame_valid && ((effect==1 && scroll==0) || returning_normal) && b[31] && !hold_ack[b[1:0]] &&
       (!query_identity[31] || query_identity[28:16]!=b[28:16] || query_identity[1:0]!=b[1:0])) begin
     b<=0;leases_good<=0;lease_settle<=2;
    end
    if(((a[31] && a[30:29]==0 && !transition_busy) || returning_normal) && !b[31] && !roll_commit_wait) begin
     if(scan_reference!=normal_reference) begin
      scan_reference<=normal_reference;scan_pic<=normal_reference==16 ? 5'd1 : normal_reference+1'b1;
      scan_left<=16;scan_active<=1;query_pic<=0;
     end else if(scan_active) begin
      if(next_eligible) begin query_pic<=scan_pic;scan_active<=0;end
      else if(scan_left<=1) begin scan_active<=0;query_pic<=0;end
      else begin scan_pic<=scan_pic==16 ? 5'd1 : scan_pic+1'b1;scan_left<=scan_left-1'b1;end
     end else if(!frame_valid && query_pic!=0 && query_identity[31] && query_identity[28:24]==query_pic) begin
      b<=query_identity;leases_good<=0;lease_settle<=2;
     end
    end
    if(publish_event && !frame_accept) begin
     published_seen<=published_identity;
     if(roll_commit_wait && source_match) begin
      a<=published_identity;roll_commit_wait<=0;
     end else begin
      retire_mask<=hold_mask & hold_ack;retire_generations<=hold_generations;
      leases_good<=0;lease_settle<=2;roll_commit_wait<=0;
      if(!a[31] || a[30:29]==published_identity[30:29] && a[30:29]!=2) begin
       a<=published_identity;b<=0;c<=0;scroll<=0;effect<=published_identity[30:29]==0 ? 1:0;
       boundary<=0;wipe_step<=0;scan_reference<=0;scan_active<=0;query_pic<=0;
      end else if(a[30:29]==2 && published_identity[30:29]==2) begin
       b<=published_identity;c<=0;scroll<=0;effect<=2;boundary<=613;wipe_step<=1;h_mod<=0;
      end else begin
       c<=published_identity;effect<=3;wipe_step<=1;
       boundary<=published_identity[30:29]>a[30:29] ? 10'd460 : 10'd532;
      end
     end
    end else if(frame_accept) begin
     retire_mask<=0;
     if(effect==0 || (effect==1 && scroll==0)) begin presented_identity<=a;presented_pulse<=1;end
     else if(transition_busy && wipe_step==24) begin
      presented_identity<=effect==2 ? b:c;presented_pulse<=1;
     end
     if(transition_busy) begin
      if(wipe_step==24) begin
       a<=effect==2 ? b:c;
       b<=returning_normal ? b:32'd0;c<=0;
       scroll<=returning_normal && b[31] && auto_play && play_started ? 10'd2:10'd0;
       boundary<=0;
       effect<=(effect==2 ? b[30:29] : c[30:29])==0 ? 1:0;wipe_step<=0;
       if(!returning_normal) begin scan_reference<=0;scan_active<=0;query_pic<=0;end
      end else begin
       wipe_step<=wipe_step+1'b1;
       if(effect==2) begin
        boundary<=boundary-(h_mod==1 ? 10'd26:10'd27);
        h_mod<=h_mod==2 ? 2'd0:h_mod+1'b1;
       end else if(boundary[9]) boundary<=boundary+10'd20;
       else boundary<=boundary-10'd20;
      end
     end else if(effect==1 && auto_play && play_started && (!foreground_claim || foreground_present_wait) && b[31] && !roll_commit_wait) begin
      if(scroll==646) begin
       retire_mask<=hold_mask & hold_ack;retire_generations<=hold_generations;
       a<=b[28:24]==a[28:24] ? a:b;b<=0;scroll<=0;leases_good<=0;lease_settle<=2;
       scan_reference<=0;scan_active<=0;query_pic<=0;
       if(b[28:24]!=a[28:24]) roll_commit_wait<=1;
      end else scroll<=scroll+10'd2;
     end
    end
   end
  end
 end
endmodule
