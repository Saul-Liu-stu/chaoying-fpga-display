`timescale 1ns/1ps
module lights_settings_control #(
 parameter integer CLK_FREQ_HZ=25000000,DEBOUNCE_MS=20
)(input wire clk,rst,vs,sw_settings,key1,key2,key3,
 output reg menu_open,output reg [1:0] item,
 output reg [3:0] brightness,contrast,volume);
 localparam integer MS=CLK_FREQ_HZ<1000?1:CLK_FREQ_HZ/1000;
 localparam integer MB=MS<2?1:$clog2(MS);
 localparam integer DB=DEBOUNCE_MS<2?1:$clog2(DEBOUNCE_MS+1);
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg [2:0] sw_sync;
 reg [MB-1:0] ms_count;
 reg [DB-1:0] sw_count;
 reg sw_stable,vs_old;
 reg [1:0] selected;
 reg [3:0] bright_store,contrast_store,volume_store;
 wire minus,plus,choose,held_minus,held_plus,held_choose;
 lights_direct_keys #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_keys(
  .clk(clk),.rst(rst || !menu_open),.previous(key1),.next(key2),.confirm(key3),
  .prev_press(minus),.next_press(plus),.confirm_press(choose),
  .held_previous(held_minus),.held_next(held_plus),.held_confirm(held_choose));
 reg [1:0] repeat_dir;
 reg [8:0] repeat_count;
 reg repeat_minus,repeat_plus;
 wire ms_tick=ms_count==MS-1;
 wire lower=minus || repeat_minus,raise=plus || repeat_plus;
 always @(posedge clk or posedge rst)begin
  if(rst)sw_sync<=0;else sw_sync<={sw_sync[1:0],sw_settings};
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   repeat_dir<=0;repeat_count<=0;repeat_minus<=0;repeat_plus<=0;
  end else begin
   repeat_minus<=0;repeat_plus<=0;
   if(!menu_open || !sw_stable || selected==3 || choose || held_choose ||
      (held_minus && held_plus) || (!held_minus && !held_plus))begin repeat_dir<=0;repeat_count<=0;end
   else if(minus || plus)begin repeat_dir<=minus?1:2;repeat_count<=499;end
   else if(ms_tick && ((repeat_dir==1 && held_minus && !held_plus) ||
                       (repeat_dir==2 && held_plus && !held_minus)))begin
    if(repeat_count==0)begin
     repeat_minus<=repeat_dir==1;repeat_plus<=repeat_dir==2;repeat_count<=149;
    end else repeat_count<=repeat_count-1'b1;
   end
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   ms_count<=0;sw_count<=0;sw_stable<=0;vs_old<=0;
   menu_open<=0;item<=0;selected<=0;
   bright_store<=4;contrast_store<=4;volume_store<=10;
   brightness<=4;contrast<=4;volume<=10;
  end else begin
   vs_old<=vs;
   if(ms_tick)begin
    ms_count<=0;
    if(sw_sync[2]==sw_stable)sw_count<=0;
    else if(sw_count==DEBOUNCE_MS-1)begin sw_stable<=sw_sync[2];sw_count<=0;end
    else sw_count<=sw_count+1'b1;
   end else ms_count<=ms_count+1'b1;
   if(menu_open && sw_stable)begin
    if(choose)selected<=selected+1'b1;
    if(raise || lower)case(selected)
     0:if(raise && bright_store<8)bright_store<=bright_store+1'b1;
       else if(lower && bright_store>0)bright_store<=bright_store-1'b1;
     1:if(raise && contrast_store<8)contrast_store<=contrast_store+1'b1;
       else if(lower && contrast_store>0)contrast_store<=contrast_store-1'b1;
     2:if(raise && volume_store<15)volume_store<=volume_store+1'b1;
       else if(lower && volume_store>0)volume_store<=volume_store-1'b1;
     3:if(plus)begin bright_store<=4;contrast_store<=4;volume_store<=10;end
       else if(minus)selected<=0;
    endcase
   end
   if(vs_old && !vs)begin
    menu_open<=sw_stable;item<=selected;
    brightness<=bright_store;contrast<=contrast_store;volume<=volume_store;
   end
  end
 end
endmodule
