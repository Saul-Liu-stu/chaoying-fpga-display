module lights_text_decode(
    input wire clk,rst,start,finish,
    input wire [9:0] file_bytes,
    input wire byte_valid,
    input wire [7:0] byte_data,
    output wire byte_ready,
    output reg done,good,
    output reg [6:0] count,
    output reg glyph_we,
    output reg [5:0] glyph_index,
    output reg [15:0] glyph_id
);
    reg active,bad,first,nonspace,byte_pending;
    (* syn_preserve=1 *) reg [7:0] byte_hold;
    reg [9:0] bytes_seen;
    reg [1:0] continuation,tail,lookup;
    reg [20:0] codepoint,minimum,find_point;
    wire [20:0] assembled={codepoint[14:0],byte_hold[5:0]};
    assign byte_ready=active && !byte_pending;
    task accept_point;
        input [20:0] point;
        begin
            first<=0;
            if(first && point==21'hfeff) begin end
            else if(tail!=0) begin
                if(tail==1 && point==21'd10) tail<=2;
                else bad<=1;
            end else if(point==21'd13) tail<=1;
            else if(point==21'd10) tail<=2;
            else if(point==0 || count>=64) bad<=1;
            else if(point>21'hffff) bad<=1;
            else begin
                glyph_we<=1; glyph_index<=count[5:0]; glyph_id<=point[15:0];
                count<=count+1'b1; if(point!=21'd32) nonspace<=1;
            end
        end
    endtask
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            active<=0; byte_pending<=0; byte_hold<=0; bad<=0; first<=1; nonspace<=0; bytes_seen<=0;
            continuation<=0; tail<=0; lookup<=0; codepoint<=0; minimum<=0;
            find_point<=0; done<=0; good<=0; count<=0;
            glyph_we<=0; glyph_index<=0; glyph_id<=0;
        end else begin
            done<=0; glyph_we<=0;
            if(start) begin
                active<=1; byte_pending<=0; bad<=file_bytes==0 || file_bytes>512; first<=1; nonspace<=0;
                bytes_seen<=0; continuation<=0; tail<=0; lookup<=0; count<=0; good<=0;
            end else if(active) begin
                if(byte_pending) begin
                    byte_pending<=0;
                    bytes_seen<=bytes_seen+1'b1;
                    if(bytes_seen>=file_bytes || bytes_seen>=512) bad<=1;
                    if(!bad) begin
                        if(continuation!=0) begin
                            if(byte_hold[7:6]!=2'b10) begin bad<=1; continuation<=0; end
                            else begin
                                codepoint<=assembled; continuation<=continuation-1'b1;
                                if(continuation==1) begin
                                    if(assembled<minimum || assembled>21'h10ffff ||
                                        (assembled>=21'hd800 && assembled<=21'hdfff)) bad<=1;
                                    else accept_point(assembled);
                                end
                            end
                        end else if(byte_hold<8'h80) accept_point({13'd0,byte_hold});
                        else if(byte_hold>=8'hc2 && byte_hold<=8'hdf) begin
                            codepoint<={16'd0,byte_hold[4:0]}; minimum<=21'h80; continuation<=1;
                        end else if(byte_hold>=8'he0 && byte_hold<=8'hef) begin
                            codepoint<={17'd0,byte_hold[3:0]}; minimum<=21'h800; continuation<=2;
                        end else if(byte_hold>=8'hf0 && byte_hold<=8'hf4) begin
                            codepoint<={18'd0,byte_hold[2:0]}; minimum<=21'h10000; continuation<=3;
                        end else bad<=1;
                    end
                end else if(byte_valid) begin
                    byte_hold<=byte_data; byte_pending<=1;
                end else if(finish) begin
                    active<=0; done<=1;
                    good<=!bad && continuation==0 && tail!=1 && bytes_seen==file_bytes && count!=0 && nonspace;
                end
            end
        end
    end
endmodule
