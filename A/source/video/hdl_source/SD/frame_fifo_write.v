`timescale 1ns/1ps
module frame_fifo_write
#
(
	parameter MEM_DATA_BITS          = 32,
    parameter FRAME_IDENTITY         = 0,
    parameter RECTANGLES             = 0,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter BURST_SIZE             = 128,
	parameter WRITE_V_FLIP           = 1,      // 1: write image rows upside-down to cancel BMP bottom-up storage
	parameter FRAME_WIDTH            = 640,
	parameter FRAME_HEIGHT           = 480
)               
(
    input [20:0] write_rect_first,
    input [10:0] write_rect_width,
    input [11:0] write_rect_jump,
    input [31:0]                     write_frame_identity,
    output reg [31:0]                active_write_identity,
	input                            rst,                  
	input                            mem_clk,                    // external memory controller user interface clock
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
	input							 App_rd_busy,
    output							 O_wr_busy,
	
	output 							 App_wr_en,
	output  [ADDR_BITS - 1:0]	 	App_wr_addr,
	/*
    output reg                       wr_burst_req,               // to external memory controller,send out a burst write request  
	output reg[BURST_BITS - 1:0]     wr_burst_len,               // to external memory controller,data length of the burst write request, not bytes 
	output reg[ADDR_BITS - 1:0]      wr_burst_addr,              // to external memory controller,base address of the burst write request 
	input                            wr_burst_data_req,          // from external memory controller,write data request ,before data 1 clock 
	input                            wr_burst_finish,            // from external memory controller,burst write finish
	*/
	input                            write_req,                  // data write module write request,keep '1' until read_req_ack = '1'
	output reg                       write_req_ack,              // data write module write request response
	output                           write_finish,               // data write module write request finish
	input[ADDR_BITS - 1:0]           write_addr_0,               // data write module write request base address 0, used when write_addr_index = 0
	input[ADDR_BITS - 1:0]           write_addr_1,               // data write module write request base address 1, used when write_addr_index = 1
	input[ADDR_BITS - 1:0]           write_addr_2,               // data write module write request base address 1, used when write_addr_index = 2
	input[ADDR_BITS - 1:0]           write_addr_3,               // data write module write request base address 1, used when write_addr_index = 3
	input[1:0]                       write_addr_index,           // select valid base address from write_addr_0 write_addr_1 write_addr_2 write_addr_3
	input[ADDR_BITS - 1:0]           write_len,                  // data write module write request data length
	output reg                       fifo_aclr,                  // to fifo asynchronous clear
	input[9:0]                      rdusedw                     // from fifo read used words
);
localparam ONE                       = 256'd1;                   //256 bit '1'   you can use ONE[n-1:0] for n bit '1'
localparam ZERO                      = 256'd0;                   //256 bit '0'

localparam [ADDR_BITS - 1:0] VFLIP_FIRST_ADDR_OFFSET = (FRAME_HEIGHT - 1) * FRAME_WIDTH;
localparam [ADDR_BITS - 1:0] VFLIP_LINE_JUMP         = (FRAME_WIDTH * 2) - 1;
localparam [15:0]            VFLIP_LINE_LAST_X       = FRAME_WIDTH - 1;

localparam S_IDLE                    = 0;                        //idle state,waiting for write
localparam S_ACK                     = 1;                        //written request response
localparam S_CHECK_FIFO              = 2;                        //check the FIFO status, ensure that there is enough space to burst write
localparam S_WRITE_BURST             = 3;                        //begin a burst write
localparam S_WRITE_BURST_END         = 4;                        //a burst write complete
localparam S_END                     = 5;                        //a frame of data is written to complete


(* syn_preserve = 1 *) reg                                 write_req_d0;                //asynchronous write request, synchronize to 'mem_clk' clock domain,first beat
(* syn_preserve = 1 *) reg                                 write_req_d1;                //the second
(* syn_preserve = 1 *) reg                                 write_req_d2;                //third,Why do you need 3 ? Here's the design habit
reg[ADDR_BITS - 1:0] write_len_d0; // stable SD payload; constant bits may propagate
reg[ADDR_BITS - 1:0] write_len_d1; // second memory sampler, locked by request ACK
reg[ADDR_BITS - 1:0]                write_len_latch;             //lock write data length
reg[ADDR_BITS - 1:0]                write_cnt;                   //write data counter
(* syn_preserve = 1 *) reg[1:0]                            write_addr_index_d0;
(* syn_preserve = 1 *) reg[1:0]                            write_addr_index_d1;
reg[3:0]                            state;                       //state machine
reg [ADDR_BITS - 1:0]	 App_wr_addr_r;
reg [(RECTANGLES ? 10 : 16)-1:0] wr_x;
reg rect_row_last;reg [9:0] rect_penultimate;

reg [BURST_BITS - 1:0]				burst_cnt;
wire								wr_burst_finish;

reg App_wr_en_r;
reg App_wr_en_d0;

reg [3:0] write_drain;
always @(posedge mem_clk or posedge rst) begin
    if(rst || App_wr_en) write_drain<=0;
    else if(write_drain<4'd10) write_drain<=write_drain+1'b1;
end


reg fifo_ready;
reg [ADDR_BITS-1:0] remaining_words;
reg [BURST_BITS-1:0] burst_target;
always @(posedge mem_clk or posedge rst) begin
    if(rst) begin remaining_words<=0;burst_target<=BURST_SIZE;end
    else begin
        remaining_words<=write_len_latch-write_cnt;
        if(state==S_CHECK_FIFO)
            burst_target<=remaining_words<BURST_SIZE ? remaining_words[BURST_BITS-1:0] : BURST_SIZE;
    end
end
always @(posedge mem_clk or posedge rst) begin
    if (rst)
        fifo_ready <= 1'b0;
    else if (state == S_CHECK_FIFO && !write_req_d2)
        fifo_ready <= RECTANGLES ? (burst_target!=0 && rdusedw>=burst_target) : ((write_len_latch <= (rdusedw + write_cnt)) || (rdusedw > BURST_SIZE));
    else
        fifo_ready <= 1'b0;
end
reg [10:0] rect_last;reg [11:0] rect_jump;
(* syn_preserve=1 *) reg [43:0] rect_stage0,rect_stage1;
always @(posedge mem_clk or posedge rst) begin
    if(rst) begin rect_stage0<=0;rect_stage1<=0;end
    else begin rect_stage0<={write_rect_first,write_rect_width,write_rect_jump};rect_stage1<=rect_stage0;end
end
reg ack_latched;
(* syn_preserve=1 *) reg [31:0] identity_stage0,identity_stage1;
always @(posedge mem_clk or posedge rst) begin
    if(rst) begin identity_stage0<=0;identity_stage1<=0;end
    else begin identity_stage0<=write_frame_identity;identity_stage1<=identity_stage0;end
end
wire [1:0] write_index_payload=FRAME_IDENTITY ? identity_stage1[1:0] : write_addr_index_d1;
wire into_burst;
assign into_burst = fifo_ready && ~App_rd_busy && !Sdr_busy && !Sdr_init_ref_vld;

assign App_wr_addr = {App_wr_addr_r[ADDR_BITS - 1:0]};
assign O_wr_busy = (state == S_WRITE_BURST || state == S_WRITE_BURST_END || (state == S_CHECK_FIFO && into_burst));//在突发，或者将要突发，则显示busy
assign wr_burst_finish = burst_cnt >= (RECTANGLES ? burst_target : BURST_SIZE);
assign write_finish = (state == S_END) ? 1'b1 : 1'b0;            //write finish at state 'S_END'
assign App_wr_en = App_wr_en_d0;


always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		write_req_d0    <=  1'b0;
		write_req_d1    <=  1'b0;
		write_req_d2    <=  1'b0;
		write_len_d0    <=  ZERO[ADDR_BITS - 1:0];              //equivalent to write_len_d0 <= 0;
		write_len_d1    <=  ZERO[ADDR_BITS - 1:0];              //equivalent to write_len_d1 <= 0;
		write_addr_index_d0    <=  2'b00;
		write_addr_index_d1    <=  2'b00;
	end
	else
	begin
		write_req_d0    <=  write_req;
		write_req_d1    <=  write_req_d0;
		write_req_d2    <=  write_req_d1;
		write_len_d0    <=  write_len;
		write_len_d1    <=  write_len_d0;
		write_addr_index_d0 <= write_addr_index;
		write_addr_index_d1 <= write_addr_index_d0;
	end 
end
always @(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		burst_cnt <= ZERO[BURST_BITS - 1:0];
		App_wr_addr_r <= ZERO[ADDR_BITS - 1:0];
		App_wr_en_d0 <= 1'b0;
        ack_latched<=0;active_write_identity<=0;rect_last<=0;rect_jump<=0;rect_row_last<=0;rect_penultimate<=0;
		wr_x <= 16'd0;
	end
	else begin
        if(state!=S_ACK) ack_latched<=0;
	
		if(state == S_CHECK_FIFO)
			burst_cnt <= ZERO[BURST_BITS - 1:0];
		else if(App_wr_en)
			burst_cnt <= burst_cnt + 1'b1;
		else
			burst_cnt <= burst_cnt;
		if(state == S_ACK && (!FRAME_IDENTITY || !ack_latched))
			begin
                ack_latched<=1;active_write_identity<=identity_stage1;
				wr_x <= 16'd0;
				if(RECTANGLES) begin
                    App_wr_addr_r<=rect_stage1[43:23];rect_last<=rect_stage1[22:12]-11'd1;rect_jump<=rect_stage1[11:0];
                    rect_row_last<=rect_stage1[22:12]==1;rect_penultimate<=rect_stage1[22:12]-11'd2;
                end else if(write_index_payload == 2'd0)
					App_wr_addr_r <= WRITE_V_FLIP ? (write_addr_0 + VFLIP_FIRST_ADDR_OFFSET) : write_addr_0;
				else if(write_index_payload == 2'd1)
					App_wr_addr_r <= WRITE_V_FLIP ? (write_addr_1 + VFLIP_FIRST_ADDR_OFFSET) : write_addr_1;
				else if(write_index_payload == 2'd2)
					App_wr_addr_r <= WRITE_V_FLIP ? (write_addr_2 + VFLIP_FIRST_ADDR_OFFSET) : write_addr_2;
				else if(write_index_payload == 2'd3)
					App_wr_addr_r <= WRITE_V_FLIP ? (write_addr_3 + VFLIP_FIRST_ADDR_OFFSET) : write_addr_3;
			end
		else if(App_wr_en)
			begin
				if(WRITE_V_FLIP)
				begin
					if(RECTANGLES ? rect_row_last : wr_x==VFLIP_LINE_LAST_X)
					begin
						wr_x <= 16'd0;
                        rect_row_last<=rect_last==0;
						App_wr_addr_r <= App_wr_addr_r - (RECTANGLES ? rect_jump : VFLIP_LINE_JUMP);
					end
					else
					begin
						wr_x <= wr_x + 1'b1;
                        rect_row_last<=wr_x==rect_penultimate;
						App_wr_addr_r <= App_wr_addr_r + 1'b1;
					end
				end
				else
					App_wr_addr_r <= App_wr_addr_r + 1'b1;
			end
		else
			App_wr_addr_r <= App_wr_addr_r;
		if(App_wr_en_r && (RECTANGLES ? (burst_cnt + App_wr_en < burst_target) : (burst_cnt + App_wr_en < BURST_SIZE && (burst_cnt + write_cnt + App_wr_en < write_len_latch))))begin
            App_wr_en_d0 <= 1'b1;
        end
		else
			App_wr_en_d0 <= 1'b0;
	
	end		
end
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		state <= S_IDLE;
		write_len_latch <= ZERO[ADDR_BITS - 1:0];
		
		App_wr_en_r <= 1'b0;
		
		write_cnt <= ZERO[ADDR_BITS - 1:0];
		fifo_aclr <= 1'b0;
		write_req_ack <= 1'b0;
		
		
	end
	else 
		case(state)
			S_IDLE:
			begin
				if(write_req_d2 == 1'b1 && Sdr_init_done)
				begin
					state <= S_ACK;
				end
				write_req_ack <= 1'b0;
			end
			S_ACK:
			begin
				if(write_req_d2 == 1'b0)
				begin
					state <= S_CHECK_FIFO;
					fifo_aclr <= 1'b0;
					write_req_ack <= 1'b0;
				end
				else
				begin
					write_req_ack <= 1'b1;
					fifo_aclr <= 1'b1;
					/*
					if(write_index_payload == 2'd0)
						wr_burst_addr <= write_addr_0;
					else if(write_index_payload == 2'd1)
						wr_burst_addr <= write_addr_1;
					else if(write_index_payload == 2'd2)
						wr_burst_addr <= write_addr_2;
					else if(write_index_payload == 2'd3)
						wr_burst_addr <= write_addr_3;
					*/
					write_len_latch <= write_len_d1;                    
				end
				write_cnt <= ZERO[ADDR_BITS - 1:0];
			end
			S_CHECK_FIFO:
			begin
				if(write_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				else if(into_burst)
				begin
					state <= S_WRITE_BURST;
					App_wr_en_r <= 1'b1;
				end
			end 
			
			S_WRITE_BURST:
			begin
				if(wr_burst_finish == 1'b1)
				begin
					App_wr_en_r <= 1'b0;
					state <= S_WRITE_BURST_END;
					write_cnt <= write_cnt + (RECTANGLES ? burst_cnt : BURST_SIZE[ADDR_BITS - 1:0]);
				end     
			end
			S_WRITE_BURST_END:
			if(write_drain == 4'd10) begin
				if(write_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				else if(write_cnt < write_len_latch)
				begin
					state <= S_CHECK_FIFO;
				end
				else
				begin
					state <= S_END;
				end
			end
			S_END:
			begin
				state <= S_IDLE;
			end
			default:
				state <= S_IDLE;
		endcase
end
endmodule
