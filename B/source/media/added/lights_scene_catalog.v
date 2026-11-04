`timescale 1ns/1ps
module lights_scene_catalog (
    input wire clk, rst, catalog_ready,
    input wire [15:0] catalog_mask,
    output reg ready,
    output reg [15:0] available_mask,
    output reg [4:0] normal_count,
    input wire [3:0] normal_index,
    output wire [3:0] normal_load_index,
    output wire [4:0] normal_number,
    input wire [4:0] query_number,
    output wire query_valid,
    output wire [3:0] query_load_index,
    input wire [4:0] tile_query_number,
    output wire tile_query_valid,
    output wire [3:0] tile_query_load_index
);
    localparam [15:0] NORMAL_MASK = 16'hf007; // PIC01/02/03/13/14/15/16
    reg building;
    reg [4:0] cursor, compact_count;
    reg [3:0] pic_to_compact [0:15];
    reg [3:0] normal_to_compact [0:6];
    reg [4:0] normal_to_number [0:6];
    wire normal_valid = ready && {1'b0,normal_index} < normal_count;
    wire [3:0] query_slot = query_number - 5'd1;
    assign normal_load_index = normal_valid ? normal_to_compact[normal_index] : 4'd0;
    assign normal_number = normal_valid ? normal_to_number[normal_index] : 5'd0;
    assign query_valid = ready && query_number >= 1 && query_number <= 16 && available_mask[query_slot];
    assign query_load_index = query_valid ? pic_to_compact[query_slot] : 4'd0;
    wire [3:0] tile_query_slot=tile_query_number-5'd1;
    assign tile_query_valid=ready && tile_query_number>=1 && tile_query_number<=16 && available_mask[tile_query_slot];
    assign tile_query_load_index=tile_query_valid?pic_to_compact[tile_query_slot]:4'd0;

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ready <= 0; available_mask <= 0; normal_count <= 0;
            building <= 0; cursor <= 0; compact_count <= 0;
            for (i=0; i<16; i=i+1) pic_to_compact[i] <= 0;
            for (i=0; i<7; i=i+1) begin
                normal_to_compact[i] <= 0; normal_to_number[i] <= 0;
            end
        end else if (!ready) begin
            if (!building && catalog_ready) begin
                available_mask <= catalog_mask;
                building <= 1; cursor <= 0; compact_count <= 0; normal_count <= 0;
            end else if (building) begin
                if (cursor == 16) begin
                    if(normal_count==0)normal_count<=compact_count;
                    ready <= 1; building <= 0;
                end
                else begin
                    if (available_mask[cursor[3:0]]) begin
                        pic_to_compact[cursor[3:0]] <= compact_count[3:0];
                        compact_count <= compact_count + 1'b1;
                        if (NORMAL_MASK[cursor[3:0]]) begin
                            normal_to_compact[normal_count[2:0]] <= compact_count[3:0];
                            normal_to_number[normal_count[2:0]] <= cursor + 5'd1;
                            normal_count <= normal_count + 1'b1;
                        end
                    end
                    cursor <= cursor + 1'b1;
                end
            end
        end
    end
endmodule
