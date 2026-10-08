//==========================================================================
//  case3_scratch_bank.v
//  scratchpad 单 bank wrapper：一个真双口 RAM（RAM_DP）+ 忙标志同步。
//  该模块不是叶子 —— 内部例化 RAM_DP（库单元）。
//
//  Ref: memory compiler 生成的 DP SRAM 外面那层 bank wrapper
//       （多 bank scratchpad 里每个 bank 的 ctrl/ECC 适配层）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_scratch_bank (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire                          BANK_CEN,
    input  wire                          BANK_WEN,
    input  wire [`C3_BANK_ADDR_W-1:0]    BANK_ADDR,
    input  wire [`C3_SCRATCH_DATA_W-1:0] BANK_WDATA,
    output wire [`C3_SCRATCH_DATA_W-1:0] BANK_RDATA,
    output wire [`C3_SCRATCH_DATA_W-1:0] BANK_AQ,
    output wire                          BANK_BUSY,
    output wire                          BANK_ERR
);

    parameter BANK_ID   = 0;
    parameter BANK_AW   = `C3_BANK_AW;
    parameter BANK_MODE = `C3_BANK_MODE_RW;

    wire                      a_cen;
    wire                      a_wen;
    wire                      b_cen;
    wire                      b_wen;
    wire [`C3_BANK_ADDR_W-1:0] b_addr_w;
    wire [`C3_SCRATCH_DATA_W-1:0] bank_a_q;
    wire [`C3_SCRATCH_DATA_W-1:0] bank_b_d;

    assign a_cen    = BANK_CEN;
    assign a_wen    = BANK_WEN;
    assign b_cen    = BANK_CEN;
    assign b_wen    = 1'b1;
    assign b_addr_w = BANK_ADDR;
    assign bank_b_d = {`C3_SCRATCH_DATA_W{1'b0}};
    assign BANK_ERR = (~BANK_WEN) & (~BANK_CEN) & (BANK_MODE == `C3_BANK_MODE_REPAIR);

    // 库单元位置端口连接：
    // CLK, A_CEN, A_WEN, A_ADDR, A_D, A_Q, B_CEN, B_WEN, B_ADDR, B_D, B_Q
    RAM_DP u_bank_ram (CLK, a_cen, a_wen, BANK_ADDR, BANK_WDATA, bank_a_q,
                       b_cen, b_wen, b_addr_w, bank_b_d, BANK_RDATA);

    // 忙标志跨 bank 同步（位置端口连接）
    case3_sync_2ff u_bank_busy_sync (CLK, RST_N, BANK_CEN, BANK_BUSY);

    // A 口读出数据（写口回读），供仲裁/校验通路使用
    assign BANK_AQ = bank_a_q;

endmodule
