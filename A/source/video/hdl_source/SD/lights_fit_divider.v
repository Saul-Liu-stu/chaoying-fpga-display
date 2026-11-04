`timescale 1ns/1ps
module lights_fit_divider(input wire clk,rst,start,input wire [31:0] numerator,
 input wire [15:0] denominator,output reg done,output reg [31:0] quotient,output reg [15:0] remainder);
 reg busy;reg [5:0] left;reg [31:0] bits;
 reg [15:0] divisor;reg [16:0] rem;
 wire [16:0] trial={rem[15:0],bits[31]};
 wire take=trial>={1'b0,divisor};
 always @(posedge clk or posedge rst) begin
  if(rst) begin busy<=0;done<=0;left<=0;bits<=0;divisor<=1;rem<=0;quotient<=0;remainder<=0;end
  else begin
   done<=0;
   if(start && !busy) begin busy<=1;left<=32;bits<=numerator;divisor<=denominator;rem<=0;end
   else if(busy) begin
    bits<={bits[30:0],take};rem<=take ? trial-{1'b0,divisor} : trial;left<=left-1'b1;
    if(left==1) begin busy<=0;done<=1;quotient<={bits[30:0],take};remainder<=take ? trial-divisor : trial;end
   end
  end
 end
endmodule
