//==========================================================================
//  case2_chi_rn.v
//  CHI request node：请求生成 + 响应跟踪 + snoop 处理 + 数据通路
//
//  Ref: CHI RN（RN-F）的四个子块，数据缓冲用库宏单元 RAM_DP。
//==========================================================================
`include "case2_define.v"

module case2_chi_rn (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire [`C2_CHI_NODEID_W-1:0]   NODEID,
    input  wire [`C2_CHI_NODEID_W-1:0]   HOMEID,
    input  wire                          REQ_START,
    input  wire [`C2_CHI_OPCODE_W-1:0]   REQ_OPCODE,
    input  wire [`C2_CHI_ADDR_W-1:0]     REQ_ADDR,
    input  wire [`C2_CHI_SIZE_W-1:0]     REQ_SIZE,
    input  wire [`C2_CHI_QOS_W-1:0]      REQ_QOS,
    input  wire [`C2_CHI_MEMATTR_W-1:0]  REQ_MEMATTR,
    input  wire [`C2_CHI_SNPATTR_W-1:0]  REQ_SNPATTR,
    input  wire [`C2_CHI_DATA_W-1:0]     WDATA,
    input  wire [`C2_CHI_BE_W-1:0]       WBE,
    input  wire                          WDATA_VALID,
    output wire                          WDATA_READY,
    output wire [`C2_REQ_FLIT_W-1:0]     REQ_FLIT,
    output wire                          REQ_FLIT_VALID,
    input  wire                          REQ_FLIT_READY,
    output wire [`C2_CHI_TXNID_W-1:0]    TXNID,
    output wire [`C2_CHI_TAG_W-1:0]      TAG,
    input  wire [`C2_RSP_FLIT_W-1:0]     RSP_RX,
    input  wire                          RSP_RX_VALID,
    output wire                          RSP_RX_READY,
    input  wire [`C2_SNP_FLIT_W-1:0]     SNP_RX,
    input  wire                          SNP_RX_VALID,
    output wire                          SNP_RX_READY,
    input  wire [`C2_DAT_FLIT_W-1:0]     DAT_RX,
    input  wire                          DAT_RX_VALID,
    output wire                          DAT_RX_READY,
    output wire [`C2_RSP_FLIT_W-1:0]     RSP_TX,
    output wire                          RSP_TX_VALID,
    input  wire                          RSP_TX_READY,
    output wire [`C2_DAT_FLIT_W-1:0]     DAT_TX,
    output wire                          DAT_TX_VALID,
    input  wire                          DAT_TX_READY,
    output wire [`C2_CHI_RESP_W-1:0]     RESP,
    output wire [`C2_CHI_RESPERR_W-1:0]  RESPERR,
    output wire [`C2_CHI_DATA_W-1:0]     RDATA,
    output wire [`C2_CHI_BE_W-1:0]       RBE,
    output wire                          RSP_DONE,
    output wire                          SNP_HIT
);

    wire [`C2_CREDIT_W-1:0]     txnid_free;
    wire                        alloc_full;
    wire [`C2_SNP_FILTER_W-1:0] txnid_mask;
    wire [`C2_CREDIT_W-1:0]     rsp_credit_ret;
    wire [`C2_VC_NUM-1:0]       rsp_vc_free;
    wire [`C2_CHI_OPCODE_W-1:0] snp_opcode;
    wire [`C2_CHI_TXNID_W-1:0]  snp_txnid;
    wire [`C2_CHI_NODEID_W-1:0] snp_fwdnid;
    wire [`C2_CHI_FWDSTATE_W-1:0] snp_fwdstate;
    wire                        snp_clean;
    wire                        rsp_order_err;
    wire [`C2_CHI_DBID_W-1:0]   wdata_dbid;

    assign RSP_DONE = RSP_RX_VALID & (~rsp_order_err);

    //------------------------------------------------------------------
    // 请求生成
    //------------------------------------------------------------------
    case2_chi_req_gen u_req_gen (
        .CLK            (CLK),
        .RST_N          (RST_N),
        .REQ_START      (REQ_START),
        .REQ_FREE       (RSP_DONE),
        .REQ_OPCODE     (REQ_OPCODE),
        .ADDR           (REQ_ADDR),
        .SIZE           (REQ_SIZE),
        .QOS            (REQ_QOS),
        .MEMATTR        (REQ_MEMATTR),
        .SNPATTR        (REQ_SNPATTR),
        .SRCID          (NODEID),
        .TGTID          (HOMEID),
        .DATA           (WDATA),
        .BE             (WBE),
        .FREE_ID        (TXNID),
        .TXNID          (TXNID),
        .TAG            (TAG),
        .REQ_FLIT       (REQ_FLIT),
        .REQ_VALID      (REQ_FLIT_VALID),
        .REQ_READY      (REQ_FLIT_READY),
        .ALLOC_FULL     (alloc_full),
        .TXNID_FREE_CNT (txnid_free),
        .TXNID_MASK     (txnid_mask)
    );

    //------------------------------------------------------------------
    // 响应跟踪
    //------------------------------------------------------------------
    case2_chi_rsp_track u_rsp_track (
        .CLK           (CLK),
        .RST_N         (RST_N),
        .RSP_RX        (RSP_RX),
        .RSP_RX_VALID  (RSP_RX_VALID),
        .RSP_RX_READY  (RSP_RX_READY),
        .TXNID         (),
        .RESP          (RESP),
        .RESPERR       (RESPERR),
        .RSP_OPCODE    (),
        .RSP_DONE      (),
        .RSP_ORDER_ERR (rsp_order_err),
        .CREDIT_RET    (rsp_credit_ret),
        .VC_FREE       (rsp_vc_free)
    );

    //------------------------------------------------------------------
    // snoop 处理
    //------------------------------------------------------------------
    case2_chi_snp_handle u_snp (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .SNP_RX     (SNP_RX),
        .SNP_RX_VALID(SNP_RX_VALID),
        .SNP_RX_READY(SNP_RX_READY),
        .RSP_TX     (RSP_TX),
        .RSP_TX_VALID(RSP_TX_VALID),
        .RSP_TX_READY(RSP_TX_READY),
        .SNP_OPCODE (snp_opcode),
        .SNP_TXNID  (snp_txnid),
        .FWDNID     (snp_fwdnid),
        .FWDSTATE   (snp_fwdstate),
        .SNP_HIT    (SNP_HIT),
        .SNP_CLEAN  (snp_clean)
    );

    //------------------------------------------------------------------
    // 数据通路（内部例化 RAM_DP）
    //------------------------------------------------------------------
    case2_chi_dat_path u_dat (
        .CLK           (CLK),
        .RST_N         (RST_N),
        .DAT_RX        (DAT_RX),
        .DAT_RX_VALID  (DAT_RX_VALID),
        .DAT_RX_READY  (DAT_RX_READY),
        .DAT_TX        (DAT_TX),
        .DAT_TX_VALID  (DAT_TX_VALID),
        .DAT_TX_READY  (DAT_TX_READY),
        .WDATA         (WDATA),
        .WDATA_VALID   (WDATA_VALID),
        .WDATA_READY   (WDATA_READY),
        .RDATA         (RDATA),
        .BE            (RBE),
        .DBID          (wdata_dbid)
    );

endmodule
