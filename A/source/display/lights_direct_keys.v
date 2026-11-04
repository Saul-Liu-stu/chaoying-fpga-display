`timescale 1ns/1ps
module lights_direct_keys #(parameter CLK_FREQ_HZ=100000000,DEBOUNCE_MS=20)(
 input wire clk,rst,previous,confirm,next,
 output reg prev_press,confirm_press,next_press,
 output wire held_previous,held_confirm,held_next);
 lights_scene_button #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_previous(clk,rst,previous,held_previous);
 lights_scene_button #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_confirm(clk,rst,confirm,held_confirm);
 lights_scene_button #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_next(clk,rst,next,held_next);
 reg armed;
 always @(posedge clk or posedge rst)begin
  if(rst)begin armed<=0;prev_press<=0;confirm_press<=0;next_press<=0;end
  else begin
   prev_press<=0;confirm_press<=0;next_press<=0;
   if(!held_previous && !held_confirm && !held_next)armed<=1;
   else if(armed)begin
    armed<=0;
    case({held_previous,held_confirm,held_next})
     3'b100:prev_press<=1;
     3'b010:confirm_press<=1;
     3'b001:next_press<=1;
     default:;
    endcase
   end
  end
 end
endmodule
