`timescale 1ns/1ps
module link_pll(input wire clk,rst,output wire clk125,locked);
 wire [4:0] clocks;
 EG_LOGIC_BUFG b(.i(clocks[0]),.o(clk125));
 EG_PHY_PLL #(.DPHASE_SOURCE("DISABLE"),.DYNCFG("DISABLE"),.FIN("50.000"),
  .FEEDBK_MODE("NORMAL"),.FEEDBK_PATH("CLKC0_EXT"),.STDBY_ENABLE("DISABLE"),
  .PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),.DERIVE_PLL_CLOCKS("DISABLE"),.GEN_BASIC_CLOCK("DISABLE"),
  .GMC_GAIN(2),.ICP_CURRENT(9),.KVCO(2),.LPF_CAPACITOR(1),.LPF_RESISTOR(8),
  .REFCLK_DIV(2),.FBCLK_DIV(5),.CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(8),.CLKC0_CPHASE(7),.CLKC0_FPHASE(0),
  .CLKC1_ENABLE("DISABLE"),.CLKC2_ENABLE("DISABLE"),.CLKC3_ENABLE("DISABLE"),.CLKC4_ENABLE("DISABLE")) pll_inst(
  .refclk(clk),.reset(rst),.stdby(1'b0),.extlock(locked),.load_reg(1'b0),.psclk(1'b0),
  .psdown(1'b0),.psstep(1'b0),.psclksel(3'd0),.psdone(),.dclk(1'b0),.dcs(1'b0),
  .dwe(1'b0),.di(8'd0),.daddr(6'd0),.do(),.fbclk(clk125),.clkc(clocks));
endmodule
module link_rx_pipeline(input wire clk,rst,input wire [7:0] raw_data,input wire raw_valid,raw_error,
 output reg [7:0] data,output reg valid,error);
 reg [7:0] half_data;reg half_valid,half_error;
 always @(negedge clk or posedge rst)begin
  if(rst)begin half_data<=0;half_valid<=0;half_error<=0;end
  else begin half_data<=raw_data;half_valid<=raw_valid;half_error<=raw_error;end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin data<=0;valid<=0;error<=0;end
  else begin data<=half_data;valid<=half_valid;error<=half_error;end
 end
endmodule
module link_reset(input wire clk,async_rst,output wire rst);
 (* ASYNC_REG="TRUE" *) reg [2:0] stages;
 always @(posedge clk or posedge async_rst)if(async_rst)stages<=3'b111;else stages<={stages[1:0],1'b0};
 assign rst=stages[2];
endmodule
module link_rgmii(input wire tx_clk,tx_rst,input wire [7:0] tx_data,input wire tx_valid,
 input wire rx_clk,rx_rst,input wire [3:0] rxd,input wire rx_ctl,
 output wire txc,output wire [3:0] txd,output wire tx_ctl,
 output wire [7:0] rx_data,output wire rx_valid,rx_error,rx_ctl_tap);
 wire ctl_rise,ctl_fall,delayed_ctl;wire [3:0] delayed_rxd;
 EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) clock_out(.q(txc),.clk(tx_clk),.d0(1'b1),.d1(1'b0),.rst(tx_rst));
 EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) control_out(.q(tx_ctl),.clk(tx_clk),.d0(tx_valid),.d1(tx_valid),.rst(tx_rst));
 genvar i;
 generate for(i=0;i<4;i=i+1)begin:lanes
  EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) data_out(.q(txd[i]),.clk(tx_clk),.d0(tx_data[i]),.d1(tx_data[i+4]),.rst(tx_rst));
  EG_LOGIC_IDELAY #(.INDEL(16)) input_delay(.i(rxd[i]),.o(delayed_rxd[i]));
  EG_LOGIC_IDDR #(.ASYNCRST("ENABLE"),.PIPEMODE("PIPED")) data_in(.q0(rx_data[i]),.q1(rx_data[i+4]),.clk(rx_clk),.d(delayed_rxd[i]),.rst(rx_rst));
 end endgenerate
 EG_LOGIC_IDELAY #(.INDEL(16)) control_delay(.i(rx_ctl),.o(delayed_ctl));
 EG_LOGIC_IDDR #(.ASYNCRST("ENABLE"),.PIPEMODE("PIPED")) control_in(.q0(ctl_rise),.q1(ctl_fall),.clk(rx_clk),.d(delayed_ctl),.rst(rx_rst));
 assign rx_ctl_tap=delayed_ctl;
 assign rx_valid=ctl_rise;assign rx_error=ctl_rise^ctl_fall;
endmodule
