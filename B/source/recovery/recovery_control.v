`timescale 1ns/1ps
module tf_probe_supervisor #(
    parameter integer INIT_TIMEOUT = 1000000000,
    parameter integer RETRY_DELAY = 100000000,
    parameter integer RESET_CYCLES = 16,
    parameter integer READ_TIMEOUT = 120000000
)(
    input wire clk, hard_reset,
    input wire monitor_enable,
    input wire sd_ready,
    input wire [3:0] normal_guard_fault,
    input wire probe_idle, probe_done,
    input wire [3:0] probe_fault,
    input wire restart_accepted, restart_complete,
    output wire isolate, driver_reset, probe_reset, probe_start,
    output wire restart_request,
    output wire [2:0] debug_state
);
    localparam RUN=3'd0, RESET_SD=3'd1, WAIT_INIT=3'd2,
               START_READ=3'd3, WAIT_READ=3'd4, REQUEST=3'd5,
               WAIT_RESTART=3'd6, BACKOFF=3'd7;
    reg [2:0] state;
    reg [31:0] count;
    assign debug_state = state;
    assign isolate = state != RUN;
    assign driver_reset = state == RESET_SD || state == BACKOFF;
    assign probe_reset = driver_reset || state == RUN;
    assign probe_start = state == START_READ;
    assign restart_request = state == REQUEST;

    always @(posedge clk or posedge hard_reset) begin
        if (hard_reset) begin
            state <= RUN;
            count <= 0;
        end else begin
            case (state)
                RUN: begin
                    if (!monitor_enable || sd_ready) count <= 0;
                    else if (count < INIT_TIMEOUT-1) count <= count + 1'b1;
                    if (normal_guard_fault != 0 ||
                        (monitor_enable && !sd_ready && count >= INIT_TIMEOUT-1)) begin
                        state <= RESET_SD;
                        count <= 0;
                    end
                end
                RESET_SD: begin
                    if (count >= RESET_CYCLES-1) begin
                        state <= WAIT_INIT;
                        count <= 0;
                    end else count <= count + 1'b1;
                end
                WAIT_INIT: begin
                    if (sd_ready && probe_idle) begin state <= START_READ; count <= 0; end
                    else if (count >= INIT_TIMEOUT-1) begin state <= BACKOFF; count <= 0; end
                    else count <= count + 1'b1;
                end
                START_READ: begin state <= WAIT_READ; count <= 0; end
                WAIT_READ: begin
                    if (probe_done) begin state <= REQUEST; count <= 0; end
                    else if (probe_fault != 0 || count >= READ_TIMEOUT-1) begin
                        state <= BACKOFF; count <= 0;
                    end else count <= count + 1'b1;
                end
                REQUEST: if (restart_accepted) state <= WAIT_RESTART;
                WAIT_RESTART: if (restart_complete && normal_guard_fault == 0) begin
                    state <= RUN; count <= 0;
                end
                BACKOFF: begin
                    if (count >= RETRY_DELAY-1) begin state <= RESET_SD; count <= 0; end
                    else count <= count + 1'b1;
                end
                default: begin state <= RESET_SD; count <= 0; end
            endcase
        end
    end
endmodule

`timescale 1ns/1ps
module probe_sector_checker #(parameter integer TIMEOUT_CYCLES=100000000)(
    input wire clk,rst,start,
    output wire idle,output reg done,output reg [3:0] fault,
    output reg sd_read,output wire [31:0] sd_lba,
    input wire sd_valid,sd_end,sd_crc_bad
);
    localparam IDLE=0,RECEIVE=1,QUIET=2,LOCKED=3;
    reg [1:0] state;reg [9:0] count;reg [31:0] watchdog;reg [2:0] quiet;
    assign idle=state==IDLE && fault==0;
    assign sd_lba=32'h0;
    always @(posedge clk or posedge rst)begin
        if(rst)begin state<=IDLE;count<=0;watchdog<=0;quiet<=0;done<=0;fault<=0;sd_read<=0;end
        else begin
            done<=0;
            case(state)
                IDLE:begin
                    sd_read<=0;
                    if(sd_valid || sd_end)begin fault<=3;state<=LOCKED;end
                    else if(start)begin sd_read<=1;count<=0;watchdog<=0;state<=RECEIVE;end
                end
                RECEIVE:begin
                    watchdog<=watchdog+1'b1;
                    if(sd_valid)begin sd_read<=0;if(count<512)count<=count+1'b1;end
                    if(sd_end)begin
                        sd_read<=0;
                        if(sd_crc_bad)begin fault<=4;state<=LOCKED;end
                        else if(count+(sd_valid?10'd1:10'd0)!=512)begin fault<=2;state<=LOCKED;end
                        else begin quiet<=0;state<=QUIET;end
                    end else if(sd_valid && count>=512)begin fault<=2;sd_read<=0;state<=LOCKED;end
                    else if(watchdog>=TIMEOUT_CYCLES-1)begin fault<=1;sd_read<=0;state<=LOCKED;end
                end
                QUIET:if(sd_valid || sd_end)begin fault<=3;state<=LOCKED;end
                      else if(quiet==3)begin done<=1;state<=IDLE;end else quiet<=quiet+1'b1;
                LOCKED:sd_read<=0;
                default:begin fault<=3;sd_read<=0;state<=LOCKED;end
            endcase
        end
    end
