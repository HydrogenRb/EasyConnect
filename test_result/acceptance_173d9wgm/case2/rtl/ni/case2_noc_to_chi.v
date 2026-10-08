//==========================================================================
//  case2_noc_to_chi.v
//  NoC flit 侧 -> CHI 协议侧：拆包 + 顺序检查 + RX FIFO
//
//  Ref: RN/HN/SN 的 NoC-to-CHI 适配层（NCU 后半）。
//==========================================================================
`include "case2_define.v"

module case2_noc_to_chi (
    input  wire                         CLK,
    input  wire                         RST_N,
    input  wire [`C2_RSP_FLIT_W-1:0]    RSP_RX,
    input  wire                         RSP_RX_VALID,
    output wire                         RSP_RX_READY,
    input  wire [`C2_DAT_FLIT_W-1:0]    DAT_RX,
    input  wire                         DAT_RX_VALID,
    output wire                         DAT_RX_READY,
    output wire [`C2_CHI_OPCODE_W-1:0]  OPCODE,
    output wire [`C2_CHI_TXNID_W-1:0]   TXNID,
    output wire [`C2_CHI_RESP_W-1:0]    RESP,
    output wire [`C2_CHI_RESPERR_W-1:0] RESPERR,
    output wire [`C2_CHI_FWDSTATE_W-1:0] FWDSTATE,
    output wire [`C2_CHI_DATA_W-1:0]    DATA,
    output wire [`C2_CHI_BE_W-1:0]      BE,
    output wire [`C2_CHI_DBID_W-1:0]    DBID,
    output wire [`C2_CHI_DATAID_W-1:0]  DATAID,
    output wire                         CHI_VALID,
    output wire                         ORDER_ERR,
    output wire                         CHI_LAST
);

    wire [`C2_CHI_QOS_W-1:0]        qos;
    wire [`C2_CHI_NODEID_W-1:0]     srcid;
    wire [`C2_CHI_NODEID_W-1:0]     tgtid;
    wire [`C2_CHI_NODEID_W-1:0]     returnid;
    wire [`C2_CHI_NODEID_W-1:0]     fwdnid;
    wire [`C2_CHI_TXNID_W-1:0]      fwdtxnid;
    wire [`C2_CHI_OPCODE_W-1:0]     req_opcode;
    wire [`C2_CHI_OPCODE_W-1:0]     snp_opcode;
    wire [`C2_CHI_OPCODE_W-1:0]     dat_opcode;
    wire [`C2_CHI_SIZE_W-1:0]       size;
    wire [`C2_CHI_ADDR_W-1:0]       addr;
    wire                            ns;
    wire [`C2_CHI_MEMATTR_W-1:0]    memattr;
    wire [`C2_CHI_SNPATTR_W-1:0]    snpattr;
    wire [`C2_CHI_EXPCOMPACK_W-1:0] expcompack;
    wire [`C2_CHI_TAG_W-1:0]        tag;
    wire [`C2_CHI_LPID_W-1:0]       lpid;
    wire [`C2_CHI_MPAM_W-1:0]       mpam;
    wire [`C2_CHI_PCRDTYPE_W-1:0]   pcrdtype;
    wire [`C2_CHI_ALLOWRETRY_W-1:0] allowretry;
    wire [`C2_CHI_ORDER_W-1:0]      order;
    wire [`C2_CHI_DATASOURCE_W-1:0] datasource;
    wire [`C2_CHI_CBUSY_W-1:0]      cbusy;
    wire [`C2_CHI_CCID_W-1:0]       ccid;
    wire [`C2_CHI_RETTOSRC_W-1:0]   rettosrc;
    wire [`C2_CHI_TRACETAG_W-1:0]   tracetag;
    wire                            is_req;
    wire                            is_rsp;
    wire                            is_snp;
    wire                            is_dat;
    wire [`C2_CHI_RESPERR_W-1:0]    resperr_acc;
    wire [`C2_SNP_FILTER_W-1:0]     order_mask;
    wire [`C2_CHI_TXNID_W-1:0]      order_head;
    wire [`C2_BUF_RAM_DW-1:0]       fifo_rd;
    wire                            fifo_empty;

    assign RSP_RX_READY = ~fifo_empty;
    assign DAT_RX_READY = ~fifo_empty;
    assign CHI_VALID    = (RSP_RX_VALID | DAT_RX_VALID) & (~fifo_empty);
    assign CHI_LAST     = is_dat | is_rsp;

    //------------------------------------------------------------------
    // flit 拆包（RSP / DAT 两个通道共用一份字段输出）
    //------------------------------------------------------------------
    case2_chi_flit_unpack u_unpack (
        .FLIT_VALID   (RSP_RX_VALID | DAT_RX_VALID),
        .REQ_FLIT     ({`C2_REQ_FLIT_W{1'b0}}),
        .RSP_FLIT     (RSP_RX),
        .SNP_FLIT     ({`C2_SNP_FLIT_W{1'b0}}),
        .DAT_FLIT     (DAT_RX),
        .QOS          (qos),
        .SRCID        (srcid),
        .TGTID        (tgtid),
        .RETURNID     (returnid),
        .FWDNID       (fwdnid),
        .TXNID        (TXNID),
        .FWDTXNID     (fwdtxnid),
        .REQ_OPCODE   (req_opcode),
        .RSP_OPCODE   (OPCODE),
        .SNP_OPCODE   (snp_opcode),
        .DAT_OPCODE   (dat_opcode),
        .SIZE         (size),
        .ADDR         (addr),
        .NS           (ns),
        .MEMATTR      (memattr),
        .SNPATTR      (snpattr),
        .EXPCOMPACK   (expcompack),
        .TAG          (tag),
        .LPID         (lpid),
        .MPAM         (mpam),
        .PCRDTYPE     (pcrdtype),
        .ALLOWRETRY   (allowretry),
        .ORDER        (order),
        .RESP         (RESP),
        .RESPERR      (RESPERR),
        .FWDSTATE     (FWDSTATE),
        .DATASOURCE   (datasource),
        .CBUSY        (cbusy),
        .DATAID       (DATAID),
        .CCID         (ccid),
        .DBID         (DBID),
        .RETTOSRC     (rettosrc),
        .TRACETAG     (tracetag),
        .BE           (BE),
        .DATA         (DATA),
        .FLIT_IS_REQ  (is_req),
        .FLIT_IS_RSP  (is_rsp),
        .FLIT_IS_SNP  (is_snp),
        .FLIT_IS_DAT  (is_dat)
    );

    //------------------------------------------------------------------
    // 响应顺序检查
    //------------------------------------------------------------------
    case2_chi_rsp_order u_order (
        .CLK         (CLK),
        .RST_N       (RST_N),
        .RSP_VALID   (RSP_RX_VALID),
        .TXNID       (TXNID),
        .RESP        (RESP),
        .RESPERR     (RESPERR),
        .ORDER_OK    (),
        .ORDER_ERR   (ORDER_ERR),
        .ORDER_HEAD  (order_head),
        .ORDER_MASK  (order_mask),
        .RESPERR_ACC (resperr_acc)
    );

    //------------------------------------------------------------------
    // RX FIFO
    //------------------------------------------------------------------
    case2_sync_fifo u_rx_fifo (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .WR_DATA    (RSP_RX[`C2_BUF_RAM_DW-1:0]),
        .WR_EN      (RSP_RX_VALID),
        .WR_READY   (),
        .RD_DATA    (fifo_rd),
        .RD_EN      (CHI_VALID),
        .RD_VALID   (),
        .FIFO_LEVEL (),
        .FIFO_FULL  (),
        .FIFO_EMPTY (fifo_empty)
    );

endmodule
