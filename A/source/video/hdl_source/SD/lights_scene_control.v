`timescale 1ns/1ps
module lights_scene_control #(
    parameter integer CLK_FREQ_HZ=100_000_000,AUTO_PLAY_MS=1000,HINT_MS=1000,EXPLAIN_MS=2500,CAPTION_SYNC=0,FRAME_IDENTITY=0,R4=0,R5=0
)(
    input wire clk,rst,catalog_ready,
    input wire normal_advance,
    input wire [15:0] available_mask,
    input wire [4:0] normal_count,
    input wire next_press,prev_press,short_press,chord_press,confirm_short,
    input wire [31:0] published_identity,presented_identity,
    input wire presented_identity_valid,
    output wire [1:0] requested_mode,
    output wire foreground_claim,
    output wire foreground_present_wait,
    output wire select_cancel,
    output reg [31:0] shown_identity,
    input wire caption_commit_ready,
    output wire [1:0] caption_banks,
    input wire command_ready,publish_pulse,published_bank,fault_locked,play_started,
    input wire presented_bank_async,presented_valid_async,
    output wire command_valid,
    output reg [3:0] command_index,
    output wire [4:0] query_number,
    input wire query_valid,
    input wire [3:0] query_load_index,
    output reg auto_play_en,
    output reg [1:0] shown_mode,
    output reg [4:0] shown_pic,
    output reg shown_valid,
    output reg shown_bank,
    output wire explain_active,
    output wire no_product_hint,confirm_ready
);
    localparam [1:0] NORMAL=0,SELECT=1,EXPLAIN=2;
    localparam [2:0] IDLE=0,SCAN=1,MAP=2,ISSUE=3,WAIT_PUBLISH=4,WAIT_PRESENT=5,SCAN_CHECK=6;
    localparam [2:0] NONE=0,NEXT=1,PREV=2,ENTER=3,EXIT=4,RETURN_SELECT=5;
    localparam integer AUTO_CYCLES=(CLK_FREQ_HZ/1000)*AUTO_PLAY_MS;
    localparam integer EXPLAIN_CYCLES=(CLK_FREQ_HZ/1000)*EXPLAIN_MS;
    localparam integer DWELL_CYCLES=AUTO_CYCLES>EXPLAIN_CYCLES ? AUTO_CYCLES : EXPLAIN_CYCLES;
    localparam integer HINT_CYCLES=(CLK_FREQ_HZ/1000)*HINT_MS;
    localparam integer AUTO_BITS=DWELL_CYCLES<2 ? 1 : $clog2(DWELL_CYCLES+1);
    localparam integer HINT_BITS=HINT_CYCLES<2 ? 1 : $clog2(HINT_CYCLES+1);
    (* syn_preserve=1 *) reg [2:0] presented_bank_sync,presented_valid_sync;
    reg [2:0] state,pending_op;
    reg [1:0] target_mode;
    reg [4:0] target_pic,cursor,remaining;
    reg scan_prev,expected_bank,exit_in_progress;
    reg [31:0] expected_identity;
    reg presented_matches_expected_q;
    always @(posedge clk or posedge rst) begin
        if(rst) presented_matches_expected_q<=0;
        else presented_matches_expected_q<=state==WAIT_PRESENT &&
             presented_identity_valid && presented_identity==expected_identity;
    end

    assign requested_mode=target_mode;
    assign foreground_claim=state!=IDLE;
    assign foreground_present_wait=state==WAIT_PRESENT;
    wire select_exit_request=R4 && target_mode==SELECT &&
        (pending_op==EXIT || (!exit_in_progress && chord_press && catalog_ready && normal_count!=0));
    assign select_cancel=state==WAIT_PUBLISH && select_exit_request;
    reg [AUTO_BITS-1:0] auto_count;
    reg [HINT_BITS-1:0] hint_count;
    wire products_available=available_mask[3] || available_mask[6] || available_mask[9];
    wire [1:0] intended_mode=state==IDLE ? shown_mode : target_mode;
    wire [4:0] main_pic=shown_pic<=6 ? 5'd4 : shown_pic<=9 ? 5'd7 : 5'd10;
    wire is_normal=cursor<=3 || cursor>=13;
    wire is_main=cursor==4 || cursor==7 || cursor==10;
    wire eligible=available_mask[cursor-5'd1] &&
        (target_mode==NORMAL ? is_normal : target_mode==SELECT ? is_main : 1'b1);
    reg eligible_q;
    reg [4:0] explain_remaining_q;
    wire [4:0] dwell_pic=state==WAIT_PRESENT ? target_pic : shown_pic;
    wire [1:0] dwell_mode=state==WAIT_PRESENT ? target_mode : shown_mode;
    reg [4:0] browse_next_q,browse_prev_q;
    always @(posedge clk or posedge rst) begin
        if(rst) begin eligible_q<=0;explain_remaining_q<=0;browse_next_q<=1;browse_prev_q<=16;end
        else begin
            if(state==SCAN) eligible_q<=eligible;
            explain_remaining_q<=(dwell_pic==4 || dwell_pic==7 || dwell_pic==10) ? 5'd2 :
                                 (dwell_pic==5 || dwell_pic==8 || dwell_pic==11) ? 5'd1 : 5'd0;
            browse_next_q<=dwell_pic==(dwell_mode==SELECT ? 5'd10 : 5'd16) ?
                           (dwell_mode==SELECT ? 5'd4 : 5'd1) : dwell_pic+1'b1;
            browse_prev_q<=dwell_pic==(dwell_mode==SELECT ? 5'd4 : 5'd1) ?
                           (dwell_mode==SELECT ? 5'd10 : 5'd16) : dwell_pic-1'b1;
        end
    end
    wire settled=shown_valid && state==IDLE && pending_op==NONE && command_ready;
    wire auto_tick=auto_count>=AUTO_CYCLES-1;
    wire explain_more=shown_pic==4 ? (available_mask[4] || available_mask[5]) :
        shown_pic==5 ? available_mask[5] :
        shown_pic==7 ? (available_mask[7] || available_mask[8]) :
        shown_pic==8 ? available_mask[8] :
        shown_pic==10 ? (available_mask[10] || available_mask[11]) :
        shown_pic==11 ? available_mask[11] : 1'b0;
    wire explain_tick=auto_count>=EXPLAIN_CYCLES-1;
    wire normal_due=R5 ? (shown_mode==NORMAL && normal_advance && normal_count>1) :
        (shown_mode==NORMAL && auto_play_en && play_started && auto_tick && normal_count>1 && !short_press);
    wire explain_due=shown_mode==EXPLAIN && explain_more && explain_tick;
    reg [2:0] event_op,chosen_op;
    assign explain_active=shown_valid && shown_mode==EXPLAIN && !fault_locked &&
        (R5 || (intended_mode==EXPLAIN && pending_op!=EXIT && pending_op!=RETURN_SELECT && event_op!=EXIT && event_op!=RETURN_SELECT));
    assign query_number=target_pic;
    wire same_role_target=(state==MAP || state==ISSUE || state==WAIT_PUBLISH || state==WAIT_PRESENT) &&
        target_mode==EXPLAIN && target_pic>shown_pic && target_pic<=main_pic+5'd2 && target_pic>=main_pic;
    assign caption_banks=explain_active ?
        ((shown_bank ? 2'b10 : 2'b01) | (same_role_target ? (shown_bank ? 2'b01 : 2'b10) : 2'b00)) : 2'b00;
    reg caption_ready_stage;
    always @(posedge clk or posedge rst) begin
        if(rst) caption_ready_stage<=0;
        else caption_ready_stage<=caption_commit_ready;
    end
    wire issue_authorized=!CAPTION_SYNC || (FRAME_IDENTITY ? caption_ready_stage : caption_commit_ready);
    assign command_valid=state==ISSUE && !fault_locked && issue_authorized;
    assign no_product_hint=hint_count!=0;
    assign confirm_ready=settled && shown_mode==SELECT && !fault_locked;

    generate if(R4) begin : g_dwell_pipeline
        reg reset_count;
        always @(posedge clk or posedge rst) begin
            if(rst) begin reset_count<=1;auto_count<=0;end
            else begin
                reset_count<=fault_locked || !(settled && chosen_op==NONE &&
                    ((!R5 && shown_mode==NORMAL && auto_play_en && play_started && normal_count>1 && !short_press) ||
                     (shown_mode==EXPLAIN && explain_more)));
                if(reset_count) auto_count<=0;
                else auto_count<=auto_count+1'b1;
            end
        end
    end endgenerate

    always @* begin
        event_op=NONE;
        if(!exit_in_progress && chord_press && catalog_ready && normal_count!=0) begin
            if(intended_mode!=NORMAL) event_op=EXIT;
            else if(products_available) event_op=ENTER;
        end else if(!exit_in_progress && short_press && intended_mode==EXPLAIN) event_op=RETURN_SELECT;
        else if(!exit_in_progress && next_press && intended_mode!=EXPLAIN) event_op=NEXT;
        else if(!exit_in_progress && prev_press && intended_mode!=EXPLAIN) event_op=PREV;
        chosen_op=pending_op;
        if(event_op==EXIT || (event_op!=NONE && pending_op!=EXIT)) chosen_op=event_op;
    end
    wire exit_now=!exit_in_progress && chord_press && catalog_ready &&
                  normal_count!=0 && intended_mode!=NORMAL;
    wire [2:0] launch_op=R4 ? (exit_now ? EXIT : pending_op) : chosen_op;
    wire gesture_safe=!R4 || !(next_press || prev_press || short_press || chord_press) || exit_now;
    always @(posedge clk or posedge rst) begin
        if(rst) begin presented_bank_sync<=0; presented_valid_sync<=0; end
        else begin
            presented_bank_sync<={presented_bank_sync[1:0],presented_bank_async};
            presented_valid_sync<={presented_valid_sync[1:0],presented_valid_async};
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE; pending_op<=NONE; target_mode<=NORMAL; target_pic<=0;
            cursor<=0; remaining<=0; scan_prev<=0; expected_bank<=0; exit_in_progress<=0;
            expected_identity<=0;shown_identity<=0;
            command_index<=0; auto_play_en<=1; shown_mode<=NORMAL;
            shown_pic<=0; shown_valid<=0; shown_bank<=0; if(!R4) auto_count<=0; hint_count<=0;
        end else begin
            if(hint_count!=0) hint_count<=hint_count-1'b1;
            if(!fault_locked) begin
                if(chord_press && catalog_ready && normal_count!=0 &&
                    intended_mode==NORMAL && !products_available) hint_count<=HINT_CYCLES;
                if(event_op!=NONE && (pending_op!=EXIT || event_op==EXIT)) pending_op<=event_op;
                if(short_press && shown_mode==NORMAL && intended_mode==NORMAL && !exit_in_progress &&
                    catalog_ready && normal_count!=0)
                    auto_play_en<=~auto_play_en;
                if(settled && chosen_op==NONE &&
                    ((!R5 && shown_mode==NORMAL && auto_play_en && play_started && normal_count>1 && !short_press) ||
                     (shown_mode==EXPLAIN && explain_more))) begin
                    if(!(shown_mode==NORMAL ? auto_tick : explain_tick)) if(!R4) auto_count<=auto_count+1'b1;
                end else if(!R4) auto_count<=0;
                if(FRAME_IDENTITY && state==IDLE && presented_identity_valid &&
                    presented_identity==published_identity && presented_identity[28:24]==shown_pic &&
                    presented_identity[30:29]==shown_mode) shown_identity<=presented_identity;
                case(state)
                    IDLE: begin
                        if(catalog_ready && normal_count!=0 && command_ready && !shown_valid) begin
                            target_mode<=NORMAL; cursor<=1; remaining<=16; scan_prev<=0; state<=SCAN;
                            if(!R4) auto_count<=0;
                        end else if(settled && confirm_short && shown_mode==SELECT && event_op==NONE) begin
                            if(R4) begin target_pic<=shown_pic;target_mode<=EXPLAIN;state<=MAP;end
                            else begin shown_mode<=EXPLAIN; target_mode<=EXPLAIN;end
                            if(!R4) auto_count<=0;
                        end else if(catalog_ready && shown_valid && command_ready && gesture_safe &&
                            (launch_op!=NONE || normal_due || explain_due)) begin
                            pending_op<=NONE; scan_prev<=0; if(!R4) auto_count<=0; state<=SCAN;
                            cursor<=launch_op==PREV ? browse_prev_q : browse_next_q;
                            if(launch_op==EXIT) begin
                                target_mode<=NORMAL; cursor<=1; remaining<=16; auto_play_en<=1; exit_in_progress<=1;
                            end else if(launch_op==ENTER || launch_op==RETURN_SELECT) begin
                                target_mode<=SELECT; cursor<=4; remaining<=7; auto_play_en<=0;
                            end else begin
                                target_mode<=shown_mode;
                                scan_prev<=launch_op==PREV;
                                if(shown_mode==NORMAL) begin
                                    remaining<=16;
                                end else if(shown_mode==SELECT) begin
                                    remaining<=7;
                                end else begin
                                    remaining<=explain_remaining_q;
                                end
                            end
                        end
                    end
                    SCAN: state<=SCAN_CHECK;
                    SCAN_CHECK: begin
                        if(eligible_q) begin
                            target_pic<=cursor;
                            if(shown_valid && cursor==shown_pic && (!R4 || target_mode==shown_mode) && !(R5 && target_mode==NORMAL)) begin shown_mode<=target_mode; state<=IDLE; exit_in_progress<=0; end
                            else state<=MAP;
                        end else if(remaining<=1) begin
                            state<=IDLE;
                        end else begin
                            state<=SCAN;
                            remaining<=remaining-1'b1;
                            if(scan_prev) cursor<=cursor==(target_mode==SELECT ? 5'd4 : 5'd1) ?
                                (target_mode==SELECT ? 5'd10 : 5'd16) : cursor-1'b1;
                            else cursor<=cursor==(target_mode==SELECT ? 5'd10 : 5'd16) ?
                                (target_mode==SELECT ? 5'd4 : 5'd1) : cursor+1'b1;
                        end
                    end
                    MAP: begin
                        if(query_valid) begin command_index<=query_load_index; state<=ISSUE; end
                    end
                    ISSUE: if(command_ready && issue_authorized) state<=WAIT_PUBLISH;
                    WAIT_PUBLISH: if(select_cancel) begin
                        pending_op<=NONE;target_mode<=NORMAL;cursor<=1;remaining<=16;scan_prev<=0;auto_play_en<=1;exit_in_progress<=1;state<=SCAN;
                    end else if(publish_pulse) begin expected_bank<=published_bank; expected_identity<=published_identity; state<=WAIT_PRESENT; end
                    WAIT_PRESENT: if(FRAME_IDENTITY ? (R4 ? presented_matches_expected_q : (presented_identity_valid && presented_identity==expected_identity)) :
                        (presented_valid_sync[2] && presented_bank_sync[2]==expected_bank)) begin
                        shown_identity<=expected_identity;
                        shown_pic<=target_pic; shown_mode<=target_mode; shown_valid<=1; shown_bank<=expected_bank; state<=IDLE; exit_in_progress<=0;
                    end
                    default: state<=IDLE;
                endcase
            end else begin pending_op<=NONE; if(!R4) auto_count<=0; hint_count<=0; end
        end
    end
endmodule
