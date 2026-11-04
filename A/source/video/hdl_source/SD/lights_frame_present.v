module lights_frame_present #(parameter integer FRAME_PIXELS=640*480,FRAME_IDENTITY=0)(
    input wire [31:0] actual_identity,
    input wire actual_valid,
    output reg [31:0] presented_identity,
    output reg presented_pulse,
    input wire pixel_clk,rst,video_de,video_vs,frame_enabled,
    input wire read_bank_async,read_valid_async,
    output wire read_bank_pixel,read_valid_pixel,
    output reg presented_valid,presented_bank
);
    localparam integer BITS=FRAME_PIXELS<2 ? 1 : $clog2(FRAME_PIXELS+1);
    (* syn_preserve=1 *) reg [2:0] read_bank_sync,read_valid_sync;
    assign read_bank_pixel=read_bank_sync[2];
    assign read_valid_pixel=FRAME_IDENTITY ? actual_valid : read_valid_sync[2];
    reg [BITS-1:0] pixels_seen;
    reg frame_bad,frame_bank,vs_delayed;
    reg [31:0] frame_identity;
    wire [31:0] current_identity=FRAME_IDENTITY ? actual_identity : {31'd0,read_bank_sync[2]};
    always @(posedge pixel_clk or posedge rst) begin
        if(rst) begin read_bank_sync<=0; read_valid_sync<=0; end
        else begin
            read_bank_sync<={read_bank_sync[1:0],read_bank_async};
            read_valid_sync<={read_valid_sync[1:0],read_valid_async};
        end
    end
    always @(posedge pixel_clk or posedge rst) begin
        if(rst) begin
            pixels_seen<=0; frame_bad<=0; frame_bank<=0; vs_delayed<=0;
            presented_valid<=0; presented_bank<=0;presented_identity<=0;presented_pulse<=0;frame_identity<=0;
        end else begin
            vs_delayed<=video_vs;presented_pulse<=0;
            if(video_de) begin
                if(!frame_enabled || !read_valid_pixel || pixels_seen>=FRAME_PIXELS)
                    frame_bad<=1;
                else begin
                    if(pixels_seen==0) begin frame_bank<=read_bank_sync[2];frame_identity<=current_identity;end
                    else if(frame_identity!=current_identity) frame_bad<=1;
                    pixels_seen<=pixels_seen+1'b1;
                end
            end
            if(vs_delayed && !video_vs) begin
                if(!frame_bad && pixels_seen==FRAME_PIXELS) begin
                    presented_valid<=1; presented_bank<=frame_bank;presented_identity<=frame_identity;presented_pulse<=1;
                end
                pixels_seen<=0; frame_bad<=0;
            end
        end
    end
endmodule
