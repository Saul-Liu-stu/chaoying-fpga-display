`timescale 1ns/1ps
module lights_overlay_switches #(
 parameter integer CLK_FREQ_HZ=25000000,DEBOUNCE_MS=20
)(input wire clk,rst,vs,sw_caption,sw_scope,
 output reg caption_visible,scope_visible);
 localparam integer MS_CYCLES=CLK_FREQ_HZ<1000?1:CLK_FREQ_HZ/1000;
 localparam integer MS_BITS=MS_CYCLES<2?1:$clog2(MS_CYCLES);
 localparam integer DB_BITS=DEBOUNCE_MS<2?1:$clog2(DEBOUNCE_MS);
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg caption_s1,caption_s2,caption_s3;
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg scope_s1,scope_s2,scope_s3;
 reg [MS_BITS-1:0] ms_count;
 reg [DB_BITS-1:0] caption_count,scope_count;
 reg caption_stable,scope_stable,vs_old;
 wire ms_tick=ms_count==MS_CYCLES-1;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   caption_s1<=1;caption_s2<=1;caption_s3<=1;
   scope_s1<=1;scope_s2<=1;scope_s3<=1;
  end else begin
   caption_s1<=sw_caption;caption_s2<=caption_s1;caption_s3<=caption_s2;
   scope_s1<=sw_scope;scope_s2<=scope_s1;scope_s3<=scope_s2;
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   ms_count<=0;caption_count<=0;scope_count<=0;
   caption_stable<=1;scope_stable<=1;vs_old<=0;
   caption_visible<=1;scope_visible<=1;
  end else begin
   vs_old<=vs;
   ms_count<=ms_tick?0:ms_count+1'b1;
   if(ms_tick)begin
    if(caption_s3==caption_stable)caption_count<=0;
    else if(caption_count==DEBOUNCE_MS-1)begin caption_stable<=caption_s3;caption_count<=0;end
    else caption_count<=caption_count+1'b1;
    if(scope_s3==scope_stable)scope_count<=0;
    else if(scope_count==DEBOUNCE_MS-1)begin scope_stable<=scope_s3;scope_count<=0;end
    else scope_count<=scope_count+1'b1;
   end
   if(vs_old && !vs)begin caption_visible<=caption_stable;scope_visible<=scope_stable;end
  end
 end
endmodule
