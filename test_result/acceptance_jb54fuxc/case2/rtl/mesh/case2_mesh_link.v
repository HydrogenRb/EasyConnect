//==========================================================================
//  case2_mesh_link.v
//  mesh 上的一条物理 flit link（320bit，单通道单向）：FIFO + 同步 + credit
//
//  层次：router port -> link -> 邻居 router port。link 内部例化
//  case2_sync_fifo（内含 RAM_SP_BE）、case2_sync_2ff、case2_gray_sync、
//  case2_noc_credit_ctrl、case2_noc_link_sync。
//
//  Ref: NoC link layer（TXREQFLIT/TXVALID/TXREADY + credit 归还）。
//==========================================================================
`include "case2_define.v"

module case2_mesh_link (
    input  wire                     CLK,
    input  wire                     RST_N,
    input  wire                     LINK_UP,
    input  wire [`C2_FLIT_W-1:0]    FLIT_IN,
    input  wire                     FLIT_IN_VALID,
    output wire                     FLIT_IN_READY,
    output wire [`C2_FLIT_W-1:0]    FLIT_OUT,
    output wire                     FLIT_OUT_VALID,
    input  wire                     FLIT_OUT_READY,
    output wire [`C2_CREDIT_W-1:0]  CREDIT_ON,
    input  wire [`C2_CREDIT_W-1:0]  CREDIT_RET,
    input  wire [`C2_BUF_PTR_W-1:0] PTR_IN,
    output wire [`C2_BUF_PTR_W-1:0] PTR_OUT
);

    wire [`C2_BUF_RAM_DW-1:0]  fifo_rd;
    wire                       fifo_empty;
    wire                       fifo_full;
    wire [`C2_BUF_PTR_W-1:0]   fifo_level;
    wire                       valid_sync;
    wire                       link_ready_int;
    wire [`C2_BUF_PTR_W-1:0]   ptr_gray;
    wire                       credit_ok;
    wire [`C2_CREDIT_W-1:0]    credit_cnt;
    wire [`C2_FLIT_KIND_W-1:0] link_kind;
    wire                       sync_err;

    assign FLIT_IN_READY  = ~fifo_full;
    assign FLIT_OUT_VALID = valid_sync & (~fifo_empty) & LINK_UP;
    assign FLIT_OUT       = {FLIT_IN[`C2_FLIT_W-1:`C2_BUF_RAM_DW], fifo_rd};
    assign link_kind      = FLIT_IN[`C2_FLIT_KIND_MSB:0];

    //------------------------------------------------------------------
    // link FIFO（内部例化 RAM_SP_BE）
    //------------------------------------------------------------------
    case2_sync_fifo u_link_fifo (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .WR_DATA    (FLIT_IN[`C2_BUF_RAM_DW-1:0]),
        .WR_EN      (FLIT_IN_VALID),
        .WR_READY   (),
        .RD_DATA    (fifo_rd),
        .RD_EN      (FLIT_OUT_READY),
        .RD_VALID   (),
        .FIFO_LEVEL (fifo_level),
        .FIFO_FULL  (fifo_full),
        .FIFO_EMPTY (fifo_empty)
    );

    //------------------------------------------------------------------
    // 握手 / 指针同步（位置连接风格）
    //------------------------------------------------------------------
    case2_sync_2ff u_valid_sync (CLK, RST_N, FLIT_IN_VALID, valid_sync);

    case2_gray_sync u_ptr_sync (
        .CLK     (CLK),
        .RST_N   (RST_N),
        .PTR_IN  (PTR_IN),
        .PTR_OUT (PTR_OUT)
    );

    //------------------------------------------------------------------
    // link credit 记账
    //------------------------------------------------------------------
    case2_noc_credit_ctrl u_link_credit (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .INIT       (~RST_N),
        .SEND       (FLIT_IN_VALID),
        .RET        (|CREDIT_RET),
        .RET_NUM    (CREDIT_RET),
        .CREDIT_CNT (credit_cnt),
        .CREDIT_OK  (credit_ok),
        .CREDIT_ON  (CREDIT_ON)
    );

    //------------------------------------------------------------------
    // link 握手同步级
    //------------------------------------------------------------------
    case2_noc_link_sync u_link_sync (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .LINK_UP   (LINK_UP),
        .KIND      (link_kind),
        .VALID_IN  (FLIT_IN_VALID),
        .READY_IN  (link_ready_int),
        .VALID_OUT (),
        .READY_OUT (FLIT_OUT_READY),
        .PTR_OUT   (ptr_gray),
        .PTR_IN    (PTR_IN),
        .SYNC_ERR  (sync_err)
    );

endmodule
