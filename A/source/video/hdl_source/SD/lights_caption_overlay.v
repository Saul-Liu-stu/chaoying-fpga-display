module lights_caption_overlay #(parameter integer BANK_AUTHORIZATION=0,FRAME_IDENTITY=0)(
    input wire [31:0] read_frame_identity,frame_authorizations,
    input wire sd_clk,cache_we,
    input wire [9:0] cache_address,
    input wire [23:0] cache_row,
    input wire clk,rst,hs,vs,de,frame_enabled,read_valid,read_bank,
    input wire [23:0] rgb,
    input wire enable,metadata_bank,
    input wire [1:0] allowed_banks,
    input wire [1:0] role,
    input wire [6:0] count,
    input wire [7:0] generation,
    output reg request_toggle,cancel_toggle,
    output reg [55:0] request_payload,
    input wire response_toggle,response_good,font_bad,
    input wire map_cache_we,
    input wire [6:0] map_cache_address,
    input wire [4:0] map_cache_slot,
    input wire [31:0] response_mask,
    output wire frame_boundary,
    output reg out_hs,out_vs,out_de,
    output reg [23:0] out_rgb,
    input wire visible // frame-latched,draw-only switch;engine continues
);
    (* ram_style="block",syn_ramstyle="block_ram" *) reg [23:0] rows[0:1023];
    always @(posedge sd_clk) if(cache_we) rows[cache_address]<=cache_row;
    (* ram_style="block",syn_ramstyle="block_ram" *) reg [4:0] window_maps[0:127];
    always @(posedge sd_clk) if(map_cache_we) window_maps[map_cache_address]<=map_cache_slot;
    reg position_bank;
    reg [31:0] pin_mask;
    reg [4:0] slot_q;
    reg [23:0] font_q;
    reg vs_old,de_old;
    reg [9:0] x;
    reg [8:0] y;
    reg session_enable,current_ready,session_disabled,outstanding,stalled;
    reg [7:0] session_generation;
    reg [1:0] session_role,speed_phase;
    reg [9:0] leading;
    reg [6:0] first_index;
    reg [4:0] first_column;
    reg [5:0] gap;
    reg [6:0] scan_index;
    reg [4:0] scan_column;
    (* syn_preserve=1 *) reg [2:0] response_sync,bad_sync;
    wire response_available=outstanding && response_sync[2]==request_toggle;
    wire response_identity=request_payload[55:48]==session_generation && request_payload[47:46]==session_role;
    wire changed=enable!=session_enable || generation!=session_generation || role!=session_role;
    wire qualified;
    wire scan_active=qualified && de && y>=454 && y<478 &&
        x>=24 && x<616 && (leading==0 || x>=24+leading);
    wire in_band=de && y>=452 && y<480 && x>=24 && x<616;
    wire draw=scan_active && scan_index<count && y>=454 && y<478 && scan_column<24;
    wire [14:0] content_key={read_frame_identity[28:16],read_frame_identity[1:0]};
    wire content_authorized=read_frame_identity[31] &&
        ((frame_authorizations[30] && content_key==frame_authorizations[14:0]) ||
         (frame_authorizations[31] && content_key==frame_authorizations[29:15]));
    wire role_matches=role==0 ? (read_frame_identity[28:24]>=4 && read_frame_identity[28:24]<=6) :
        role==1 ? (read_frame_identity[28:24]>=7 && read_frame_identity[28:24]<=9) :
        role==2 && read_frame_identity[28:24]>=10 && read_frame_identity[28:24]<=12;
    assign qualified=enable && session_enable && generation==session_generation && role==session_role &&
        current_ready && !session_disabled && !stalled &&
        frame_enabled && read_valid && count!=0 &&
        (FRAME_IDENTITY ? (content_authorized && role_matches && read_frame_identity[30:29]==2) :
         BANK_AUTHORIZATION ? allowed_banks[read_bank] : read_bank==metadata_bank);
    assign frame_boundary=vs_old && !vs;
    wire map_read=draw && qualified;
    always @(posedge clk) if(map_read) slot_q<=window_maps[{position_bank,scan_index[5:0]}];
    reg [23:0] rgb1,rgb2;
    reg hs1,vs1,de1,hs2,vs2,de2,band1,band2,draw1,draw2;
    reg [4:0] column1,column2,row1;
    wire [9:0] font_address=({5'd0,slot_q}<<4)+({5'd0,slot_q}<<3)+row1;
    wire font_read=draw1;
    always @(posedge clk) if(font_read) font_q<=rows[font_address];
    task commit_window;
        begin position_bank<=request_toggle;pin_mask<=response_mask;outstanding<=0;stalled<=0;end
    endtask
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            vs_old<=0;de_old<=0;x<=0;y<=0;session_enable<=0;session_generation<=0;session_role<=0;
            speed_phase<=0;leading<=592;first_index<=0;first_column<=0;gap<=0;scan_index<=0;scan_column<=0;
            current_ready<=0;session_disabled<=0;outstanding<=0;stalled<=0;position_bank<=0;pin_mask<=0;
            request_toggle<=0;cancel_toggle<=0;request_payload<=0;response_sync<=0;bad_sync<=0;
        end else begin
            vs_old<=vs;de_old<=de;response_sync<={response_sync[1:0],response_toggle};bad_sync<={bad_sync[1:0],font_bad};
            if(de)x<=x+1'b1;
            else begin x<=0;scan_index<=first_index;scan_column<=first_column;end
            if(frame_boundary)y<=0;
            else if(de_old && !de)y<=y+1'b1;
            if(scan_active)begin
                if(scan_column==25)begin scan_column<=0;scan_index<=scan_index+1'b1;end
                else scan_column<=scan_column+1'b1;
            end
            if(frame_boundary) begin
                if(changed) begin
                    session_enable<=enable;session_generation<=generation;session_role<=role;
                    current_ready<=0;session_disabled<=0;stalled<=0;pin_mask<=0;
                    speed_phase<=0;leading<=592;first_index<=0;first_column<=0;gap<=0;
                    if(outstanding || current_ready)cancel_toggle<=~cancel_toggle;
                end else if(response_available && (!response_identity || !enable)) begin
                    outstanding<=0;
                end else if(enable && !session_disabled) begin
                    if(bad_sync[2] || response_available && response_identity && !response_good) begin
                        session_disabled<=1;current_ready<=0;pin_mask<=0;outstanding<=0;
                        cancel_toggle<=~cancel_toggle;
                    end else if(!current_ready) begin
                        if(response_available && response_identity)begin commit_window();current_ready<=1;end
                        else if(!outstanding)begin
                            request_payload<={session_generation,session_role,7'd0,count,32'd0};
                            request_toggle<=~request_toggle;outstanding<=1;
                        end
                    end else begin
                        if(!outstanding) begin
                            request_payload<={session_generation,session_role,
                                first_index<count ? first_index+7'd1 : 7'd0,count,pin_mask};
                            request_toggle<=~request_toggle;outstanding<=1;
                        end
                        speed_phase<=speed_phase+1'b1;
                        if(speed_phase!=3) begin
                            if(leading!=0)leading<=leading-1'b1;
                            else if(first_index<count) begin
                                if(first_column==25) begin
                                    if(response_available && response_identity && request_payload[45:39]==first_index+7'd1) begin
                                        commit_window();first_column<=0;first_index<=first_index+1'b1;
                                    end else begin stalled<=1;speed_phase<=speed_phase;end
                                end else first_column<=first_column+1'b1;
                            end else if(gap==63) begin
                                if(response_available && response_identity && request_payload[45:39]==0) begin
                                    commit_window();leading<=592;first_index<=0;first_column<=0;gap<=0;
                                end else begin stalled<=1;speed_phase<=speed_phase;end
                            end else gap<=gap+1'b1;
                        end
                    end
                end
            end
        end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            rgb1<=0;rgb2<=0;hs1<=0;vs1<=0;de1<=0;hs2<=0;vs2<=0;de2<=0;
            band1<=0;band2<=0;draw1<=0;draw2<=0;column1<=0;column2<=0;row1<=0;
            out_rgb<=0;out_hs<=0;out_vs<=0;out_de<=0;
        end else begin
            rgb1<=rgb;hs1<=hs;vs1<=vs;de1<=de;
            band1<=in_band && qualified;draw1<=draw && qualified;
            if(map_read) begin column1<=scan_column;row1<=y-454;end
            rgb2<=rgb1;hs2<=hs1;vs2<=vs1;de2<=de1;
            band2<=band1;draw2<=draw1;if(draw1) column2<=column1;
            out_hs<=hs2;out_vs<=vs2;out_de<=de2;
            if(visible && draw2 && font_q[23-column2])out_rgb<=24'hffffff;
            else if(visible && band2)out_rgb<={1'b0,rgb2[23:17],1'b0,rgb2[15:9],1'b0,rgb2[7:1]};
            else out_rgb<=rgb2;
        end
    end
endmodule
