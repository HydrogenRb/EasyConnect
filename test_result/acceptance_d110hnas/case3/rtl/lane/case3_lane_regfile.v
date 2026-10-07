//==========================================================================
//  case3_lane_regfile.v
//  寄存器堆 wrapper：用简单双口 RAM（RAM_2P）搭出 1 写 2 读的 lane 私有 RF。
//  该模块不是叶子 —— 它只例化库单元 RAM_2P（库单元才是层次树叶子）。
//
//  Ref: Vivado/Quartus 推断出的 regfile RAM（RAM_2P 实现 1W2R 的常见手法）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_lane_regfile (
    input  wire                     CLK,
    input  wire                     RST_N,
    input  wire [`C3_REG_ADDR_W-1:0] RD_ADDR_A,
    input  wire [`C3_REG_ADDR_W-1:0] RD_ADDR_B,
    output wire [`C3_DATA_W-1:0]    RD_DATA_A,
    output wire [`C3_DATA_W-1:0]    RD_DATA_B,
    input  wire [`C3_REG_ADDR_W-1:0] WR_ADDR,
    input  wire [`C3_DATA_W-1:0]    WR_DATA,
    input  wire                     WR_EN,
    input  wire                     RD_EN_A,
    input  wire                     RD_EN_B,
    output wire                     RF_BUSY
);

    parameter RF_DEPTH = `C3_REG_NUM;
    parameter RF_WIDTH = `C3_DATA_W;

    wire                      a_cen;
    wire                      a_wen;
    wire                      rd_a_cen;
    wire                      rd_b_cen;
    wire [`C3_REG_ADDR_W-1:0] wr_addr_w;
    wire [`C3_REG_ADDR_W-1:0] rd_addr_a_w;
    wire [`C3_REG_ADDR_W-1:0] rd_addr_b_w;

    assign a_cen       = ~WR_EN;
    assign a_wen       = ~WR_EN;
    assign rd_a_cen    = ~RD_EN_A;
    assign rd_b_cen    = ~RD_EN_B;
    assign wr_addr_w   = WR_ADDR;
    assign rd_addr_a_w = RD_ADDR_A;
    assign rd_addr_b_w = RD_ADDR_B;
    assign RF_BUSY     = WR_EN | RD_EN_A | RD_EN_B;

    // 写口 + 读口 A：库单元位置端口连接
    RAM_2P u_rf_bank_a (CLK, a_cen, a_wen, wr_addr_w, WR_DATA,
                        rd_a_cen, rd_addr_a_w, RD_DATA_A);

    // 读口 B：位置端口连接（库单元例化常用风格）
    RAM_2P u_rf_bank_b (CLK, rd_b_cen, 1'b1, wr_addr_w, WR_DATA, rd_b_cen, rd_addr_b_w, RD_DATA_B);

endmodule
