//==========================================================================
//  case3_lane_aligner.v
//  访存对齐单元：按字节偏移做桶形旋转，并生成字节使能 / lane mask。
//  叶子模块（内部没有任何例化）。
//
//  Ref: load-store unit 里的 aligner / byte-rotator（Rocket L1D、Cortex-M7 LSU）。
//==========================================================================
`include "case3_define.v"

module case3_lane_aligner (
    input  wire [`C3_DATA_W-1:0]    DATA_IN,
    input  wire [`C3_BANK_AW-1:0]   OFFSET,
    input  wire [`C3_OP_W-1:0]      MODE,
    input  wire [`C3_LANE_W-1:0]    LANE_SEL,
    output reg  [`C3_DATA_W-1:0]    DATA_OUT,
    output reg  [`C3_BANK_NUM-1:0]  BEN,
    output reg  [`C3_LANE_NUM-1:0]  LANE_MASK,
    output reg  [`C3_FLAG_W-1:0]    ALIGN_FLAGS
);

    reg [`C3_DATA_W-1:0] rot_tmp;
    reg [`C3_BANK_NUM-1:0] ben_tmp;

    always @(*) begin
        case (OFFSET)
            `C3_BANK_AW'd0: rot_tmp = DATA_IN;
            `C3_BANK_AW'd1: rot_tmp = {DATA_IN[`C3_ADDR_MSB:0], DATA_IN[`C3_DATA_MSB:`C3_ADDR_MSB+1]};
            `C3_BANK_AW'd2: rot_tmp = {DATA_IN[`C3_PE_MSB:0], DATA_IN[`C3_DATA_MSB:`C3_PE_MSB+1]};
            default:        rot_tmp = {DATA_IN[`C3_BYTE_MSB:0], DATA_IN[`C3_DATA_MSB:`C3_BYTE_W]};
        endcase
        ben_tmp  = {`C3_BANK_NUM{1'b1}};
        LANE_MASK = {`C3_LANE_NUM{1'b0}};
        ALIGN_FLAGS = {`C3_FLAG_W{1'b0}};
        if (MODE == `C3_OP_ST) begin
            ben_tmp   = ~({`C3_BANK_NUM{1'b1}} << OFFSET);
            LANE_MASK = {`C3_LANE_NUM{1'b1}} >> LANE_SEL[`C3_LANE_AW-1:0];
            ALIGN_FLAGS[`C3_FLAG_STICKY] = 1'b1;
        end else if (MODE == `C3_OP_LD) begin
            ben_tmp   = {`C3_BANK_NUM{1'b1}};
            LANE_MASK = {`C3_LANE_NUM{1'b1}};
            ALIGN_FLAGS[`C3_FLAG_ZERO] = ~|OFFSET;
        end else begin
            ben_tmp   = {`C3_BANK_NUM{1'b0}};
            LANE_MASK = {`C3_LANE_NUM{1'b0}};
            ALIGN_FLAGS[`C3_FLAG_OVF] = |OFFSET;
        end
        DATA_OUT = rot_tmp;
        BEN      = ben_tmp;
    end

endmodule
