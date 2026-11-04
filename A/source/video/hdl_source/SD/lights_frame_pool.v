`timescale 1ns/1ps
module lights_frame_pool #(
    parameter integer CAPTION_SYNC=1,SOURCE_FAULT_INPUT=0,WRITE_FINISH_TIMEOUT=1_500_000_000,R4=0,R5=0
)(
    input wire clk,rst,catalog_ready,
    input wire published_prefetch_ok,
    input wire [4:0] cache_query_pic,output wire [31:0] cache_query_identity,
    input wire [15:0] available_mask,
    input wire command_valid,
    input wire foreground_claim,
    input wire pause_background,
    input wire [3:0] command_index,
    input wire [4:0] command_pic,
    input wire [1:0] command_mode,
    output wire command_ready,
    input wire view_valid,
    input wire [4:0] view_pic,
    input wire [1:0] view_mode,
    input wire source_idle,source_success,
    input wire [4:0] source_number,
    input wire [7:0] source_error,
    input wire source_fault,
    input wire write_done_valid,
    input wire [31:0] write_done_identity,
    input wire presented_valid,
    input wire [31:0] presented_identity,
    input wire caption_commit_ready,
    input wire [3:0] extra_hold,
    input wire [31:0] extra_generations,
    input wire extra_changed,
    output wire [3:0] hold_ack_mask,
    output reg load_start,
    output reg [3:0] load_index,
    output reg [1:0] write_buf_idx,disp_buf_idx,
    output reg [31:0] write_identity,display_identity,
    output wire [31:0] prepared_identity,
    output wire prepared_valid,
    output reg display_valid,publish_pulse,load_busy,source_done_seen,
    output wire write_finish_pulse,
    output reg fault_locked,
    output reg [7:0] error_code,
    output wire [3:0] valid_slots,protected_slots
);
    wire source_failed=SOURCE_FAULT_INPUT ? source_fault : source_error!=0;
    reg [3:0] valid_mask;
    reg [4:0] slot_pic[0:3];
    reg [7:0] slot_generation[0:3];
    reg [7:0] next_generation[0:3];
    reg publication_qualified;
    reg [1:0] rank[0:3];
    reg [3:0] compact[0:15];
    reg mapping_ready;
    reg [4:0] map_cursor,map_count;
    reg front_pending,front_reserved,publication_wait;
    reg [4:0] front_pic,loading_pic;
    reg [3:0] front_index;
    reg [1:0] front_mode,front_slot;
    reg [7:0] front_generation,presentation_serial;
    reg write_done_seen;
    reg [31:0] write_timer;
    reg [3:0] retire_mask;
    reg [4:0] wish0,wish1,plan_pic,scan_pic,scan_left;
    reg [1:0] plan_mode,scan_phase;
    reg plan_valid;
    wire published_window=R5 && publication_wait && display_valid && display_identity[30:29]==0 && published_prefetch_ok && !pause_background;
    wire planning_valid=published_window ? 1'b1 : view_valid;
    wire [4:0] planning_pic=published_window ? display_identity[28:24] : view_pic;
    wire [1:0] planning_mode=published_window ? 2'd0 : view_mode;
    wire published_plan_matches=plan_valid && display_identity[28:24]==plan_pic && plan_mode==0;
    wire view_plan_matches=view_valid==plan_valid && view_pic==plan_pic && view_mode==plan_mode;
    wire plan_changed=published_window ? !published_plan_matches : !view_plan_matches;
    wire background_context_ok=published_window ? published_plan_matches :
        (!publication_wait && !foreground_claim && view_plan_matches);
    wire normal_candidate=scan_pic<=3 || scan_pic>=13;
    wire [4:0] role_end=plan_pic<=6 ? 5'd6 : plan_pic<=9 ? 5'd9 : 5'd12;
    wire eligible=scan_pic>=1 && scan_pic<=16 && available_mask[scan_pic-1'b1] && scan_pic!=plan_pic &&
        (plan_mode==0 ? normal_candidate : plan_mode==2 && scan_pic>plan_pic && scan_pic<=role_end);
    assign command_ready=mapping_ready && !front_pending && !publication_wait && !fault_locked;
    assign prepared_valid=(front_pending && front_reserved) || publication_wait;
    assign prepared_identity=publication_wait ? display_identity :
        {1'b1,front_mode,front_pic,front_generation,presentation_serial,6'd0,front_slot};
    assign valid_slots=valid_mask;
    assign write_finish_pulse=load_busy && write_done_valid && write_done_identity==write_identity;
    genvar g;
    generate for(g=0;g<4;g=g+1) begin : g_leases
        assign hold_ack_mask[g]=extra_hold[g] && valid_mask[g] && extra_generations[g*8 +: 8]==slot_generation[g];
        assign protected_slots[g]=hold_ack_mask[g] || retire_mask[g] ||
            (display_valid && disp_buf_idx==g) || (load_busy && write_buf_idx==g) ||
            (front_pending && front_reserved && front_slot==g);
    end endgenerate
    reg [31:0] query_stage;
    assign cache_query_identity=query_stage;
    always @(posedge clk or posedge rst) begin
        if(rst) query_stage<=0;
        else begin
            query_stage<=0;
            if(R5) for(integer k=0;k<4;k=k+1)
                if(valid_mask[k] && slot_pic[k]==cache_query_pic)
                    query_stage<={1'b1,2'd0,slot_pic[k],slot_generation[k],8'd0,6'd0,k[1:0]};
        end
    end
    integer i;
    reg hit_front,hit0,hit1,victim_front,victim_background;
    reg [1:0] front_hit_slot,free_front_slot,free_background_slot;
    reg [4:0] background_pic;
    reg [3:0] front_score[0:3],background_score[0:3];
    reg [3:0] front_score_stage[0:3],background_score_stage[0:3];
    reg [2:0] scores_epoch;
    reg hit_front_stage;reg [1:0] hit_slot_stage;
    reg [4:0] background_pic_stage;
    reg [1:0] front_pair0,front_pair1,background_pair0,background_pair1;
    reg [3:0] front_pair_score0,front_pair_score1,background_pair_score0,background_pair_score1;
    reg [1:0] front_pair_slot0,front_pair_slot1,background_pair_slot0,background_pair_slot1;
    reg [2:0] pair_epoch;
    reg pair_hit;reg [1:0] pair_hit_slot;reg [4:0] pair_background_pic;
    function prefer_left;
      input [3:0] left,right;
      reg low_le;
      begin
       low_le=(!left[1] && right[1]) || (left[1]==right[1] && (!left[0] || right[0]));
       prefer_left=(!left[3] && right[3]) || (left[3]==right[3] &&
          ((!left[2] && right[2]) || (left[2]==right[2] && low_le)));
      end
    endfunction
    reg [3:0] hit_mask;
    always @* begin
        hit_front=0;front_hit_slot=0;hit0=0;hit1=0;
        hit_mask=0;
        for(integer j=0;j<4;j=j+1) begin
            hit_mask[j]=valid_mask[j] && slot_pic[j]==front_pic;
            if(valid_mask[j] && slot_pic[j]==wish0) hit0=1;
            if(valid_mask[j] && slot_pic[j]==wish1) hit1=1;
            front_score[j]=protected_slots[j] ? 4'd15 : {1'b0,valid_mask[j],rank[j]};
            background_score[j]=protected_slots[j] || (valid_mask[j] && (slot_pic[j]==wish0 || slot_pic[j]==wish1)) ? 4'd15 : {1'b0,valid_mask[j],rank[j]};
        end
        hit_front=|hit_mask;front_hit_slot={hit_mask[2]|hit_mask[3],hit_mask[1]|hit_mask[3]};
        background_pic=wish0!=0 && !hit0 ? wish0 : wish1!=0 && !hit1 ? wish1 : 5'd0;
    end
    always @* begin
        front_pair0=prefer_left(front_score_stage[0],front_score_stage[1]) ? 0:1;
        front_pair1=prefer_left(front_score_stage[2],front_score_stage[3]) ? 2:3;
        background_pair0=prefer_left(background_score_stage[0],background_score_stage[1]) ? 0:1;
        background_pair1=prefer_left(background_score_stage[2],background_score_stage[3]) ? 2:3;
        free_front_slot=prefer_left(front_pair_score0,front_pair_score1) ? front_pair_slot0:front_pair_slot1;
        free_background_slot=prefer_left(background_pair_score0,background_pair_score1) ? background_pair_slot0:background_pair_slot1;
        victim_front=front_pair_score0!=15 || front_pair_score1!=15;
        victim_background=background_pair_score0!=15 || background_pair_score1!=15;
    end
    reg [2:0] selection_epoch,decision_epoch,candidate_epoch;
    reg candidate_hit,candidate_front_victim,candidate_background_victim;
    reg [1:0] candidate_hit_slot,candidate_front_slot,candidate_background_slot;
    reg [4:0] candidate_background_pic;
    reg caption_ready_q;reg [31:0] caption_identity_q;
    reg hit_front_q,victim_front_q,victim_background_q;
    reg [1:0] front_hit_slot_q,free_front_slot_q,free_background_slot_q;
    reg [4:0] background_pic_q;reg background_nonzero_q;
    reg loading_matches_front_q;
    reg [7:0] hit_generation_q,front_generation_q,background_generation_q;
    reg [7:0] front_next_generation_q,background_next_generation_q;
    wire decision_ready=decision_epoch==selection_epoch && !extra_changed;
    reg presented_match_q;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            decision_epoch<=8'hff;hit_front_q<=0;victim_front_q<=0;victim_background_q<=0;
            front_hit_slot_q<=0;free_front_slot_q<=0;free_background_slot_q<=0;background_pic_q<=0;background_nonzero_q<=0;
            hit_generation_q<=0;front_generation_q<=0;background_generation_q<=0;presented_match_q<=0;
            front_next_generation_q<=0;background_next_generation_q<=0;
            candidate_epoch<=8'hff;candidate_hit<=0;candidate_front_victim<=0;candidate_background_victim<=0;
            candidate_hit_slot<=0;candidate_front_slot<=0;candidate_background_slot<=0;candidate_background_pic<=0;
            caption_ready_q<=0;caption_identity_q<=0;publication_qualified<=0;loading_matches_front_q<=0;
            pair_epoch<=8'hfe;pair_hit<=0;pair_hit_slot<=0;pair_background_pic<=0;
            front_pair_score0<=15;front_pair_score1<=15;background_pair_score0<=15;background_pair_score1<=15;
            front_pair_slot0<=0;front_pair_slot1<=2;background_pair_slot0<=0;background_pair_slot1<=2;
            scores_epoch<=8'hff;hit_front_stage<=0;hit_slot_stage<=0;background_pic_stage<=0;
            for(integer j=0;j<4;j=j+1) begin front_score_stage[j]<=15;background_score_stage[j]<=15;end
        end else begin
            loading_matches_front_q<=load_busy && loading_pic==front_pic;
            scores_epoch<=selection_epoch;hit_front_stage<=hit_front;hit_slot_stage<=front_hit_slot;background_pic_stage<=background_pic;
            for(integer j=0;j<4;j=j+1) begin front_score_stage[j]<=front_score[j];background_score_stage[j]<=background_score[j];end
            pair_epoch<=scores_epoch;pair_hit<=hit_front_stage;pair_hit_slot<=hit_slot_stage;pair_background_pic<=background_pic_stage;
            front_pair_score0<=front_score_stage[front_pair0];front_pair_score1<=front_score_stage[front_pair1];
            background_pair_score0<=background_score_stage[background_pair0];background_pair_score1<=background_score_stage[background_pair1];
            front_pair_slot0<=front_pair0;front_pair_slot1<=front_pair1;background_pair_slot0<=background_pair0;background_pair_slot1<=background_pair1;
            candidate_epoch<=pair_epoch;candidate_hit<=pair_hit;
            candidate_front_victim<=victim_front;candidate_background_victim<=victim_background;
            candidate_hit_slot<=pair_hit_slot;candidate_front_slot<=free_front_slot;
            candidate_background_slot<=free_background_slot;candidate_background_pic<=pair_background_pic;
            decision_epoch<=candidate_epoch;hit_front_q<=candidate_hit;
            victim_front_q<=candidate_front_victim;victim_background_q<=candidate_background_victim;
            front_hit_slot_q<=candidate_hit_slot;free_front_slot_q<=candidate_front_slot;
            free_background_slot_q<=candidate_background_slot;background_pic_q<=candidate_background_pic;background_nonzero_q<=candidate_background_pic!=0;
            hit_generation_q<=slot_generation[candidate_hit_slot];front_generation_q<=next_generation[candidate_front_slot];
            background_generation_q<=next_generation[candidate_background_slot];
            front_next_generation_q<=next_generation[candidate_front_slot]+8'd1;
            background_next_generation_q<=next_generation[candidate_background_slot]+8'd1;
            presented_match_q<=publication_wait && presented_valid && presented_identity==display_identity;
            caption_ready_q<=caption_commit_ready;caption_identity_q<=prepared_identity;
            publication_qualified<=front_pending && front_reserved && valid_mask[front_slot] &&
                slot_pic[front_slot]==front_pic && slot_generation[front_slot]==front_generation &&
                (!CAPTION_SYNC || (caption_ready_q && caption_identity_q==prepared_identity));
        end
    end
    generate if(R4) begin : g_write_timer
        always @(posedge clk or posedge rst) begin
            if(rst) write_timer<=0;
            else if(load_busy && !fault_locked) write_timer<=write_timer+1'b1;
            else write_timer<=0;
        end
    end endgenerate
    task touch;
        input [1:0] slot;
        begin
            for(integer j=0;j<4;j=j+1) if(j!=slot && rank[j]>rank[slot]) rank[j]<=rank[j]-1'b1;
            rank[slot]<=3;
        end
    endtask
    task begin_load;
        input [4:0] pic;
        input [3:0] index;
        input [1:0] slot;
        input [7:0] new_generation;
        input [7:0] following_generation;
        begin
            load_start<=1;load_index<=index;write_buf_idx<=slot;loading_pic<=pic;
            load_busy<=1;valid_mask[slot]<=0;slot_pic[slot]<=pic;
            slot_generation[slot]<=new_generation;
            next_generation[slot]<=following_generation;
            write_identity<={1'b1,2'd0,pic,new_generation,8'd0,6'd0,slot};
            source_done_seen<=0;write_done_seen<=0;if(!R4) write_timer<=0;
            selection_epoch<=selection_epoch+1'b1;
        end
    endtask
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            mapping_ready<=0;map_cursor<=0;map_count<=0;valid_mask<=0;
            front_pending<=0;front_reserved<=0;front_pic<=0;front_index<=0;front_mode<=0;
            front_slot<=0;front_generation<=0;presentation_serial<=0;publication_wait<=0;retire_mask<=0;
            load_start<=0;load_index<=0;write_buf_idx<=0;disp_buf_idx<=0;loading_pic<=0;
            write_identity<=0;display_identity<=0;display_valid<=0;publish_pulse<=0;
            load_busy<=0;source_done_seen<=0;write_done_seen<=0;if(!R4) write_timer<=0;fault_locked<=0;error_code<=0;
            wish0<=0;wish1<=0;plan_pic<=0;plan_mode<=0;plan_valid<=0;scan_pic<=0;scan_left<=0;scan_phase<=0;
            selection_epoch<=0;
            for(i=0;i<4;i=i+1) begin slot_pic[i]<=0;slot_generation[i]<=0;next_generation[i]<=1;rank[i]<=i;end
            for(i=0;i<16;i=i+1) compact[i]<=0;
        end else begin
            load_start<=0;publish_pulse<=0;
            if(extra_changed) selection_epoch<=selection_epoch+1'b1;
            if(catalog_ready && !mapping_ready) begin
                if(map_cursor==16) mapping_ready<=1;
                else begin
                    compact[map_cursor[3:0]]<=map_count[3:0];map_cursor<=map_cursor+1'b1;
                    if(available_mask[map_cursor[3:0]]) map_count<=map_count+1'b1;
                end
            end
            if(plan_changed) begin
                selection_epoch<=selection_epoch+1'b1;
                plan_valid<=planning_valid;plan_pic<=planning_pic;plan_mode<=planning_mode;wish0<=0;wish1<=0;
                scan_pic<=planning_pic==16 ? 5'd1 : planning_pic+1'b1;scan_left<=16;
                scan_phase<=planning_valid && (planning_mode==0 || planning_mode==2) ? 1 : 0;
            end else if(scan_phase!=0) begin
                selection_epoch<=selection_epoch+1'b1;
                if(eligible) begin
                    if(scan_phase==1) begin wish0<=scan_pic;scan_phase<=2;end
                    else begin wish1<=scan_pic;scan_phase<=0;end
                end
                scan_pic<=scan_pic==16 ? 5'd1 : scan_pic+1'b1;scan_left<=scan_left-1'b1;
                if(scan_left<=1) scan_phase<=0;
            end
            if(source_failed && !fault_locked) begin
                fault_locked<=1;error_code<=source_error;
                if(load_busy) valid_mask[write_buf_idx]<=0;
            end else if(!fault_locked) begin
                if(publication_wait && presented_match_q) begin
                    publication_wait<=0;retire_mask<=0;
                    selection_epoch<=selection_epoch+1'b1;
                end
                if(command_valid && command_ready) begin
                    selection_epoch<=selection_epoch+1'b1;
                    front_pending<=1;front_reserved<=0;front_pic<=command_pic;front_index<=command_index;
                    front_mode<=command_mode;presentation_serial<=presentation_serial+1'b1;
                end else if(!(R4 && (pause_background || foreground_claim)) && command_ready && display_valid && view_valid && view_pic==display_identity[28:24] &&
                    view_mode!=display_identity[30:29]) begin
                    front_pending<=1;front_reserved<=1;front_pic<=view_pic;front_mode<=view_mode;
                    front_slot<=disp_buf_idx;front_generation<=slot_generation[disp_buf_idx];
                    presentation_serial<=presentation_serial+1'b1;
                    selection_epoch<=selection_epoch+1'b1;
                end
                if(load_busy) begin
                    if(!R4) write_timer<=write_timer+1'b1;
                    if(source_success && source_number==loading_pic) source_done_seen<=1;
                    if(write_finish_pulse) write_done_seen<=1;
                    if((source_done_seen || (source_success && source_number==loading_pic)) && (write_done_seen || write_finish_pulse)) begin
                        load_busy<=0;valid_mask[write_buf_idx]<=1;if(!R4) write_timer<=0;
                        selection_epoch<=selection_epoch+1'b1;
                    end else if(write_timer>=WRITE_FINISH_TIMEOUT-1) begin
                        fault_locked<=1;error_code<=8'h42;valid_mask[write_buf_idx]<=0;
                    end
                end
                if(front_pending && !front_reserved) begin
                    if(decision_ready && hit_front_q) begin
                        front_slot<=front_hit_slot_q;front_generation<=hit_generation_q;front_reserved<=1;
                        selection_epoch<=selection_epoch+1'b1;
                    end else if(R4 ? (decision_ready && loading_matches_front_q) : (load_busy && loading_pic==front_pic)) begin
                        front_slot<=write_buf_idx;front_generation<=slot_generation[write_buf_idx];front_reserved<=1;
                        selection_epoch<=selection_epoch+1'b1;
                    end else if(decision_ready && !load_busy && source_idle && victim_front_q) begin
                        begin_load(front_pic,front_index,free_front_slot_q,front_generation_q,front_next_generation_q);
                        front_slot<=free_front_slot_q;front_generation<=front_generation_q;front_reserved<=1;
                    end
                end
                if(front_pending && front_reserved && publication_qualified) begin
                    retire_mask<=display_valid ? (4'b0001<<disp_buf_idx) : 4'd0;
                    display_identity<=prepared_identity;disp_buf_idx<=front_slot;display_valid<=1;
                    front_pending<=0;front_reserved<=0;publication_wait<=1;publish_pulse<=1;
                    selection_epoch<=selection_epoch+1'b1;
                end
                if(!(R4 && pause_background) && !front_pending && background_context_ok && !command_valid && !load_busy && source_idle && mapping_ready &&
                    scan_phase==0 && decision_ready && background_nonzero_q && victim_background_q) begin
                    begin_load(background_pic_q,compact[background_pic_q-1'b1],free_background_slot_q,background_generation_q,background_next_generation_q);
                end
                if(publication_wait && presented_match_q) touch(disp_buf_idx);
                else if(load_busy && (source_done_seen || (source_success && source_number==loading_pic)) &&
                    (write_done_seen || write_finish_pulse)) touch(write_buf_idx);
            end
        end
    end
endmodule
