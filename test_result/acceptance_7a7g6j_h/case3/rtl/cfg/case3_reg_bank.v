//==========================================================================
//  case3_reg_bank.v
//  配置寄存器堆 wrapper：真双口 RAM（RAM_DP）实现 16 x 32bit 配置寄存器组。
//  该模块不是叶子 —— 内部例化 RAM_DP。
//
//  Ref: SoC 里 config/control register file 的 RAM 实现（Cortex-M 系统控制块风格）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_reg_bank (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire [`C3_CFG_ADDR_W-1:0]  REG_ADDR,
    input  wire [`C3_CFG_DATA_W-1:0]  REG_WDATA,
    output wire [`C3_CFG_DATA_W-1:0]  REG_RDATA,
    input  wire                       REG_WR,
    input  wire                       REG_RD,
    output wire                       REG_READY,
    output wire [`C3_BANK_AW-1:0]     BANK_SEL,
    output wire                       BANK_ERR
);

    parameter BANK_ID    = 0;
    parameter BANK_SPLIT = `C3_RF_BANK_NUM;

    wire                       a_cen;
    wire                       a_wen;
    wire                       b_cen;
    wire [`C3_CFG_ADDR_W-1:0]  reg_addr_w;
    wire [`C3_CFG_DATA_W-1:0]  reg_wdata_w;
    wire                       ready_r;
    wire [`C3_CFG_DATA_W-1:0]  bank_aq_w;

    assign a_cen     = ~REG_WR;
    assign a_wen     = ~REG_WR;
    assign b_cen     = ~REG_RD;
    assign reg_addr_w  = REG_ADDR;
    assign reg_wdata_w = REG_WDATA;
    assign BANK_SEL  = REG_ADDR[`C3_BANK_AW-1:0];
    assign BANK_ERR  = REG_WR & REG_RD;

    // 库单元位置端口连接：
    // CLK, A_CEN, A_WEN, A_ADDR, A_D, A_Q, B_CEN, B_WEN, B_ADDR, B_D, B_Q
    RAM_DP u_reg_ram (CLK, a_cen, a_wen, reg_addr_w, reg_wdata_w, bank_aq_w,
                      b_cen, 1'b1, reg_addr_w, {`C3_CFG_DATA_W{1'b0}}, REG_RDATA);

    case3_sync_2ff u_reg_ready_sync (CLK, RST_N, REG_WR | REG_RD, ready_r);

    assign REG_READY = ready_r;

endmodule
