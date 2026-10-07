//==========================================================================
//  case3_lane_shf.v
//  桶形移位器：逻辑左移 / 逻辑右移 / 算术右移 / 饱和移位，带 sticky 位。
//  叶子模块（内部没有任何例化）。
//
//  Ref: DSP 里的 shifter + rounding/sticky 逻辑（TI C6x .S 单元风格）。
//==========================================================================
`include "case3_define.v"

module case3_lane_shf (
    input  wire [`C3_DATA_W-1:0]   A,
    input  wire [`C3_LANE_W-1:0]   AMT,
    input  wire [`C3_OP_W-1:0]     MODE,
    input  wire [`C3_ROUND_W-1:0]  ROUND,
    output reg  [`C3_DATA_W-1:0]   Y,
    output reg  [`C3_DATA_W-1:0]   STICKY,
    output reg                     SHIFT_OVF
);

    parameter SHIFT_LAT = `C3_SHIFT_LAT;

    reg [`C3_DATA_W-1:0] shf_tmp;
    reg [`C3_DATA_W-1:0] rnd_mask;

    always @(*) begin
        rnd_mask = {{(`C3_DATA_W-`C3_ROUND_W){1'b0}}, ROUND};
        shf_tmp  = A;
        STICKY   = {`C3_DATA_W{1'b0}};
        SHIFT_OVF = 1'b0;
        case (MODE)
            `C3_OP_SLL: begin
                shf_tmp   = (A << AMT) | rnd_mask;
                STICKY    = (A >> ((`C3_DATA_W - 1) - AMT));
                SHIFT_OVF = (AMT > `C3_LANE_W);
            end
            `C3_OP_SRL: begin
                shf_tmp   = (A >> AMT) | rnd_mask;
                STICKY    = (A << ((`C3_DATA_W - 1) - AMT));
                SHIFT_OVF = 1'b0;
            end
            `C3_OP_SAT: begin
                shf_tmp   = A >>> AMT;
                STICKY    = A & rnd_mask;
                SHIFT_OVF = A[`C3_DATA_MSB];
            end
            `C3_OP_CMP: begin
                shf_tmp   = {A[`C3_ADDR_MSB:0], A[`C3_DATA_MSB:`C3_ADDR_MSB+1]};
                STICKY    = rnd_mask;
            end
            default: begin
                shf_tmp   = A;
                STICKY    = {`C3_DATA_W{1'b0}};
            end
        endcase
        Y = shf_tmp;
    end

endmodule
