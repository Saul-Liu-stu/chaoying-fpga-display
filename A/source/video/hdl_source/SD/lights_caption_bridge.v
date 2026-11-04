module lights_caption_bridge #(parameter integer BANK_AUTHORIZATION=0,FRAME_IDENTITY=0)(
    input wire [31:0] frame_authorizations,
    output reg [31:0] frame_authorizations_pixel,
    input wire sd_clk,sd_rst,active,
    input wire [1:0] role,
    input wire [6:0] count,
    input wire bank,
    input wire [1:0] allowed_banks,
    output wire source_ready,
    output reg [1:0] allowed_banks_pixel,
    input wire pixel_clk,pixel_rst,frame_boundary,
    output reg enable_pixel,bank_pixel,
    output reg [1:0] role_pixel,
    output reg [6:0] count_pixel,
    output reg [7:0] generation_pixel,
    output reg commit_pixel
);
    reg was_active;
    reg active_stage;
    wire packet_active=FRAME_IDENTITY ? active_stage : active;
    reg [7:0] generation;
    (* syn_preserve=1 *) reg [52:0] payload_hold;
    (* syn_preserve=1 *) reg [52:0] desired_stage;
    (* syn_preserve=1 *) reg request_toggle,ack_toggle;
    (* syn_preserve=1 *) reg [2:0] request_sync,ack_sync;
    reg [7:0] incremented_generation;
    reg [31:0] authorization_stage;
    wire [31:0] authorization_current=FRAME_IDENTITY && active ? frame_authorizations : 32'd0;
    wire [7:0] incremented=FRAME_IDENTITY ? incremented_generation : generation+8'd1;
    wire [7:0] next_generation=packet_active && !was_active ? incremented : generation;
    wire [31:0] authorization_desired=FRAME_IDENTITY ? authorization_stage : 32'd0;
    wire [52:0] desired={authorization_desired,next_generation,packet_active,packet_active ? role : 2'd0,
                        packet_active ? count : 7'd0,packet_active ? bank : 1'b0,
                        BANK_AUTHORIZATION && packet_active ? allowed_banks : 2'b00};
    wire same_generation=generation==desired_stage[20:13];
    wire new_generation=incremented_generation==desired_stage[20:13];
    wire session_matches_stage=(active && !was_active) ? new_generation : same_generation;
    wire current_matches_stage=session_matches_stage &&
        (active ? (desired_stage[12] && frame_authorizations==desired_stage[52:21] &&
            role==desired_stage[11:10] && count==desired_stage[9:3] && bank==desired_stage[2] &&
            (BANK_AUTHORIZATION ? allowed_banks==desired_stage[1:0] : desired_stage[1:0]==0)) :
            (desired_stage[12:0]==0 && desired_stage[52:21]==0));
    assign source_ready=request_toggle==ack_sync[2] && desired_stage==payload_hold && (FRAME_IDENTITY ? (active==active_stage && current_matches_stage && authorization_stage==desired_stage[52:21]) : desired==desired_stage);
    always @(posedge sd_clk or posedge sd_rst) begin
        if(sd_rst) begin
            was_active<=0; active_stage<=0; generation<=0; payload_hold<=0; desired_stage<=0; request_toggle<=0; ack_sync<=0; incremented_generation<=1; authorization_stage<=0;
        end else begin
            active_stage<=active; was_active<=packet_active; generation<=next_generation;
            authorization_stage<=authorization_current;
            if(packet_active && !was_active) incremented_generation<=incremented_generation+8'd1;
            desired_stage<=desired;
            ack_sync<={ack_sync[1:0],ack_toggle};
            if(request_toggle==ack_sync[2] && desired_stage!=payload_hold) begin
                payload_hold<=desired_stage; request_toggle<=~request_toggle;
            end
        end
    end
    always @(posedge pixel_clk or posedge pixel_rst) begin
        if(pixel_rst) begin
            request_sync<=0; ack_toggle<=0; enable_pixel<=0; bank_pixel<=0;
            role_pixel<=0; count_pixel<=0; generation_pixel<=0; commit_pixel<=0; allowed_banks_pixel<=0; frame_authorizations_pixel<=0;
        end else begin
            request_sync<={request_sync[1:0],request_toggle}; commit_pixel<=0;
            if(frame_boundary && request_sync[2]!=ack_toggle) begin
                {frame_authorizations_pixel,generation_pixel,enable_pixel,role_pixel,count_pixel,bank_pixel,allowed_banks_pixel}<=payload_hold;
                ack_toggle<=request_sync[2]; commit_pixel<=1;
            end
        end
    end
endmodule
