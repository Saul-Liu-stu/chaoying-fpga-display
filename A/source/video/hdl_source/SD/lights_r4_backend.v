`timescale 1ns/1ps
module lights_r4_backend #(parameter CAPTION_SYNC=1,R5=0)(
 input wire [3:0] extra_hold,input wire [31:0] extra_generations,input wire extra_changed,output wire [3:0] hold_ack_mask,
 input wire [4:0] cache_query_pic,output wire [31:0] cache_query_identity,
 input wire clk,rst,catalog_ready,input wire [15:0] available_mask,
 input wire accepted_command,input wire [3:0] accepted_index,input wire [4:0] accepted_pic,
 input wire [1:0] accepted_mode,requested_mode,input wire foreground_claim,select_cancel,
 output wire command_ready,input wire view_valid,input wire [4:0] view_pic,input wire [1:0] view_mode,
 input wire source_idle,source_success,input wire [4:0] source_number,input wire [7:0] source_error,
 input wire source_fault,write_done_valid,input wire [31:0] write_done_identity,
 input wire presented_valid,input wire [31:0] presented_identity,input wire caption_commit_ready,
 output reg load_start,output reg [3:0] load_index,output wire [1:0] write_buf_idx,disp_buf_idx,
 output wire [31:0] write_identity,output reg [31:0] display_identity,
 output wire [31:0] prepared_identity,output wire prepared_valid,
 output reg display_valid,publish_pulse,output wire load_busy,source_done_seen,write_finish_pulse,
 output wire fault_locked,output wire [7:0] error_code,
 output wire page_owner,background_req,background_valid,output wire [23:0] background_pixel,
 output wire [20:0] rect_first,rect_length,output wire [10:0] rect_width,output wire [11:0] rect_jump,
 input wire write_req_ack,write_ready);
 wire pool_ready,pool_load,pool_busy,pool_display_valid,pool_publish,pool_fault;
 wire [3:0] pool_index;wire [1:0] pool_disp;wire [31:0] pool_wid,pool_did;wire [7:0] pool_error;
 wire page_ready,page_load,page_publish,page_fault,page_active,page_valid;
 wire [3:0] page_index;wire [31:0] page_wid,page_did;
 wire [20:0] page_first,page_length;wire [10:0] page_width;wire [11:0] page_jump;
 wire page_background_req,page_background_valid;
 reg background_request_q;
 always @(posedge clk or posedge rst) begin
  if(rst) background_request_q<=0;
  else if(!page_background_req) background_request_q<=0;
  else if(!source_fault && !fault_locked) background_request_q<=1;
 end
 reg select_active,cancel_hold;
 reg command_pending,dispatch_pool,dispatch_page,requested_select_q;
 reg [3:0] pending_index;
 reg [4:0] pending_pic;
 reg [1:0] pending_mode,ready_mode_q;
 reg ready_q,source_idle_q;
 wire pending_cancel=select_cancel || (pending_mode==1 && cancel_hold) ||
                     requested_mode!=pending_mode;
 wire dispatch_allowed=requested_mode==pending_mode && !source_fault && !fault_locked &&
                       !(pending_mode==1 && (select_cancel || cancel_hold));
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   command_pending<=0;dispatch_pool<=0;dispatch_page<=0;requested_select_q<=0;
   pending_index<=0;pending_pic<=0;pending_mode<=0;ready_mode_q<=0;
   ready_q<=0;source_idle_q<=0;
  end else begin
   requested_select_q<=requested_mode==1;
   ready_mode_q<=requested_mode;
   ready_q<=requested_mode==1 ? page_ready : pool_ready && !page_owner;
   source_idle_q<=source_idle && !source_fault;
   dispatch_pool<=0;dispatch_page<=0;
   if(source_fault || fault_locked || (command_pending && pending_cancel))
    command_pending<=0;
   else if(accepted_command && !command_pending) begin
    pending_index<=accepted_index;pending_pic<=accepted_pic;pending_mode<=accepted_mode;
    command_pending<=1;
   end else if(command_pending) begin
    if(pending_mode==1 ? page_ready : (pool_ready && !page_owner)) begin
     command_pending<=0;
     dispatch_page<=pending_mode==1;dispatch_pool<=pending_mode!=1;
    end
   end
  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin select_active<=0;cancel_hold<=0;display_identity<=0;display_valid<=0;publish_pulse<=0;end
  else begin
   publish_pulse<=0;
   if(accepted_command) select_active<=accepted_mode==1;
   if(select_cancel) begin select_active<=0;cancel_hold<=1;end
   else if(requested_mode!=1 && !page_active) cancel_hold<=0;
   if(pool_publish && !source_fault && !fault_locked) begin display_identity<=pool_did;display_valid<=pool_display_valid;publish_pulse<=1;end
   if(page_publish && !source_fault && !fault_locked && !select_cancel && !cancel_hold) begin display_identity<=page_did;display_valid<=1;publish_pulse<=1;end
  end
 end
 assign command_ready=ready_q && ready_mode_q==requested_mode && !source_fault && !fault_locked &&
                      !command_pending && !accepted_command && !dispatch_pool && !dispatch_page;
 assign disp_buf_idx=display_identity[1:0];
 always @(posedge clk or posedge rst) begin
  if(rst) begin load_start<=0;load_index<=0;end
  else begin load_start<=!source_fault && !fault_locked && (page_owner ? page_load : pool_load);
   load_index<=page_owner ? page_index : pool_index;end
 end
 assign write_identity=page_owner ? page_wid : pool_wid;
 assign load_busy=page_owner || pool_busy;
 assign fault_locked=pool_fault || page_fault;assign error_code=page_fault ? 8'h46 : pool_error;
 wire [20:0] slot_base=write_buf_idx==0 ? 21'd0 : write_buf_idx==1 ? 21'd307200 : write_buf_idx==2 ? 21'd614400 : 21'd921600;
 assign rect_first=page_owner ? page_first : slot_base+21'd306560;
 assign rect_length=page_owner ? page_length : 21'd307200;
 assign rect_width=page_owner ? page_width : 11'd640;
 assign rect_jump=page_owner ? page_jump : 12'd1279;
 assign background_req=background_request_q;
 assign background_valid=page_background_valid && !source_fault && !fault_locked;
 lights_frame_pool #(.CAPTION_SYNC(CAPTION_SYNC),.SOURCE_FAULT_INPUT(1),.R4(1),.R5(R5)) u_pool(
  .extra_hold(extra_hold),.extra_generations(extra_generations),.extra_changed(extra_changed),.hold_ack_mask(hold_ack_mask),
  .cache_query_pic(cache_query_pic),.cache_query_identity(cache_query_identity),
  .published_prefetch_ok(requested_mode==0 && !accepted_command && !command_pending && !dispatch_pool && !dispatch_page && !select_cancel),
  .clk(clk),.rst(rst),.catalog_ready(catalog_ready),.available_mask(available_mask),
  .command_valid(dispatch_pool && dispatch_allowed),.foreground_claim(foreground_claim || command_pending || dispatch_pool || dispatch_page),
  .pause_background(requested_select_q || select_active || page_owner),
  .command_index(pending_index),.command_pic(pending_pic),.command_mode(pending_mode),.command_ready(pool_ready),
  .view_valid(view_valid),.view_pic(view_pic),.view_mode(view_mode),
  .source_idle(source_idle_q && !page_owner),.source_success(source_success && !page_owner),.source_number(source_number),
  .source_error(source_error),.source_fault(source_fault),
  .write_done_valid(write_done_valid && !write_done_identity[2]),.write_done_identity(write_done_identity),
  .presented_valid(presented_valid && !presented_identity[2]),.presented_identity(presented_identity),
  .caption_commit_ready(caption_commit_ready),
  .load_start(pool_load),.load_index(pool_index),.write_buf_idx(write_buf_idx),.disp_buf_idx(pool_disp),
  .write_identity(pool_wid),.display_identity(pool_did),.prepared_identity(prepared_identity),.prepared_valid(prepared_valid),
  .display_valid(pool_display_valid),.publish_pulse(pool_publish),.load_busy(pool_busy),.source_done_seen(source_done_seen),
  .write_finish_pulse(write_finish_pulse),.fault_locked(pool_fault),.error_code(pool_error),.valid_slots(),.protected_slots());
 lights_select_page u_page(
  .clk(clk),.rst(rst),.catalog_ready(catalog_ready),.available_mask(available_mask),
  .command_valid(dispatch_page && dispatch_allowed),.command_pic(pending_pic),.command_ready(page_ready),
  .cancel(select_cancel || cancel_hold),.pool_load_busy(pool_busy),.source_idle(source_idle_q),.source_success(source_success && page_owner),
  .write_done_valid(write_done_valid),.write_done_identity(write_done_identity),.source_fault(source_fault),
  .owner(page_owner),.load_start(page_load),.load_index(page_index),.write_identity(page_wid),.display_identity(page_did),.publish_pulse(page_publish),
  .rect_first(page_first),.rect_length(page_length),.rect_width(page_width),.rect_jump(page_jump),
  .background_req(page_background_req),.write_req_ack(write_req_ack),.background_valid(page_background_valid),
  .background_pixel(background_pixel),.write_ready(write_ready),.page_valid(page_valid),.fault(page_fault),.active(page_active));
endmodule
