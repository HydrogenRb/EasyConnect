//==========================================================================
//  case3_xbar_cell.v
//  交叉开关单元：4 个 VC 仲裁器（同一模块 4 个不同实例名，带参数覆盖）
//  + 一个用 RAM_SP 搭的 skid buffer。
//
//  Ref: crossbar cell（每个 turn point 一个 cell，多 VC 仲裁 + skid buffer 反压）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_xbar_cell (
    input  wire                    CLK,
    input  wire                    RST_N,
    input  wire                    CELL_REQ,
    input  wire [`C3_LANE_AW-1:0]  CELL_SEL,
    input  wire [`C3_DATA_W-1:0]   CELL_DATA_IN,
    output wire [`C3_DATA_W-1:0]   CELL_DATA_OUT,
    output wire                    CELL_GRANT,
    output wire                    CELL_BUSY
);

    parameter CELL_ID   = 0;
    parameter PRIO_MODE = `C3_XBAR_FIXED_PRIO;

    wire [`C3_LANE_NUM-1:0] req_vec_w;
    wire [`C3_LANE_NUM-1:0] grant_vec_w [0:`C3_XFER_ID_W-1];
    wire [`C3_LANE_AW-1:0]  sel_w       [0:`C3_XFER_ID_W-1];
    wire                    arb_busy_w  [0:`C3_XFER_ID_W-1];
    wire                    skid_cen_w;
    wire                    skid_wen_w;
    wire [`C3_BANK_NUM-1:0] skid_ben_w;
    wire [`C3_BANK_ADDR_W-1:0] skid_addr_w;
    wire [`C3_DATA_W-1:0]   skid_q_w;

    assign req_vec_w   = {`C3_LANE_NUM{CELL_REQ}};
    assign skid_cen_w  = ~CELL_REQ;
    assign skid_wen_w  = ~(CELL_REQ & CELL_SEL[0]);
    assign skid_ben_w  = {`C3_BANK_NUM{CELL_REQ}};
    assign skid_addr_w = {`C3_BANK_ADDR_W{1'b0}} | CELL_SEL;
    assign CELL_DATA_OUT = skid_q_w ^ CELL_DATA_IN;
    assign CELL_GRANT    = |grant_vec_w[0];
    assign CELL_BUSY     = arb_busy_w[0] | arb_busy_w[1] | arb_busy_w[2] | arb_busy_w[3];

    case3_xbar_arb #(
        .VC_ID     (0),
        .PRIO_MODE (`C3_XBAR_FIXED_PRIO)
    ) u_arb_vc0 (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REQ_VEC   (req_vec_w),
        .PRIO      (CELL_SEL),
        .GRANT_VEC (grant_vec_w[0]),
        .SEL       (sel_w[0]),
        .ARB_BUSY  (arb_busy_w[0])
    );

    case3_xbar_arb #(
        .VC_ID     (1),
        .PRIO_MODE (`C3_XBAR_ROUND_ROBIN)
    ) u_arb_vc1 (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REQ_VEC   (req_vec_w),
        .PRIO      (CELL_SEL),
        .GRANT_VEC (grant_vec_w[1]),
        .SEL       (sel_w[1]),
        .ARB_BUSY  (arb_busy_w[1])
    );

    case3_xbar_arb #(
        .VC_ID     (2),
        .PRIO_MODE (`C3_XBAR_ROUND_ROBIN)
    ) u_arb_vc2 (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REQ_VEC   (req_vec_w),
        .PRIO      (CELL_SEL),
        .GRANT_VEC (grant_vec_w[2]),
        .SEL       (sel_w[2]),
        .ARB_BUSY  (arb_busy_w[2])
    );

    case3_xbar_arb #(
        .VC_ID     (3),
        .PRIO_MODE (2'b00)
    ) u_arb_vc3 (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REQ_VEC   (req_vec_w),
        .PRIO      (CELL_SEL),
        .GRANT_VEC (grant_vec_w[3]),
        .SEL       (sel_w[3]),
        .ARB_BUSY  (arb_busy_w[3])
    );

    // skid buffer 存储体：库单元位置端口连接
    RAM_SP u_skid_buf (CLK, skid_cen_w, skid_wen_w, skid_ben_w, skid_addr_w, CELL_DATA_IN, skid_q_w);

endmodule