endmodule

`timescale 1ns/1ps
module restart_master #(
    parameter integer QUIET_CYCLES=8, RETRY_CYCLES=5000, HOLD_CYCLES=2000
)(
    input wire clk,hard_reset,trigger,busy,available,app_tx_activity,
    input wire [111:0] recv_info,
    output reg send,output reg [111:0] send_info,output wire take,
    output wire block_app,freeze_rx,soft_reset,output reg accepted,complete,exhausted,
    output reg [15:0] epoch
);
    localparam IDLE=0,DRAIN=1,SEND_PREP=2,WAIT_PREP_TX=3,WAIT_READY=4,
               SEND_COMMIT=5,WAIT_COMMIT_TX=6,WAIT_FINAL=7,RESET=8;
    localparam [31:0] MAGIC=32'h52535431;
    reg [3:0] state;reg [31:0] count;reg [15:0] epoch_base;
    wire is_ack=recv_info[111:104]==8'h91 && recv_info[95:80]==epoch &&
                recv_info[79:64]==~epoch && recv_info[31:0]==MAGIC;
    assign block_app=state!=IDLE;
    assign freeze_rx=state!=IDLE;
    assign soft_reset=state==RESET;
    assign take=available && (recv_info[111:104]==8'h91 || freeze_rx);
    always @(posedge clk or posedge hard_reset) begin
        if(hard_reset)begin state<=IDLE;count<=0;send<=0;send_info<=0;accepted<=0;complete<=0;epoch<=0;epoch_base<=0;exhausted<=0;end
        else begin
            send<=0;accepted<=0;complete<=0;
            case(state)
                IDLE:if(!exhausted && trigger)begin accepted<=1;state<=DRAIN;count<=0;epoch_base<=epoch;end
                DRAIN:if(busy || app_tx_activity)count<=0;
                      else if(count<QUIET_CYCLES)count<=count+1'b1;
                      else begin
                          if(epoch_base==16'hffff)begin exhausted<=1;state<=IDLE;end
                          else begin epoch<=epoch_base+1'b1;state<=SEND_PREP;count<=0;end
                      end
                SEND_PREP:if(!busy)begin
                    send<=1;send_info<={8'd17,8'd0,epoch,~epoch,32'h0,MAGIC};state<=WAIT_PREP_TX;
                end
                WAIT_PREP_TX:if(busy)begin state<=WAIT_READY;count<=0;end
                WAIT_READY:begin
                    if(available && is_ack && recv_info[103:96]==0)begin state<=SEND_COMMIT;count<=0;end
                    else if(!busy && count>=RETRY_CYCLES-1)begin state<=SEND_PREP;count<=0;end
                    else if(!busy)count<=count+1'b1;
                end
                SEND_COMMIT:if(!busy)begin
                    send<=1;send_info<={8'd17,8'd1,epoch,~epoch,32'h0,MAGIC};state<=WAIT_COMMIT_TX;
                end
                WAIT_COMMIT_TX:if(busy)begin state<=WAIT_FINAL;count<=0;end
                WAIT_FINAL:begin
                    if(available && is_ack && recv_info[103:96]==1)begin state<=RESET;count<=0;end
                    else if(!busy && count>=RETRY_CYCLES-1)begin state<=SEND_PREP;count<=0;end
                    else if(!busy)count<=count+1'b1;
                end
                RESET:if(count>=HOLD_CYCLES-1)begin state<=IDLE;count<=0;complete<=1;end
                      else count<=count+1'b1;
                default:begin state<=IDLE;count<=0;end
            endcase
        end
    end
endmodule

module restart_slave #(
    parameter integer QUIET_CYCLES=8,HOLD_CYCLES=1000,WAIT_CYCLES=10000
)(
    input wire clk,hard_reset,busy,available,app_tx_activity,input wire [111:0] recv_info,
    output reg send,output reg [111:0] send_info,output wire take,
    output wire block_app,freeze_rx,soft_reset,output reg [15:0] epoch
);
    localparam IDLE=0,DRAIN=1,SEND_ACK=2,WAIT_BUSY=3,WAIT_DONE=4,WAIT_COMMIT=5,RESET=6;
    localparam AFTER_IDLE=0,AFTER_WAIT=1,AFTER_RESET=2;
    localparam [31:0] MAGIC=32'h52535431;
    reg [2:0] state;reg [1:0] after_send,ack_phase;reg [31:0] count;reg [15:0] pending_epoch;
    wire is_control=recv_info[111:104]==8'd17;
    wire valid_request=is_control && recv_info[79:64]==~recv_info[95:80] &&
                       recv_info[31:0]==MAGIC && recv_info[95:80]!=0 && recv_info[103:96]<=1;
    assign block_app=state!=IDLE || (available && is_control);
    assign freeze_rx=state!=IDLE;
    assign soft_reset=state==RESET;
    assign take=available && (is_control || freeze_rx);
    always @(posedge clk or posedge hard_reset)begin
        if(hard_reset)begin state<=IDLE;count<=0;pending_epoch<=0;send<=0;send_info<=0;epoch<=0;after_send<=0;ack_phase<=0;end
        else begin
            send<=0;
            case(state)
                IDLE:if(available && valid_request)begin
                    if(recv_info[103:96]==0 && recv_info[95:80]>epoch)begin
                        pending_epoch<=recv_info[95:80];ack_phase<=0;after_send<=AFTER_WAIT;state<=DRAIN;count<=0;
                    end else if(recv_info[95:80]==epoch)begin
                        pending_epoch<=epoch;ack_phase<={1'b0,recv_info[96]};after_send<=AFTER_IDLE;state<=DRAIN;count<=0;
                    end
                end
                DRAIN:if(busy || app_tx_activity)count<=0;
                      else if(count<QUIET_CYCLES)count<=count+1'b1;
                      else begin state<=SEND_ACK;count<=0;end
                SEND_ACK:if(!busy)begin send<=1;
                    send_info<={8'h91,{6'd0,ack_phase},pending_epoch,~pending_epoch,32'h0,MAGIC};
                    state<=WAIT_BUSY;end
                WAIT_BUSY:if(busy)state<=WAIT_DONE;
                WAIT_DONE:if(!busy)begin
                    count<=0;
                    if(after_send==AFTER_RESET)begin epoch<=pending_epoch;state<=RESET;end
                    else if(after_send==AFTER_WAIT)state<=WAIT_COMMIT;
                    else state<=IDLE;
                end
                WAIT_COMMIT:begin
                    if(available && valid_request && recv_info[103:96]<=1 && recv_info[95:80]==pending_epoch)begin
                        ack_phase<={1'b0,recv_info[96]};
                        after_send<=recv_info[96]?AFTER_RESET:AFTER_WAIT;
                        state<=DRAIN;count<=0;
                    end else if(count>=WAIT_CYCLES-1)begin state<=IDLE;count<=0;end
                    else count<=count+1'b1;
                end
                RESET:if(count>=HOLD_CYCLES-1)begin state<=IDLE;count<=0;end else count<=count+1'b1;
                default:begin state<=IDLE;count<=0;end
            endcase
        end
    end
endmodule
