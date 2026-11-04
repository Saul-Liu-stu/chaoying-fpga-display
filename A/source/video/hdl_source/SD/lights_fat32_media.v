`timescale 1ns/1ps
module lights_fat32_media #(
    parameter integer MAX_IMAGES=4,
    parameter integer VARIABLE_BMP=0,
    parameter integer CAPTIONS=0,
    parameter integer TF_FONT=0,
    parameter integer SHARED_SERVICE=0,
    parameter integer MEDIA_QUOTA=2,
    parameter integer INIT_TIMEOUT=500_000_000,
    parameter integer SECTOR_TIMEOUT=100_000_000,
    parameter integer HANDSHAKE_TIMEOUT=200_000_000,
    parameter integer CATALOG_TIMEOUT=2_000_000_000,
    parameter integer FILE_TIMEOUT=1_000_000_000,
    parameter integer ROOT_SECTOR_LIMIT=4096,
    parameter integer ROOT_CLUSTER_LIMIT=128
)(
    input wire clk, rst, sd_init_done,
    input wire [15:0] bmp_width, bmp_height,
    output wire idle,
    output reg catalog_ready,
    output reg [4:0] image_count,
    output reg [15:0] catalog_mask, // bit n: PIC(n+1) actually included in compact playlist
    output reg [7:0] error_code,
    output reg fault_present, // Same-edge sticky equivalent of fault_present.
    output wire [3:0] state_code,
    input wire load_start,
    input wire [3:0] load_index,
    output reg [4:0] source_number,
    output wire source_success,
    output wire write_req,
    input wire write_req_ack,
    output wire image_begin,image_stream_open,
    output wire [10:0] source_width,source_height,
    input wire pixel_ready,
    output wire pixel_valid,
    output wire [23:0] pixel,
    output wire sd_read,
    output wire [31:0] sd_lba,
    input wire [7:0] sd_byte,
    output wire caption_we,
    output wire [7:0] caption_address,
    output wire [15:0] caption_glyph,
    output reg [2:0] caption_ready,
    output reg [20:0] caption_lengths,
    output reg [23:0] caption_errors,
    input wire font_request, font_release, font_chain_fault,
    input wire [31:0] font_lba,
    input wire [8:0] font_buffer_addr,
    output wire font_grant,font_sector_done,
    output wire [7:0] font_buffer_byte,
    output reg font_found,font_duplicate,
    output reg [31:0] font_cluster,font_size,
    output wire [31:0] font_fat_base,font_data_base,font_max_cluster,
    output wire [32:0] font_volume_end,
    output wire [3:0] font_cluster_shift,
    input wire service_request,service_release,service_chain_fault,
    input wire [31:0] service_lba,
    input wire [8:0] service_buffer_addr,
    output wire service_grant,service_done,
    output wire [7:0] service_buffer_byte,
    input wire sd_valid, sd_end
);
    localparam INIT=0, READ_REQ=1, READ_WAIT=2, BYTE_ADDR=3, BYTE_WAIT=4, BYTE_USE=5,
        BOOT_TEST=6, MBR_INIT=7, MBR_ENTRY=8, MBR_END=9, BPB_BASIC=10,
        LAYOUT1=11, LAYOUT2=12, LAYOUT3=13, LAYOUT4=14, LAYOUT5=15,
        ROOT_BEGIN=16, VISIT_BEGIN=17, VISIT_ADDR=18, VISIT_WAIT=19,
        VISIT_TEST=20, VISIT_SAVE=21, FAT_ADDRESS=22, FAT_PARSE=23,
        DATA_SHIFT=24, DATA_ADD=25, DATA_RANGE=26, DIR_ENTRY=27,
        DIR_SAVE=28, DIR_RESUME=29, DIR_NEXT=30, PRE_BEGIN=31, PRE_NEXT=32,
        FILE_BEGIN=33, HEADER_BEGIN=34, HEADER_CHECK=35, HEADER_WAIT=36,
        FRAME_BEGIN=37, FRAME_WAIT=38, FILE_REPLAY=39, FILE_NEXT=40,
        BUILD_BEGIN=41, BUILD_ENTRY=42, READY=43, FILE_END=44, FILE_SUCCESS=45,
        LOCKED=46, MBR_RANGE=47, DESCRIPTOR_WAIT=48, DESCRIPTOR_TEST=49,
        DATA_CHECK=50, DATA_SUB=51, BPB_EVAL=52, DESCRIPTOR_EVAL=53, DESCRIPTOR_CHECK=54,
        DIR_SLOT=55, VISIT_EVAL=56, LAYOUT_EVAL=57,
        TXT_SAVE=58, TXT_SELECT=59, TXT_BEGIN=60, TXT_FINISH=61, TXT_WAIT=62, TXT_NEXT=63, TXT_DESCRIPTOR_READ=64, TXT_DESCRIPTOR_EVAL=65, TXT_DESCRIPTOR_TEST=66, FILE_EVAL=67, FAT_EVAL=68, TXT_BYTE_USE=69, BYTE_CAPTURE=70;
    localparam BOOT_BYTES=0, DIRECTORY_BYTES=1, FAT_BYTES=2, HEADER_BYTES=3, FILE_BYTES=4, TEXT_BYTES=5;
    reg [73:0] state, return_state, visit_return;
    reg [2:0] byte_mode;
    reg [8:0] byte_index, last_byte;
    (* syn_preserve=1 *) reg [8:0] boot_index;
    reg visit_invalid;
    reg sector_start;
    reg [31:0] request_lba;
    wire sector_idle, sector_done,guard_idle,guard_done;
    wire [3:0] sector_fault;
    reg [8:0] buffer_addr;
    wire [7:0] buffer_byte;
    (* syn_preserve=1, syn_keep=1 *) reg [7:0] parse_byte_q;
    always @(posedge clk or posedge rst) begin
        if(rst) parse_byte_q<=0;
        else parse_byte_q<=buffer_byte;
    end
    wire [7:0] parse_byte=VARIABLE_BMP ? parse_byte_q : buffer_byte;
    wire [1:0] sector_owner;
    wire font_owner=sector_owner==2;
    wire media_grant,schedule_start;
    wire [31:0] schedule_lba;
    wire [8:0] schedule_address;
    wire safe_boundary=catalog_ready && (state[READ_REQ] || (state[READY] && !load_start));
    reg font_request_q,more_sectors_q,next_eoc_q;

    assign sector_idle=guard_idle && sector_owner==0;
    assign font_buffer_byte=buffer_byte;
    assign service_buffer_byte=buffer_byte;
    lights_sector_scheduler #(.MEDIA_QUOTA(MEDIA_QUOTA),.AUX_ENABLE(SHARED_SERVICE)) u_schedule(
        .clk(clk),.rst(rst),.guard_idle(guard_idle),.guard_done(guard_done),.guard_fault(sector_fault),
        .media_request(state[READ_REQ]),.media_release(state[READ_REQ] || state[READY]),
        .font_request(TF_FONT && (VARIABLE_BMP ? font_request_q : font_request) && safe_boundary && !fault_present),.font_release(font_release),
        .aux_request(SHARED_SERVICE && service_request && safe_boundary && !fault_present),.aux_release(SHARED_SERVICE && service_release),
        .media_lba(request_lba),.font_lba(font_lba),.aux_lba(SHARED_SERVICE ? service_lba : 32'd0),
        .media_address(buffer_addr),.font_address(font_buffer_addr),.aux_address(SHARED_SERVICE ? service_buffer_addr : 9'd0),
        .media_grant(media_grant),.font_grant(font_grant),.aux_grant(service_grant),
        .media_done(sector_done),.font_done(font_sector_done),.aux_done(service_done),
        .start(schedule_start),.lba(schedule_lba),.address(schedule_address),.owner_debug(sector_owner));
    lights_sector_guard #(.TIMEOUT_CYCLES(SECTOR_TIMEOUT)) u_sector (
        .clk(clk),.rst(rst),.start(schedule_start),.lba(schedule_lba),
        .idle(guard_idle),.done(guard_done),.fault(sector_fault),
        .buffer_addr(schedule_address),.buffer_byte(buffer_byte),
        .sd_read(sd_read),.sd_lba(sd_lba),.sd_byte(sd_byte),.sd_valid(sd_valid),.sd_end(sd_end)
    );

    reg [31:0] init_timer, operation_timer;
    reg catalog_expired, file_expired;
    reg from_mbr;
    reg [31:0] partition_lba, partition_size;
    reg [32:0] partition_end;
    reg [15:0] signature, bytes_per_sector, reserved_sectors, root_entries,
        total16, fat16, ext_flags, fs_version;
    reg [7:0] jump0, jump2, sectors_per_cluster, fat_count;
    reg [31:0] total_sectors, fat_sectors, bpb_root, hidden_sectors;
    reg [7:0] mbr_type[0:3], mbr_status[0:3];
    reg [31:0] mbr_lba, mbr_size;
    reg [2:0] partition_index, partition_matches;
    reg mbr_protective_q,mbr_fat_q,mbr_status_bad_q,mbr_last_q;
    reg [31:0] mbr_lba_q,mbr_size_q;
    reg [3:0] cluster_shift;
    reg [32:0] fat_span, relative_data, volume_end, data_wide;
    reg [31:0] data_sectors, cluster_count, max_cluster, fat_base, data_base;
    assign font_fat_base=fat_base; assign font_data_base=data_base;
    assign font_max_cluster=max_cluster; assign font_volume_end=volume_end;
    assign font_cluster_shift=cluster_shift;
    reg [39:0] fat_capacity;
    reg [4:0] bpb_invalid;
    reg [39:0] required_fat_entries;
    reg [4:0] layout_invalid;

    reg [27:0] current_cluster, next_cluster;
    reg [27:0] hare_cluster;reg [1:0] hare_phase;reg hare_ended;

    wire [27:0] fat_cursor=hare_phase!=0 ? hare_cluster : current_cluster;
    reg [31:0] fat_value;
    reg fat_text_invalid,fat_chain_invalid;
    reg fat_eoc_q,fat_meets_next_q;
    reg partition_zero_q;
    localparam DATA_EVAL=71,VISIT_DECIDE=72,MBR_DECIDE=73;reg request_outside_q;
    reg [8:0] fat_offset;
    reg [32:0] cluster_offset, cluster_lba;
    reg [27:0] cluster_minus_two;
    reg [32:0] request_wide;
    reg [31:0] file_remaining;
    reg [7:0] sector_in_cluster;
    reg [12:0] root_sector_count;
    reg [11:0] visited_count, visited_index;
    localparam integer VISITED_DEPTH=VARIABLE_BMP && ROOT_CLUSTER_LIMIT<2048 ?
        (ROOT_CLUSTER_LIMIT<2 ? 2 : ROOT_CLUSTER_LIMIT) : 2048;
    localparam integer VISITED_BITS=$clog2(VISITED_DEPTH);
    (* ram_style="block", syn_ramstyle="block_ram" *) reg [27:0] visited[0:VISITED_DEPTH-1];
    reg [27:0] visited_value;
    reg visited_match,visited_last;
    wire visited_read=state[VISIT_ADDR];
    always @(posedge clk) begin
        if(visited_read) visited_value<=visited[visited_index[VISITED_BITS-1:0]];
        if(state[VISIT_SAVE]) visited[visited_count[VISITED_BITS-1:0]]<=current_cluster;
    end

    reg [87:0] directory_name;
    reg [7:0] directory_attr;
    reg [31:0] directory_cluster, directory_size;
    reg [15:0] candidate_mask, good_mask;
    reg [15:0] pre_scan_mask,build_scan_mask;
    reg candidate_duplicate;
    (* ram_style="block", syn_ramstyle="block_ram" *) reg [59:0] descriptors[0:15];
    reg [59:0] descriptor_read;
    reg descriptor_invalid;
    reg [3:0] playlist[0:15];
    reg [3:0] slot;
    reg [4:0] pre_index, build_index;
    reg had_bad_header, file_mode, precheck;
    reg [31:0] file_size, file_position;
    reg file_at_end;
    always @(posedge clk) begin
        if(state[DESCRIPTOR_WAIT]) descriptor_read<=descriptors[slot];
        if(state[DIR_SAVE] && !candidate_duplicate)
            descriptors[slot]<={directory_cluster[27:0],directory_size};
    end
    wire [4:0] directory_number = directory_name[31:24]==8'h31 ?
        (5'd10 + directory_name[39:32] - 8'h30) : (directory_name[39:32] - 8'h30);
    wire target_name = directory_name[23:0]==24'h434950 &&
        (directory_name[31:24]==8'h30 || directory_name[31:24]==8'h31) &&
        directory_name[39:32]>=8'h30 && directory_name[39:32]<=8'h39 &&
        directory_name[63:40]==24'h202020 && directory_name[87:64]==24'h504d42 &&
        directory_number>=1 && directory_number<=16;


    reg [27:0] text_clusters[0:2];
    reg [31:0] text_sizes[0:2];
    reg [2:0] text_found,text_duplicate;
    reg [1:0] text_role;
    reg text_mode,text_start,text_finish,text_descriptor_bad;
    wire floyd=VARIABLE_BMP && file_mode && !precheck && !text_mode;
    wire text_done,text_good,text_byte_ready;
    wire [6:0] text_count;
    wire [15:0] text_glyph;
    wire [5:0] text_index;
    wire text_we;
    wire font_name=directory_name[47:0]==48'h3432544e4f46 &&
        directory_name[63:48]==16'h2020 && directory_name[87:64]==24'h4e4942;
    wire text_name=directory_name[31:0]==32'h30425553 &&
        directory_name[39:32]>=8'h31 && directory_name[39:32]<=8'h33 &&
        directory_name[63:40]==24'h202020 && directory_name[87:64]==24'h545854;
    lights_text_decode u_text(.clk(clk),.rst(rst),.start(text_start),.finish(text_finish),
        .file_bytes(file_size[9:0]),.byte_valid(state[TXT_BYTE_USE]),
        .byte_data(parse_byte),.byte_ready(text_byte_ready),.done(text_done),.good(text_good),
        .count(text_count),.glyph_we(text_we),.glyph_index(text_index),.glyph_id(text_glyph));
    assign caption_we=text_we;
    assign caption_address={text_role,text_index};
    assign caption_glyph=text_glyph;

    reg header_begin, header_check, frame_begin, stream_success, abort_frame;
    always @(posedge clk or posedge rst) begin
        if(rst) begin font_request_q<=0;more_sectors_q<=0;next_eoc_q<=0;end
        else begin
            font_request_q<=font_request;
            more_sectors_q<=sector_in_cluster+1'b1<sectors_per_cluster;
            next_eoc_q<=next_cluster>=28'hffffff8;
        end
    end
    wire header_checked, header_good, pixels_enabled;
    wire [31:0] pixel_offset;
    wire [3:0] bmp_fault;wire bmp_byte_ready;
    reg bmp_header_valid,bmp_payload_valid;
    assign image_begin=frame_begin;assign image_stream_open=pixels_enabled;
    lights_bmp_gate #(.HANDSHAKE_TIMEOUT(HANDSHAKE_TIMEOUT),.VARIABLE_BMP(VARIABLE_BMP)) u_bmp (
        .clk(clk),.rst(rst),.header_begin(header_begin),
        .header_valid(bmp_header_valid),
        .header_index(byte_index[5:0]),.header_byte(parse_byte),.header_check(header_check),
        .directory_size(file_size),.width(bmp_width),.height(bmp_height),
        .header_checked(header_checked),.header_good(header_good),.pixel_offset(pixel_offset),
        .frame_begin(frame_begin),.write_req(write_req),.write_req_ack(write_req_ack),
        .pixels_enabled(pixels_enabled),.source_width(source_width),.source_height(source_height),
        .pixel_ready(pixel_ready),.byte_ready(bmp_byte_ready),
        .byte_valid(bmp_payload_valid),
        .byte_data(parse_byte),.byte_offset(file_position),.stream_success(stream_success),
        .abort_frame(abort_frame),.pixel_valid(pixel_valid),.pixel(pixel),
        .source_success(source_success),.fault(bmp_fault)
    );
    assign idle=state[READY] && !fault_present;
    assign state_code=fault_present ? 4'hf :
        (state[INIT] ? 4'h0 : (!catalog_ready ? 4'h2 :
        (state[READY] ? 4'h1 : (state[FRAME_BEGIN] || state[FRAME_WAIT] ? 4'h3 : 4'h4))));

    wire data_outside=VARIABLE_BMP ? request_outside_q : (request_wide>=volume_end || request_wide[32]);
    wire error_init=state[INIT] && !sd_init_done && init_timer>=INIT_TIMEOUT-1;
    wire error_boot=state[BOOT_TEST] && signature!=16'haa55;
    wire error_mbr=state[MBR_DECIDE] && (mbr_protective_q || (mbr_fat_q && mbr_status_bad_q));
    wire error_mbr_count=state[MBR_END] && partition_matches!=1;
    wire error_mbr_range=state[MBR_RANGE] && ((VARIABLE_BMP ? partition_zero_q : (partition_lba==0 || partition_size==0)) || (partition_end[32] && partition_end[31:0]!=0));
    wire error_bpb=state[BPB_BASIC] && (|bpb_invalid);
    wire error_layout2=state[LAYOUT2] && (relative_data>=total_sectors || volume_end>33'h100000000);
    wire error_layout=state[LAYOUT_EVAL] && (|layout_invalid);
    wire error_visit=(state[VISIT_EVAL] && visit_invalid) || (state[VISIT_DECIDE] && visited_match);
    wire error_floyd=state[FAT_PARSE] && floyd && !fat_eoc_q && (fat_chain_invalid || (hare_phase==1 && fat_meets_next_q));
    wire error_fat=state[FAT_PARSE] && !floyd && !(text_mode && fat_text_invalid) && !(VARIABLE_BMP ? fat_eoc_q : fat_value[27:0]>=28'hffffff8) && fat_chain_invalid && !(file_mode && precheck);
    wire error_data=state[DATA_CHECK] && data_outside && !text_mode;
    wire error_root_limit=state[DATA_CHECK] && !data_outside && !file_mode && root_sector_count>=ROOT_SECTOR_LIMIT;
    wire error_duplicate=state[DIR_SAVE] && candidate_duplicate;
    wire error_descriptor=state[DESCRIPTOR_CHECK] && descriptor_invalid && !precheck;
    wire error_header=state[HEADER_WAIT] && header_checked && !precheck && !header_good;
    wire error_early_eoc=state[FILE_NEXT] && !file_at_end && !(VARIABLE_BMP ? more_sectors_q : (sector_in_cluster+1'b1<sectors_per_cluster)) && (VARIABLE_BMP ? next_eoc_q : (next_cluster>=28'hffffff8));
    wire error_empty=state[BUILD_ENTRY] && build_index[4] && image_count==0;
    wire error_invalid=state[HEADER_BEGIN] || !(|state);
    wire local_error_valid=error_init || error_boot || error_mbr || error_mbr_count || error_mbr_range || error_bpb || error_layout2 || error_layout || error_visit || error_floyd || error_fat || error_data || error_root_limit || error_duplicate || error_descriptor || error_header || error_early_eoc || error_empty || error_invalid;
    wire [7:0] local_error_word=
        ({8{error_init}} & (8'h01)) |
        ({8{error_boot}} & (8'h02)) |
        ({8{error_mbr}} & (8'h03)) |
        ({8{error_mbr_count}} & (partition_matches==0 ? 8'h03 : 8'h05)) |
        ({8{error_mbr_range}} & (8'h04)) |
        ({8{error_bpb}} & (8'h03)) |
        ({8{error_layout2}} & (8'h04)) |
        ({8{error_layout}} & (8'h04)) |
        ({8{error_visit}} & (file_mode ? 8'h0b : 8'h07)) |
        ({8{error_floyd}} & (8'h0b)) |
        ({8{error_fat}} & (file_mode ? 8'h0b : 8'h07)) |
        ({8{error_data}} & (8'h04)) |
        ({8{error_root_limit}} & (8'h06)) |
        ({8{error_duplicate}} & (8'h08)) |
        ({8{error_descriptor}} & (8'h0b)) |
        ({8{error_header}} & (8'h0c)) |
        ({8{error_early_eoc}} & (8'h0b)) |
        ({8{error_empty}} & (had_bad_header ? 8'h0a : 8'h09)) |
        ({8{error_invalid}} & (8'h0f));
    wire fatal_sector=sector_fault!=0;
    wire fatal_chain=(TF_FONT && font_chain_fault) || (SHARED_SERVICE && service_chain_fault);
    wire fatal_bmp=bmp_fault!=0;
    wire fatal_timeout=!state[INIT] && !state[READY] && (catalog_ready ? file_expired : catalog_expired);
    wire fatal_error_valid=!state[LOCKED] && (fatal_sector || fatal_chain || fatal_bmp || fatal_timeout);
    wire [7:0] fatal_error_word=
        ({8{fatal_sector}} & (8'h20 | {4'd0,sector_fault})) |
        ({8{!fatal_sector && fatal_chain}} & 8'h50) |
        ({8{!fatal_sector && !fatal_chain && fatal_bmp}} & (8'h30 | {4'd0,bmp_fault})) |
        ({8{!fatal_sector && !fatal_chain && !fatal_bmp && fatal_timeout}} & (catalog_ready ? 8'h41 : 8'h40));
    always @(posedge clk or posedge rst) begin
        if(rst) error_code<=0;
        else if(fatal_error_valid) error_code<=fatal_error_word;
        else if(local_error_valid) error_code<=local_error_word;
    end

    always @(posedge clk or posedge rst) begin
        if(rst) fault_present<=0;
        else if(fatal_error_valid || local_error_valid) fault_present<=1;
    end

    integer n;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=74'b1<<INIT; return_state<=0; visit_return<=0; byte_mode<=0;
            byte_index<=0; last_byte<=0; boot_index<=0; visit_invalid<=0;
            sector_start<=0; request_lba<=0; buffer_addr<=0;
            catalog_ready<=0; image_count<=0; catalog_mask<=0; source_number<=0;
            init_timer<=0; operation_timer<=0; catalog_expired<=0; file_expired<=0;
            from_mbr<=0; partition_lba<=0; partition_size<=0; partition_end<=0;partition_zero_q<=0;request_outside_q<=0;
            signature<=0; bytes_per_sector<=0; reserved_sectors<=0; root_entries<=0;
            total16<=0; fat16<=0; ext_flags<=0; fs_version<=0;
            jump0<=0; jump2<=0; sectors_per_cluster<=0; fat_count<=0;
            total_sectors<=0; fat_sectors<=0; bpb_root<=0; hidden_sectors<=0;
            partition_index<=0; partition_matches<=0;
            mbr_protective_q<=0;mbr_fat_q<=0;mbr_status_bad_q<=0;mbr_last_q<=0;mbr_lba<=0;mbr_size<=0;mbr_lba_q<=0;mbr_size_q<=0;
            cluster_shift<=0; bpb_invalid<=0;
            fat_span<=0; relative_data<=0; volume_end<=0; data_wide<=0;
            required_fat_entries<=0; layout_invalid<=0;
            data_sectors<=0; cluster_count<=0; max_cluster<=0; fat_base<=0; data_base<=0; fat_capacity<=0;
            current_cluster<=0; next_cluster<=0;hare_cluster<=0;hare_phase<=0;hare_ended<=0; fat_value<=0; fat_text_invalid<=0; fat_chain_invalid<=0; fat_eoc_q<=0;fat_meets_next_q<=0;fat_offset<=0;
            cluster_offset<=0; cluster_lba<=0; cluster_minus_two<=0; request_wide<=0;
            file_remaining<=0; sector_in_cluster<=0; root_sector_count<=0;
            visited_count<=0; visited_index<=0;visited_match<=0;visited_last<=0;
            directory_name<=0; directory_attr<=0; directory_cluster<=0; directory_size<=0;
            candidate_mask<=0; good_mask<=0;pre_scan_mask<=0;build_scan_mask<=0; candidate_duplicate<=0;
            slot<=0; pre_index<=0; build_index<=0; descriptor_invalid<=0;
            had_bad_header<=0; file_mode<=0; precheck<=0; file_size<=0; file_position<=0; file_at_end<=0;
            header_begin<=0; header_check<=0; frame_begin<=0; stream_success<=0; abort_frame<=0;
            bmp_header_valid<=0;bmp_payload_valid<=0;
            text_mode<=0; text_start<=0; text_finish<=0; text_role<=0; text_descriptor_bad<=0;
            font_found<=0; font_duplicate<=0; font_cluster<=0; font_size<=0;
            text_found<=0; text_duplicate<=0; caption_ready<=0; caption_lengths<=0; caption_errors<=24'h010101;
            for(n=0;n<3;n=n+1) begin text_clusters[n]<=0; text_sizes[n]<=0; end
            for(n=0;n<4;n=n+1) begin
                mbr_type[n]<=0; mbr_status[n]<=0;
            end
            for(n=0;n<16;n=n+1) playlist[n]<=0;
        end else begin
            text_start<=0; text_finish<=0;
            sector_start<=0; header_begin<=0; header_check<=0; frame_begin<=0;
            stream_success<=0; abort_frame<=0;
            bmp_header_valid<=(state[BYTE_CAPTURE] || (!VARIABLE_BMP && state[BYTE_WAIT])) && byte_mode==HEADER_BYTES;
            bmp_payload_valid<=((state[BYTE_CAPTURE] || (!VARIABLE_BMP && state[BYTE_WAIT])) && byte_mode==FILE_BYTES) ||
                (bmp_payload_valid && state[BYTE_USE] && !bmp_byte_ready);
            if(state[INIT] || state[READY] || state[LOCKED]) begin
                operation_timer<=0; catalog_expired<=0; file_expired<=0;
            end else begin
                operation_timer<=operation_timer+1'b1;
                catalog_expired<=operation_timer>=CATALOG_TIMEOUT-1;
                file_expired<=operation_timer>=FILE_TIMEOUT-1;
            end
            (* parallel_case = 1 *) case(1'b1)
                state[INIT]: begin
                    if(sd_init_done) begin
                        request_lba<=0; byte_mode<=BOOT_BYTES; byte_index<=0; last_byte<=511;
                        return_state<=74'b1<<BOOT_TEST; state<=74'b1<<READ_REQ;
                    end else if(init_timer>=INIT_TIMEOUT-1) begin state<=74'b1<<LOCKED; end
                    else init_timer<=init_timer+1'b1;
                end
                state[READ_REQ]: if(media_grant) begin sector_start<=1; state<=74'b1<<READ_WAIT; end
                state[READ_WAIT]: if(sector_done) state<=74'b1<<BYTE_ADDR;
                state[BYTE_ADDR]: begin
                    buffer_addr<=byte_index;
                    if(byte_mode==BOOT_BYTES) boot_index<=byte_index;
                    state<=74'b1<<BYTE_WAIT;
                end
                state[BYTE_WAIT]: state<=VARIABLE_BMP ? 74'b1<<BYTE_CAPTURE : (byte_mode==TEXT_BYTES ? 74'b1<<TXT_BYTE_USE : 74'b1<<BYTE_USE);
                state[BYTE_CAPTURE]: state<=byte_mode==TEXT_BYTES ? 74'b1<<TXT_BYTE_USE : 74'b1<<BYTE_USE;
                state[BYTE_USE]: if(byte_mode!=FILE_BYTES || bmp_byte_ready) begin
                    if(byte_mode==BOOT_BYTES) begin
                        case(boot_index)
                            0: jump0<=parse_byte;
                            2: jump2<=parse_byte;
                            11: bytes_per_sector[7:0]<=parse_byte;
                            12: bytes_per_sector[15:8]<=parse_byte;
                            13: sectors_per_cluster<=parse_byte;
                            14: reserved_sectors[7:0]<=parse_byte;
                            15: reserved_sectors[15:8]<=parse_byte;
                            16: fat_count<=parse_byte;
                            17: root_entries[7:0]<=parse_byte;
                            18: root_entries[15:8]<=parse_byte;
                            19: total16[7:0]<=parse_byte;
                            20: total16[15:8]<=parse_byte;
                            22: fat16[7:0]<=parse_byte;
                            23: fat16[15:8]<=parse_byte;
                            28: hidden_sectors[7:0]<=parse_byte;
                            29: hidden_sectors[15:8]<=parse_byte;
                            30: hidden_sectors[23:16]<=parse_byte;
                            31: hidden_sectors[31:24]<=parse_byte;
                            32: total_sectors[7:0]<=parse_byte;
                            33: total_sectors[15:8]<=parse_byte;
                            34: total_sectors[23:16]<=parse_byte;
                            35: total_sectors[31:24]<=parse_byte;
                            36: fat_sectors[7:0]<=parse_byte;
                            37: fat_sectors[15:8]<=parse_byte;
                            38: fat_sectors[23:16]<=parse_byte;
                            39: fat_sectors[31:24]<=parse_byte;
                            40: ext_flags[7:0]<=parse_byte;
                            41: ext_flags[15:8]<=parse_byte;
                            42: fs_version[7:0]<=parse_byte;
                            43: fs_version[15:8]<=parse_byte;
                            44: bpb_root[7:0]<=parse_byte;
                            45: bpb_root[15:8]<=parse_byte;
                            46: bpb_root[23:16]<=parse_byte;
                            47: bpb_root[31:24]<=parse_byte;
                            446: mbr_status[0]<=parse_byte;
                            450: mbr_type[0]<=parse_byte;
                            454: if(mbr_type[0]==8'h0b || mbr_type[0]==8'h0c) mbr_lba[7:0]<=parse_byte;
                            455: if(mbr_type[0]==8'h0b || mbr_type[0]==8'h0c) mbr_lba[15:8]<=parse_byte;
                            456: if(mbr_type[0]==8'h0b || mbr_type[0]==8'h0c) mbr_lba[23:16]<=parse_byte;
                            457: if(mbr_type[0]==8'h0b || mbr_type[0]==8'h0c) mbr_lba[31:24]<=parse_byte;
                            458: if(mbr_type[0]==8'h0b || mbr_type[0]==8'h0c) mbr_size[7:0]<=parse_byte;
                            459: if(mbr_type[0]==8'h0b || mbr_type[0]==8'h0c) mbr_size[15:8]<=parse_byte;
                            460: if(mbr_type[0]==8'h0b || mbr_type[0]==8'h0c) mbr_size[23:16]<=parse_byte;
                            461: if(mbr_type[0]==8'h0b || mbr_type[0]==8'h0c) mbr_size[31:24]<=parse_byte;
                            462: mbr_status[1]<=parse_byte;
                            466: mbr_type[1]<=parse_byte;
                            470: if(mbr_type[1]==8'h0b || mbr_type[1]==8'h0c) mbr_lba[7:0]<=parse_byte;
                            471: if(mbr_type[1]==8'h0b || mbr_type[1]==8'h0c) mbr_lba[15:8]<=parse_byte;
                            472: if(mbr_type[1]==8'h0b || mbr_type[1]==8'h0c) mbr_lba[23:16]<=parse_byte;
                            473: if(mbr_type[1]==8'h0b || mbr_type[1]==8'h0c) mbr_lba[31:24]<=parse_byte;
                            474: if(mbr_type[1]==8'h0b || mbr_type[1]==8'h0c) mbr_size[7:0]<=parse_byte;
                            475: if(mbr_type[1]==8'h0b || mbr_type[1]==8'h0c) mbr_size[15:8]<=parse_byte;
                            476: if(mbr_type[1]==8'h0b || mbr_type[1]==8'h0c) mbr_size[23:16]<=parse_byte;
                            477: if(mbr_type[1]==8'h0b || mbr_type[1]==8'h0c) mbr_size[31:24]<=parse_byte;
                            478: mbr_status[2]<=parse_byte;
                            482: mbr_type[2]<=parse_byte;
                            486: if(mbr_type[2]==8'h0b || mbr_type[2]==8'h0c) mbr_lba[7:0]<=parse_byte;
                            487: if(mbr_type[2]==8'h0b || mbr_type[2]==8'h0c) mbr_lba[15:8]<=parse_byte;
                            488: if(mbr_type[2]==8'h0b || mbr_type[2]==8'h0c) mbr_lba[23:16]<=parse_byte;
                            489: if(mbr_type[2]==8'h0b || mbr_type[2]==8'h0c) mbr_lba[31:24]<=parse_byte;
                            490: if(mbr_type[2]==8'h0b || mbr_type[2]==8'h0c) mbr_size[7:0]<=parse_byte;
                            491: if(mbr_type[2]==8'h0b || mbr_type[2]==8'h0c) mbr_size[15:8]<=parse_byte;
                            492: if(mbr_type[2]==8'h0b || mbr_type[2]==8'h0c) mbr_size[23:16]<=parse_byte;
                            493: if(mbr_type[2]==8'h0b || mbr_type[2]==8'h0c) mbr_size[31:24]<=parse_byte;
                            494: mbr_status[3]<=parse_byte;
                            498: mbr_type[3]<=parse_byte;
                            502: if(mbr_type[3]==8'h0b || mbr_type[3]==8'h0c) mbr_lba[7:0]<=parse_byte;
                            503: if(mbr_type[3]==8'h0b || mbr_type[3]==8'h0c) mbr_lba[15:8]<=parse_byte;
                            504: if(mbr_type[3]==8'h0b || mbr_type[3]==8'h0c) mbr_lba[23:16]<=parse_byte;
                            505: if(mbr_type[3]==8'h0b || mbr_type[3]==8'h0c) mbr_lba[31:24]<=parse_byte;
                            506: if(mbr_type[3]==8'h0b || mbr_type[3]==8'h0c) mbr_size[7:0]<=parse_byte;
                            507: if(mbr_type[3]==8'h0b || mbr_type[3]==8'h0c) mbr_size[15:8]<=parse_byte;
                            508: if(mbr_type[3]==8'h0b || mbr_type[3]==8'h0c) mbr_size[23:16]<=parse_byte;
                            509: if(mbr_type[3]==8'h0b || mbr_type[3]==8'h0c) mbr_size[31:24]<=parse_byte;
                            510: signature[7:0]<=parse_byte;
                            511: signature[15:8]<=parse_byte;
                            default: ;
                        endcase
                    end else if(byte_mode==DIRECTORY_BYTES) begin
                        case(byte_index[4:0])
                            0: directory_name[7:0]<=parse_byte;
                            1: directory_name[15:8]<=parse_byte;
                            2: directory_name[23:16]<=parse_byte;
                            3: directory_name[31:24]<=parse_byte;
                            4: directory_name[39:32]<=parse_byte;
                            5: directory_name[47:40]<=parse_byte;
                            6: directory_name[55:48]<=parse_byte;
                            7: directory_name[63:56]<=parse_byte;
                            8: directory_name[71:64]<=parse_byte;
                            9: directory_name[79:72]<=parse_byte;
                            10: directory_name[87:80]<=parse_byte;
                            11: directory_attr<=parse_byte;
                            20: directory_cluster[23:16]<=parse_byte;
                            21: directory_cluster[31:24]<=parse_byte;
                            26: directory_cluster[7:0]<=parse_byte;
                            27: directory_cluster[15:8]<=parse_byte;
                            28: directory_size[7:0]<=parse_byte;
                            29: directory_size[15:8]<=parse_byte;
                            30: directory_size[23:16]<=parse_byte;
                            31: directory_size[31:24]<=parse_byte;
                            default: ;
                        endcase
                    end else if(byte_mode==FAT_BYTES) begin
                        case(byte_index[1:0])
                            0: fat_value[7:0]<=parse_byte;
                            1: fat_value[15:8]<=parse_byte;
                            2: fat_value[23:16]<=parse_byte;
                            3: fat_value[31:24]<=parse_byte;
                        endcase
                    end else if(byte_mode==FILE_BYTES) begin file_position<=file_position+1'b1; end
                    if(byte_mode==DIRECTORY_BYTES && byte_index[4:0]==31) state<=74'b1<<DIR_ENTRY;
                    else if(byte_index==last_byte) state<=return_state;
                    else begin byte_index<=byte_index+1'b1; state<=74'b1<<BYTE_ADDR; end
                end
                state[TXT_BYTE_USE]: if(text_byte_ready) begin
                    if(byte_index==last_byte) state<=return_state;
                    else begin byte_index<=byte_index+1'b1; state<=74'b1<<BYTE_ADDR; end
                end
                state[BOOT_TEST]: begin
                    if(signature!=16'haa55) begin state<=74'b1<<LOCKED; end
                    else if(from_mbr || (bytes_per_sector==512 && root_entries==0 && fat16==0)) state<=74'b1<<BPB_EVAL;
                    else state<=74'b1<<MBR_INIT;
                end
                state[MBR_INIT]: begin partition_index<=0; partition_matches<=0; state<=74'b1<<MBR_ENTRY; end
                state[MBR_ENTRY]: begin
                    mbr_protective_q<=mbr_type[partition_index[1:0]]==8'hee;
                    mbr_fat_q<=mbr_type[partition_index[1:0]]==8'h0b || mbr_type[partition_index[1:0]]==8'h0c;
                    mbr_status_bad_q<=mbr_status[partition_index[1:0]]!=0 && mbr_status[partition_index[1:0]]!=8'h80;
                    mbr_last_q<=partition_index==3;
                    mbr_lba_q<=mbr_lba;mbr_size_q<=mbr_size;
                    state<=74'b1<<MBR_DECIDE;
                end
                state[MBR_DECIDE]: begin
                    if(mbr_protective_q || (mbr_fat_q && mbr_status_bad_q)) begin
                        state<=74'b1<<LOCKED;
                    end else begin
                        if(mbr_fat_q) begin
                            partition_matches<=partition_matches+1'b1;
                            partition_lba<=mbr_lba_q;partition_size<=mbr_size_q;
                        end
                        if(mbr_last_q) state<=74'b1<<MBR_END;
                        else begin partition_index<=partition_index+1'b1;state<=74'b1<<MBR_ENTRY;end
                    end
                end
                state[MBR_END]: begin
                    partition_zero_q<=partition_lba==0 || partition_size==0;
                    if(partition_matches!=1) begin state<=74'b1<<LOCKED; end
                    else begin
                        partition_end<={1'b0,partition_lba}+{1'b0,partition_size}; state<=74'b1<<MBR_RANGE;
                    end
                end
                state[MBR_RANGE]: begin
                    if((VARIABLE_BMP ? partition_zero_q : (partition_lba==0 || partition_size==0)) ||
                        (partition_end[32] && partition_end[31:0]!=0)) begin state<=74'b1<<LOCKED; end
                    else begin
                        from_mbr<=1; request_lba<=partition_lba; byte_mode<=BOOT_BYTES;
                        byte_index<=0; last_byte<=511; return_state<=74'b1<<BOOT_TEST; state<=74'b1<<READ_REQ;
                    end
                end
                state[BPB_EVAL]: begin
                    bpb_invalid[0]<=bytes_per_sector!=512 || reserved_sectors==0 || root_entries!=0 || total16!=0 || fat16!=0;
                    bpb_invalid[1]<=(fat_count!=1 && fat_count!=2) || fat_sectors==0 || total_sectors==0 || fs_version!=0;
                    bpb_invalid[2]<=(jump0!=8'he9 && !(jump0==8'heb && jump2==8'h90)) ||
                        sectors_per_cluster==0 || sectors_per_cluster>128 ||
                        (sectors_per_cluster & (sectors_per_cluster-1'b1))!=0;
                    bpb_invalid[3]<=ext_flags[7] && ext_flags[3:0]>=fat_count;
                    bpb_invalid[4]<=hidden_sectors!=partition_lba || (from_mbr && total_sectors>partition_size);
                    state<=74'b1<<BPB_BASIC;
                end
                state[BPB_BASIC]: begin
                    if(|bpb_invalid) begin
                        state<=74'b1<<LOCKED;
                    end else begin
                        case(sectors_per_cluster)
                            1:cluster_shift<=0; 2:cluster_shift<=1; 4:cluster_shift<=2; 8:cluster_shift<=3;
                            16:cluster_shift<=4; 32:cluster_shift<=5; 64:cluster_shift<=6; 128:cluster_shift<=7;
                        endcase
                        fat_span<=fat_count==2 ? {fat_sectors,1'b0} : {1'b0,fat_sectors};
                        fat_capacity<={1'b0,fat_sectors,7'd0};
                        volume_end<={1'b0,partition_lba}+{1'b0,total_sectors};
                        state<=74'b1<<LAYOUT1;
                    end
                end
                state[LAYOUT1]: begin relative_data<=fat_span+reserved_sectors; state<=74'b1<<LAYOUT2; end
                state[LAYOUT2]: begin
                    if(relative_data>=total_sectors || volume_end>33'h100000000) begin state<=74'b1<<LOCKED; end
                    else begin
                        data_sectors<=total_sectors-relative_data;
                        data_wide<={1'b0,partition_lba}+relative_data;
                        fat_base<=partition_lba+reserved_sectors;
                        state<=74'b1<<LAYOUT3;
                    end
                end
                state[LAYOUT3]: begin
                    cluster_count<=data_sectors>>cluster_shift; data_base<=data_wide[31:0];
                    if(ext_flags[7] && ext_flags[3:0]==1) fat_base<=fat_base+fat_sectors;
                    state<=74'b1<<LAYOUT4;
                end
                state[LAYOUT4]: begin
                    max_cluster<=cluster_count+1'b1;
                    required_fat_entries<={8'd0,cluster_count}+40'd2;
                    state<=74'b1<<LAYOUT5;
                end
                state[LAYOUT5]: begin
                    layout_invalid[0]<=cluster_count<65525;
                    layout_invalid[1]<=cluster_count>32'h0fffffee;
                    layout_invalid[2]<=fat_capacity<required_fat_entries;
                    layout_invalid[3]<=bpb_root[27:0]<2 || bpb_root[27:0]>max_cluster;
                    layout_invalid[4]<=data_wide[32];
                    state<=74'b1<<LAYOUT_EVAL;
                end
                state[LAYOUT_EVAL]: begin
                    if(|layout_invalid) begin
                        state<=74'b1<<LOCKED;
                    end else state<=74'b1<<ROOT_BEGIN;
                end
                state[ROOT_BEGIN]: begin
                    file_mode<=0; visited_count<=0; root_sector_count<=0; sector_in_cluster<=0;
                    current_cluster<=bpb_root[27:0]; visit_return<=74'b1<<FAT_ADDRESS; state<=74'b1<<VISIT_BEGIN;
                end
                state[VISIT_BEGIN]: begin
                    visit_invalid<=current_cluster<28'd2 || current_cluster>max_cluster ||
                        current_cluster>=28'hffffff0 || (!floyd && visited_count>=(file_mode ? 2048 : ROOT_CLUSTER_LIMIT));
                    state<=74'b1<<VISIT_EVAL;
                end
                state[VISIT_EVAL]: begin
                    if(visit_invalid) begin
                        abort_frame<=file_mode && !precheck; state<=74'b1<<LOCKED;
                    end else if(floyd) state<=visit_return;
                    else if(visited_count==0) state<=74'b1<<VISIT_SAVE;
                    else begin visited_index<=0; state<=74'b1<<VISIT_ADDR; end
                end
                state[VISIT_ADDR]: state<=74'b1<<VISIT_WAIT;
                state[VISIT_WAIT]: state<=74'b1<<VISIT_TEST;
                state[VISIT_TEST]: begin
                    visited_match<=visited_value==current_cluster;
                    visited_last<=visited_index+1'b1>=visited_count;
                    state<=74'b1<<VISIT_DECIDE;
                end
                state[VISIT_DECIDE]: begin
                    if(visited_match) begin
                        abort_frame<=file_mode && !precheck; state<=74'b1<<LOCKED;
                    end else if(visited_last) state<=74'b1<<VISIT_SAVE;
                    else begin visited_index<=visited_index+1'b1; state<=74'b1<<VISIT_ADDR; end
                end
                state[VISIT_SAVE]: begin visited_count<=visited_count+1'b1; state<=visit_return; end
                state[FAT_ADDRESS]: begin
                    request_lba<=fat_base+{11'd0,fat_cursor[27:7]};
                    fat_offset<={fat_cursor[6:0],2'b0}; byte_index<={fat_cursor[6:0],2'b0};
                    last_byte<={fat_cursor[6:0],2'b11}; byte_mode<=FAT_BYTES;
                    return_state<=74'b1<<FAT_EVAL; state<=74'b1<<READ_REQ;
                end
                state[FAT_EVAL]: begin
                    fat_eoc_q<=fat_value[27:0]>=28'hffffff8;
                    fat_meets_next_q<=fat_value[27:0]==next_cluster;
                    fat_text_invalid<=fat_value[27:0]<2 ||
                        (fat_value[27:0]<28'hffffff8 && (fat_value[27:0]>max_cluster ||
                         fat_value[27:0]>=28'hffffff0 || fat_value[27:0]==current_cluster));
                    fat_chain_invalid<=fat_value[27:0]<2 || fat_value[27:0]>max_cluster || fat_value[27:0]>=28'hffffff0;
                    state<=74'b1<<FAT_PARSE;
                end
                state[FAT_PARSE]: begin
                  if(floyd && hare_phase!=0) begin
                    if(fat_eoc_q) begin hare_ended<=1;hare_phase<=0;state<=74'b1<<DATA_SUB;end
                    else if(fat_chain_invalid || (hare_phase==1 && fat_meets_next_q)) begin
                        abort_frame<=1;hare_phase<=0;state<=74'b1<<LOCKED;
                    end else begin
                        hare_cluster<=fat_value[27:0];hare_phase<=hare_phase-1'b1;
                        state<=hare_phase==2 ? 74'b1<<FAT_ADDRESS : 74'b1<<DATA_SUB;
                    end
                  end else if(floyd) begin
                    if(fat_eoc_q) begin next_cluster<=fat_value[27:0];state<=74'b1<<DATA_SUB;end
                    else if(fat_chain_invalid) begin abort_frame<=1;state<=74'b1<<LOCKED;end
                    else begin
                        next_cluster<=fat_value[27:0];
                        if(!hare_ended) begin hare_phase<=2;state<=74'b1<<FAT_ADDRESS;end
                        else state<=74'b1<<DATA_SUB;
                    end
                  end else if(text_mode && fat_text_invalid) begin
                    caption_errors[text_role*8 +: 8]<=4; state<=74'b1<<TXT_NEXT;
                  end else begin
                    if(VARIABLE_BMP ? fat_eoc_q : fat_value[27:0]>=28'hffffff8) begin next_cluster<=fat_value[27:0]; state<=74'b1<<DATA_SUB; end
                    else if(fat_chain_invalid) begin
                        if(file_mode && precheck) begin had_bad_header<=1; state<=74'b1<<PRE_NEXT; end
                        else begin abort_frame<=file_mode; state<=74'b1<<LOCKED; end
                    end else begin next_cluster<=fat_value[27:0]; state<=74'b1<<DATA_SUB; end
                end
                  end
                state[DATA_SUB]: begin cluster_minus_two<=current_cluster-28'd2; state<=74'b1<<DATA_SHIFT; end
                state[DATA_SHIFT]: begin cluster_offset<={5'd0,cluster_minus_two}<<cluster_shift; state<=74'b1<<DATA_ADD; end
                state[DATA_ADD]: begin cluster_lba<={1'b0,data_base}+cluster_offset; state<=74'b1<<DATA_RANGE; end
                state[DATA_RANGE]: begin
                    request_wide<=cluster_lba+{25'd0,sector_in_cluster};
                    file_remaining<=file_size-file_position; state<=VARIABLE_BMP ? 74'b1<<DATA_EVAL : 74'b1<<DATA_CHECK;
                end
                state[DATA_EVAL]: begin
                    request_outside_q<=request_wide>=volume_end || request_wide[32];
                    state<=74'b1<<DATA_CHECK;
                end
                state[DATA_CHECK]: begin
                    if(VARIABLE_BMP ? request_outside_q : (request_wide>=volume_end || request_wide[32])) begin
                        if(text_mode) begin caption_errors[text_role*8 +: 8]<=4; state<=74'b1<<TXT_NEXT; end
                        else begin abort_frame<=file_mode && !precheck; state<=74'b1<<LOCKED; end
                    end else if(!file_mode && root_sector_count>=ROOT_SECTOR_LIMIT) begin state<=74'b1<<LOCKED; end
                    else begin
                        request_lba<=request_wide[31:0]; byte_index<=0;
                        if(text_mode) begin
                            text_start<=1; last_byte<=file_size[8:0]-9'd1;
                            byte_mode<=TEXT_BYTES; return_state<=74'b1<<TXT_FINISH;
                        end else if(!file_mode) begin
                            root_sector_count<=root_sector_count+1'b1; last_byte<=511;
                            byte_mode<=DIRECTORY_BYTES; return_state<=74'b1<<DIR_NEXT;
                        end else if(file_position==0) begin
                            header_begin<=1; last_byte<=53; byte_mode<=HEADER_BYTES; return_state<=74'b1<<HEADER_CHECK;
                        end else begin
                            last_byte<=file_remaining>=32'd512 ? 9'd511 : file_remaining[8:0]-9'd1;
                            byte_mode<=FILE_BYTES; return_state<=74'b1<<FILE_EVAL;
                        end
                        state<=74'b1<<READ_REQ;
                    end
                end
                state[DIR_ENTRY]: begin
                    if(directory_name[7:0]==0) state<=74'b1<<PRE_BEGIN;
                    else if(directory_name[7:0]!=8'he5 && (directory_attr & 8'h18)==0 &&
                        directory_attr[3:0]!=4'hf && directory_attr[7:6]==0 && target_name) begin
                        slot<=directory_number-1'b1; state<=74'b1<<DIR_SLOT;
                    end else if(CAPTIONS && directory_name[7:0]!=8'he5 &&
                        (directory_attr & 8'h18)==0 && directory_attr[3:0]!=4'hf &&
                        directory_attr[7:6]==0 && text_name) begin
                        text_role<=directory_name[39:32]-8'h31; state<=74'b1<<TXT_SAVE;
                    end else if(TF_FONT && directory_name[7:0]!=8'he5 &&
                        (directory_attr & 8'h18)==0 && directory_attr[3:0]!=4'hf &&
                        directory_attr[7:6]==0 && font_name) begin
                        if(font_found) font_duplicate<=1;
                        else begin font_found<=1; font_cluster<=directory_cluster; font_size<=directory_size; end
                        state<=74'b1<<DIR_RESUME;
                    end else state<=74'b1<<DIR_RESUME;
                end
                state[TXT_SAVE]: begin
                    if(text_found[text_role]) text_duplicate[text_role]<=1;
                    else begin
                        text_found[text_role]<=1;
                        text_clusters[text_role]<=directory_cluster[27:0]; text_sizes[text_role]<=directory_size;
                    end
                    state<=74'b1<<DIR_RESUME;
                end
                state[DIR_SLOT]: begin candidate_duplicate<=candidate_mask[slot]; state<=74'b1<<DIR_SAVE; end
                state[DIR_SAVE]: begin
                    if(candidate_duplicate) begin state<=74'b1<<LOCKED; end
                    else begin
                        candidate_mask[slot]<=1; state<=74'b1<<DIR_RESUME;
                    end
                end
                state[DIR_RESUME]: begin
                    if(byte_index==511) state<=74'b1<<DIR_NEXT;
                    else begin byte_index<=byte_index+1'b1; state<=74'b1<<BYTE_ADDR; end
                end
                state[DIR_NEXT]: begin
                    if(VARIABLE_BMP ? more_sectors_q : (sector_in_cluster+1'b1<sectors_per_cluster)) begin sector_in_cluster<=sector_in_cluster+1'b1; state<=74'b1<<DATA_RANGE; end
                    else if(VARIABLE_BMP ? next_eoc_q : (next_cluster>=28'hffffff8)) state<=74'b1<<PRE_BEGIN;
                    else begin current_cluster<=next_cluster; sector_in_cluster<=0; state<=74'b1<<VISIT_BEGIN; end
                end
                state[PRE_BEGIN]: begin pre_index<=0; good_mask<=0;pre_scan_mask<=candidate_mask; state<=74'b1<<PRE_NEXT; end
                state[PRE_NEXT]: begin
                    file_mode<=0;
                    if(pre_index[4]) state<=74'b1<<BUILD_BEGIN;
                    else begin
                        pre_index<=pre_index+1'b1;pre_scan_mask<=pre_scan_mask>>1;
                        if(pre_scan_mask[0]) begin
                            slot<=pre_index[3:0]; precheck<=1; state<=74'b1<<DESCRIPTOR_WAIT;
                        end
                    end
                end
                state[DESCRIPTOR_WAIT]: state<=74'b1<<DESCRIPTOR_TEST;
                state[DESCRIPTOR_TEST]: begin
                    file_size<=descriptor_read[31:0]; current_cluster<=descriptor_read[59:32];
                    state<=74'b1<<DESCRIPTOR_EVAL;
                end
                state[DESCRIPTOR_EVAL]: begin
                    descriptor_invalid<=current_cluster<28'd2 || current_cluster>max_cluster ||
                        file_size<32'd54 || file_size>(VARIABLE_BMP ? 32'd2424832 : 32'd1048576);
                    state<=74'b1<<DESCRIPTOR_CHECK;
                end
                state[DESCRIPTOR_CHECK]: begin
                    if(descriptor_invalid) begin
                        if(precheck) begin had_bad_header<=1; state<=74'b1<<PRE_NEXT; end
                        else begin state<=74'b1<<LOCKED; end
                    end else state<=74'b1<<FILE_BEGIN;
                end
                state[FILE_BEGIN]: begin
                    file_mode<=1;hare_cluster<=current_cluster;hare_phase<=0;hare_ended<=0;
                    file_position<=0; sector_in_cluster<=0; visited_count<=0;
                    visit_return<=74'b1<<FAT_ADDRESS; state<=74'b1<<VISIT_BEGIN;
                end
                state[HEADER_CHECK]: begin header_check<=1; state<=74'b1<<HEADER_WAIT; end
                state[HEADER_WAIT]: if(header_checked) begin
                    if(precheck) begin
                        if(header_good) good_mask[slot]<=1;
                        else had_bad_header<=1;
                        state<=74'b1<<PRE_NEXT;
                    end else if(!header_good) begin state<=74'b1<<LOCKED; end
                    else state<=74'b1<<FRAME_BEGIN;
                end
                state[FRAME_BEGIN]: begin frame_begin<=1; state<=74'b1<<FRAME_WAIT; end
                state[FRAME_WAIT]: if(pixels_enabled) state<=74'b1<<FILE_REPLAY;
                state[FILE_REPLAY]: begin
                    byte_index<=0; last_byte<=VARIABLE_BMP && file_size<512 ? file_size[8:0]-9'd1 : 9'd511;
                    byte_mode<=FILE_BYTES; return_state<=74'b1<<FILE_EVAL; state<=74'b1<<BYTE_ADDR;
                end
                state[FILE_EVAL]: begin
                    file_at_end<=file_position>=file_size; state<=74'b1<<FILE_NEXT;
                end
                state[FILE_NEXT]: begin
                    if(file_at_end) state<=74'b1<<FILE_END;
                    else if(VARIABLE_BMP ? more_sectors_q : (sector_in_cluster+1'b1<sectors_per_cluster)) begin sector_in_cluster<=sector_in_cluster+1'b1; state<=74'b1<<DATA_RANGE; end
                    else if(VARIABLE_BMP ? next_eoc_q : (next_cluster>=28'hffffff8)) begin abort_frame<=1; state<=74'b1<<LOCKED; end
                    else begin current_cluster<=next_cluster; sector_in_cluster<=0; state<=74'b1<<VISIT_BEGIN; end
                end
                state[FILE_END]: begin stream_success<=1; state<=74'b1<<FILE_SUCCESS; end
                state[FILE_SUCCESS]: if(source_success) begin file_mode<=0; state<=74'b1<<READY; end
                state[BUILD_BEGIN]: begin build_index<=0;build_scan_mask<=good_mask; image_count<=0; catalog_mask<=0; state<=74'b1<<BUILD_ENTRY; end
                state[BUILD_ENTRY]: begin
                    if(build_index[4]) begin
                        if(CAPTIONS && image_count!=0) begin
                            text_role<=0; text_mode<=1; file_mode<=1; precheck<=1; state<=74'b1<<TXT_SELECT;
                        end else begin
                            catalog_ready<=1;
                            state<=74'b1<<READY;
                        end
                    end else begin
                        if(build_scan_mask[0] && image_count<MAX_IMAGES) begin
                            playlist[image_count[3:0]]<=build_index[3:0]; image_count<=image_count+1'b1;
                            catalog_mask[build_index[3:0]]<=1'b1;
                        end
                        build_index<=build_index+1'b1;build_scan_mask<=build_scan_mask>>1;
                    end
                end
                state[TXT_SELECT]: begin
                    if(text_role==3) begin
                        text_mode<=0; file_mode<=0; catalog_ready<=1; state<=74'b1<<READY;
                    end else if(!text_found[text_role]) state<=74'b1<<TXT_NEXT;
                    else if(text_duplicate[text_role]) begin
                        caption_errors[text_role*8 +: 8]<=2; state<=74'b1<<TXT_NEXT;
                    end else state<=74'b1<<TXT_DESCRIPTOR_READ;
                end
                state[TXT_DESCRIPTOR_READ]: begin
                    current_cluster<=text_clusters[text_role]; file_size<=text_sizes[text_role];
                    state<=74'b1<<TXT_DESCRIPTOR_EVAL;
                end
                state[TXT_DESCRIPTOR_EVAL]: begin
                    text_descriptor_bad<=file_size==0 || file_size>512 || current_cluster<2 ||
                        current_cluster>max_cluster || current_cluster>=28'hffffff0;
                    state<=74'b1<<TXT_DESCRIPTOR_TEST;
                end
                state[TXT_DESCRIPTOR_TEST]: begin
                    if(text_descriptor_bad) begin caption_errors[text_role*8 +: 8]<=2; state<=74'b1<<TXT_NEXT; end
                    else state<=74'b1<<TXT_BEGIN;
                end
                state[TXT_BEGIN]: begin
                    file_position<=0; sector_in_cluster<=0; visited_count<=0;
                    visit_return<=74'b1<<FAT_ADDRESS; state<=74'b1<<VISIT_BEGIN;
                end
                state[TXT_FINISH]: if(text_byte_ready) begin text_finish<=1; state<=74'b1<<TXT_WAIT; end
                state[TXT_WAIT]: if(text_done) begin
                    caption_ready[text_role]<=text_good;
                    caption_lengths[text_role*7 +: 7]<=text_good ? text_count : 7'd0;
                    caption_errors[text_role*8 +: 8]<=text_good ? 8'd0 : 8'd3;
                    state<=74'b1<<TXT_NEXT;
                end
                state[TXT_NEXT]: begin text_role<=text_role+1'b1; state<=74'b1<<TXT_SELECT; end
                state[READY]: if(load_start && !fault_present && {1'b0,load_index}<image_count) begin
                    slot<=playlist[load_index]; source_number<={1'b0,playlist[load_index]}+5'd1;
                    precheck<=0; state<=74'b1<<DESCRIPTOR_WAIT;
                end
                state[LOCKED]: begin sector_start<=0; stream_success<=0; end
                default: begin state<=74'b1<<LOCKED; end
            endcase
            if(sector_fault!=0 && !state[LOCKED]) begin
                bmp_header_valid<=0;bmp_payload_valid<=0;
                abort_frame<=file_mode && !precheck; state<=74'b1<<LOCKED;
                text_start<=0; text_finish<=0;
            sector_start<=0; header_begin<=0; header_check<=0; frame_begin<=0; stream_success<=0;
            end else if(((TF_FONT && font_chain_fault) || (SHARED_SERVICE && service_chain_fault)) && !state[LOCKED]) begin
                bmp_header_valid<=0;bmp_payload_valid<=0;
                abort_frame<=file_mode && !precheck; state<=74'b1<<LOCKED;
                sector_start<=0; header_begin<=0; header_check<=0; frame_begin<=0; stream_success<=0;
            end else if(bmp_fault!=0 && !state[LOCKED]) begin
                bmp_header_valid<=0;bmp_payload_valid<=0;
                state<=74'b1<<LOCKED;
                text_start<=0; text_finish<=0;
            sector_start<=0; header_begin<=0; header_check<=0; frame_begin<=0; stream_success<=0;
            end else if(!state[INIT] && !state[READY] && !state[LOCKED] &&
                (catalog_ready ? file_expired : catalog_expired)) begin
                bmp_header_valid<=0;bmp_payload_valid<=0;
                abort_frame<=file_mode && !precheck; state<=74'b1<<LOCKED;
                text_start<=0; text_finish<=0;
            sector_start<=0; header_begin<=0; header_check<=0; frame_begin<=0; stream_success<=0;
            end
        end
    end
endmodule
