module media_start_controller #(
    parameter integer FRAME_PIXELS = 640 * 480,
    parameter integer PIXEL_FREQ_HZ = 25_000_000,
    parameter integer STARTUP_SETTLE_MS = 3000
)(
    input wire pixel_clk, pixel_rst, audio_clk, audio_rst,
    input wire video_link_locked, audio_packet_valid,
    input wire frame_enabled, video_de, video_vs,
    output reg startup_ready,
    output reg play_started,
    output wire audio_source_rst,
    output wire video_audio_rst
);
localparam integer COUNT_BITS = (FRAME_PIXELS < 2) ? 1 : $clog2(FRAME_PIXELS + 1);
localparam integer SETTLE_CYCLES = (PIXEL_FREQ_HZ / 1000) * STARTUP_SETTLE_MS;
localparam integer SETTLE_BITS = (SETTLE_CYCLES < 2) ? 1 : $clog2(SETTLE_CYCLES + 1);
reg [SETTLE_BITS-1:0] settle_count;
reg audio_packet_seen;
reg [COUNT_BITS-1:0] pixels_seen;
reg frame_bad, vs_delayed;

always @(posedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst) begin
        startup_ready <= 0; settle_count <= 0; audio_packet_seen <= 0;
    end else begin
        if (audio_packet_valid) audio_packet_seen <= 1;
        if (!play_started) begin
            if (!video_link_locked || !audio_packet_seen) begin
                startup_ready <= 0; settle_count <= 0;
            end else if (!startup_ready) begin
                if (SETTLE_CYCLES <= 1 || settle_count >= SETTLE_CYCLES-1)
                    startup_ready <= 1;
                else settle_count <= settle_count + 1'b1;
            end
        end
    end
end

always @(posedge pixel_clk or posedge pixel_rst) begin
    if (pixel_rst) begin
        play_started <= 0; pixels_seen <= 0; frame_bad <= 0; vs_delayed <= 0;
    end else begin
        vs_delayed <= video_vs;
        if (!play_started) begin
            if (video_de) begin
                if (!startup_ready || !frame_enabled || pixels_seen >= FRAME_PIXELS)
                    frame_bad <= 1;
                else pixels_seen <= pixels_seen + 1'b1;
            end
            if (vs_delayed && !video_vs) begin
                if (startup_ready && !frame_bad && pixels_seen == FRAME_PIXELS)
                    play_started <= 1;
                pixels_seen <= 0; frame_bad <= 0;
            end
        end
    end
end

assign video_audio_rst = pixel_rst;
reset_release_sync u_audio_start_reset (
    .clk(audio_clk), .async_reset(audio_rst | ~play_started), .rst(audio_source_rst)
);
endmodule
