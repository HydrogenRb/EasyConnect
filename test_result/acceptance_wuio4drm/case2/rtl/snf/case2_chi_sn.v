//==========================================================================
//  case2_chi_sn.v
//  一个 CHI slave node：协议流水 + 存储缓冲 + DBID 分配
//
//  Ref: CHI SN-F（每个 SN 一份协议流水 + 一块 RAM_SP_BE 缓冲）。
//==========================================================================
`include "case2_define.v"

module case2_chi_sn (
    input  wire                        CLK,
    input  wire                        RST_N,
    input  wire [`C2_CHI_NODEID_W-1:0] SN_ID,
    input  wire [`C2_REQ_FLIT_W-1:0]   REQ_RX,
    input  wire                        REQ_RX_VALID,
    output wire                        REQ_RX_READY,
    output wire [`C2_RSP_FLIT_W-1:0]   RSP_TX,
    output wire                        RSP_TX_VALID,
    input  wire                        RSP_TX_READY,
    output wire [`C2_DAT_FLIT_W-1:0]   DAT_TX,
    output wire                        DAT_TX_VALID,
    input  wire                        DAT_TX_READY,
    input  wire [`C2_DAT_FLIT_W-1:0]   DAT_RX,
    input  wire                        DAT_RX_VALID,
    output wire                        DAT_RX_READY,
    output wire [`C2_CHI_DATA_W-1:0]   SN_DATA,
    output wire [`C2_CHI_BE_W-1:0]     SN_BE,
    output wire [`C2_CHI_DBID_W-1:0]   SN_DBID,
    output wire                        SN_ACTIVE
);

    wire [`C2_FLIT_W-1:0]      sn_flit_out;
    wire [`C2_FLIT_W-1:0]      sn_flit_in;
    wire [`C2_BUF_PTR_W-1:0]   sn_wr_ptr;
    wire [`C2_BUF_PTR_W-1:0]   sn_rd_ptr;
    wire [`C2_CREDIT_W-1:0]    sn_ram_credit;
    wire                       sn_ram_ready;
    wire [`C2_BUF_RAM_DW-1:0]  sn_ram_word;
    wire [`C2_CHI_DBID_W-1:0]  sn_dbid;
    wire [`C2_CHI_DBID_W-1:0]  sn_pipe_dbid;
    wire                       sn_dbid_valid;
    wire [`C2_CHI_DBID_W-1:0]  sn_dbid_cnt;
    wire [`C2_CHI_CBUSY_W-1:0] sn_dbid_cbusy;
    wire                       sn_pipe_idle;

    assign SN_DATA   = sn_flit_out[`C2_CHI_DATA_MSB:`C2_CHI_DATA_LSB];
    assign SN_BE     = sn_ram_word[`C2_CHI_BE_MSB:`C2_CHI_BE_LSB];
    assign SN_DBID   = sn_dbid;
    assign SN_ACTIVE = ~sn_pipe_idle;

    //------------------------------------------------------------------
    // 协议流水
    //------------------------------------------------------------------
    case2_chi_sn_pipe u_pipe (
        .CLK          (CLK),
        .RST_N        (RST_N),
        .NODEID       (SN_ID),
        .REQ_RX       (REQ_RX),
        .REQ_RX_VALID (REQ_RX_VALID),
        .REQ_RX_READY (REQ_RX_READY),
        .RSP_TX       (RSP_TX),
        .RSP_TX_VALID (RSP_TX_VALID),
        .RSP_TX_READY (RSP_TX_READY),
        .DAT_TX       (DAT_TX),
        .DAT_TX_VALID (DAT_TX_VALID),
        .DAT_TX_READY (DAT_TX_READY),
        .DAT_RX       (DAT_RX),
        .DAT_RX_VALID (DAT_RX_VALID),
        .DAT_RX_READY (DAT_RX_READY),
        .DBID         (sn_pipe_dbid),
        .DATA         (),
        .BE           (),
        .SN_PIPE_IDLE (sn_pipe_idle)
    );

    //------------------------------------------------------------------
    // 存储缓冲（内部例化 RAM_SP_BE）
    //------------------------------------------------------------------
    case2_noc_buf_ram_wrap u_ram_wrap (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .FLIT_WR   (REQ_RX_VALID),
        .FLIT_IN   (sn_flit_in),
        .WR_PTR    (sn_wr_ptr),
        .RD_PTR    (sn_rd_ptr),
        .FLIT_OUT  (sn_flit_out),
        .RAM_READY (sn_ram_ready),
        .RAM_CREDIT(sn_ram_credit),
        .RAM_Q_WORD(sn_ram_word)
    );

    //------------------------------------------------------------------
    // DBID 分配
    //------------------------------------------------------------------
    case2_chi_dbid_alloc u_dbid (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .DBID_REQ   (REQ_RX_VALID),
        .DBID_FREE  (DAT_TX_READY),
        .DBID_IN    (sn_dbid_cnt),
        .DBID       (sn_dbid),
        .DBID_CNT   (sn_dbid_cnt),
        .DBID_VALID (sn_dbid_valid),
        .DBID_CBUSY (sn_dbid_cbusy)
    );

    assign sn_flit_in = {{`C2_REQ_PAD_W{1'b0}}, REQ_RX};
    assign sn_wr_ptr  = REQ_RX[`C2_BUF_PTR_W-1:0];
    assign sn_rd_ptr  = sn_dbid[`C2_BUF_PTR_W-1:0];

endmodule
