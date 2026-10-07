//==========================================================================
//  case2_hn_dat_pipe.v
//  HN 数据流水：DAT flit 缓冲 + 拆包 + DBID 分配
//
//  Ref: home node 的 data pipe（从 SN 收数据、向 RN 回数据）。
//==========================================================================
`include "case2_define.v"

module case2_hn_dat_pipe (
    input  wire                        CLK,
    input  wire                        RST_N,
    input  wire [`C2_DAT_FLIT_W-1:0]   DAT_IN,
    input  wire                        DAT_IN_VALID,
    output wire                        DAT_IN_READY,
    output wire [`C2_DAT_FLIT_W-1:0]   DAT_OUT,
    output wire                        DAT_OUT_VALID,
    input  wire                        DAT_OUT_READY,
    output wire [`C2_CHI_DATA_W-1:0]   DATA,
    output wire [`C2_CHI_BE_W-1:0]     BE,
    output wire [`C2_CHI_DBID_W-1:0]   DBID,
    output wire [`C2_CHI_DATAID_W-1:0] DATAID,
    output wire                        DAT_LAST
);

    wire [`C2_BUF_RAM_DW-1:0]  fifo_rd;
    wire                       fifo_empty;
    wire [`C2_CHI_QOS_W-1:0]        qos;
    wire [`C2_CHI_NODEID_W-1:0]     srcid;
    wire [`C2_CHI_NODEID_W-1:0]     tgtid;
    wire [`C2_CHI_NODEID_W-1:0]     returnid;
    wire [`C2_CHI_NODEID_W-1:0]     fwdnid;
    wire [`C2_CHI_TXNID_W-1:0]      txnid;
    wire [`C2_CHI_TXNID_W-1:0]      fwdtxnid;
    wire [`C2_CHI_OPCODE_W-1:0]     req_opcode;
    wire [`C2_CHI_OPCODE_W-1:0]     rsp_opcode;
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
    wire [`C2_CHI_RESP_W-1:0]       resp;
    wire [`C2_CHI_RESPERR_W-1:0]    resperr;
    wire [`C2_CHI_FWDSTATE_W-1:0]   fwdstate;
    wire [`C2_CHI_DATASOURCE_W-1:0] datasource;
    wire [`C2_CHI_CBUSY_W-1:0]      cbusy;
    wire [`C2_CHI_CCID_W-1:0]       ccid;
    wire [`C2_CHI_RETTOSRC_W-1:0]   rettosrc;
    wire [`C2_CHI_TRACETAG_W-1:0]   tracetag;
    wire                            is_req;
    wire                            is_rsp;
    wire                            is_snp;
    wire                            is_dat;
    wire                            dbid_valid;
    wire [`C2_CHI_DBID_W-1:0]       dbid_cnt;
    wire [`C2_CHI_CBUSY_W-1:0]      dbid_cbusy;

    assign DAT_IN_READY = ~fifo_empty;
    assign DAT_LAST     = is_dat & (~fifo_empty);

    //------------------------------------------------------------------
    // DAT flit 拆包
    //------------------------------------------------------------------
    case2_chi_flit_unpack u_unpack (
        .FLIT_VALID   (DAT_IN_VALID),
        .REQ_FLIT     ({`C2_REQ_FLIT_W{1'b0}}),
        .RSP_FLIT     ({`C2_RSP_FLIT_W{1'b0}}),
        .SNP_FLIT     ({`C2_SNP_FLIT_W{1'b0}}),
        .DAT_FLIT     (DAT_IN),
        .QOS          (qos),
        .SRCID        (srcid),
        .TGTID        (tgtid),
        .RETURNID     (returnid),
        .FWDNID       (fwdnid),
        .TXNID        (txnid),
        .FWDTXNID     (fwdtxnid),
        .REQ_OPCODE   (req_opcode),
        .RSP_OPCODE   (rsp_opcode),
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
        .RESP         (resp),
        .RESPERR      (resperr),
        .FWDSTATE     (fwdstate),
        .DATASOURCE   (datasource),
        .CBUSY        (cbusy),
        .DATAID       (DATAID),
        .CCID         (ccid),
        .DBID         (),
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
    // DBID 分配
    //------------------------------------------------------------------
    case2_chi_dbid_alloc u_dbid (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .DBID_REQ   (DAT_IN_VALID),
        .DBID_FREE  (DAT_LAST),
        .DBID_IN    (DAT_IN[`C2_DAT_FIELD_DBID_MSB:`C2_DAT_FIELD_DBID_LSB]),
        .DBID       (DBID),
        .DBID_CNT   (dbid_cnt),
        .DBID_VALID (dbid_valid),
        .DBID_CBUSY (dbid_cbusy)
    );

    //------------------------------------------------------------------
    // 数据 FIFO（描述符）
    //------------------------------------------------------------------
    case2_sync_fifo u_dat_fifo (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .WR_DATA    (DAT_IN[`C2_BUF_RAM_DW-1:0]),
        .WR_EN      (DAT_IN_VALID),
        .WR_READY   (),
        .RD_DATA    (fifo_rd),
        .RD_EN      (DAT_IN_READY),
        .RD_VALID   (),
        .FIFO_LEVEL (),
        .FIFO_FULL  (),
        .FIFO_EMPTY (fifo_empty)
    );

    assign DAT_OUT       = DAT_IN;
    assign DAT_OUT_VALID = DAT_IN_VALID & (~DAT_OUT_READY);

endmodule
