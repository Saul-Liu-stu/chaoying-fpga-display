module lights_font_cache_ce #(
    parameter integer WAIT_CYCLES=1_600_000_000
)(
    input wire clk,rst,mounted,clock_enable,
    input wire text_we,
    input wire [7:0] text_address,
    input wire [15:0] text_point,
    input wire [2:0] text_ready,
    input wire [20:0] text_lengths,
    input wire anchor_we,anchor_read,
    input wire [2:0] anchor_write_address,anchor_read_address,
    input wire [27:0] anchor_write_data,
    output wire [27:0] anchor_read_data,
    input wire file_ready,file_unavailable,file_idle,file_done,file_good,file_byte_valid,
    input wire [8:0] file_byte_index,
    input wire [7:0] file_byte,
    input wire [31:0] file_size,
    output reg file_start,file_cancel,
    output reg [31:0] file_offset,
    output reg [9:0] file_length,
    input wire request_toggle,cancel_toggle,request_expired,
    input wire [55:0] request_payload,
    output reg response_toggle,response_good,font_bad,
    output wire map_cache_we,
    output wire [6:0] map_cache_address,
    output wire [4:0] map_cache_slot,
    output reg [31:0] response_mask,
    output reg cache_we,
    output reg [9:0] cache_address,
    output reg [23:0] cache_row,
    output wire [2:0] invalid_roles
);
    localparam IDLE=0,HEADER_START=1,READ_FILE=2,HEADER_CHECK=3,
        MAP_ADDR=4,MAP_WAIT=5,MAP_CAPTURE=6,MAP_CRC1=7,MAP_CRC2=8,MAP_START=9,MAP_CHECK=10,MAP_NEXT=11,
        WINDOW_BEGIN=12,BODY_ADDR=13,BODY_WAIT=14,BODY_CAPTURE=15,
        SLOT_FIND=16,VICTIM=17,GLYPH_START=18,GLYPH_CHECK=19,JOB_NEXT=20,MAP_COMMIT=21,SLOT_READ=22,SLOT_COMPARE=23,GLYPH_PUBLISH=24,SLOT_WAIT=25;
    localparam HEADER=0,INDEX=1,GLYPH=2;
    reg [4:0] state;
    reg [1:0] job;
    (* ram_style="block",syn_ramstyle="block_ram" *) reg [31:0] body[0:255];
    reg [7:0] body_addr,body_write_addr;
    reg [31:0] body_q,body_write_value;
    reg body_we;
    wire body_read=anchor_read || state==MAP_WAIT || state==BODY_WAIT || state==SLOT_WAIT;
    always @(posedge clk) if(clock_enable) begin
        if(body_read) body_q<=body[anchor_read ? {5'b11100,anchor_read_address} : body_addr];
        if(text_we) body[text_address]<={text_point,16'hffff};
        else if(anchor_we) body[{5'b11100,anchor_write_address}]<={4'd0,anchor_write_data};
        else if(body_we) body[body_write_addr]<=body_write_value;
    end
    assign anchor_read_data=body_q[27:0];
    (* syn_preserve=1 *) reg [2:0] request_sync,cancel_sync;
    reg request_seen,cancel_seen,view_pending,disabled_valid;
    reg [7:0] wanted_generation,disabled_generation,work_generation;
    reg [1:0] wanted_role,work_role,map_role;
    reg [6:0] wanted_first,wanted_count,work_first,work_count;
    reg work_token,background;
    reg [31:0] pins,published_mask,work_mask,view_timer;
    reg map_we;
    reg [5:0] map_write_index;
    reg [4:0] map_write_slot;
    assign map_cache_we=map_we && !background;
    assign map_cache_address={work_token,map_write_index};
    assign map_cache_slot=map_write_slot;
    reg [5:0] work_position;
    reg [7:0] body_position;
    reg work_finished;
    wire [6:0] map_count=text_lengths[map_role*7 +: 7];
    reg [6:0] map_progress[0:2];
    reg [2:0] map_done,map_invalid;
    assign invalid_roles=map_done & map_invalid;
    reg [15:0] expected_point,index_id,index_stored,index_crc;reg [12:0] expected_id;
    reg [15:0] glyph_point,glyph_id,glyph_count;
    reg [31:0] crc,stored_crc,header_size;
    reg header_bad,header_ready;
    reg [1:0] row_phase;
    reg [4:0] row_number,slot_scan,chosen_slot,victim_cursor,victim_scan;
    reg [5:0] victim_steps;
    reg [23:0] row_hold;
    reg [31:0] slot_valid;
    reg [12:0] selected_tag;reg selected_valid,slot_match;
    wire [31:0] protected_slots=pins|published_mask|work_mask;
    function [31:0] crc32_byte;
        input [31:0] value;input [7:0] data;
        reg [31:0] v;integer i;
        begin v=value^{24'd0,data};for(i=0;i<8;i=i+1)v=v[0] ? (v>>1)^32'hedb88320 : v>>1;crc32_byte=v;end
    endfunction
    function [15:0] crc16_byte;
        input [15:0] value;input [7:0] data;
        reg [15:0] v;integer i;
        begin v=value^{data,8'd0};for(i=0;i<8;i=i+1)v=v[15] ? (v<<1)^16'h1021 : v<<1;crc16_byte=v;end
    endfunction
    function [7:0] header_expected;
        input [8:0] index;
        begin
            case(index)
                0:header_expected="L";1:header_expected="T";2:header_expected="F";
                3:header_expected="2";4:header_expected="4";5:header_expected="R";6:header_expected="3";
                8:header_expected=1;10,12:header_expected=24;14:header_expected=26;
                16:header_expected=96;18:header_expected=8'hf4;19:header_expected=1;
                20:header_expected=80;25,33:header_expected=2;30:header_expected=1;34:header_expected=4;
                default:header_expected=0;
            endcase
        end
    endfunction
    reg byte_valid_q,done_q,good_q;
    reg [8:0] byte_index_q;
    reg [7:0] byte_q;
    always @(posedge clk or posedge rst) begin
        if(rst)begin byte_valid_q<=0;done_q<=0;good_q<=0;byte_index_q<=0;byte_q<=0;end
        else if(clock_enable) begin
            byte_valid_q<=file_byte_valid;done_q<=file_done;good_q<=file_good;
            if(file_byte_valid)begin byte_index_q<=file_byte_index;byte_q<=file_byte;end
        end
    end
    integer n;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE;job<=HEADER;file_start<=0;file_cancel<=0;file_offset<=0;file_length<=0;
            body_addr<=0;body_we<=0;body_write_addr<=0;body_write_value<=0;
            request_sync<=0;cancel_sync<=0;request_seen<=0;cancel_seen<=0;response_toggle<=0;
            response_good<=0;response_mask<=0;font_bad<=0;
            view_pending<=0;disabled_valid<=0;disabled_generation<=0;wanted_generation<=0;work_generation<=0;
            wanted_role<=0;work_role<=0;map_role<=0;wanted_first<=0;wanted_count<=0;work_first<=0;work_count<=0;
            work_token<=0;background<=0;pins<=0;published_mask<=0;work_mask<=0;view_timer<=0;work_position<=0;
            body_position<=0;work_finished<=0;
            map_we<=0;map_write_index<=0;map_write_slot<=0;
            map_done<=0;map_invalid<=0;expected_point<=0;expected_id<=0;index_id<=0;index_stored<=0;index_crc<=0;
            glyph_point<=0;glyph_id<=0;glyph_count<=0;crc<=0;stored_crc<=0;header_size<=0;header_bad<=0;header_ready<=0;
            row_phase<=0;row_number<=0;slot_scan<=0;chosen_slot<=0;victim_cursor<=0;victim_scan<=0;victim_steps<=0;
            selected_tag<=0;selected_valid<=0;slot_match<=0;
            row_hold<=0;slot_valid<=0;cache_we<=0;cache_address<=0;cache_row<=0;
            for(n=0;n<3;n=n+1)map_progress[n]<=0;

        end else if(clock_enable) begin
            file_start<=0;body_we<=0;cache_we<=0;map_we<=0;
            request_sync<={request_sync[1:0],request_toggle};cancel_sync<={cancel_sync[1:0],cancel_toggle};
            if(file_idle) file_cancel<=0;
            if(file_unavailable) font_bad<=1;
            if(view_pending) view_timer<=view_timer+1'b1;
            if(request_sync[2]!=request_seen && !view_pending) begin
                request_seen<=request_sync[2];
                if(request_expired)begin
                    response_good<=0;response_mask<=0;response_toggle<=request_sync[2];
                    pins<=0;published_mask<=0;view_pending<=0;
                end else begin
                    {wanted_generation,wanted_role,wanted_first,wanted_count,pins}<=request_payload;
                    published_mask<=0;view_pending<=1;view_timer<=0;
                end
                if(disabled_valid && request_payload[55:48]!=disabled_generation) disabled_valid<=0;
            end
            if(mounted) map_done<=map_done|~text_ready;
            case(state)
                IDLE: if(file_idle) begin
                    if(file_ready && !header_ready && !font_bad) state<=HEADER_START;
                    else if(header_ready && !font_bad) begin
                        if(view_pending && (disabled_valid && wanted_generation==disabled_generation ||
                            map_done[wanted_role] && map_invalid[wanted_role])) begin
                            response_good<=0;response_mask<=0;response_toggle<=request_seen;view_pending<=0;
                        end else if(view_pending && map_done[wanted_role]) state<=WINDOW_BEGIN;
                        else if(view_pending && !map_done[wanted_role]) begin map_role<=wanted_role;state<=MAP_ADDR;end
                        else if(map_done!=3'b111) begin
                            map_role<=!map_done[0] ? 0 : !map_done[1] ? 1 : 2;state<=MAP_ADDR;
                        end
                    end
                end
                HEADER_START: begin
                    file_offset<=0;file_length<=512;file_start<=1;job<=HEADER;
                    crc<=32'hffffffff;stored_crc<=0;header_bad<=0;state<=READ_FILE;
                end
                READ_FILE: begin
                    if(byte_valid_q) begin
                        if(job==HEADER) begin
                            if(byte_index_q<508) crc<=crc32_byte(crc,byte_q);
                            else stored_crc<={byte_q,stored_crc[31:8]};
                            if(byte_index_q==22 || byte_index_q==23) glyph_count<={byte_q,glyph_count[15:8]};
                            else if(byte_index_q>=36 && byte_index_q<=39) header_size<={byte_q,header_size[31:8]};
                            else if(byte_index_q<508 && byte_q!=header_expected(byte_index_q)) header_bad<=1;
                        end else if(job==INDEX) begin
                            if(byte_index_q<2) begin index_id<={byte_q,index_id[15:8]};index_crc<=crc16_byte(index_crc,byte_q);end
                            else index_stored<={byte_q,index_stored[15:8]};
                        end else begin
                            if(byte_index_q<4 || byte_index_q>=8) crc<=crc32_byte(crc,byte_q);
                            if(byte_index_q<2) glyph_point<={byte_q,glyph_point[15:8]};
                            else if(byte_index_q<4) glyph_id<={byte_q,glyph_id[15:8]};
                            else if(byte_index_q<8) stored_crc<={byte_q,stored_crc[31:8]};
                            else begin
                                row_hold<={row_hold[15:0],byte_q};
                                if(row_phase==2) begin
                                    cache_we<=1;cache_address<=({5'd0,chosen_slot}<<4)+({5'd0,chosen_slot}<<3)+row_number;
                                    cache_row<={row_hold[15:0],byte_q};row_phase<=0;row_number<=row_number+1'b1;
                                end else row_phase<=row_phase+1'b1;
                            end
                        end
                    end
                    if(done_q) begin
                        if(!good_q) state<=IDLE;
                        else state<=job==HEADER ? HEADER_CHECK : job==INDEX ? MAP_CHECK : GLYPH_CHECK;
                    end
                end
                HEADER_CHECK: begin
                    if(header_bad || (crc^32'hffffffff)!=stored_crc || glyph_count==0 || glyph_count>8192 ||
                        header_size!=file_size || header_size!=262656+({16'd0,glyph_count}<<6)+({16'd0,glyph_count}<<4)) font_bad<=1;
                    else header_ready<=1;
                    state<=IDLE;
                end
                MAP_ADDR: begin body_addr<={map_role,map_progress[map_role][5:0]};state<=MAP_WAIT;end
                MAP_WAIT: state<=MAP_CAPTURE;
                MAP_CAPTURE: begin expected_point<=body_q[31:16];index_crc<=16'hffff;state<=MAP_CRC1;end
                MAP_CRC1: begin index_crc<=crc16_byte(index_crc,expected_point[7:0]);state<=MAP_CRC2;end
                MAP_CRC2: begin index_crc<=crc16_byte(index_crc,expected_point[15:8]);state<=MAP_START;end
                MAP_START: if(file_idle) begin
                    file_offset<=512+{14'd0,expected_point,2'b0};file_length<=4;file_start<=1;
                    job<=INDEX;index_id<=0;index_stored<=0;state<=READ_FILE;
                end
                MAP_CHECK: begin
                    if(index_crc!=index_stored || (index_id!=16'hffff && index_id>=glyph_count)) begin font_bad<=1;state<=IDLE;end
                    else if(index_id==16'hffff) begin map_invalid[map_role]<=1;map_done[map_role]<=1;state<=IDLE;end
                    else begin
                        body_we<=1;body_write_addr<={map_role,map_progress[map_role][5:0]};
                        body_write_value<={expected_point,index_id};state<=MAP_NEXT;
                    end
                end
                MAP_NEXT: begin
                    map_progress[map_role]<=map_progress[map_role]+1'b1;
                    if(map_progress[map_role]+1'b1==map_count) map_done[map_role]<=1;
                    state<=IDLE;
                end
                WINDOW_BEGIN: begin
                    work_generation<=wanted_generation;work_token<=request_seen;work_role<=wanted_role;
                    work_first<=wanted_first;work_count<=wanted_count;work_position<=0;
                    body_position<={1'b0,wanted_first};work_finished<=0;
                    work_mask<=0;background<=0;state<=BODY_ADDR;
                end
                BODY_ADDR: begin
                    if(body_position>=work_count || work_position>=(background ? 32 : 24)) begin
                        work_finished<=1;state<=JOB_NEXT;
                    end
                    else begin body_addr<={work_role,body_position[5:0]};state<=BODY_WAIT;end
                end
                BODY_WAIT: state<=BODY_CAPTURE;
                BODY_CAPTURE: begin
                    expected_point<=body_q[31:16];expected_id<=body_q[12:0];slot_scan<=0;state<=SLOT_READ;
                end
                SLOT_READ: begin body_addr<={3'b110,slot_scan};state<=SLOT_WAIT;end
                SLOT_WAIT: state<=SLOT_COMPARE;
                SLOT_COMPARE: begin slot_match<=slot_valid[slot_scan] && body_q[12:0]==expected_id[12:0];state<=SLOT_FIND;end
                SLOT_FIND: begin
                    if(slot_match) begin
                        map_we<=1;map_write_index<=body_position[5:0];map_write_slot<=slot_scan;
                        work_mask[slot_scan]<=1;
                        work_position<=work_position+1'b1;body_position<=body_position+1'b1;state<=MAP_COMMIT;
                    end else if(slot_scan==31) begin victim_scan<=victim_cursor;victim_steps<=0;state<=VICTIM;end
                    else begin slot_scan<=slot_scan+1'b1;state<=SLOT_READ;end
                end
                VICTIM: begin
                    if(!protected_slots[victim_scan]) begin
                        chosen_slot<=victim_scan;slot_valid[victim_scan]<=0;victim_cursor<=victim_scan+1'b1;state<=GLYPH_START;
                    end else if(victim_steps==31 && background) state<=IDLE;
                    else begin victim_scan<=victim_scan+1'b1;victim_steps<=victim_steps+1'b1;end
                end
                GLYPH_START: if(file_idle) begin
                    file_offset<=262656+({19'd0,expected_id}<<6)+({19'd0,expected_id}<<4);
                    file_length<=80;file_start<=1;job<=GLYPH;crc<=32'hffffffff;stored_crc<=0;
                    glyph_point<=0;glyph_id<=0;row_phase<=0;row_number<=0;row_hold<=0;state<=READ_FILE;
                end
                GLYPH_CHECK: begin
                    if(glyph_point!=expected_point || glyph_id!=expected_id || (crc^32'hffffffff)!=stored_crc || row_number!=24) begin
                        font_bad<=1;state<=IDLE;
                    end else state<=GLYPH_PUBLISH;
                end
                GLYPH_PUBLISH: begin
                        body_we<=1;body_write_addr<={3'b110,chosen_slot};body_write_value<={19'd0,expected_id[12:0]};
                        slot_valid[chosen_slot]<=1;
                        map_we<=1;map_write_index<=body_position[5:0];map_write_slot<=chosen_slot;
                        work_mask[chosen_slot]<=1;
                        work_position<=work_position+1'b1;body_position<=body_position+1'b1;state<=MAP_COMMIT;
                end
                MAP_COMMIT: begin
                    work_finished<=body_position>=work_count || work_position>=(background ? 32 : 24);
                    state<=JOB_NEXT;
                end
                JOB_NEXT: begin
                    if((!background && (!view_pending || work_token!=request_seen)) || (background && view_pending)) state<=IDLE;
                    else if(work_finished) begin
                        if(!background) begin
                            response_mask<=work_mask;published_mask<=work_mask;
                            response_good<=1;response_toggle<=request_seen;view_pending<=0;
                            background<=1;work_position<=24;body_position<={1'b0,work_first}+8'd24;state<=BODY_ADDR;
                        end else state<=IDLE;
                    end else state<=BODY_ADDR;
                end
                default: begin font_bad<=1;state<=IDLE;end
            endcase
            if(font_bad && view_pending) begin
                response_good<=0;response_mask<=0;response_toggle<=request_seen;view_pending<=0;
                published_mask<=0;work_mask<=0;file_cancel<=1;state<=IDLE;
            end else if(view_pending && view_timer>=WAIT_CYCLES-1) begin
                response_good<=0;response_mask<=0;response_toggle<=request_seen;view_pending<=0;
                disabled_valid<=1;disabled_generation<=wanted_generation;
                published_mask<=0;work_mask<=0;
                if(job==GLYPH) file_cancel<=1;
                state<=IDLE;
            end
            if(cancel_sync[2]!=cancel_seen) begin
                cancel_seen<=cancel_sync[2];pins<=0;published_mask<=0;work_mask<=0;
                if(view_pending) begin
                    response_good<=0;response_mask<=0;response_toggle<=request_seen;view_pending<=0;
                end
                if(job==GLYPH) file_cancel<=1;
                if(job==GLYPH)state<=IDLE;
            end
        end
    end
endmodule
