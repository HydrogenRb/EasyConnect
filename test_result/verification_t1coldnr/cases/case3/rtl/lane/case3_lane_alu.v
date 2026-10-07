//==========================================================================
//  case3_lane_alu.v
//  通用算术逻辑单元：加 / 减 / 与 / 或 / 异或 / 比较，全组合逻辑。
//  叶子模块（内部没有任何例化）。
//
//  Ref: 经典 ALU 结构（MIPS/RISC-V 单周期 ALU + DSP 的 SIMD byte ALU）。
//==========================================================================
`include "case3_define.v"

module case3_lane_alu (
    input  wire [`C3_DATA_W-1:0]   A,
    input  wire [`C3_DATA_W-1:0]   B,
    input  wire                    CIN,
    input  wire [`C3_OP_W-1:0]     MODE,
    output reg  [`C3_DATA_W-1:0]   Y,
    output reg                     COUT,
    output reg  [`C3_FLAG_W-1:0]   FLAGS
);

    reg [`C3_DATA_W-1:0] logic_and;
    reg [`C3_DATA_W-1:0] logic_or;
    reg [`C3_DATA_W-1:0] logic_xor;
    reg [`C3_DATA_W-1:0] logic_not;

    always @(*) begin
        logic_and = A & B;
        logic_or  = A | B;
        logic_xor = A ^ B;
        logic_not = ~(A ^ B);
    end

    always @(*) begin
        COUT = 1'b0;
        Y    = {`C3_DATA_W{1'b0}};
        case (MODE)
            `C3_OP_ADD: begin
                {COUT, Y} = {1'b0, A} + {1'b0, B} + {{`C3_DATA_W{1'b0}}, CIN};
            end
            `C3_OP_SUB: begin
                {COUT, Y} = {1'b0, A} - {1'b0, B} - {{`C3_DATA_W{1'b0}}, CIN};
            end
            `C3_OP_SLL: begin
                Y = logic_and;
            end
            `C3_OP_SRL: begin
                Y = logic_or;
            end
            `C3_OP_CMP: begin
                Y = logic_xor;
            end
            `C3_OP_SAT: begin
                Y = logic_not;
            end
            default: begin
                {COUT, Y} = {1'b0, A} + {1'b0, B};
            end
        endcase
    end

    always @(*) begin
        FLAGS = {`C3_FLAG_W{1'b0}};
        FLAGS[`C3_FLAG_ZERO] = ~|Y;
        FLAGS[`C3_FLAG_NEG]  = Y[`C3_DATA_MSB];
        FLAGS[`C3_FLAG_OVF]  = COUT ^ Y[`C3_DATA_MSB];
        FLAGS[`C3_FLAG_SAT]  = COUT & (~Y[`C3_DATA_MSB]);
        FLAGS[`C3_FLAG_STICKY] = FLAGS[`C3_FLAG_OVF] | FLAGS[`C3_FLAG_ZERO];
    end

endmodule
