module lights_sector_scheduler #(
    parameter integer MEDIA_QUOTA=2,
    parameter integer AUX_ENABLE=0
)(
    input wire clk,rst,guard_idle,guard_done,
    input wire [3:0] guard_fault,
    input wire media_request,media_release,font_request,font_release,aux_request,aux_release,
    input wire [31:0] media_lba,font_lba,aux_lba,
    input wire [8:0] media_address,font_address,aux_address,
    output wire media_grant,font_grant,aux_grant,
    output wire media_done,font_done,aux_done,
    output wire start,
    output wire [31:0] lba,
    output wire [8:0] address,
    output wire [1:0] owner_debug
);
    localparam NONE=0,MEDIA=1,FONT=2,AUX=3;
    reg [1:0] owner;
    reg [7:0] media_credit;
    reg prefer_aux;
    reg response_complete;
    wire pending_aux=AUX_ENABLE && aux_request;
    wire backend=font_request || pending_aux;
    wire available=owner==NONE && guard_idle && guard_fault==0;
    wire media_selected=media_request && (!backend || media_credit<MEDIA_QUOTA);
    assign media_grant=available && media_selected;
    assign font_grant=available && !media_selected && font_request && (!pending_aux || !prefer_aux);
    assign aux_grant=available && !media_selected && pending_aux && (!font_request || prefer_aux);
    assign start=media_grant || font_grant || aux_grant;
    assign lba=media_grant ? media_lba : font_grant ? font_lba : aux_lba;
    assign address=owner==FONT ? font_address : owner==AUX ? aux_address : media_address;
    assign media_done=guard_done && owner==MEDIA;
    assign font_done=guard_done && owner==FONT;
    assign aux_done=guard_done && owner==AUX;
    assign owner_debug=owner;
    always @(posedge clk or posedge rst) begin
        if(rst) begin owner<=NONE;media_credit<=0;prefer_aux<=0;response_complete<=0;end
        else begin
            if(guard_done && owner!=NONE)response_complete<=1;
            if(media_grant) begin
                owner<=MEDIA;response_complete<=0;
                if(backend && media_credit<MEDIA_QUOTA)media_credit<=media_credit+1'b1;
                else if(!backend)media_credit<=0;
            end else if(font_grant) begin owner<=FONT;media_credit<=0;prefer_aux<=1;response_complete<=0;end
            else if(aux_grant) begin owner<=AUX;media_credit<=0;prefer_aux<=0;response_complete<=0;end
            else if((response_complete || guard_done) &&
                    ((owner==MEDIA && media_release) || (owner==FONT && font_release) ||
                    (owner==AUX && aux_release)))owner<=NONE;
        end
    end
endmodule
