module lights_font_request_bridge(
    input wire pixel_clk,pixel_rst,request_toggle,cancel_toggle,
    input wire [55:0] request_payload,
    input wire sd_clk,sd_rst,
    output reg sd_request_toggle,sd_request_expired,
    output reg [55:0] sd_request_payload
);
    reg [55:0] packet;
    reg token,epoch,request_seen,beat_toggle;
    reg [3:0] beat_data,send_index;
    reg [1:0] send_state;
    reg beat_ack;
    (* syn_preserve=1 *) reg [2:0] ack_sync,beat_sync,cancel_sync;
    reg beat_seen,receive_token,receive_epoch;
    reg [3:0] receive_index;
    reg [55:0] assembled;
    reg [3:0] captured;
    reg receive_pending;
    always @(posedge pixel_clk or posedge pixel_rst) begin
        if(pixel_rst) begin
            packet<=0;token<=0;epoch<=0;request_seen<=0;beat_toggle<=0;
            beat_data<=0;send_index<=0;send_state<=0;ack_sync<=0;
        end else begin
            ack_sync<={ack_sync[1:0],beat_ack};
            case(send_state)
                0:if(request_toggle!=request_seen) begin
                    packet<=request_payload;token<=request_toggle;epoch<=cancel_toggle;
                    request_seen<=request_toggle;send_index<=0;send_state<=1;
                end
                1:begin
                    beat_data<=send_index==0 ? {2'd0,epoch,token} : packet[3:0];
                    send_state<=2;
                end
                2:begin beat_toggle<=~beat_toggle;send_state<=3;end
                3:if(ack_sync[2]==beat_toggle) begin
                    if(send_index==14)send_state<=0;
                    else begin
                        if(send_index!=0)packet<=packet>>4;
                        send_index<=send_index+1'b1;send_state<=1;
                    end
                end
            endcase
        end
    end
    integer lane;
    always @(posedge sd_clk or posedge sd_rst) begin
        if(sd_rst) assembled<=0;
        else if(receive_pending && receive_index!=0)
            for(lane=0;lane<14;lane=lane+1)
                if(receive_index==lane+1)assembled[lane*4 +: 4]<=captured;
    end
    always @(posedge sd_clk or posedge sd_rst) begin
        if(sd_rst) begin
            beat_ack<=0;beat_sync<=0;cancel_sync<=0;beat_seen<=0;
            receive_token<=0;receive_epoch<=0;receive_index<=0;captured<=0;receive_pending<=0;
            sd_request_toggle<=0;sd_request_expired<=0;sd_request_payload<=0;
        end else begin
            beat_sync<={beat_sync[1:0],beat_toggle};cancel_sync<={cancel_sync[1:0],cancel_toggle};
            if(beat_sync[2]!=beat_seen && !receive_pending) begin
                beat_seen<=beat_sync[2];captured<=beat_data;receive_pending<=1;
            end else if(receive_pending) begin
                receive_pending<=0;beat_ack<=beat_seen;
                if(receive_index==0) begin receive_token<=captured[0];receive_epoch<=captured[1];end
                if(receive_index==14)begin
                    sd_request_payload<={captured,assembled[51:0]};
                    sd_request_expired<=receive_epoch!=cancel_sync[2];
                    sd_request_toggle<=receive_token;receive_index<=0;
                end else receive_index<=receive_index+1'b1;
            end
        end
    end
endmodule
