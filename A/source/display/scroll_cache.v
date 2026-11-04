`timescale 1ns/1ps
module scroll_cache #(parameter HOLD_CYCLES=100000000)(
 input wire clk,rst,published_valid,input wire [31:0] published_identity,
 input wire cache_commit,input wire [31:0] cache_identity,
 input wire reserve,input wire [31:0] reserve_identity,
 input wire frame_valid,input wire [117:0] frame_pose,
 input wire auto_play,manual_event,input wire [1:0] requested_mode,
 input wire [15:0] available_mask,
 output reg allocate_ready,output reg [1:0] allocate_bank,
 output wire [117:0] pose,output wire [31:0] primary_identity,
 output wire primary_valid,output reg [4:0] prefetch_pic,
 input wire [1:0] lookup_mode,input wire [4:0] lookup_pic,
 output reg [31:0] lookup_identity,
 input wire fast_lookup_enable,input wire [1:0] fast_lookup_mode,input wire [4:0] fast_lookup_pic,
 output reg [31:0] fast_lookup_identity,input wire [3:0] extra_held_banks,input wire [1:0] normal_style,output reg [4:0] prefetch_reply);
 reg [31:0] a,b,c,seen;reg [9:0] offset;reg frozen,accept,vertical;
 reg [4:0] wipe_step;reg [9:0] boundary;reg [1:0] h_mod;
 reg [31:0] tags[0:3];reg [3:0] retire;
 reg [1:0] settle;reg [4:0] next1,next2,next3,ref1,ref2;reg [15:0] mask1,mask2,mask3;
 reg [31:0] source1,source2;reg [3:0] held_banks;
 reg [31:0] lookup_candidate,fast_candidate;
 reg [4:0] previous_pic,explain_previous;reg previous_cached;
 reg [4:0] explain_next;reg explain_cached;
 localparam HOLD_BITS=HOLD_CYCLES>1?$clog2(HOLD_CYCLES):1;
 reg pace_half;
 reg [HOLD_BITS-1:0] hold_count;reg hold_armed,hold_done;reg [1:0] style_d;
 wire lookahead_enabled=requested_mode==0 && auto_play && !manual_event && !frozen;
 wire continuous_half=normal_style==1 && (normal_style!=style_d || !pace_half);
 wire [1:0] roll_step=continuous_half?2'd1:2'd2;
 wire roll_allowed=normal_style==1 || offset!=0 || (normal_style==0 && hold_done);
 integer k;reg found;
 assign primary_identity=a;assign primary_valid=a[31];
 wire wiping=wipe_step!=0;
 wire same_explain=a[31] && a[30:29]==2 && published_identity[30:29]==2 &&
   ((a[28:24]>=4 && a[28:24]<=6 && published_identity[28:24]>=4 && published_identity[28:24]<=6) ||
    (a[28:24]>=7 && a[28:24]<=9 && published_identity[28:24]>=7 && published_identity[28:24]<=9) ||
    (a[28:24]>=10 && a[28:24]<=12 && published_identity[28:24]>=10 && published_identity[28:24]<=12));
 wire select_page=a[31] && a[30:29]!=published_identity[30:29];
 assign pose={a,b,c,offset,(wiping?(vertical?2'd3:2'd2):a[31] && a[30:29]==0?2'd1:2'd0),boundary};
 wire front=published_valid && published_identity[31] && published_identity!=seen;
 wire neighbors_ready=settle==0 && available_mask!=0 && mask3==available_mask;
 generate for(genvar bank=0;bank<4;bank=bank+1)begin: tag_bank
  always @(posedge clk or posedge rst)begin
   if(rst)tags[bank][31]<=0;
   else begin
    if(reserve && !reserve_identity[2] && reserve_identity[1:0]==bank)tags[bank][31]<=0;
    if(cache_commit)begin
     if((tags[bank][31]?tags[bank][28:24]:5'd0)==cache_identity[28:24])tags[bank][31]<=0;
     if(cache_identity[1:0]==bank)tags[bank][31]<=cache_identity[31];
    end
    if(front && !published_identity[2])begin
     if((tags[bank][31]?tags[bank][28:24]:5'd0)==published_identity[28:24])tags[bank][31]<=0;
     if(published_identity[1:0]==bank)tags[bank][31]<=published_identity[31];
    end
   end
  end
  always @(posedge clk)begin
   if(cache_commit && cache_identity[1:0]==bank)tags[bank][30:0]<=cache_identity[30:0];
   if(front && !published_identity[2] && published_identity[1:0]==bank)tags[bank][30:0]<=published_identity[30:0];
  end
 end endgenerate
 always @*begin
  lookup_candidate=0;fast_candidate=0;
  for(integer j=0;j<4;j=j+1)
   if(!lookup_candidate[31] && tags[j][31] && tags[j][30:29]==lookup_mode && tags[j][28:24]==lookup_pic)
    lookup_candidate=tags[j];
  for(integer j=0;j<4;j=j+1)
   if(!fast_candidate[31] && tags[j][31] && tags[j][30:29]==fast_lookup_mode && tags[j][28:24]==fast_lookup_pic &&
      !(reserve && !reserve_identity[2] && reserve_identity[1:0]==j))fast_candidate=tags[j];
 end
 always @(posedge clk or posedge rst)
  if(rst)begin lookup_identity<=0;fast_lookup_identity<=0;end
  else begin lookup_identity<=lookup_candidate;fast_lookup_identity<=fast_candidate;end
 function [4:0] first_set(input [15:0] mask);
  reg [7:0] half;reg [3:0] quarter;reg [1:0] pair;reg [3:0] index;
  begin
   index=0;
   if(|mask[7:0])half=mask[7:0];else begin half=mask[15:8];index[3]=1;end
   if(|half[3:0])quarter=half[3:0];else begin quarter=half[7:4];index[2]=1;end
   if(|quarter[1:0])pair=quarter[1:0];else begin pair=quarter[3:2];index[1]=1;end
   index[0]=!pair[0];first_set=|mask?{1'b0,index}+5'd1:5'd0;
  end
 endfunction
 function [4:0] successor(input [4:0] p,input [15:0] mask);
  reg [15:0] allowed,later;integer n;
  begin
   allowed=(mask & 16'hf007)!=0?(mask & 16'hf007):mask;
   for(n=1;n<=16;n=n+1)later[n-1]=allowed[n-1] && n>p;
   successor=|later?first_set(later):|allowed?first_set(allowed):p;
  end
 endfunction
 function [4:0] last_set(input [15:0] mask);
  reg [7:0] half;reg [3:0] quarter;reg [1:0] pair;reg [3:0] index;
  begin
   index=0;
   if(|mask[15:8])begin half=mask[15:8];index[3]=1;end else half=mask[7:0];
   if(|half[7:4])begin quarter=half[7:4];index[2]=1;end else quarter=half[3:0];
   if(|quarter[3:2])begin pair=quarter[3:2];index[1]=1;end else pair=quarter[1:0];
   index[0]=pair[1];last_set=|mask?{1'b0,index}+5'd1:5'd0;
  end
 endfunction
 function [4:0] predecessor(input [4:0] p,input [15:0] mask);
  reg [15:0] allowed,earlier;integer n;
  begin
   allowed=(mask & 16'hf007)!=0?(mask & 16'hf007):mask;
   for(n=1;n<=16;n=n+1)earlier[n-1]=allowed[n-1] && n<p;
   predecessor=|earlier?last_set(earlier):|allowed?last_set(allowed):p;
  end
 endfunction
 wire [3:0] next1_hit,next2_hit,next3_hit;
 generate for(genvar slot=0;slot<4;slot=slot+1)begin:presence
  assign next1_hit[slot]=tags[slot][31] && tags[slot][30:29]==0 && tags[slot][28:24]==next1;
  assign next3_hit[slot]=tags[slot][31] && tags[slot][30:29]==0 && tags[slot][28:24]==next3;
  assign next2_hit[slot]=tags[slot][31] && tags[slot][30:29]==0 && tags[slot][28:24]==next2;
 end endgenerate
 wire source1_present=next1==a[28:24] && a[30:29]==0?a[31]:|next1_hit;
 wire source3_present=next3==a[28:24] && a[30:29]==0?a[31]:|next3_hit;
 wire source2_present=next2==a[28:24] && a[30:29]==0?a[31]:|next2_hit;
 always @*begin
  source1=0;source2=0;held_banks=retire | extra_held_banks;explain_cached=0;previous_cached=0;
  if(fast_lookup_enable && fast_candidate[31] && !fast_candidate[2])held_banks[fast_candidate[1:0]]=1;
  if(a[31] && !a[2])held_banks[a[1:0]]=1;
  if(b[31] && !b[2])held_banks[b[1:0]]=1;
  if(c[31] && !c[2])held_banks[c[1:0]]=1;
  for(integer j=0;j<4;j=j+1)if(tags[j][31] && tags[j][30:29]==0)begin
   if(tags[j][28:24]==next1)source1=tags[j];
   if(tags[j][28:24]==next2)source2=tags[j];
   if(a[30:29]==0 && tags[j][28:24]==previous_pic)previous_cached=1;
   if(a[30:29]==0 && (tags[j][28:24]==next1 || (!lookahead_enabled && tags[j][28:24]==previous_pic) ||
      (lookahead_enabled && (tags[j][28:24]==next2 || tags[j][28:24]==next3))))held_banks[j]=1;
  end
  for(integer j=0;j<4;j=j+1)if(tags[j][31] && tags[j][30:29]==2 && tags[j][28:24]==explain_next)begin
   explain_cached=1;
   if(a[31] && a[30:29]==2)held_banks[j]=1;
  end
  for(integer j=0;j<4;j=j+1)if(tags[j][31] && tags[j][30:29]==2 && tags[j][28:24]==explain_previous)begin
   if(a[30:29]==2)previous_cached=1;
   if(a[31] && a[30:29]==2)held_banks[j]=1;
  end
  if(next1==a[28:24] && a[30:29]==0)source1=a;
  if(next2==a[28:24] && a[30:29]==0)source2=a;
  allocate_ready=0;allocate_bank=0;found=0;
  for(integer j=0;j<4;j=j+1)if(!found && !held_banks[j] && !tags[j][31])begin allocate_bank=j;found=1;end
  for(integer j=0;j<4;j=j+1)if(!found && !held_banks[j])begin allocate_bank=j;found=1;end
  allocate_ready=found && settle==0;
  prefetch_pic=0;
  if(primary_valid && a[30:29]==0 && requested_mode==0 && !frozen && !wiping && neighbors_ready)begin
   if(!source1_present)prefetch_pic=next1;
   else if(lookahead_enabled && !source2_present)prefetch_pic=next2;
   else if(lookahead_enabled && !source3_present)prefetch_pic=next3;
   else if(!lookahead_enabled && !previous_cached && previous_pic!=a[28:24])prefetch_pic=previous_pic;
  end
  if(primary_valid && a[30:29]==2 && requested_mode==2 && !wiping && neighbors_ready)begin
   if(explain_next!=0 && !explain_cached)prefetch_pic=explain_next;
   else if(explain_previous!=0 && !previous_cached)prefetch_pic=explain_previous;
  end
 end
 reg reply_normal,reply_explain,reply_need1,reply_previous,reply_need2,reply_need3,reply_en,reply_ep;
 reg [4:0] reply_next1,reply_next2,reply_next3,reply_prev,reply_explain_next,reply_explain_previous;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   reply_normal<=0;reply_explain<=0;reply_need1<=0;reply_previous<=0;reply_need2<=0;reply_need3<=0;reply_en<=0;reply_ep<=0;
   reply_next1<=0;reply_next2<=0;reply_next3<=0;reply_prev<=0;reply_explain_next<=0;reply_explain_previous<=0;
  end else begin
   reply_normal<=primary_valid && a[30:29]==0 && requested_mode==0 && !frozen && !wiping && neighbors_ready;
   reply_explain<=primary_valid && a[30:29]==2 && requested_mode==2 && !wiping && neighbors_ready;
   reply_need1<=!source1_present;reply_previous<=!lookahead_enabled && !previous_cached && previous_pic!=a[28:24];reply_need2<=lookahead_enabled && !source2_present;reply_need3<=lookahead_enabled && !source3_present;
   reply_en<=explain_next!=0 && !explain_cached;reply_ep<=explain_previous!=0 && !previous_cached;
   reply_next1<=next1;reply_next2<=next2;reply_next3<=next3;reply_prev<=previous_pic;reply_explain_next<=explain_next;reply_explain_previous<=explain_previous;
  end
 end
 always @*begin
  prefetch_reply=0;
  if(reply_normal)begin
   if(reply_need1)prefetch_reply=reply_next1;else if(reply_need2)prefetch_reply=reply_next2;else if(reply_need3)prefetch_reply=reply_next3;else if(reply_previous)prefetch_reply=reply_prev;
  end
  if(reply_explain)begin
   if(reply_en)prefetch_reply=reply_explain_next;else if(reply_ep)prefetch_reply=reply_explain_previous;
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   a<=0;b<=0;c<=0;vertical<=0;seen<=0;offset<=0;frozen<=0;accept<=0;retire<=0;settle<=0;next1<=0;next2<=0;next3<=0;ref1<=0;ref2<=0;mask1<=0;mask2<=0;mask3<=0;pace_half<=0;
   hold_count<=0;hold_armed<=0;hold_done<=0;style_d<=0;
   wipe_step<=0;boundary<=0;h_mod<=0;explain_next<=0;explain_previous<=0;previous_pic<=0;
  end else begin
   style_d<=normal_style;
   if(normal_style!=style_d)pace_half<=0;
   if(front || normal_style!=style_d || !a[31] || a[30:29]!=0 || requested_mode!=0 || wiping || offset!=0 || normal_style!=0)begin
    hold_count<=0;hold_armed<=0;hold_done<=0;
   end else if(!hold_armed)begin
    if(frame_valid && frame_pose==pose)begin hold_armed<=1;hold_count<=0;end
   end else if(!hold_done)begin
    if(hold_count==HOLD_CYCLES-1)hold_done<=1;
    else hold_count<=hold_count+1'b1;
   end
   explain_next<=0;explain_previous<=0;previous_pic<=predecessor(a[28:24],available_mask);
   case(a[28:24])
    5:if(available_mask[3])explain_previous<=4;
    6:if(available_mask[4])explain_previous<=5;else if(available_mask[3])explain_previous<=4;
    8:if(available_mask[6])explain_previous<=7;
    9:if(available_mask[7])explain_previous<=8;else if(available_mask[6])explain_previous<=7;
    11:if(available_mask[9])explain_previous<=10;
    12:if(available_mask[10])explain_previous<=11;else if(available_mask[9])explain_previous<=10;
   endcase
   case(a[28:24])
    4:if(available_mask[4])explain_next<=5;else if(available_mask[5])explain_next<=6;
    5:if(available_mask[5])explain_next<=6;
    7:if(available_mask[7])explain_next<=8;else if(available_mask[8])explain_next<=9;
    8:if(available_mask[8])explain_next<=9;
    10:if(available_mask[10])explain_next<=11;else if(available_mask[11])explain_next<=12;
    11:if(available_mask[11])explain_next<=12;
   endcase
   next1<=successor(a[28:24],available_mask);next2<=successor(next1,available_mask);next3<=successor(next2,available_mask);ref1<=a[28:24];ref2<=ref1;mask1<=available_mask;mask2<=mask1;mask3<=mask2;
   accept<=frame_valid && frame_pose==pose && a[31];
   if(settle!=0)settle<=settle-1'b1;
   frozen<=manual_event && a[30:29]==0;
   if(front)begin
    seen<=published_identity;pace_half<=0;
    retire<=retire | (a[31] && !a[2]?4'b1<<a[1:0]:4'd0) | (b[31] && !b[2]?4'b1<<b[1:0]:4'd0);
    frozen<=0;settle<=3;
    if(select_page && !wiping)begin
     c<=published_identity;vertical<=1;wipe_step<=1;boundary<=published_identity[30:29]>a[30:29]?10'd460:10'd532;h_mod<=0;
    end else if(same_explain && !wiping && a[28:24]!=published_identity[28:24])begin
     b<=published_identity;c<=0;offset<=0;vertical<=0;wipe_step<=1;boundary<=613;h_mod<=0;
    end else begin a<=published_identity;b<=0;c<=0;offset<=0;vertical<=0;wipe_step<=0;boundary<=0;h_mod<=0;end
   end else begin
    if(!wiping && !b[31] && a[31] && a[30:29]==0 && neighbors_ready && source1[31])b<=source1;
    if(accept)begin
     retire<=0;
     if(wiping)begin
      if(wipe_step==24)begin
       retire<=(a[2]?4'd0:4'b1<<a[1:0]) | (vertical && b[31] && !b[2]?4'b1<<b[1:0]:4'd0);
       a<=vertical?c:b;b<=0;c<=0;offset<=0;vertical<=0;wipe_step<=0;boundary<=0;settle<=3;
      end else begin
       wipe_step<=wipe_step+1'b1;
       if(vertical)boundary<=boundary[9]?boundary+10'd20:boundary-10'd20;
       else begin boundary<=boundary-(h_mod==1?10'd26:10'd27);h_mod<=h_mod==2?2'd0:h_mod+1'b1;end
      end
     end else if(a[30:29]==0 && b[31] && (auto_play || (normal_style==2 && offset!=0)) && roll_allowed && !frozen && !manual_event && requested_mode==0)begin
      if(normal_style==1)pace_half<=continuous_half;
      if(offset>=(roll_step==1?10'd647:10'd646))begin
       retire<=a[2]?4'd0:4'b1<<a[1:0];a<=b;b<=next2==b[28:24]?b:source2;offset<=0;settle<=3;pace_half<=0;
      end else offset<=offset+roll_step;
     end
    end
   end
  end
 end
endmodule
