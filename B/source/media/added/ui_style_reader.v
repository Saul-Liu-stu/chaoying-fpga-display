`timescale 1ns/1ps
module ui_style_reader #(parameter WAIT_CYCLES=100000000)(
 input wire clk,rst,mounted,found,duplicate,input wire [31:0] first_cluster,file_size,
 input wire [31:0] fat_base,data_base,max_cluster,input wire [32:0] volume_end,input wire [3:0] cluster_shift,
 input wire [3:0] sector_fault,
 output wire sector_request,output wire [31:0] sector_lba,input wire sector_grant,sector_done,
 output wire sector_release,output wire [8:0] buffer_addr,input wire [7:0] buffer_byte,
 output reg block_valid,output reg [2:0] block_index,output wire [31:0] file_crc,
 output reg [31:0] block_crc,input wire block_read_enable,input wire [8:0] block_address,output reg [7:0] block_byte,
 input wire block_done,block_good,output reg done,valid,failed,output reg [119:0] palette);
 localparam MOUNT=0,CHAIN=1,START=2,READ=3,TRANSFER=4,FINISH=5;
 reg [2:0] state;reg span_start;reg [11:0] offset;
 wire span_ready,span_unavailable,span_fault,span_idle,span_done,span_good,span_byte_valid;
 wire [8:0] span_byte_index;wire [7:0] span_byte;wire [9:0] span_count;
 wire [11:0] position=offset+{3'd0,span_byte_index};
 reg [31:0] crc,chunk_crc,expected_crc;reg header_good;
 reg [119:0] candidate_palette;
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [7:0] block_ram[0:511];
 always @(posedge clk)begin
  if(span_byte_valid)block_ram[span_byte_index]<=span_byte;
  if(block_read_enable)block_byte<=block_ram[block_address];
 end
 assign file_crc=expected_crc;
 lights_file_span #(.POSITION_BITS(16),.INDEX_BITS(4),.ANCHOR_SHIFT(3),.MIN_FILE_BYTES(3072),.MAX_FILE_BYTES(3072),.STRICT_RANGE(1),.COMPACT_FONT(1),.BYTE_STALL_LIMIT(WAIT_CYCLES)) u_span(
  .request_tag(8'd1),.sector_fault(sector_fault),.accepted(),.response_tag(),.status(),.count(span_count),.eof(),
  .clk(clk),.rst(rst),.mounted(mounted),.found(found),.duplicate(duplicate),.first_cluster(first_cluster),.file_size(file_size),
  .fat_base(fat_base),.data_base(data_base),.max_cluster(max_cluster),.volume_end(volume_end),.cluster_shift(cluster_shift),
  .ready(span_ready),.unavailable(span_unavailable),.chain_fault(span_fault),.start(span_start),.cancel(done),.offset({20'd0,offset}),.length(10'd512),
  .idle(span_idle),.done(span_done),.good(span_good),.byte_valid(span_byte_valid),.byte_index(span_byte_index),.byte_data(span_byte),.byte_ready(1'b1),
  .sector_request(sector_request),.sector_lba(sector_lba),.sector_grant(sector_grant),.sector_done(sector_done),.sector_release(sector_release),.buffer_addr(buffer_addr),
  .anchor_we(),.anchor_write_address(),.anchor_write_data(),.anchor_read(),.anchor_read_address(),.anchor_read_data(first_cluster[27:0]),.buffer_byte(buffer_byte));
 function [31:0] crc_byte(input [31:0] c,input [7:0] d);
  reg [31:0] t;integer k;begin t=c;for(k=0;k<8;k=k+1)t=(t>>1)^((t[0]^d[k])?32'hedb88320:32'd0);crc_byte=t;end
 endfunction
 function header_byte_good(input [11:0] a,input [7:0] d);
  begin case(a)
   0:header_byte_good=d==8'h55;1:header_byte_good=d==8'h49;2:header_byte_good=d==8'h53;3:header_byte_good=d==8'h31;
   4,5:header_byte_good=d==1;6:header_byte_good=d==64;9:header_byte_good=d==12;12:header_byte_good=d==48;13:header_byte_good=d==11;
   16,17,18,20,21,22,24,25,26,28,29,30,32,33,34,35,36,37,38:header_byte_good=1;
   default:header_byte_good=a>=64 && a<2928?1:d==0;
  endcase end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=MOUNT;span_start<=0;offset<=0;block_valid<=0;block_index<=0;block_crc<=0;done<=0;valid<=0;failed<=0;palette<=0;
   crc<=32'hffffffff;chunk_crc<=32'hffffffff;expected_crc<=0;header_good<=1;candidate_palette<=0;
  end else begin
   span_start<=0;
   if(span_byte_valid)begin
    chunk_crc<=crc_byte(chunk_crc,span_byte);
    if(position<32 || position>=36)crc<=crc_byte(crc,span_byte);
    if(!header_byte_good(position,span_byte))header_good<=0;
    case(position)
     16:candidate_palette[119:112]<=span_byte;17:candidate_palette[111:104]<=span_byte;18:candidate_palette[103:96]<=span_byte;
     20:candidate_palette[95:88]<=span_byte;21:candidate_palette[87:80]<=span_byte;22:candidate_palette[79:72]<=span_byte;
     24:candidate_palette[71:64]<=span_byte;25:candidate_palette[63:56]<=span_byte;26:candidate_palette[55:48]<=span_byte;
     28:candidate_palette[47:40]<=span_byte;29:candidate_palette[39:32]<=span_byte;30:candidate_palette[31:24]<=span_byte;
     32:expected_crc[7:0]<=span_byte;33:expected_crc[15:8]<=span_byte;34:expected_crc[23:16]<=span_byte;35:expected_crc[31:24]<=span_byte;
     36:candidate_palette[23:16]<=span_byte;37:candidate_palette[15:8]<=span_byte;38:candidate_palette[7:0]<=span_byte;
    endcase
   end
   if(!done && mounted && (span_unavailable || span_fault))begin done<=1;failed<=1;block_valid<=0;state<=FINISH;end
   else case(state)
    MOUNT:if(mounted)begin
     if(!found || duplicate || file_size!=3072)begin done<=1;failed<=found;state<=FINISH;end else state<=CHAIN;
    end
    CHAIN:if(span_ready && span_idle)state<=START;
    START:if(span_idle)begin chunk_crc<=32'hffffffff;span_start<=1;state<=READ;end
    READ:if(span_done)begin
     if(!span_good || span_count!=512 || !header_good || (block_index==5 && ~crc!=expected_crc))begin done<=1;failed<=1;state<=FINISH;end
     else begin block_crc<=~chunk_crc;block_valid<=1;state<=TRANSFER;end
    end
    TRANSFER:if(block_done)begin
     block_valid<=0;
     if(!block_good)begin done<=1;failed<=1;state<=FINISH;end
     else if(block_index==5)begin done<=1;valid<=1;palette<=candidate_palette;state<=FINISH;end
     else begin block_index<=block_index+1'b1;offset<=offset+12'd512;state<=START;end
    end
   endcase
  end
 end
endmodule

module ui_font_sector_mux(
 input wire clk,rst,font_request,font_release,ui_request,ui_release,
 input wire [31:0] font_lba,ui_lba,input wire [8:0] font_address,ui_address,
 output wire request,out_release,output wire [31:0] lba,output wire [8:0] address,
 input wire grant,sector_done,output wire font_grant,font_done,ui_grant,ui_done);
 reg active,ui_owner;
 always @(posedge clk or posedge rst)
  if(rst)begin active<=0;ui_owner<=0;end
  else if(!active && (font_request || ui_request))begin active<=1;ui_owner<=!font_request;end
  else if(active && (ui_owner?ui_release:font_release))active<=0;
 assign request=active && (ui_owner?ui_request:font_request);
 assign out_release=active && (ui_owner?ui_release:font_release);
 assign lba=ui_owner?ui_lba:font_lba;assign address=ui_owner?ui_address:font_address;
 assign font_grant=active && !ui_owner && grant;assign ui_grant=active && ui_owner && grant;
 assign font_done=active && !ui_owner && sector_done;assign ui_done=active && ui_owner && sector_done;
endmodule
