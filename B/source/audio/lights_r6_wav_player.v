module lights_r6_wav_player #(parameter integer BANK_BITS=9, SHARED_FONT=0)(
 input wire clk,rst,mounted,input wire [1:0] selection,
 input wire [2:0] found,duplicate,input wire [95:0] clusters,sizes,
 input wire [31:0] fat_base,data_base,max_cluster,
 input wire [32:0] volume_end,input wire [3:0] cluster_shift,
 output reg [1:0] command_mode,output reg flush_toggle,
 input wire flush_done,output wire clear_pcm,run_pcm,
 output wire pcm_valid,output wire [15:0] pcm_data,input wire pcm_ready,
 input wire [BANK_BITS+1:0] pcm_room,
 output wire sector_request,sector_release,output wire [31:0] sector_lba,
 input wire sector_grant,sector_done,input wire [7:0] buffer_byte,
 output wire [8:0] buffer_addr,output reg [7:0] error_code,
 input wire font_boot_done,font_found,font_duplicate,
 input wire [31:0] font_cluster,font_size,
 input wire font_start,font_cancel,input wire [31:0] font_offset,input wire [9:0] font_length,
 output wire font_ready,font_unavailable,font_chain_fault,font_idle,font_done,font_good,font_byte_valid,
 output wire [8:0] font_byte_index,output wire [7:0] font_byte,input wire font_byte_ready,
 output wire font_request,font_release,output wire [31:0] font_lba,
 input wire font_grant,font_sector_done,output wire [8:0] font_buffer_addr,input wire [7:0] font_buffer_byte,
 output wire player_idle
);
 localparam IDLE=0,CHANGE=1,FLUSH=2,DRAIN=3,RESET_FILE=4,CHAIN=5,ISSUE=6,READ=7,
  RIFF_CHECK=8,CHUNK_CHECK=9,FMT_CHECK=10,STREAM_NEXT=11,STREAM_WAIT=12,BAD=13,PLAN_LENGTH=14,PLAN_ROOM=15;
 reg [3:0] state;reg [1:0] reset_wait,read_kind;
 assign player_idle=state==IDLE;
 reg file_reset;reg [1:0] file_mode;
 wire span_reset=rst || file_reset;
 wire span_ready,span_unavailable,span_fault,span_idle,span_done,span_good;
 wire byte_valid;wire [8:0] byte_index;wire [7:0] byte_data;
 reg [21:0] offset,data_start,data_remaining,data_length,riff_end,chunk_length,next_chunk;
 reg [9:0] length;
 reg [31:0] word_acc;reg chunk_fmt,chunk_data;
 reg header_bad,fmt_seen,fmt_bad,chunk_bad,half;
 reg [7:0] low_byte;
 wire [31:0] next_word={byte_data,word_acc[31:8]};
 wire [1:0] role=file_mode-1'b1;
 wire [31:0] file_cluster=clusters[role*32 +: 32];
 wire [31:0] file_size=sizes[role*32 +: 32];
 wire cancel=state==CHANGE || state==FLUSH || state==DRAIN;
 wire accept_pcm=state==STREAM_WAIT && selection==command_mode;
 assign pcm_valid=accept_pcm && byte_valid && half;
 assign pcm_data={byte_data,low_byte};
 assign clear_pcm=state==FLUSH && flush_done;
 assign run_pcm=(state==STREAM_NEXT || state==STREAM_WAIT || state==PLAN_LENGTH || state==PLAN_ROOM) && selection==command_mode;
 wire byte_ready=state==STREAM_WAIT ? pcm_ready && accept_pcm : 1'b1;
 wire [9:0] sector_left=10'd512-{1'b0,offset[8:0]};
 wire [9:0] sector_length=data_remaining<sector_left ? data_remaining[9:0] : sector_left;
 reg [BANK_BITS+1:0] room_q;
 reg [9:0] sector_length_q,next_length;
 reg [22:0] chunk_end;
 reg [23:0] chunk_plus8_q,next_plus8_q;
 reg chunk_range_bad_q,chunk_next_fits_q,fmt_next_fits_q,riff_bad_q;
 always @(posedge clk)begin
  chunk_end<={1'b0,offset}+23'd8+{1'b0,chunk_length}+chunk_length[0];
  chunk_plus8_q<={1'b0,chunk_end}+24'd8;
  chunk_range_bad_q<=chunk_end[22] || chunk_end>{1'b0,riff_end};
  chunk_next_fits_q<=chunk_plus8_q<={2'd0,riff_end};
  next_plus8_q<={2'd0,next_chunk}+24'd8;
  fmt_next_fits_q<=next_plus8_q<={2'd0,riff_end};
  riff_bad_q<=riff_end<44 || riff_end>file_size[21:0];
 end
 wire reader_available;
 generate if(SHARED_FONT) begin : g_shared
  reg wav_owner,handoff_reset,saved_ready,saved_unavailable,saved_fault;
  wire r_ready,r_unavailable,r_fault,r_idle,r_done,r_good,r_valid,r_request,r_release;
  wire [8:0] r_index,r_address;wire [7:0] r_byte;wire [31:0] r_lba;
  always @(posedge clk or posedge rst) begin
   if(rst)begin wav_owner<=0;handoff_reset<=0;saved_ready<=0;saved_unavailable<=0;saved_fault<=0;end
   else begin
    handoff_reset<=0;
    if(!wav_owner && font_boot_done && (r_idle || r_unavailable || r_fault) && !r_release)begin
     wav_owner<=1;handoff_reset<=1;saved_ready<=r_ready;saved_unavailable<=r_unavailable;saved_fault<=r_fault;
    end
   end
  end
  assign reader_available=wav_owner;
  assign font_ready=wav_owner ? saved_ready : r_ready;
  assign font_unavailable=wav_owner ? saved_unavailable : r_unavailable;
  assign font_chain_fault=wav_owner ? saved_fault : r_fault;
  assign font_idle=wav_owner || r_idle;
  assign font_done=!wav_owner && r_done;assign font_good=!wav_owner && r_good;
  assign font_byte_valid=!wav_owner && r_valid;assign font_byte_index=r_index;assign font_byte=r_byte;
  assign font_request=!wav_owner && r_request;assign font_release=!wav_owner && r_release;
  assign font_lba=r_lba;assign font_buffer_addr=r_address;
  assign span_ready=wav_owner && r_ready;assign span_unavailable=wav_owner && r_unavailable;
  assign span_fault=wav_owner && r_fault;assign span_idle=wav_owner && r_idle;
  assign span_done=wav_owner && r_done;assign span_good=wav_owner && r_good;
  assign byte_valid=wav_owner && r_valid;assign byte_index=r_index;assign byte_data=r_byte;
  assign sector_request=wav_owner && r_request;assign sector_release=wav_owner && r_release;
  assign sector_lba=r_lba;assign buffer_addr=r_address;
  lights_theme_font_file #(.FILE_BITS(22),.DUAL_MODE(1)) u_span(
   .clk(clk),.rst(rst || handoff_reset || (wav_owner && file_reset)),.wav_mode(wav_owner),
   .mounted(mounted && (!wav_owner || file_mode!=0)),
   .found(wav_owner ? found[role] : font_found),.duplicate(wav_owner ? duplicate[role] : font_duplicate),
   .first_cluster(wav_owner ? file_cluster : font_cluster),.file_size(wav_owner ? file_size : font_size),
   .fat_base(fat_base),.data_base(data_base),.max_cluster(max_cluster),.volume_end(volume_end),.cluster_shift(cluster_shift),
   .ready(r_ready),.unavailable(r_unavailable),.chain_fault(r_fault),
   .start(wav_owner ? (state==ISSUE || (state==STREAM_NEXT && next_length!=0 && pcm_ready)) : font_start),
   .cancel(wav_owner ? cancel : font_cancel),.offset(wav_owner ? {10'd0,offset} : font_offset),
   .length(wav_owner ? (state==STREAM_NEXT ? next_length : length) : font_length),
   .idle(r_idle),.done(r_done),.good(r_good),.byte_valid(r_valid),.byte_index(r_index),.byte_data(r_byte),
   .byte_ready(wav_owner ? byte_ready : font_byte_ready),.sector_request(r_request),.sector_lba(r_lba),
   .sector_grant(wav_owner ? sector_grant : font_grant),.sector_done(wav_owner ? sector_done : font_sector_done),
   .sector_release(r_release),.buffer_addr(r_address),.buffer_byte(wav_owner ? buffer_byte : font_buffer_byte),
   .anchor_read_data(28'd0));
 end else begin : g_separate
  assign reader_available=1;
  assign font_ready=0;assign font_unavailable=0;assign font_chain_fault=0;assign font_idle=1;
  assign font_done=0;assign font_good=0;assign font_byte_valid=0;assign font_byte_index=0;assign font_byte=0;
  assign font_request=0;assign font_release=0;assign font_lba=0;assign font_buffer_addr=0;
 lights_r6_file_reader u_span(
  .clk(clk),.rst(span_reset),.mounted(mounted && file_mode!=0),
  .found(found[role]),.duplicate(duplicate[role]),.first_cluster(file_cluster),.file_size(file_size),
  .fat_base(fat_base),.data_base(data_base),.max_cluster(max_cluster),.volume_end(volume_end),.cluster_shift(cluster_shift),
  .ready(span_ready),.unavailable(span_unavailable),.chain_fault(span_fault),
  .start(state==ISSUE || (state==STREAM_NEXT && next_length!=0 && pcm_ready)),
  .cancel(cancel),.offset({10'd0,offset}),.length(state==STREAM_NEXT ? next_length : length),
  .idle(span_idle),.done(span_done),.good(span_good),.byte_valid(byte_valid),.byte_index(byte_index),
  .byte_data(byte_data),.byte_ready(byte_ready),.sector_request(sector_request),.sector_lba(sector_lba),
  .sector_grant(sector_grant),.sector_done(sector_done),.sector_release(sector_release),
  .buffer_addr(buffer_addr),.buffer_byte(buffer_byte));
 end endgenerate
 function [7:0] riff_byte;
  input [8:0] i;
  begin case(i)
   0:riff_byte=8'h52;1:riff_byte=8'h49;2,3:riff_byte=8'h46;
   8:riff_byte=8'h57;9:riff_byte=8'h41;10:riff_byte=8'h56;11:riff_byte=8'h45;
   default:riff_byte=0;
  endcase end
 endfunction
 function [7:0] fmt_byte;
  input [8:0] i;
  begin case(i)
   0,2,10:fmt_byte=1;4:fmt_byte=8'h80;5:fmt_byte=8'hbb;
   9:fmt_byte=8'h77;12:fmt_byte=2;14:fmt_byte=16;default:fmt_byte=0;
  endcase end
 endfunction
 always @(posedge clk or posedge rst) begin
  if(rst) begin state<=IDLE;command_mode<=0;flush_toggle<=0;reset_wait<=0;read_kind<=0;file_reset<=1;file_mode<=0;
   offset<=0;length<=0;data_start<=0;data_remaining<=0;data_length<=0;riff_end<=0;chunk_length<=0;next_chunk<=0;
   room_q<=0;sector_length_q<=0;next_length<=0;word_acc<=0;chunk_fmt<=0;chunk_data<=0;header_bad<=0;fmt_seen<=0;fmt_bad<=0;chunk_bad<=0;half<=0;low_byte<=0;error_code<=0;end
  else begin
    if(selection!=command_mode && state!=CHANGE && state!=FLUSH && state!=DRAIN) state<=CHANGE;
   else if((span_fault || span_unavailable) && state!=IDLE && state!=CHANGE && state!=FLUSH && state!=DRAIN && state!=RESET_FILE && state!=BAD) begin error_code<=10;state<=BAD;end
   else case(state)
    IDLE: ;
    CHANGE: begin command_mode<=selection;flush_toggle<=!flush_toggle;state<=FLUSH;end
    FLUSH: if(flush_done) state<=DRAIN;
     DRAIN: if(span_idle || span_unavailable || span_fault || file_reset || !reader_available) begin
     reset_wait<=0;file_reset<=1;state<=RESET_FILE;end
    RESET_FILE: begin
     reset_wait<=reset_wait+1'b1;header_bad<=0;fmt_seen<=0;fmt_bad<=0;chunk_bad<=0;half<=0;error_code<=0;
     if(reset_wait==3) begin file_mode<=command_mode;file_reset<=command_mode==0;state<=command_mode==0 ? IDLE : CHAIN;end
    end
    CHAIN: if(span_unavailable || span_fault) begin error_code<=1;state<=BAD;end
      else if(span_ready) begin offset<=0;length<=12;read_kind<=0;word_acc<=0;state<=ISSUE;end
    ISSUE: if(span_idle) begin word_acc<=0;chunk_fmt<=1;chunk_data<=1;state<=READ;end
    READ: begin
     if(byte_valid) begin
      word_acc<=next_word;
      if(read_kind==0) begin
       if((byte_index<4 || byte_index>=8) && byte_data!=riff_byte(byte_index)) header_bad<=1;
       if(byte_index==7) begin riff_end<=next_word[21:0]+22'd8;if(next_word[31:22]!=0)header_bad<=1;end
      end else if(read_kind==1) begin
       if(byte_index<4)begin
        case(byte_index)
         0:begin chunk_fmt<=byte_data==8'h66;chunk_data<=byte_data==8'h64;end
         1:begin chunk_fmt<=chunk_fmt && byte_data==8'h6d;chunk_data<=chunk_data && byte_data==8'h61;end
         2:begin chunk_fmt<=chunk_fmt && byte_data==8'h74;chunk_data<=chunk_data && byte_data==8'h74;end
         3:begin chunk_fmt<=chunk_fmt && byte_data==8'h20;chunk_data<=chunk_data && byte_data==8'h61;end
        endcase
       end
       if(byte_index==7) begin chunk_length<=next_word[21:0];chunk_bad<=next_word[31:22]!=0;end
      end else if(byte_data!=fmt_byte(byte_index)) fmt_bad<=1;
     end
     if(span_done) begin
      if(!span_good) begin error_code<=2;state<=BAD;end
      else state<=read_kind==0 ? RIFF_CHECK : read_kind==1 ? CHUNK_CHECK : FMT_CHECK;
     end
    end
    RIFF_CHECK: begin
     if(header_bad || riff_bad_q)begin error_code<=3;state<=BAD;end
     else begin offset<=12;length<=8;read_kind<=1;state<=ISSUE;end
    end
    CHUNK_CHECK: begin
     next_chunk<=chunk_end[21:0];
     if(chunk_bad || chunk_range_bad_q || offset>4096)begin error_code<=4;state<=BAD;end
     else if(chunk_fmt) begin
      if(fmt_seen || (chunk_length!=16 && chunk_length!=18)) begin error_code<=5;state<=BAD;end
      else begin fmt_bad<=0;offset<=offset+22'd8;length<=chunk_length[9:0];read_kind<=2;state<=ISSUE;end
     end else if(chunk_data) begin
      if(!fmt_seen || chunk_length<2 || chunk_length[0])begin error_code<=6;state<=BAD;end
      else begin data_start<=offset+22'd8;offset<=offset+22'd8;
       data_remaining<=chunk_length;data_length<=chunk_length;half<=0;state<=PLAN_LENGTH;end
     end else if(!chunk_next_fits_q)begin error_code<=7;state<=BAD;end
     else begin offset<=chunk_end[21:0];length<=8;read_kind<=1;state<=ISSUE;end
    end
    FMT_CHECK: if(fmt_bad || !fmt_next_fits_q)begin error_code<=8;state<=BAD;end
     else begin fmt_seen<=1;offset<=next_chunk;length<=8;read_kind<=1;state<=ISSUE;end
    PLAN_LENGTH:begin room_q<=pcm_room;sector_length_q<=sector_length;state<=PLAN_ROOM;end
    PLAN_ROOM:begin next_length<=room_q<({1'b0,sector_length_q}>>1)?(room_q<<1):sector_length_q;state<=STREAM_NEXT;end
    STREAM_NEXT: if(next_length!=0 && pcm_ready && span_idle) begin length<=next_length;state<=STREAM_WAIT;end
      else if(next_length==0)state<=PLAN_LENGTH;
    STREAM_WAIT: begin
     if(byte_valid && byte_ready) begin
      half<=!half;if(!half)low_byte<=byte_data;
     end
     if(span_done) begin
      if(!span_good) begin error_code<=9;state<=BAD;end
      else if(data_remaining==length) begin offset<=data_start;data_remaining<=data_length;state<=PLAN_LENGTH;end
      else begin offset<=offset+length;data_remaining<=data_remaining-length;state<=PLAN_LENGTH;end
     end
    end
    BAD: ;
    default:state<=BAD;
   endcase
  end
 end
endmodule
