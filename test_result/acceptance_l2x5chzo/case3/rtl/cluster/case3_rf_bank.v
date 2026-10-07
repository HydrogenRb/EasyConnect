//==========================================================================
//  case3_rf_bank.v
//  共享寄存器堆：两个 case3_reg_bank 乒乓（#( .BANK_ID(...) ) 参数覆盖）。
//
//  Ref: 向量机里的 shared RF / uniformity register file（Vision P6 共享 RF 池）。
//==========================================================================
`include "case3_define.v"

module case3_rf_bank (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire [`C3_REG_ADDR_W-1:0]  RF_ADDR,
    input  wire [`C3_DATA_W-1:0]      RF_WDATA,
    output wire [`C3_DATA_W-1:0]      RF_RDATA,
    input  wire                       RF_WE,
    input  wire                       RF_RE,
    output wire                       RF_READY,
    output wire                       RF_BUSY,
    output wire [`C3_BANK_AW-1:0]     RF_BANK_SEL,
    output wire                       RF_ERR
);

    parameter RF_PINGPONG = `C3_RF_BANK_NUM;

    wire                  ready_lo_w;
    wire                  ready_hi_w;
    wire                  err_hi_w;
    wire [`C3_BANK_AW-1:0] bank_sel_lo_w;
    wire [`C3_BANK_AW-1:0] bank_sel_hi_w;
    wire                  rf_ready_sync_w;

    // 低位 bank：参数覆盖 #( .BANK_ID(0) )
    case3_reg_bank #(
        .BANK_ID    (0),
        .BANK_SPLIT (`C3_RF_BANK_NUM)
    ) u_bank_lo (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REG_ADDR  (RF_ADDR),
        .REG_WDATA (RF_WDATA),
        .REG_RDATA (RF_RDATA),
        .REG_WR    (RF_WE),
        .REG_RD    (RF_RE),
        .REG_READY (ready_lo_w),
        .BANK_SEL  (bank_sel_lo_w),
        .BANK_ERR  ()
    );

    // 高位 bank：参数覆盖 #( .BANK_ID(1) )
    case3_reg_bank #(
        .BANK_ID    (1),
        .BANK_SPLIT (`C3_RF_BANK_NUM)
    ) u_bank_hi (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REG_ADDR  (RF_ADDR),
        .REG_WDATA (RF_WDATA),
        .REG_RDATA (),
        .REG_WR    (RF_WE),
        .REG_RD    (RF_RE),
        .REG_READY (ready_hi_w),
        .BANK_SEL  (bank_sel_hi_w),
        .BANK_ERR  (err_hi_w)
    );

    case3_sync_2ff u_rf_ready_sync (CLK, RST_N, ready_lo_w, rf_ready_sync_w);

    assign RF_BANK_SEL = bank_sel_lo_w | bank_sel_hi_w;
    assign RF_READY    = ready_hi_w;
    assign RF_BUSY     = RF_WE | RF_RE | rf_ready_sync_w;
    assign RF_ERR      = err_hi_w;

endmodule
