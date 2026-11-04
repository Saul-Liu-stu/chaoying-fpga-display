`timescale 1ns/1ps
module lights_sector_guard #(
    parameter integer TIMEOUT_CYCLES = 100_000_000
)(
    input wire clk, rst,
    input wire start,
    input wire [31:0] lba,
    output wire idle,
    output reg done,
    output reg [3:0] fault,
    input wire [8:0] buffer_addr,
    output reg [7:0] buffer_byte,
    output reg sd_read,
    output reg [31:0] sd_lba,
    input wire [7:0] sd_byte,
    input wire sd_valid, sd_end, sd_crc_bad
);
    localparam IDLE=0, RECEIVE=1, QUIET=2, LOCKED=3;
    reg [1:0] state;
    reg [9:0] received;
    reg [31:0] watchdog;
    reg [2:0] quiet_count;
    (* ram_style="block", syn_ramstyle="block_ram" *) reg [7:0] sector [0:511];
    assign idle = state == IDLE && fault == 0;
    always @(posedge clk) begin
        buffer_byte <= sector[buffer_addr];
        if (state == RECEIVE && sd_valid && received < 512)
            sector[received[8:0]] <= sd_byte;
    end
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state<=IDLE; received<=0; watchdog<=0; quiet_count<=0;
            done<=0; fault<=0; sd_read<=0; sd_lba<=0;
        end else begin
            done<=0;
            case(state)
                IDLE: begin
                    sd_read<=0;
                    if (sd_valid || sd_end) begin
                        fault<=3; state<=LOCKED;
                    end else if (start) begin
                        sd_lba<=lba; sd_read<=1; received<=0;
                        watchdog<=0; state<=RECEIVE;
                    end
                end
                RECEIVE: begin
                    watchdog<=watchdog+1'b1;
                    if (sd_valid) begin
                        sd_read<=0;
                        if (received < 512) received<=received+1'b1;
                    end
                    if (sd_end) begin
                        sd_read<=0;
                        if (sd_crc_bad) begin
                            fault<=4; state<=LOCKED;
                        end else if (received + (sd_valid ? 10'd1 : 10'd0) != 512) begin
                            fault<=2; state<=LOCKED;
                        end else begin
                            quiet_count<=0; state<=QUIET;
                        end
                    end else if (sd_valid && received >= 512) begin
                        fault<=2; sd_read<=0; state<=LOCKED;
                    end else if (watchdog >= TIMEOUT_CYCLES-1) begin
                        fault<=1; sd_read<=0; state<=LOCKED;
                    end
                end
                QUIET: begin
                    if (sd_valid || sd_end) begin
                        fault<=3; state<=LOCKED;
                    end else if (quiet_count==3) begin
                        done<=1; state<=IDLE;
                    end else quiet_count<=quiet_count+1'b1;
                end
                LOCKED: sd_read<=0;
                default: begin fault<=3; sd_read<=0; state<=LOCKED; end
            endcase
        end
    end
endmodule
