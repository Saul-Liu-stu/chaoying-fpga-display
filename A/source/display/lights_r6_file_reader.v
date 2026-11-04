module lights_r6_file_reader(
 input wire clk,rst,mounted,found,duplicate,
 input wire [31:0] first_cluster,file_size,fat_base,data_base,max_cluster,
 input wire [32:0] volume_end,input wire [3:0] cluster_shift,
 output reg ready,unavailable,chain_fault,
 input wire start,cancel,input wire [31:0] offset,input wire [9:0] length,
 output wire idle,output reg done,good,output wire byte_valid,
 output reg [8:0] byte_index,output wire [7:0] byte_data,input wire byte_ready,
 output wire sector_request,output reg [31:0] sector_lba,
 input wire sector_grant,sector_done,output reg sector_release,
 output reg [8:0] buffer_addr,input wire [7:0] buffer_byte
);
 localparam MOUNT=0,FAT_LBA=1,LBA_CHECK=2,REQ=3,WAIT_SECTOR=4,ADDR=5,BYTE_WAIT=6,
  USE=7,FAT_CHECK=8,IDLE=9,SEEK=10,DATA_SUB=11,DATA_SHIFT=12,DATA_ADD=13,NEXT=14,FINISH=15,STOP=16,MOUNT_CHECK=17,SPAN_CHECK=18,SEEK_PLAN=19;
 reg [4:0] state;reg audit,is_fat,aborting;reg mount_bad,span_bad;
 reg [27:0] cursor;reg [13:0] cursor_index,audit_left,target_index;
 reg [31:0] fat_word;reg [21:0] position;
 reg [9:0] remaining,count;reg [8:0] begin_byte,index;
 reg [32:0] address_work;reg [2:0] shift_left;
 wire [27:0] next_cluster=fat_word[27:0];
 wire next_valid=next_cluster>=2 && next_cluster<=max_cluster && next_cluster<28'hffffff0 && next_cluster!=cursor;
 wire [9:0] sector_left=10'd512-{1'b0,position[8:0]};
 wire [6:0] sector_mask=7'h7f>>(3'd7-cluster_shift[2:0]);
 assign idle=state==IDLE;
 assign sector_request=state==REQ && !aborting && !cancel;
 assign byte_valid=state==USE && !is_fat && !aborting && !cancel;
 assign byte_data=buffer_byte;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=MOUNT;ready<=0;unavailable<=0;chain_fault<=0;done<=0;good<=0;sector_release<=0;
   cursor<=0;cursor_index<=0;audit_left<=0;target_index<=0;fat_word<=0;position<=0;remaining<=0;count<=0;
   begin_byte<=0;index<=0;address_work<=0;shift_left<=0;buffer_addr<=0;sector_lba<=0;byte_index<=0;
   audit<=0;is_fat<=0;aborting<=0;mount_bad<=0;span_bad<=0;end
  else begin
   done<=0;sector_release<=0;
   if(cancel && state!=MOUNT && state!=IDLE && state!=STOP)aborting<=1;
   case(state)
    MOUNT: if(mounted)begin
     mount_bad<=!found || duplicate || file_size<44 || file_size>=32'd4194304 || cluster_shift>7 ||
      first_cluster<2 || first_cluster>max_cluster || first_cluster>=32'h0ffffff0;
     cursor<=first_cluster[27:0];cursor_index<=0;
     audit_left<=((file_size[21:0]-22'd1)>>9>>cluster_shift[2:0])+14'd1;
     state<=MOUNT_CHECK;
    end
    MOUNT_CHECK:if(mount_bad)begin unavailable<=1;state<=STOP;end
     else begin audit<=1;state<=FAT_LBA;end
    FAT_LBA: begin address_work<={1'b0,fat_base}+{12'd0,cursor[27:7]};
     begin_byte<={cursor[6:0],2'b0};count<=4;index<=0;fat_word<=0;is_fat<=1;state<=LBA_CHECK;end
    LBA_CHECK: if(address_work[32] || address_work>=volume_end)begin chain_fault<=1;state<=STOP;end
     else begin sector_lba<=address_work[31:0];state<=REQ;end
    REQ: if(aborting || cancel)state<=FINISH;
     else if(sector_grant)state<=WAIT_SECTOR;
    WAIT_SECTOR: if(sector_done)state<=ADDR;
    ADDR: begin buffer_addr<=begin_byte+index;state<=BYTE_WAIT;end
    BYTE_WAIT: state<=USE;
    USE: if(is_fat || byte_ready || aborting || cancel)begin
     if(is_fat)fat_word[index[1:0]*8 +:8]<=buffer_byte;
     else begin position<=position+1'b1;remaining<=remaining-1'b1;byte_index<=byte_index+1'b1;end
     if({1'b0,index}+1==count)begin sector_release<=1;state<=is_fat ? FAT_CHECK : NEXT;end
     else begin index<=index+1'b1;state<=ADDR;end
    end
    FAT_CHECK: if(aborting || cancel)state<=FINISH;
     else if(audit && audit_left==1)begin
      if(next_cluster<28'hffffff8)begin chain_fault<=1;state<=STOP;end
      else begin ready<=1;audit<=0;cursor<=first_cluster[27:0];cursor_index<=0;state<=IDLE;end
     end else if(!next_valid)begin chain_fault<=1;state<=STOP;end
     else begin cursor<=next_cluster;cursor_index<=cursor_index+1'b1;
      if(audit)begin audit_left<=audit_left-1'b1;state<=FAT_LBA;end else state<=SEEK;end
    IDLE: if(start)begin
     done<=0;good<=0;aborting<=cancel;byte_index<=0;
     span_bad<=offset[31:22]!=0 || length==0 || length>512 || ({1'b0,offset[21:0]}+{13'd0,length})>{1'b0,file_size[21:0]};
     position<=offset[21:0];remaining<=length;target_index<=({1'b0,offset[21:9]}>>cluster_shift[2:0]);
     state<=SPAN_CHECK;
    end
    SPAN_CHECK:if(span_bad)state<=FINISH;else state<=SEEK_PLAN;
    SEEK_PLAN:begin
     if(target_index<cursor_index)begin cursor<=first_cluster[27:0];cursor_index<=0;end
     state<=SEEK;
    end
    SEEK: if(aborting || cancel)state<=FINISH;
     else if(cursor_index==target_index)state<=DATA_SUB;else state<=FAT_LBA;
    DATA_SUB: begin address_work<={5'd0,cursor}-33'd2;shift_left<=cluster_shift[2:0];state<=DATA_SHIFT;end
    DATA_SHIFT: if(shift_left==0)state<=DATA_ADD;
     else begin address_work<=address_work<<1;shift_left<=shift_left-1'b1;end
    DATA_ADD: begin address_work<={1'b0,data_base}+address_work+{26'd0,(position[15:9]&sector_mask)};
     begin_byte<=position[8:0];count<=remaining<sector_left ? remaining : sector_left;
     index<=0;is_fat<=0;state<=LBA_CHECK;end
    NEXT: if(aborting || cancel)state<=FINISH;
     else if(remaining==0)begin good<=1;state<=FINISH;end
     else begin target_index<=({1'b0,position[21:9]}>>cluster_shift[2:0]);state<=SEEK;end
    FINISH: begin done<=1;if(aborting || cancel)good<=0;state<=IDLE;end
    STOP: ready<=0;
    default:begin chain_fault<=1;state<=STOP;end
   endcase
  end
 end
endmodule
