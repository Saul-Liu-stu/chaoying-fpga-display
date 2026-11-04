
module hdmi_audio_tone_i2s_64fs #(
    parameter [31:0] PHASE_INC = 32'd39370534,   // 兼容旧顶层，实际本版内部不用它
    parameter signed [23:0] AMP = 24'sd2000000,
    parameter integer NOTE_HOLD_FRAMES = 24000   // 每个音持续 0.5s @ 48kHz
)(
    input  wire I_mclk,      // 12.288MHz
    input  wire I_rst,
    input  wire I_play_enable, // audio-clock synchronous: hold content, keep silent transport
    output reg  O_i2s_BCLK,
    output reg  O_i2s_LRCK,
    output reg  O_i2s_DOUT
);

function [31:0] note_inc_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: note_inc_lut = 32'd23409862; // do  C4 261.63Hz
            3'd1: note_inc_lut = 32'd26276681; // re  D4 293.66Hz
            3'd2: note_inc_lut = 32'd29494578; // mi  E4 329.63Hz
            3'd3: note_inc_lut = 32'd31248410; // fa  F4 349.23Hz
            3'd4: note_inc_lut = 32'd35075155; // so  G4 392.00Hz
            3'd5: note_inc_lut = 32'd39370534; // la  A4 440.00Hz
            3'd6: note_inc_lut = 32'd44191930; // si  B4 493.88Hz
            default: note_inc_lut = 32'd46819716; // do  C5 523.25Hz
        endcase
    end
endfunction

