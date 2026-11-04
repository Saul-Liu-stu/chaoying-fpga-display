module video_timing_data
#(
	parameter DATA_WIDTH = 16                       // Video data one clock data width
)
(
	input                       video_clk,          // Video pixel clock
	input                       rst,
	input                       startup_ready, // same pixel domain; local startup qualification
	input                       frame_valid_async, // SD domain: a complete image has been committed
	output reg                  display_enable,    // Pixel domain: this entire frame may be shown
	output reg                  read_req,           // Start reading a frame of data     
	input                       read_req_ack,       // Read request response
	output                      hs,                 // horizontal synchronization
	output                      vs,                 // vertical synchronization
	output                      de                  // video valid
);
wire                   video_hs;
wire                   video_vs;
wire                   video_de;
reg                    video_hs_d0;
reg                    video_vs_d0;
reg                    video_de_d0;
reg                    video_hs_d1;
reg                    video_vs_d1;
reg                    video_de_d1;

(* syn_preserve = 1 *) reg [2:0] frame_valid_sync;
(* syn_preserve = 1 *) reg [2:0] read_ack_sync;
reg                    read_for_this_frame;
reg                    frame_read_ready;
reg                    active_started;
wire                   frame_start = video_vs_d0 & ~video_vs;

assign hs = video_hs_d1;
assign vs = video_vs_d1;
assign de = video_de_d1;
always@(posedge video_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		video_hs_d0 <= 1'b0;
		video_vs_d0 <= 1'b0;
		video_de_d0 <= 1'b0;
		video_hs_d1 <= 1'b0;
		video_vs_d1 <= 1'b0;
		video_de_d1 <= 1'b0;
	end
	else
	begin
		video_hs_d0 <= video_hs;
		video_vs_d0 <= video_vs;
		video_de_d0 <= video_de;
		video_hs_d1 <= video_hs_d0;
		video_vs_d1 <= video_vs_d0;
		video_de_d1 <= video_de_d0;		
	end
end
/*
always@(posedge video_clk or posedge rst)
begin
	if(rst == 1'b1)
		vout_data_r <= {DATA_WIDTH{1'b0}};
	else if(video_de_d0)
		vout_data_r <= read_data;
	else
		vout_data_r <= {DATA_WIDTH{1'b0}};
end
*/
always@(posedge video_clk or posedge rst)
begin
	if(rst) begin
		frame_valid_sync <= 3'b000;
		read_ack_sync <= 3'b000;
	end else begin
		frame_valid_sync <= {frame_valid_sync[1:0], frame_valid_async};
		read_ack_sync <= {read_ack_sync[1:0], read_req_ack};
	end
end

always@(posedge video_clk or posedge rst)
begin
	if(rst) begin
		read_req <= 1'b0;
		read_for_this_frame <= 1'b0;
		frame_read_ready <= 1'b0;
		active_started <= 1'b0;
		display_enable <= 1'b0;
	end else begin
		if(read_req && read_ack_sync[2])
			read_req <= 1'b0;

		if(read_for_this_frame && !read_req && !read_ack_sync[2]) begin
			frame_read_ready <= 1'b1;
			read_for_this_frame <= 1'b0;
		end

		if(frame_start) begin
			frame_read_ready <= 1'b0;
			read_for_this_frame <= 1'b0;
			active_started <= 1'b0;
			display_enable <= 1'b0;
			if(startup_ready && frame_valid_sync[2] && !read_req && !read_ack_sync[2]) begin
				read_req <= 1'b1;
				read_for_this_frame <= 1'b1;
			end
		end else if(video_de_d1 && !active_started) begin
			active_started <= 1'b1;
			display_enable <= startup_ready && frame_valid_sync[2] && frame_read_ready;
		end

		if(!frame_valid_sync[2] || !startup_ready) begin
			display_enable <= 1'b0;
			frame_read_ready <= 1'b0;
			read_for_this_frame <= 1'b0;
		end
	end
end

color_bar color_bar_m0(
	.clk(video_clk),
	.rst(rst),
	.hs(video_hs),
	.vs(video_vs),
	.de(video_de),
	.rgb_r(),
	.rgb_g(),
	.rgb_b()
);
endmodule
