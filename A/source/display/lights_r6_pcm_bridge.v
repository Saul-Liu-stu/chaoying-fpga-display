module lights_r6_pcm_bridge #(parameter integer BANK_BITS=9,parameter integer BANK_COUNT=2)(
 input wire sd_clk,sd_rst,pixel_clk,pixel_rst,
 input wire [1:0] command_mode,input wire flush_toggle,run_sd,clear_sd,
 output wire flush_done,
 input wire sample_valid,input wire [15:0] sample_data,
 output wire sample_ready,output wire [BANK_BITS+1:0] sample_room,
 input wire tick,input wire [23:0] tone_left,tone_right,
 output reg audio_valid,output reg [23:0] audio_left,audio_right,
 output reg underflow,output wire [1:0] active_mode
);
 localparam integer BANK_SAMPLES=1<<BANK_BITS;
 localparam integer TOTAL_SAMPLES=BANK_SAMPLES*BANK_COUNT;
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [15:0] pcm[0:TOTAL_SAMPLES-1];
 reg [BANK_BITS+1:0] write_index,read_index;
 reg [3:0] published,released;
 reg flush_ack;
 (* syn_preserve=1 *) reg [3:0] release_s1,release_s2,release_s3;
 (* syn_preserve=1 *) reg ack_s1,ack_s2,ack_s3;
 (* syn_preserve=1 *) reg [3:0] publish_s1,publish_s2,publish_s3;
 (* syn_preserve=1 *) reg flush_s1,flush_s2,flush_s3,run_s1,run_s2,run_s3;
 reg [1:0] selected_mode;reg started;
 assign active_mode=selected_mode;
 reg [15:0] read_data;
 wire [1:0] write_bank=write_index[BANK_BITS +: 2];
 wire [1:0] read_bank=read_index[BANK_BITS +: 2];
 wire [BANK_BITS-1:0] write_offset=write_index[BANK_BITS-1:0];
 wire [BANK_BITS-1:0] read_offset=read_index[BANK_BITS-1:0];
 wire current_free=(write_bank<BANK_COUNT) && published[write_bank]==release_s3[write_bank];
 reg [1:0] free_other_count;integer free_i;
 always @* begin
  free_other_count=0;
  for(free_i=0;free_i<4;free_i=free_i+1)
   if(free_i<BANK_COUNT && free_i!=write_bank && published[free_i]==release_s3[free_i])
    free_other_count=free_other_count+1'b1;
 end
 assign sample_ready=current_free && flush_done;
 assign sample_room=sample_ready ?
     BANK_SAMPLES-{1'b0,write_offset}+free_other_count*BANK_SAMPLES : 0;
 assign flush_done=ack_s3==flush_toggle;
 always @(posedge sd_clk or posedge sd_rst) begin
  if(sd_rst) begin release_s1<=0;release_s2<=0;release_s3<=0;ack_s1<=0;ack_s2<=0;ack_s3<=0;end
  else begin release_s1<=released;release_s2<=release_s1;release_s3<=release_s2;
   ack_s1<=flush_ack;ack_s2<=ack_s1;ack_s3<=ack_s2;end
 end
 always @(posedge sd_clk or posedge sd_rst) begin
  if(sd_rst) begin write_index<=0;published<=0;end
  else if(clear_sd) write_index<=0;
  else if(sample_valid && sample_ready) begin
   if(write_index==TOTAL_SAMPLES-1)write_index<=0;else write_index<=write_index+1'b1;
   if(write_offset==BANK_SAMPLES-1) published[write_bank]<=!published[write_bank];
  end
 end
 always @(posedge sd_clk) if(sample_valid && sample_ready && !clear_sd)
  pcm[write_index]<=sample_data;
 always @(posedge pixel_clk) read_data<=pcm[read_index];
 always @(posedge pixel_clk or posedge pixel_rst) begin
  if(pixel_rst) begin publish_s1<=0;publish_s2<=0;publish_s3<=0;
   flush_s1<=0;flush_s2<=0;flush_s3<=0;run_s1<=0;run_s2<=0;run_s3<=0;end
  else begin publish_s1<=published;publish_s2<=publish_s1;publish_s3<=publish_s2;
   flush_s1<=flush_toggle;flush_s2<=flush_s1;flush_s3<=flush_s2;
   run_s1<=run_sd;run_s2<=run_s1;run_s3<=run_s2;end
 end
 always @(posedge pixel_clk or posedge pixel_rst) begin
  if(pixel_rst) begin read_index<=0;released<=0;flush_ack<=0;selected_mode<=0;
   audio_valid<=0;audio_left<=0;audio_right<=0;underflow<=0;started<=0;end
  else begin
   audio_valid<=tick;audio_left<=0;audio_right<=0;
   if(flush_s3!=flush_ack) begin
    selected_mode<=command_mode;read_index<=0;released<=publish_s3;
    flush_ack<=flush_s3;underflow<=0;started<=0;
   end else if(tick) begin
    if(selected_mode==0) begin audio_left<=tone_left;audio_right<=tone_right;end
    else if(run_s3 && publish_s3[read_bank]!=released[read_bank]) begin
     audio_left<={read_data,8'd0};audio_right<={read_data,8'd0};started<=1;
     if(read_index==TOTAL_SAMPLES-1)read_index<=0;else read_index<=read_index+1'b1;
     if(read_offset==BANK_SAMPLES-1) released[read_bank]<=publish_s3[read_bank];
    end else if(run_s3 && started) underflow<=1;
   end
  end
 end
endmodule
