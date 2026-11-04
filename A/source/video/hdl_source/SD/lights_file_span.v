module lights_file_span #(
    parameter integer POSITION_BITS=32,
    parameter integer INDEX_BITS=24,
    parameter integer ANCHOR_SHIFT=20,
    parameter [31:0] MIN_FILE_BYTES=0,
    parameter [31:0] MAX_FILE_BYTES=32'hffffffff,
    parameter integer STRICT_RANGE=0,
    parameter integer BYTE_STALL_LIMIT=100_000_000,
    parameter integer COMPACT_FONT=0
)(
    input wire [7:0] request_tag,
    input wire [3:0] sector_fault,
    output reg accepted,
    output reg [7:0] response_tag,
    output reg [3:0] status,
    output wire [9:0] count,
    output reg eof,
    input wire clk,rst,mounted,found,duplicate,
    input wire [31:0] first_cluster,file_size,fat_base,data_base,max_cluster,
    input wire [32:0] volume_end,
    input wire [3:0] cluster_shift,
    output reg ready,unavailable,chain_fault,
    input wire start,cancel,
    input wire [31:0] offset,
    input wire [9:0] length,
    output wire idle,
    output reg done,good,
    output wire byte_valid,
    output wire [8:0] byte_index,
    output wire [7:0] byte_data,
    input wire byte_ready,
    output wire sector_request,
    output wire [31:0] sector_lba,
    input wire sector_grant,sector_done,
    output reg sector_release,
    output reg [8:0] buffer_addr,
    output reg anchor_we,
    output reg [2:0] anchor_write_address,
    output reg [27:0] anchor_write_data,
    output wire anchor_read,
    output wire [2:0] anchor_read_address,
    input wire [27:0] anchor_read_data,
    input wire [7:0] buffer_byte
);
    localparam WAIT_MOUNT=0,CHAIN_BEGIN=1,CHAIN_FAT=2,REQ=3,WAIT_SECTOR=4,
        ADDR=5,WAIT_BYTE=6,USE_BYTE=7,FAT_EVAL=8,READY=9,SEEK=10,
        SEEK_FAT=11,DATA_SUB=12,DATA_SHIFT=13,DATA_ADD=14,DATA_CHECK=15,
        NEXT_DATA=16,FINISH=17,STOP=18,RANGE_BEGIN=19,FAT_CHECK=20,FAT_ADVANCE=21,RANGE_ANCHOR=22,ANCHOR_WAIT=23,
        LBA_TEST=24,DATA_COMMIT=25;
    localparam CHAIN=0,SEEK_KIND=1,DATA=2;
    reg [4:0] state;
    reg [1:0] kind;
    reg [27:0] cursor,next_cluster;
    reg [INDEX_BITS-1:0] cursor_index,target_index,chain_count;
    assign anchor_read=state==RANGE_ANCHOR;
    assign anchor_read_address=(target_index >> ANCHOR_SHIFT);
    reg [31:0] fat_value;reg [POSITION_BITS-1:0] position;
    reg [9:0] remaining,emitted,chunk;
    reg [8:0] begin_byte,read_index;
    reg [9:0] read_count;
    reg read_last_q,lba_valid_q;
    reg [31:0] relative;
    reg [32:0] cluster_lba_storage,lba_wide;reg [POSITION_BITS:0] range_end;
    wire [32:0] cluster_lba=COMPACT_FONT ? lba_wide : cluster_lba_storage;
    reg [31:0] sector_lba_storage;
    assign sector_lba=COMPACT_FONT ? lba_wide[31:0] : sector_lba_storage;
    reg cancelling;
    reg [3:0] fat_byte;
    reg [POSITION_BITS-1:0] requested_offset;reg bad_offset;reg [2:0] shift_left;reg [6:0] sector_mask;
    reg [9:0] requested_length;
    reg next_valid,last_cluster,end_marker;
    reg [31:0] snap_first,snap_size,snap_fat,snap_data,snap_max;
    reg [32:0] snap_end;reg [3:0] snap_shift;
    wire [31:0] d_first=COMPACT_FONT ? first_cluster : snap_first;
    wire [31:0] d_size=COMPACT_FONT ? file_size : snap_size;
    wire [31:0] d_fat=COMPACT_FONT ? fat_base : snap_fat;
    wire [31:0] d_data=COMPACT_FONT ? data_base : snap_data;
    wire [31:0] d_max=COMPACT_FONT ? max_cluster : snap_max;
    wire [32:0] d_end=COMPACT_FONT ? volume_end : snap_end;
    wire [3:0] d_shift=COMPACT_FONT ? cluster_shift : snap_shift;
    reg [31:0] stall_timer;
    reg [9:0] transferred;
    assign count=transferred;
    wire valid_next=fat_value[27:0]>=2 && fat_value[27:0]<=d_max &&
        fat_value[27:0]<28'hffffff0 && fat_value[27:0]!=cursor;
    assign idle=state==READY;
    assign sector_request=state==REQ && lba_valid_q && sector_fault==0;
    assign byte_valid=state==USE_BYTE && kind==DATA && !cancelling && !cancel;
    assign byte_index=emitted[8:0];
    assign byte_data=buffer_byte;
    integer n;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=WAIT_MOUNT;ready<=0;unavailable<=0;chain_fault<=0;
            cursor<=0;cursor_index<=0;target_index<=0;chain_count<=0;next_cluster<=0;
            position<=0;remaining<=0;emitted<=0;chunk<=0;fat_value<=0;kind<=CHAIN;
            sector_lba_storage<=0;sector_release<=0;buffer_addr<=0;begin_byte<=0;read_index<=0;
            read_count<=0;read_last_q<=0;lba_valid_q<=0;relative<=0;cluster_lba_storage<=0;lba_wide<=0;range_end<=0;
            cancelling<=0;done<=0;good<=0;fat_byte<=0;requested_offset<=0;requested_length<=0;bad_offset<=0;shift_left<=0;sector_mask<=0;
            next_valid<=0;last_cluster<=0;end_marker<=0;
            anchor_we<=0;anchor_write_address<=0;anchor_write_data<=0;
            accepted<=0;response_tag<=0;status<=0;eof<=0;stall_timer<=0;transferred<=0;
            snap_first<=0;snap_size<=0;snap_fat<=0;snap_data<=0;snap_max<=0;snap_end<=0;snap_shift<=0;
        end else begin
            sector_release<=0;done<=0;anchor_we<=0;accepted<=0;
            if(byte_valid && byte_ready)transferred<=transferred+1'b1;
            if(cancel && kind!=CHAIN && state!=READY) cancelling<=1;
            case(state)
                WAIT_MOUNT: if(mounted) begin
                    snap_first<=first_cluster;snap_size<=file_size;snap_fat<=fat_base;snap_data<=data_base;
                    snap_max<=max_cluster;snap_end<=volume_end;snap_shift<=cluster_shift;
                    if(!found || duplicate || file_size<MIN_FILE_BYTES || file_size>MAX_FILE_BYTES ||
                        (POSITION_BITS<32 && (file_size >> POSITION_BITS)!=0) || cluster_shift>7 ||
                        (file_size!=0 && (first_cluster<2 || first_cluster>max_cluster || first_cluster>=32'h0ffffff0))) begin
                        unavailable<=1;state<=STOP;
                    end else if(file_size==0) begin ready<=1;state<=READY;end
                    else begin
                        chain_count<=(({1'b0,file_size}-33'd1)>>9>>cluster_shift)+1;
                        sector_mask<=7'h7f>>(7-cluster_shift);
                        state<=CHAIN_BEGIN;
                    end
                end
                CHAIN_BEGIN: begin
                    cursor<=d_first[27:0];cursor_index<=0;anchor_we<=1;anchor_write_address<=0;anchor_write_data<=d_first[27:0];
                    kind<=CHAIN;state<=CHAIN_FAT;
                end
                CHAIN_FAT,SEEK_FAT: begin
                    lba_wide<={1'b0,d_fat}+{12'd0,cursor[27:7]};
                    sector_lba_storage<=d_fat+{11'd0,cursor[27:7]};
                    begin_byte<={cursor[6:0],2'b0};read_index<=0;read_count<=4;
                    fat_value<=0;state<=LBA_TEST;
                end
                LBA_TEST: begin lba_valid_q<=!lba_wide[32] && lba_wide<d_end;state<=REQ;end
                REQ: begin
                    if(!lba_valid_q) begin chain_fault<=1;state<=STOP;end
                    else if(sector_grant) state<=WAIT_SECTOR;
                    else if(cancelling && kind!=CHAIN) state<=FINISH;
                end
                WAIT_SECTOR: if(sector_done) state<=ADDR;
                ADDR: begin buffer_addr<=begin_byte+read_index;state<=WAIT_BYTE;end
                WAIT_BYTE: begin read_last_q<=({1'b0,read_index}+10'd1==read_count);state<=USE_BYTE;end
                USE_BYTE: if(kind==DATA && !byte_ready && !cancelling) begin
                    stall_timer<=stall_timer+1'b1;
                    if(stall_timer>=BYTE_STALL_LIMIT-1) begin cancelling<=1;status<=3;end
                end else begin
                    stall_timer<=0;
                    if(kind!=DATA) fat_value[read_index[1:0]*8 +: 8]<=buffer_byte;
                    else begin position<=position+1'b1;emitted<=emitted+1'b1;remaining<=remaining-1'b1;end
                    if(read_last_q) begin
                        sector_release<=1;state<=kind==DATA ? NEXT_DATA : FAT_EVAL;
                    end else begin read_index<=read_index+1'b1;state<=ADDR;end
                end
                FAT_EVAL: begin
                    next_valid<=valid_next;
                    last_cluster<=cursor_index+1==chain_count;
                    end_marker<=fat_value[27:0]>=28'hffffff8;
                    state<=FAT_CHECK;
                end
                FAT_CHECK: begin
                    if(cancelling && kind!=CHAIN) state<=FINISH;
                    else if(kind==CHAIN) begin
                        if(last_cluster) begin
                            if(!end_marker) begin chain_fault<=1;state<=STOP;end
                            else begin ready<=1;state<=READY;end
                        end else if(!next_valid) begin chain_fault<=1;status<=4;done<=1;state<=STOP;end
                        else state<=FAT_ADVANCE;
                    end else if(!next_valid) begin chain_fault<=1;status<=4;done<=1;state<=STOP;end
                    else state<=FAT_ADVANCE;
                end
                FAT_ADVANCE: begin
                    cursor<=fat_value[27:0];cursor_index<=cursor_index+1'b1;
                    if(kind==CHAIN) begin
                        for(n=1;n<8;n=n+1)
                            if(cursor_index==n*(1<<ANCHOR_SHIFT)-1) begin
                                anchor_we<=1;anchor_write_address<=n;anchor_write_data<=fat_value[27:0];
                            end
                        state<=CHAIN_FAT;
                    end else state<=SEEK;
                end
                READY: if(start) begin
                    accepted<=1;response_tag<=request_tag;status<=0;eof<=0;stall_timer<=0;transferred<=0;
                    requested_offset<=offset[POSITION_BITS-1:0];bad_offset<=|(offset >> POSITION_BITS);
                    requested_length<=length;
                    range_end<={1'b0,offset[POSITION_BITS-1:0]}+length;
                    good<=0;emitted<=0;cancelling<=cancel;
                    state<=RANGE_BEGIN;
                end
                RANGE_BEGIN: begin
                    if(bad_offset || requested_length>512 ||
                       (STRICT_RANGE && (requested_length==0 || range_end>d_size)) ||
                       (!STRICT_RANGE && (requested_offset>d_size || range_end[POSITION_BITS]))) begin
                        status<=1;
                        if(STRICT_RANGE) begin unavailable<=1;state<=STOP;end
                        else state<=FINISH;
                    end else if(cancelling) begin status<=2;state<=FINISH;end
                    else if(requested_length==0 || requested_offset==d_size) begin
                        good<=1;eof<=requested_offset==d_size;state<=FINISH;
                    end else begin
                        position<=requested_offset;
                        remaining<=range_end>d_size ? d_size-requested_offset : requested_length;
                        eof<=range_end>=d_size;
                        target_index<=requested_offset[POSITION_BITS-1:9]>>d_shift;
                        kind<=SEEK_KIND;state<=RANGE_ANCHOR;
                        if(cursor_index<=(requested_offset[POSITION_BITS-1:9]>>d_shift) &&
                           (cursor_index>>ANCHOR_SHIFT)==((requested_offset[POSITION_BITS-1:9]>>d_shift)>>ANCHOR_SHIFT)) state<=SEEK;
                    end
                end
                RANGE_ANCHOR: state<=ANCHOR_WAIT;
                ANCHOR_WAIT: begin
                    cursor_index<=(target_index>>ANCHOR_SHIFT)<<ANCHOR_SHIFT;
                    cursor<=anchor_read_data;state<=SEEK;
                end
                SEEK: begin
                    if(cancelling) state<=FINISH;
                    else if(cursor_index==target_index) state<=DATA_SUB;
                    else state<=SEEK_FAT;
                end
                DATA_SUB: begin
                    if(COMPACT_FONT) lba_wide<={5'd0,cursor}-33'd2;
                    else cluster_lba_storage<={5'd0,cursor}-33'd2;
                    shift_left<=d_shift[2:0];state<=DATA_SHIFT;
                end
                DATA_SHIFT: begin
                    if(shift_left==0) state<=DATA_ADD;
                    else begin
                        if(COMPACT_FONT) lba_wide<=cluster_lba<<1;
                        else cluster_lba_storage<=cluster_lba<<1;
                        shift_left<=shift_left-1'b1;
                    end
                end
                DATA_ADD: begin
                    lba_wide<={1'b0,d_data}+cluster_lba+{26'd0,(position[15:9]&sector_mask)};
                    state<=DATA_CHECK;
                end
                DATA_CHECK: begin lba_valid_q<=!lba_wide[32] && lba_wide<d_end;state<=DATA_COMMIT;end
                DATA_COMMIT: begin
                    if(!lba_valid_q) begin chain_fault<=1;state<=STOP;end
                    else begin
                        sector_lba_storage<=lba_wide[31:0];begin_byte<=position[8:0];read_index<=0;
                        read_count<=remaining<(10'd512-{1'b0,position[8:0]}) ? remaining : 10'd512-{1'b0,position[8:0]};
                        kind<=DATA;state<=REQ;
                    end
                end
                NEXT_DATA: begin
                    if(cancelling) state<=FINISH;
                    else if(remaining==0) begin good<=1;state<=FINISH;end
                    else begin
                        target_index<=position[POSITION_BITS-1:9]>>d_shift[2:0];
                        kind<=SEEK_KIND;state<=SEEK;
                    end
                end
                FINISH: begin
                    done<=1;
                    if(cancelling || cancel)begin good<=0;if(status==0)status<=2;end
                    state<=READY;
                end
                STOP: begin ready<=0;end
                default: begin chain_fault<=1;state<=STOP;end
            endcase
            if(sector_fault!=0 && state!=STOP) begin
                ready<=0;chain_fault<=1;status<=5;done<=state!=WAIT_MOUNT;
                good<=0;state<=STOP;
            end
        end
    end
endmodule