localparam signed [63:0] SOFT_AMP = (AMP * 64'sd3) / 64'sd4;
function signed [23:0] sine_word;
 input [31:0] phase;
 reg [5:0] idx;
 reg signed [23:0] mag;
 begin
  idx=phase[30] ? ~phase[29:24] : phase[29:24];
  case(idx)
   6'd0: mag=(SOFT_AMP * 64'sd402) / 64'sd32767;
   6'd1: mag=(SOFT_AMP * 64'sd1206) / 64'sd32767;
   6'd2: mag=(SOFT_AMP * 64'sd2009) / 64'sd32767;
   6'd3: mag=(SOFT_AMP * 64'sd2811) / 64'sd32767;
   6'd4: mag=(SOFT_AMP * 64'sd3612) / 64'sd32767;
   6'd5: mag=(SOFT_AMP * 64'sd4410) / 64'sd32767;
   6'd6: mag=(SOFT_AMP * 64'sd5205) / 64'sd32767;
   6'd7: mag=(SOFT_AMP * 64'sd5998) / 64'sd32767;
   6'd8: mag=(SOFT_AMP * 64'sd6786) / 64'sd32767;
   6'd9: mag=(SOFT_AMP * 64'sd7571) / 64'sd32767;
   6'd10: mag=(SOFT_AMP * 64'sd8351) / 64'sd32767;
   6'd11: mag=(SOFT_AMP * 64'sd9126) / 64'sd32767;
   6'd12: mag=(SOFT_AMP * 64'sd9896) / 64'sd32767;
   6'd13: mag=(SOFT_AMP * 64'sd10659) / 64'sd32767;
   6'd14: mag=(SOFT_AMP * 64'sd11417) / 64'sd32767;
   6'd15: mag=(SOFT_AMP * 64'sd12167) / 64'sd32767;
   6'd16: mag=(SOFT_AMP * 64'sd12910) / 64'sd32767;
   6'd17: mag=(SOFT_AMP * 64'sd13645) / 64'sd32767;
   6'd18: mag=(SOFT_AMP * 64'sd14372) / 64'sd32767;
   6'd19: mag=(SOFT_AMP * 64'sd15090) / 64'sd32767;
   6'd20: mag=(SOFT_AMP * 64'sd15800) / 64'sd32767;
   6'd21: mag=(SOFT_AMP * 64'sd16499) / 64'sd32767;
   6'd22: mag=(SOFT_AMP * 64'sd17189) / 64'sd32767;
   6'd23: mag=(SOFT_AMP * 64'sd17869) / 64'sd32767;
   6'd24: mag=(SOFT_AMP * 64'sd18537) / 64'sd32767;
   6'd25: mag=(SOFT_AMP * 64'sd19195) / 64'sd32767;
   6'd26: mag=(SOFT_AMP * 64'sd19841) / 64'sd32767;
   6'd27: mag=(SOFT_AMP * 64'sd20475) / 64'sd32767;
   6'd28: mag=(SOFT_AMP * 64'sd21096) / 64'sd32767;
   6'd29: mag=(SOFT_AMP * 64'sd21705) / 64'sd32767;
   6'd30: mag=(SOFT_AMP * 64'sd22301) / 64'sd32767;
   6'd31: mag=(SOFT_AMP * 64'sd22884) / 64'sd32767;
   6'd32: mag=(SOFT_AMP * 64'sd23452) / 64'sd32767;
   6'd33: mag=(SOFT_AMP * 64'sd24007) / 64'sd32767;
   6'd34: mag=(SOFT_AMP * 64'sd24547) / 64'sd32767;
   6'd35: mag=(SOFT_AMP * 64'sd25072) / 64'sd32767;
   6'd36: mag=(SOFT_AMP * 64'sd25582) / 64'sd32767;
   6'd37: mag=(SOFT_AMP * 64'sd26077) / 64'sd32767;
   6'd38: mag=(SOFT_AMP * 64'sd26556) / 64'sd32767;
   6'd39: mag=(SOFT_AMP * 64'sd27019) / 64'sd32767;
   6'd40: mag=(SOFT_AMP * 64'sd27466) / 64'sd32767;
   6'd41: mag=(SOFT_AMP * 64'sd27896) / 64'sd32767;
   6'd42: mag=(SOFT_AMP * 64'sd28310) / 64'sd32767;
   6'd43: mag=(SOFT_AMP * 64'sd28706) / 64'sd32767;
   6'd44: mag=(SOFT_AMP * 64'sd29085) / 64'sd32767;
   6'd45: mag=(SOFT_AMP * 64'sd29447) / 64'sd32767;
   6'd46: mag=(SOFT_AMP * 64'sd29791) / 64'sd32767;
   6'd47: mag=(SOFT_AMP * 64'sd30117) / 64'sd32767;
   6'd48: mag=(SOFT_AMP * 64'sd30424) / 64'sd32767;
   6'd49: mag=(SOFT_AMP * 64'sd30714) / 64'sd32767;
   6'd50: mag=(SOFT_AMP * 64'sd30985) / 64'sd32767;
   6'd51: mag=(SOFT_AMP * 64'sd31237) / 64'sd32767;
   6'd52: mag=(SOFT_AMP * 64'sd31470) / 64'sd32767;
   6'd53: mag=(SOFT_AMP * 64'sd31685) / 64'sd32767;
   6'd54: mag=(SOFT_AMP * 64'sd31880) / 64'sd32767;
   6'd55: mag=(SOFT_AMP * 64'sd32057) / 64'sd32767;
   6'd56: mag=(SOFT_AMP * 64'sd32213) / 64'sd32767;
   6'd57: mag=(SOFT_AMP * 64'sd32351) / 64'sd32767;
   6'd58: mag=(SOFT_AMP * 64'sd32469) / 64'sd32767;
   6'd59: mag=(SOFT_AMP * 64'sd32567) / 64'sd32767;
   6'd60: mag=(SOFT_AMP * 64'sd32646) / 64'sd32767;
   6'd61: mag=(SOFT_AMP * 64'sd32705) / 64'sd32767;
   6'd62: mag=(SOFT_AMP * 64'sd32745) / 64'sd32767;
   default: mag=(SOFT_AMP * 64'sd32765) / 64'sd32767;
  endcase
  sine_word=phase[31] ? -mag : mag;
 end
endfunction

reg  [5:0]  S_bit_cnt;
reg  [63:0] S_shift_reg;
reg  [31:0] S_phase_acc;
reg signed [23:0] S_sample_word;
reg signed [23:0] S_sample_next;
reg  [2:0]  S_note_idx;
reg [15:0]  S_note_frame_cnt;

wire [31:0] W_note_inc = note_inc_lut(S_note_idx);

always @(posedge I_mclk or posedge I_rst) begin
    if (I_rst) begin
        O_i2s_BCLK      <= 1'b0;
        O_i2s_LRCK      <= 1'b0;
        O_i2s_DOUT      <= 1'b0;
        S_bit_cnt       <= 6'd0;
        S_shift_reg     <= 64'd0;
        S_phase_acc     <= 32'd0;
        S_sample_word   <= 24'sd0;
        S_sample_next   <= 24'sd0;
        S_note_idx      <= 3'd0;
        S_note_frame_cnt<= 16'd0;
    end
    else begin
        if (!I_play_enable) begin
            S_phase_acc <= 32'd0;
            S_sample_word <= 24'sd0;
            S_sample_next <= 24'sd0;
            S_note_idx <= 3'd0;
            S_note_frame_cnt <= 16'd0;
        end
        O_i2s_BCLK <= ~O_i2s_BCLK;

        if (O_i2s_BCLK == 1'b1) begin
            O_i2s_DOUT  <= S_shift_reg[63];
            S_shift_reg <= {S_shift_reg[62:0], 1'b0};

            if (S_bit_cnt == 6'd63) begin
                S_bit_cnt <= 6'd0;

                if (O_i2s_LRCK == 1'b0) begin
                    O_i2s_LRCK  <= 1'b1;
                    S_shift_reg <= I_play_enable ? {S_sample_word[23:0], 40'd0} : 64'd0;
                end
                else begin
                    O_i2s_LRCK  <= 1'b0;

                    if (I_play_enable) begin
                    S_phase_acc <= S_phase_acc + W_note_inc;
                    S_sample_next <= sine_word(S_phase_acc);

                    S_sample_word <= S_sample_next;
                    S_shift_reg   <= {S_sample_next[23:0], 40'd0};

                    if (S_note_frame_cnt == NOTE_HOLD_FRAMES - 1) begin
                        S_note_frame_cnt <= 16'd0;
                        if (S_note_idx == 3'd7)
                            S_note_idx <= 3'd0;
                        else
                            S_note_idx <= S_note_idx + 3'd1;
                    end
                    else begin
                        S_note_frame_cnt <= S_note_frame_cnt + 16'd1;
                    end
                    end else S_shift_reg <= 64'd0;
                end
            end
            else begin
                S_bit_cnt <= S_bit_cnt + 6'd1;
            end
        end
    end
end

endmodule
