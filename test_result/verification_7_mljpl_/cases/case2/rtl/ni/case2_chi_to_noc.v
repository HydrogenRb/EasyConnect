//==========================================================================
//  case2_chi_to_noc.v
//  CHI 协议侧 -> NoC flit 侧：打包 + TxnID 分配 + credit 归还 + TX FIFO
//
//  Ref: RN/HN/SN 的 CHI-to-NoC 适配层（NCU 前半）。
//==========================================================================
`include "case2_define.v"

module case2_chi_to_noc (
    input  wire                         CLK,
    input  wire                         RST_N,
    input  wire [`C2_CHI_OPCODE_W-1:0]  OPCODE,
    input  wire [`C2_CHI_ADDR_W-1:0]    ADDR,
    input  wire [`C2_CHI_SIZE_W-1:0]    SIZE,
    input  wire [`C2_CHI_QOS_W-1:0]     QOS,
    input  wire [`C2_CHI_MEMATTR_W-1:0] MEMATTR,
    input  wire [`C2_CHI_SNPATTR_W-1:0] SNPATTR,
    input  wire [`C2_CHI_NODEID_W-1:0]  SRCID,
    input  wire [`C2_CHI_NODEID_W-1:0]  TGTID,
    input  wire [`C2_CHI_DATA_W-1:0]    DATA,
    input  wire [`C2_CHI_BE_W-1:0]      BE,
    input  wire                         CHI_VALID,
    output wire                         CHI_READY,
    output wire [`C2_CHI_TXNID_W-1:0]   TXNID,
    output wire [`C2_CHI_TAG_W-1:0]     TAG,
    output wire [`C2_REQ_FLIT_W-1:0]    REQ_TX,
    output wire                         REQ_TX_VALID,
    input  wire                         REQ_TX_READY,
    output wire [`C2_DAT_FLIT_W-1:0]    DAT_TX,
    output wire                         DAT_TX_VALID,
    input  wire                         DAT_TX_READY,
    input  wire [`C2_CREDIT_W-1:0]      CREDIT_RET,
    output wire [`C2_CREDIT_W-1:0]      CREDIT_ON,
    output wire [`C2_VC_NUM-1:0]        VC_FREE
);

    wire [`C2_CHI_TXNID_W-1:0] txnid_alloc;
    wire                       txnid_valid;
    wire                       alloc_full;
    wire [`C2_CREDIT_W-1:0]    txnid_free;
    wire [`C2_SNP_FILTER_W-1:0] txnid_mask;
    wire [`C2_REQ_FLIT_W-1:0]  packed_req;
    wire [`C2_DAT_FLIT_W-1:0]  packed_dat;
    wire [`C2_BUF_RAM_DW-1:0]  fifo_rd;
    wire                       fifo_empty;
    wire [`C2_BUF_PTR_W-1:0]   fifo_level;
    wire [`C2_CREDIT_W-1:0]    release_credit;
    wire [`C2_VC_NUM-1:0]      release_vc;
    wire                       req_push;
    wire                       dat_push;

    assign CHI_READY    = ~alloc_full;
    assign TXNID        = txnid_alloc;
    assign req_push     = CHI_VALID & (~alloc_full) & (~REQ_TX_READY);
    assign dat_push     = CHI_VALID & (|BE) & (~DAT_TX_READY);
    assign REQ_TX       = packed_req;
    assign DAT_TX       = packed_dat;
    assign REQ_TX_VALID = req_push;
    assign DAT_TX_VALID = dat_push;

    //------------------------------------------------------------------
    // flit 打包（REQ + DAT 两个通道共用一份字段）
    //------------------------------------------------------------------
    case2_chi_flit_pack u_pack (
        .CHI_VALID   (CHI_VALID),
        .QOS         (QOS),
        .SRCID       (SRCID),
        .TGTID       (TGTID),
        .RETURNID    (SRCID),
        .FWDNID      (TGTID),
        .TXNID       (txnid_alloc),
        .FWDTXNID    (txnid_alloc),
        .OPCODE      (OPCODE),
        .SIZE        (SIZE),
        .ADDR        (ADDR),
        .NS          (1'b0),
        .MEMATTR     (MEMATTR),
        .SNPATTR     (SNPATTR),
        .EXPCOMPACK  (1'b1),
        .TAG         (TAG),
        .LPID        ({`C2_CHI_LPID_W{1'b0}}),
        .MPAM        ({`C2_CHI_MPAM_W{1'b0}}),
        .PCRDTYPE    ({`C2_CHI_PCRDTYPE_W{1'b0}}),
        .ALLOWRETRY  (1'b1),
        .ORDER       ({`C2_CHI_ORDER_W{1'b0}}),
        .RESP        (`C2_RESP_ICO),
        .RESPERR     (`C2_RESPERR_OKAY),
        .FWDSTATE    (`C2_FWDSTATE_I),
        .DATASOURCE  ({`C2_CHI_DATASOURCE_W{1'b0}}),
        .CBUSY       ({`C2_CHI_CBUSY_W{1'b0}}),
        .DATAID      ({`C2_CHI_DATAID_W{1'b1}}),
        .CCID        ({`C2_CHI_CCID_W{1'b0}}),
        .DBID        ({`C2_CHI_DBID_W{1'b0}}),
        .RETTOSRC    (1'b0),
        .TRACETAG    ({`C2_CHI_TRACETAG_W{1'b0}}),
        .BE          (BE),
        .DATA        (DATA),
        .REQ_FLIT    (packed_req),
        .RSP_FLIT    (),
        .SNP_FLIT    (),
        .DAT_FLIT    (packed_dat)
    );

    assign TAG = CHI_VALID ? ADDR[`C2_CHI_TAG_W-1:0] : {`C2_CHI_TAG_W{1'b0}};

    //------------------------------------------------------------------
    // TxnID 分配
    //------------------------------------------------------------------
    case2_chi_txnid_alloc u_txnid (
        .CLK            (CLK),
        .RST_N          (RST_N),
        .ALLOC_REQ      (CHI_VALID),
        .FREE_REQ       (REQ_TX_READY),
        .FREE_ID        (txnid_alloc),
        .TXNID          (txnid_alloc),
        .TXNID_VALID    (txnid_valid),
        .TXNID_FREE_CNT (txnid_free),
        .ALLOC_FULL     (alloc_full),
        .TXNID_MASK     (txnid_mask)
    );

    //------------------------------------------------------------------
    // 事务完成后的 credit 归还
    //------------------------------------------------------------------
    case2_chi_credit_release u_credit_rel (
        .CLK          (CLK),
        .RST_N        (RST_N),
        .RELEASE      (REQ_TX_READY & DAT_TX_READY),
        .TXNID        (txnid_alloc),
        .VC_BUSY      ({`C2_VC_NUM{1'b1}}),
        .CREDIT_RET   (release_credit),
        .VC_FREE      (release_vc),
        .RELEASE_DONE (),
        .TXNID_HOLD   ()
    );

    assign CREDIT_ON = CREDIT_RET | release_credit;
    assign VC_FREE   = release_vc;

    //------------------------------------------------------------------
    // TX FIFO（REQ 描述符）
    //------------------------------------------------------------------
    case2_sync_fifo u_tx_fifo (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .WR_DATA    (packed_req[`C2_BUF_RAM_DW-1:0]),
        .WR_EN      (req_push),
        .WR_READY   (),
        .RD_DATA    (fifo_rd),
        .RD_EN      (REQ_TX_READY),
        .RD_VALID   (),
        .FIFO_LEVEL (fifo_level),
        .FIFO_FULL  (),
        .FIFO_EMPTY (fifo_empty)
    );

endmodule
