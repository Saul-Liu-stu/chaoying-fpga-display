`timescale 1ns/1ps
module image_return_test #(parameter BOARD_ID=1)(input wire clk,rst_n,sw_spectrum,
 input wire rx_clk,rx_ctl,input wire [3:0] rxd,
 output wire tx_clk,tx_ctl,output wire [3:0] txd,inout wire mdio,mdc,
 output wire sd_ncs,sd_dclk,sd_mosi,input wire sd_miso,
 output wire [5:0] seg_sel,output wire [7:0] seg_data);
 wire net_clk,locked,sys_rst,tx_rst,rx_rst,rx_logic_clk;
 EG_LOGIC_BUFG rx_clock_buffer(.i(rx_clk),.o(rx_logic_clk));
 link_pll u_pll(clk,!rst_n,net_clk,locked);
 wire async_reset_request=!rst_n || !locked;
 wire hard_sys_rst,hard_tx_rst,hard_rx_rst,soft_restart;
 link_reset sys_hard_reset(clk,async_reset_request,hard_sys_rst);
 link_reset tx_hard_reset(net_clk,async_reset_request,hard_tx_rst);
 link_reset rx_hard_reset(rx_logic_clk,async_reset_request,hard_rx_rst);
 wire recovery_reset_request=async_reset_request || soft_restart;
 link_reset sys_reset(clk,recovery_reset_request,sys_rst);
 link_reset tx_reset(net_clk,recovery_reset_request,tx_rst);
 link_reset rx_reset(rx_logic_clk,recovery_reset_request,rx_rst);
 wire ready,link_up,mdc_value;wire [15:0] fault,phy_status;
 assign mdc=mdc_value?1'bz:1'b0;
 link_phy_setup #(.BOARD_ID(BOARD_ID)) u_phy(clk,sys_rst,mdio,mdc_value,ready,link_up,fault,phy_status);
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg [2:0] tx_enable_sync,rx_enable_sync;
 always @(posedge net_clk or posedge tx_rst)begin
  if(tx_rst)tx_enable_sync<=0;else tx_enable_sync<={tx_enable_sync[1:0],ready && link_up};
 end
 always @(posedge rx_logic_clk or posedge rx_rst)begin
  if(rx_rst)rx_enable_sync<=0;else rx_enable_sync<={rx_enable_sync[1:0],ready && link_up};
 end
 wire [7:0] tx_byte,rx_byte,raw_rx_byte;wire tx_valid,rx_valid,rx_error,raw_rx_valid,raw_rx_error,unused_tap;
 link_rgmii u_io(net_clk,tx_rst,tx_byte,tx_valid,rx_logic_clk,rx_rst,rxd,rx_ctl,tx_clk,txd,tx_ctl,raw_rx_byte,raw_rx_valid,raw_rx_error,unused_tap);
 link_rx_pipeline rx_tuple(rx_logic_clk,rx_rst,raw_rx_byte,raw_rx_valid,raw_rx_error,rx_byte,rx_valid,rx_error);
 wire app_send,busy,app_mem_we,available,app_take;wire [111:0] app_info,recv_info;
 wire [8:0] mem_addr,read_addr;wire [7:0] mem_byte,read_byte;
 wire rec_send,rec_take,rec_block,rec_freeze,control_available;wire [111:0] rec_info,control_info;wire [15:0] epoch;
 (* ASYNC_REG="TRUE",syn_preserve=1,syn_keep=1 *) reg [15:0] tx_epoch_s0,tx_epoch_s1,tx_epoch_s2,rx_epoch_s0,rx_epoch_s1,rx_epoch_s2;
 always @(posedge net_clk or posedge hard_tx_rst)if(hard_tx_rst)begin tx_epoch_s0<=0;tx_epoch_s1<=0;tx_epoch_s2<=0;end
  else begin tx_epoch_s0<=epoch;tx_epoch_s1<=tx_epoch_s0;tx_epoch_s2<=tx_epoch_s1;end
 always @(posedge rx_logic_clk or posedge hard_rx_rst)if(hard_rx_rst)begin rx_epoch_s0<=0;rx_epoch_s1<=0;rx_epoch_s2<=0;end
  else begin rx_epoch_s0<=epoch;rx_epoch_s1<=rx_epoch_s0;rx_epoch_s2<=rx_epoch_s1;end
 sector_wire_txpipe #(.BOARD_ID(BOARD_ID)) u_wire(
  .app_clk(clk),.app_rst(sys_rst),.tx_clk(net_clk),.tx_rst(tx_rst),.rx_clk(rx_logic_clk),.rx_rst(rx_rst),
  .tx_enable(tx_enable_sync[2]),.rx_enable(rx_enable_sync[2]),.tx_epoch(tx_epoch_s2),.rx_epoch(rx_epoch_s2),
  .control_available(control_available),.control_info(control_info),.control_take(rec_take),
  .send(rec_send || app_send),.send_info(rec_send?rec_info:app_info),.busy(busy),
  .mem_we(app_mem_we),.mem_addr(mem_addr),.mem_byte(mem_byte),
  .available(available),.recv_info(recv_info),.take(app_take || (available && rec_freeze)),.read_addr(read_addr),.read_byte(read_byte),
  .tx_byte(tx_byte),.tx_valid(tx_valid),.rx_byte(rx_byte),.rx_valid(rx_valid),.rx_error(rx_error));
 restart_slave #(.QUIET_CYCLES(16),.HOLD_CYCLES(1000000),.WAIT_CYCLES(100000000)) u_recovery(
  .clk(clk),.hard_reset(hard_sys_rst),.busy(busy),.available(control_available),.app_tx_activity(app_mem_we || app_send),.recv_info(control_info),
  .send(rec_send),.send_info(rec_info),.take(rec_take),.block_app(rec_block),.freeze_rx(rec_freeze),.soft_reset(soft_restart),.epoch(epoch));
 (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [2:0] spectrum_sync;
 reg spectrum_debounced;reg [19:0] spectrum_timer;
 always @(posedge clk or posedge sys_rst)begin
  if(sys_rst)begin spectrum_sync<=0;spectrum_debounced<=0;spectrum_timer<=0;end
  else begin
   spectrum_sync<={spectrum_sync[1:0],sw_spectrum};
   if(spectrum_sync[2]==spectrum_debounced)spectrum_timer<=0;
   else if(spectrum_timer==20'd999999)begin spectrum_debounced<=spectrum_sync[2];spectrum_timer<=0;end
   else spectrum_timer<=spectrum_timer+1'b1;
  end
 end
 wire [15:0] app_status;wire [31:0] verified;
 media_scene_app u_app(clk,sys_rst,ready && link_up,app_send,app_info,busy || rec_block,app_mem_we,mem_addr,mem_byte,
  available && !rec_freeze,recv_info,app_take,read_addr,read_byte,app_status,verified,spectrum_debounced);
 assign sd_ncs=1;assign sd_dclk=1;assign sd_mosi=1;
 wire [15:0] diagnosis=(fault!=0)?fault:!ready?16'd1:!link_up?16'd3:app_status;
 reg [23:0] screen;
 always @(posedge clk or posedge sys_rst)begin
  if(sys_rst)screen<=0;else screen<={(BOARD_ID==1)?4'ha:4'hb,4'd0,diagnosis};
 end
 wire [6:0] digits[0:5];genvar j;
 generate for(j=0;j<6;j=j+1)begin:d
  seg_decoder hex_digit(screen[j*4+:4],digits[j]);
 end endgenerate
 seg_scan display(.clk(clk),.rst_n(!sys_rst),.seg_sel(seg_sel),.seg_data(seg_data),
  .seg_data_0({1'b1,digits[0]}),.seg_data_1({1'b1,digits[1]}),.seg_data_2({1'b1,digits[2]}),
  .seg_data_3({1'b1,digits[3]}),.seg_data_4({1'b1,digits[4]}),.seg_data_5({1'b1,digits[5]}));
endmodule
