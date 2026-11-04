`timescale 1ns/1ps
module lights_bmp_gate #(
    parameter integer HANDSHAKE_TIMEOUT = 200_000_000,
    parameter integer HEADER_SKIP_LIMIT = 65536,
    parameter integer VARIABLE_BMP = 0
)(
    input wire clk, rst,
    input wire header_begin, header_valid,
    input wire [5:0] header_index,
    input wire [7:0] header_byte,
    input wire header_check,
    input wire [31:0] directory_size,
    input wire [15:0] width, height,
    output reg header_checked, header_good,
    output reg [31:0] pixel_offset,
    output wire [10:0] source_width,source_height,
    input wire pixel_ready,
    output wire byte_ready,
    input wire frame_begin,
    output reg write_req,
    input wire write_req_ack,
    output wire pixels_enabled,
    input wire byte_valid,
    input wire [7:0] byte_data,
    input wire [31:0] byte_offset,
    input wire stream_success,
    input wire abort_frame,
    output reg pixel_valid,
    output reg [23:0] pixel,
    output reg source_success,
    output reg [3:0] fault
);
    localparam PIXEL_BYTES=921600, PIXELS=307200;
    localparam WAIT=0, ACK_HIGH=1, ACK_LOW=2, PIXEL=3, LOCKED=4;
    reg [2:0] state;
    (* syn_preserve=1 *) reg [2:0] write_ack_sync;
    reg [31:0] timer;
    reg [15:0] signature, reserved1, reserved2, planes, bpp;
    reg [31:0] declared_size, dib, w, h, compression, image_size;
    reg [32:0] pixel_end;
    reg [1:0] phase;
    reg [20:0] pixel_count;
    reg [12:0] row_byte;reg eof_seen;
    reg [12:0] active_bytes,stride;
    reg [23:0] body;
    reg [20:0] expected_pixels;
    reg [5:0] check_pipe;
    reg format_ok, dimensions_ok, offset_ok, image_ok, end_ok;
    assign source_width=w[10:0];assign source_height=h[10:0];
    assign byte_ready=!VARIABLE_BMP || !pixel_valid || pixel_ready;
    reg [7:0] blue, green;
    assign pixels_enabled = state==PIXEL && fault==0;
    always @(posedge clk or posedge rst) begin
        if(rst) write_ack_sync<=0;
        else write_ack_sync<={write_ack_sync[1:0],write_req_ack};
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            signature<=0; declared_size<=0; reserved1<=0; reserved2<=0;
            pixel_offset<=0; dib<=0; w<=0; h<=0; planes<=0; bpp<=0;
            compression<=0; image_size<=0; pixel_end<=0;
            header_checked<=0; header_good<=0;
            active_bytes<=0;stride<=0;body<=0;expected_pixels<=0;
            check_pipe<=0;format_ok<=0;dimensions_ok<=0;offset_ok<=0;image_ok<=0;end_ok<=0;
        end else begin
            active_bytes<={2'd0,w[10:0]}+{1'd0,w[10:0],1'b0};
            stride<=(active_bytes+13'd3)&13'h1ffc;
            body<=stride*{13'd0,h[10:0]};
            expected_pixels<=w[10:0]*{10'd0,h[10:0]};
            pixel_end<={1'b0,pixel_offset}+(VARIABLE_BMP ? {9'd0,body} : 33'd921600);
            format_ok<=signature==16'h4d42 && declared_size==directory_size && reserved1==0 && reserved2==0 && dib==40 && planes==1 && bpp==24 && compression==0;
            dimensions_ok<=w>=1 && h>=1 && w<=1920 && h<=1920 && (w<=1080 || h<=1080);
            offset_ok<=pixel_offset>=54 && pixel_offset<=HEADER_SKIP_LIMIT && directory_size<=6286336;
            image_ok<=image_size==0 || image_size=={8'd0,body};
            end_ok<=!pixel_end[32] && pixel_end<=directory_size;
            check_pipe<={check_pipe[4:0],header_check};
            if(header_begin) begin header_checked<=0; header_good<=0;check_pipe<=0; end
            if(header_valid) begin
                case(header_index)
                    0,1: signature[header_index*8 +: 8]<=header_byte;
                    2,3,4,5: declared_size[(header_index-2)*8 +: 8]<=header_byte;
                    6,7: reserved1[(header_index-6)*8 +: 8]<=header_byte;
                    8,9: reserved2[(header_index-8)*8 +: 8]<=header_byte;
                    10,11,12,13: pixel_offset[(header_index-10)*8 +: 8]<=header_byte;
                    14,15,16,17: dib[(header_index-14)*8 +: 8]<=header_byte;
                    18,19,20,21: w[(header_index-18)*8 +: 8]<=header_byte;
                    22,23,24,25: h[(header_index-22)*8 +: 8]<=header_byte;
                    26,27: planes[(header_index-26)*8 +: 8]<=header_byte;
                    28,29: bpp[(header_index-28)*8 +: 8]<=header_byte;
                    30,31,32,33: compression[(header_index-30)*8 +: 8]<=header_byte;
                    34,35,36,37: image_size[(header_index-34)*8 +: 8]<=header_byte;
                    default: ;
                endcase
            end
            if(VARIABLE_BMP && check_pipe[5]) begin
                header_checked<=1;header_good<=format_ok && dimensions_ok && offset_ok && image_ok && end_ok;
            end else if(!VARIABLE_BMP && header_check) begin
                header_checked<=1;
                header_good<=signature==16'h4d42 && declared_size==directory_size &&
                    reserved1==0 && reserved2==0 && dib==40 &&
                    (VARIABLE_BMP ? (w>=1 && h>=1 && w<=1920 && h<=1920 && (w<=1080 || h<=1080)) :
                    (w=={16'd0,width} && h=={16'd0,height} && width==640 && height==480)) && planes==1 && bpp==24 &&
                    compression==0 && (image_size==0 || image_size==(VARIABLE_BMP ? {8'd0,body} : PIXEL_BYTES)) &&
                    pixel_offset>=54 && pixel_offset<=HEADER_SKIP_LIMIT &&
                    !pixel_end[32] && pixel_end<=directory_size && directory_size<=(VARIABLE_BMP ? 6286336 : 1048576);
            end
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=WAIT; timer<=0; phase<=0; pixel_count<=0;row_byte<=0;eof_seen<=0;
            blue<=0; green<=0; pixel<=0; pixel_valid<=0;
            write_req<=0; source_success<=0; fault<=0;
        end else begin
            if(!VARIABLE_BMP || pixel_ready) pixel_valid<=0; source_success<=0;
            if(abort_frame) begin
                write_req<=0; fault<=3; state<=LOCKED;
            end else case(state)
                WAIT: if(frame_begin) begin
                    if(!header_checked || !header_good || write_ack_sync[2]) begin
                        fault<=2; state<=LOCKED;
                    end else begin
                        write_req<=1; timer<=0; phase<=0; pixel_count<=0;row_byte<=0;eof_seen<=0;
                        state<=ACK_HIGH;
                    end
                end
                ACK_HIGH: begin
                    timer<=timer+1'b1;
                    if(write_ack_sync[2]) begin write_req<=0; timer<=0; state<=ACK_LOW; end
                    else if(timer>=HANDSHAKE_TIMEOUT-1) begin
                        write_req<=0; fault<=1; state<=LOCKED;
                    end
                end
                ACK_LOW: begin
                    timer<=timer+1'b1;
                    if(!write_ack_sync[2]) state<=PIXEL;
                    else if(timer>=HANDSHAKE_TIMEOUT-1) begin fault<=1; state<=LOCKED; end
                end
                PIXEL: begin
                    if(byte_valid && byte_ready && byte_offset>=pixel_offset && {1'b0,byte_offset}<pixel_end) begin
                        if(VARIABLE_BMP) row_byte<=row_byte==stride-1'b1 ? 13'd0 : row_byte+1'b1;
                        if(!VARIABLE_BMP || row_byte<active_bytes) case(phase)
                            0: begin blue<=byte_data; phase<=1; end
                            1: begin green<=byte_data; phase<=2; end
                            2: begin
                                pixel<={byte_data,green,blue}; pixel_valid<=1;
                                pixel_count<=pixel_count+1'b1; phase<=0;
                            end
                            default: begin fault<=2; state<=LOCKED; end
                        endcase
                    end
                    if(stream_success) eof_seen<=1;
                    if((VARIABLE_BMP ? eof_seen && !pixel_valid : stream_success)) begin
                        if(pixel_count==(VARIABLE_BMP ? expected_pixels : PIXELS) && phase==0 && (!VARIABLE_BMP || row_byte==0)) begin source_success<=1; state<=WAIT; end
                        else begin fault<=2; state<=LOCKED; end
                    end
                end
                LOCKED: write_req<=0;
                default: begin fault<=2; write_req<=0; state<=LOCKED; end
            endcase
        end
    end
endmodule
