`timescale 1ns/1ps
module lights_scene_keys #(
    parameter integer CLK_FREQ_HZ=100_000_000,
    parameter integer DEBOUNCE_MS=20,
    parameter integer GAP_MS=150,
    parameter integer LONG_MS=800,
    parameter integer CHORD_MS=1000
)(
    input wire clk,rst,key1,key2,confirm_ready,
    output wire next_press,prev_press,short_press,chord_press,confirm_short
);
    wire pressed1,pressed2;
    reg pressed2_d,confirm_armed;
    assign confirm_short=short_press && confirm_armed;
    always @(posedge clk or posedge rst) begin
        if(rst) begin pressed2_d<=1; confirm_armed<=0; end
        else begin
            pressed2_d<=pressed2;
            if(pressed2 && !pressed2_d) confirm_armed<=confirm_ready && !pressed1;
            else if(pressed2 && !confirm_ready) confirm_armed<=0;
        end
    end
    lights_scene_button #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_button1(
        .clk(clk),.rst(rst),.button_in(key1),.pressed(pressed1));
    lights_scene_button #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_button2(
        .clk(clk),.rst(rst),.button_in(key2),.pressed(pressed2));
    lights_key_events #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.GAP_MS(GAP_MS),
        .LONG_MS(LONG_MS),.CHORD_MS(CHORD_MS)) u_events(
        .clk(clk),.rst(rst),.pressed1(pressed1),.pressed2(pressed2),
        .next_press(next_press),.prev_press(prev_press),.short_press(short_press),.chord_press(chord_press));
endmodule

module lights_scene_button #(
    parameter integer CLK_FREQ_HZ=100_000_000,DEBOUNCE_MS=20
)(input wire clk,rst,button_in,output wire pressed);
    localparam integer CYCLES=(CLK_FREQ_HZ/1000)*DEBOUNCE_MS;
    localparam integer BITS=CYCLES<2 ? 1 : $clog2(CYCLES+1);
    (* syn_preserve=1 *) reg [2:0] button_sync;
    reg [2:0] warmup;
    reg stable;
    reg [BITS-1:0] count;
    assign pressed=~stable;
    always @(posedge clk or posedge rst) begin
        if(rst) begin button_sync<=3'b111; warmup<=0; stable<=0; count<=0; end
        else begin
            button_sync<={button_sync[1:0],button_in};
            warmup<={warmup[1:0],1'b1};
            if(!warmup[2] || button_sync[2]==stable) count<=0;
            else if(CYCLES<=1 || count>=CYCLES-1) begin stable<=button_sync[2]; count<=0; end
            else count<=count+1'b1;
        end
    end
endmodule

module lights_key_events #(
    parameter integer CLK_FREQ_HZ=100_000_000,GAP_MS=150,LONG_MS=800,CHORD_MS=1000
)(
    input wire clk,rst,pressed1,pressed2,
    output reg next_press,prev_press,short_press,chord_press
);
    localparam integer GAP=(CLK_FREQ_HZ/1000)*GAP_MS;
    localparam integer LONG=(CLK_FREQ_HZ/1000)*LONG_MS;
    localparam integer CHORD=(CLK_FREQ_HZ/1000)*CHORD_MS;
    localparam integer BITS=$clog2(CHORD+1);
    localparam [2:0] LOCK=0,IDLE=1,FIRST1=2,FIRST2=3,BOTH=4;
    reg [2:0] state;
    reg [BITS-1:0] age;
    always @(posedge clk or posedge rst) begin
        if(rst) begin state<=LOCK; age<=0; next_press<=0; prev_press<=0; short_press<=0; chord_press<=0; end
        else begin
            next_press<=0; prev_press<=0; short_press<=0; chord_press<=0;
            case(state)
                LOCK: begin age<=0; if(!pressed1 && !pressed2) state<=IDLE; end
                IDLE: begin
                    age<=0;
                    if(pressed1 && pressed2) state<=BOTH;
                    else if(pressed1) state<=FIRST1;
                    else if(pressed2) state<=FIRST2;
                end
                FIRST1: begin
                    if(pressed1 && pressed2 && age<=GAP-1) begin state<=BOTH; age<=0; end
                    else if(age>=GAP-1) begin next_press<=1; state<=LOCK; age<=0; end
                    else age<=age+1'b1;
                end
                FIRST2: begin
                    if(pressed1 && pressed2 && age<=GAP-1) begin state<=BOTH; age<=0; end
                    else if(age>=LONG-1) begin prev_press<=1; state<=LOCK; age<=0; end
                    else if(!pressed2) begin short_press<=1; state<=LOCK; age<=0; end
                    else age<=age+1'b1;
                end
                BOTH: begin
                    if(age>=CHORD-1) begin chord_press<=1; state<=LOCK; age<=0; end
                    else if(!pressed1 || !pressed2) begin state<=LOCK; age<=0; end
                    else age<=age+1'b1;
                end
                default: state<=LOCK;
            endcase
        end
    end
endmodule
