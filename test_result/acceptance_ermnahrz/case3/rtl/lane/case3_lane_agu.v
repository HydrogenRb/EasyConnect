//==========================================================================
//  case3_lane_agu.v
//  地址生成单元：基址 + 偏移 + 步长，支持 wrap 检测与 bank 选择。
//  叶子模块（内部没有任何例化）。
//
//  Ref: DMA / 向量 load-store 的 address generator（NVDLA CDMA、Vision P6 vagu）。
//==========================================================================
`include "case3_define.v"

module case3_lane_agu (
    input  wire                     CLK,
    input  wire                     RST_N,
    input  wire [`C3_ADDR_W-1:0]    BASE,
    input  wire [`C3_ADDR_W-1:0]    OFFSET,
    input  wire [`C3_ADDR_W-1:0]    STRIDE,
    input  wire [`C3_OP_W-1:0]      MODE,
    input  wire                     STEP,
    output wire [`C3_ADDR_W-1:0]    ADDR,
    output reg                      WRAP,
    output reg                      REQ,
    output wire [`C3_BANK_AW-1:0]   BANK_SEL,
    output wire [`C3_SCRATCH_ADDR_W-1:0] LOCAL_ADDR
);

    parameter AGU_MODE = `C3_XBAR_ROUND_ROBIN;

    reg [`C3_ADDR_W-1:0] addr_r;
    reg [`C3_ADDR_W-1:0] next_addr;

    always @(*) begin
        case (MODE)
            `C3_OP_LD:  next_addr = addr_r + STRIDE;
            `C3_OP_ST:  next_addr = addr_r + STRIDE;
            `C3_OP_ADD: next_addr = BASE + OFFSET;
            `C3_OP_MAC: next_addr = BASE + OFFSET + STRIDE;
            default:    next_addr = addr_r;
        endcase
    end

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            addr_r <= {`C3_ADDR_W{1'b0}};
            WRAP   <= 1'b0;
            REQ    <= 1'b0;
        end else if (STEP) begin
            addr_r <= next_addr;
            WRAP   <= |(next_addr[`C3_ADDR_MSB:`C3_SCRATCH_MSB]);
            REQ    <= (MODE == `C3_OP_LD) || (MODE == `C3_OP_ST);
        end else begin
            REQ    <= 1'b0;
        end
    end

    assign ADDR       = addr_r;
    assign BANK_SEL   = addr_r[`C3_BANK_AW+`C3_BANK_ADDR_W-1:`C3_BANK_ADDR_W];
    assign LOCAL_ADDR = addr_r[`C3_SCRATCH_MSB:0];

endmodule
