`timescale 1ns/1ps
module lights_fft512 #(parameter PERIOD_CYCLES=1250000)(
 input wire clk,rst,pcm_valid,input wire signed [15:0] pcm_sample,
 output reg bars_valid,output reg [159:0] bars
);
 localparam CAPTURE=0,WINDOW_MULT=1,WINDOW_WRITE=2,READ=3,MULT=4,STORE0=5,STORE1=6,STORE2=7,SUM=8,WRITE=9,
   NEXT=10,BIN_READ=11,BIN_WAIT=12,BIN_USE=13,COMMIT=14,WAIT_PERIOD=15;
 reg [3:0] state,level;
 reg [8:0] capture_index,base,j,bin;
 wire [8:0] half_span=9'd1<<level;
 wire [8:0] address_a=base+j,address_b=base+j+half_span;
 wire [7:0] twiddle_address=j<<(8-level);
 function [8:0] reversed;
  input [8:0] v;integer i;
  begin for(i=0;i<9;i=i+1)reversed[i]=v[8-i];end
 endfunction
 (* ram_style="bram" *) reg signed [15:0] real_mem[0:511],imag_mem[0:511];
 (* ram_style="bram",rom_style="block" *) reg [31:0] twiddle_rom[0:255];
 (* ram_style="bram",rom_style="block" *) reg [15:0] window_rom[0:511];
 initial begin
  $readmemh("fft_twiddle.hex",twiddle_rom);$readmemh("fft_hann.hex",window_rom);
 end
 reg signed [15:0] sample_hold,window_q;
 reg signed [15:0] ar,ai,br,bi,wr,wi;
 reg signed [31:0] product,accumulator;
 reg signed [15:0] multiply_a,multiply_b;
 wire multiply_enable=state==WINDOW_MULT || state==MULT || state==STORE0 || state==STORE1 || state==STORE2;
 always @*begin
  multiply_a=br;multiply_b=wr;
  case(state)
   WINDOW_MULT:begin multiply_a=sample_hold;multiply_b=window_q;end
   STORE0:begin multiply_a=bi;multiply_b=wi;end
   STORE1:begin multiply_a=br;multiply_b=wi;end
   STORE2:begin multiply_a=bi;multiply_b=wr;end
  endcase
 end
 always @(posedge clk)if(multiply_enable)product<=multiply_a*multiply_b;
 reg signed [16:0] tr,ti;
 wire signed [17:0] sum_ar=$signed(ar)+tr,sum_ai=$signed(ai)+ti;
 wire signed [17:0] sum_br=$signed(ar)-tr,sum_bi=$signed(ai)-ti;
 wire [8:0] port_a_address=state==WINDOW_WRITE?reversed(capture_index):state==BIN_READ?bin:address_a;
 wire [15:0] port_a_real=state==WINDOW_WRITE?product>>>15:sum_ar>>>1;
 wire [15:0] port_a_imag=state==WINDOW_WRITE?16'd0:sum_ai>>>1;
 wire port_a_write=state==WINDOW_WRITE || state==WRITE;
 wire port_a_enable=port_a_write || state==READ || state==BIN_READ;
 always @(posedge clk)if(port_a_enable)begin
  if(port_a_write)begin real_mem[port_a_address]<=port_a_real;imag_mem[port_a_address]<=port_a_imag;end
  ar<=real_mem[port_a_address];ai<=imag_mem[port_a_address];
 end
 always @(posedge clk)if(state==WRITE || state==READ)begin
  if(state==WRITE)begin real_mem[address_b]<=sum_br>>>1;imag_mem[address_b]<=sum_bi>>>1;end
  br<=real_mem[address_b];bi<=imag_mem[address_b];
 end
 always @(posedge clk)begin
  if(state==CAPTURE && pcm_valid)window_q<=window_rom[capture_index];
  if(state==READ){wr,wi}<=twiddle_rom[twiddle_address];
 end
 function [4:0] bucket;
  input [8:0] k;
  begin
   if(k<9)bucket=k-1;
   else if(k<25)bucket=8+((k-9)>>1);
   else if(k<89)bucket=16+((k-25)>>3);
   else if(k<110)bucket=24;else if(k<131)bucket=25;
   else if(k<152)bucket=26;else if(k<173)bucket=27;
   else if(k<194)bucket=28;else if(k<215)bucket=29;
   else if(k<236)bucket=30;else bucket=31;
  end
 endfunction
 wire [15:0] abs_real=ar[15]?(~ar+16'd1):ar;
 wire [15:0] abs_imag=ai[15]?(~ai+16'd1):ai;
 wire [16:0] magnitude={1'b0,abs_real}+{1'b0,abs_imag};
 function [4:0] height;
  input [16:0] v;integer n;reg [4:0] h;
  begin
   h=0;
   for(n=2;n<17;n=n+1)if(v[n])h=n>=12?20:((n-2)*2+1);
   height=h;
  end
 endfunction
 reg [4:0] work[0:31];genvar g;wire [159:0] work_packed;
 generate for(g=0;g<32;g=g+1)begin:pack_bars assign work_packed[g*5+:5]=work[g];end endgenerate
 reg [$clog2(PERIOD_CYCLES+1)-1:0] period;
 integer i;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=CAPTURE;level<=0;capture_index<=0;base<=0;j<=0;bin<=1;
   sample_hold<=0;accumulator<=0;tr<=0;ti<=0;
   bars_valid<=0;bars<=0;period<=0;
   for(i=0;i<32;i=i+1)work[i]<=0;
  end else begin
   bars_valid<=0;if(period<PERIOD_CYCLES)period<=period+1'b1;
   case(state)
    CAPTURE:if(pcm_valid)begin sample_hold<=pcm_sample;state<=WINDOW_MULT;end
    WINDOW_MULT:state<=WINDOW_WRITE;
    WINDOW_WRITE:if(capture_index==511)begin level<=0;base<=0;j<=0;state<=READ;end
     else begin capture_index<=capture_index+1'b1;state<=CAPTURE;end
    READ:state<=MULT;
    MULT:state<=STORE0;
    STORE0:begin accumulator<=product;state<=STORE1;end
    STORE1:begin tr<=($signed({accumulator[31],accumulator})-$signed({product[31],product}))>>>15;state<=STORE2;end
    STORE2:begin accumulator<=product;state<=SUM;end
    SUM:begin ti<=($signed({accumulator[31],accumulator})+$signed({product[31],product}))>>>15;state<=WRITE;end
    WRITE:state<=NEXT;
    NEXT:if(j+1<half_span)begin j<=j+1'b1;state<=READ;end
     else if({1'b0,base}+({1'b0,half_span}<<1)<512)begin base<=base+(half_span<<1);j<=0;state<=READ;end
     else if(level<8)begin level<=level+1'b1;base<=0;j<=0;state<=READ;end
     else begin bin<=1;for(i=0;i<32;i=i+1)work[i]<=0;state<=BIN_READ;end
    BIN_READ:state<=BIN_WAIT;
    BIN_WAIT:state<=BIN_USE;
    BIN_USE:begin
     if(height(magnitude)>work[bucket(bin)])work[bucket(bin)]<=height(magnitude);
     if(bin==255)state<=COMMIT;else begin bin<=bin+1'b1;state<=BIN_READ;end
    end
    COMMIT:begin bars<=work_packed;bars_valid<=1;state<=WAIT_PERIOD;end
    WAIT_PERIOD:if(period>=PERIOD_CYCLES)begin period<=0;capture_index<=0;state<=CAPTURE;end
    default:state<=CAPTURE;
   endcase
  end
 end
endmodule
