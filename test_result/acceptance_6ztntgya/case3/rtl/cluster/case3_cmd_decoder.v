//==========================================================================
//  case3_cmd_decoder.v
//  命令译码器：把配置字（CFG_CTRL）拆成 opcode / lane mask / slice mask / 立即数。
//  内部例化两个小单元（sync_2ff 同步、clk_gate 门控），均为位置端口连接。
//
//  Ref: 向量引擎前端的 instruction decoder（Vision P6 VLIW 指令槽译码）。
//==========================================================================
`include "case3_define.v"

module case3_cmd_decoder (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire [`C3_CFG_DATA_W-1:0]  CFG_CTRL,
    input  wire                       CL_GO,
    input  wire [`C3_CFG_DATA_W-1:0]  CFG_MASK,
    output reg  [`C3_OP_W-1:0]        DEC_OP,
    output reg  [`C3_LANE_NUM-1:0]    DEC_LANE_MASK,
    output reg  [`C3_SLICE_NUM-1:0]   DEC_SLICE_MASK,
    output reg  [`C3_PE_W-1:0]        DEC_IMM,
    output reg                        DEC_VALID,
    output reg                        DEC_ERR,
    output wire                       CMD_CLK
);

    parameter DEC_STAGE = `C3_PIPE_STAGE;

    reg  dec_en;
    reg  dec_go_sync;
    wire dec_gclk;

    always @(*) begin
        DEC_LANE_MASK  = CFG_MASK[`C3_LANE_NUM-1:0];
        DEC_SLICE_MASK = CFG_MASK[`C3_SLICE_NUM-1:0];
        DEC_IMM        = CFG_CTRL[`C3_PE_MSB:0];
        DEC_ERR        = 1'b0;
        case (CFG_CTRL[`C3_OP_W+`C3_FU_AW-1:`C3_FU_AW])
            `C3_OP_ADD: DEC_OP = `C3_OP_ADD;
            `C3_OP_SUB: DEC_OP = `C3_OP_SUB;
            `C3_OP_MUL: DEC_OP = `C3_OP_MUL;
            `C3_OP_MAC: DEC_OP = `C3_OP_MAC;
            `C3_OP_SLL: DEC_OP = `C3_OP_SLL;
            `C3_OP_SRL: DEC_OP = `C3_OP_SRL;
            `C3_OP_SAT: DEC_OP = `C3_OP_SAT;
            `C3_OP_CMP: DEC_OP = `C3_OP_CMP;
            `C3_OP_LD:  DEC_OP = `C3_OP_LD;
            `C3_OP_ST:  DEC_OP = `C3_OP_ST;
            `C3_OP_NOP: DEC_OP = `C3_OP_NOP;
            `C3_OP_HALT: DEC_OP = `C3_OP_HALT;
            `C3_OP_RD:  DEC_OP = `C3_OP_RD;
            `C3_OP_WR:  DEC_OP = `C3_OP_WR;
            default: begin
                DEC_OP  = `C3_OP_NOP;
                DEC_ERR = 1'b1;
            end
        endcase
    end

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            DEC_VALID <= 1'b0;
            dec_en    <= 1'b0;
        end else begin
            DEC_VALID <= dec_go_sync & ~DEC_ERR;
            dec_en    <= CL_GO | DEC_VALID;
        end
    end

    // 启动脉冲同步（位置端口连接）
    case3_sync_2ff u_go_sync (CLK, RST_N, CL_GO, dec_go_sync);

    // 命令通路时钟门控（位置端口连接）
    case3_clk_gate u_cmd_gate (CLK, dec_en, dec_gclk);

    assign CMD_CLK = dec_gclk;

endmodule
