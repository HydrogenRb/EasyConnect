//==========================================================================
//  case2_chi_dat_path.v
//  RN 数据通路：写数据缓冲（RAM_DP）+ DAT flit 拆包 / 组装
//
//  Ref: CHI RN 的 data path（DBID + write data buffer）。
//==========================================================================
`include "case2_define.v"

module case2_chi_dat_path (
    input  wire                      CLK,
    input  wire                      RST_N,
    input  wire [`C2_DAT_FLIT_W-1:0] DAT_RX,
    input  wire                      DAT_RX_VALID,
    output wire                      DAT_RX_READY,
    output wire [`C2_DAT_FLIT_W-1:0] DAT_TX,
    output wire                      DAT_TX_VALID,
    input  wire                      DAT_TX_READY,
    input  wire [`C2_CHI_DATA_W-1:0] WDATA,
    input  wire                      WDATA_VALID,
    output wire                      WDATA_READY,
    output wire [`C2_CHI_DATA_W-1:0] RDATA,
    output wire [`C2_CHI_BE_W-1:0]   BE,
    output wire [`C2_CHI_DBID_W-1:0] DBID
);

    wire [`C2_TAG_RAM_AW-1:0]  wd_addr;
    wire [`C2_TAG_RAM_DW-1:0]  wd_d;
    wire [`C2_TAG_RAM_DW-1:0]  wd_q;
    wire                       wd_a_cen;
    wire                       wd_a_wen;
    wire                       wd_b_cen;
    wire                       wd_b_wen;
    wire [`C2_TAG_RAM_DW-1:0]  wd_b_d;
    wire                       wd_full;
    wire                       wd_empty;
    wire [`C2_BUF_RAM_DW-1:0]  fifo_rd;
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
    wire [`C2_CHI_DATAID_W-1:0]     dataid;
    wire [`C2_CHI_CCID_W-1:0]       ccid;
    wire [`C2_CHI_RETTOSRC_W-1:0]   rettosrc;
    wire [`C2_CHI_TRACETAG_W-1:0]   tracetag;
    wire                            is_req;
    wire                            is_rsp;
    wire                            is_snp;
    wire                            is_dat;

    assign wd_a_cen     = ~WDATA_VALID;
    assign wd_a_wen     = ~WDATA_VALID;
    assign wd_b_cen     = ~DAT_TX_VALID;
    assign wd_b_wen     = 1'b1;
    assign wd_addr      = fifo_rd[`C2_TAG_RAM_AW-1:0];
    assign wd_d         = WDATA[`C2_TAG_RAM_DW-1:0];
    assign wd_b_d       = {`C2_TAG_RAM_DW{1'b0}};
    assign WDATA_READY  = ~wd_full;
    assign DAT_RX_READY = ~wd_empty;

    //------------------------------------------------------------------
    // DAT flit 拆包
    //------------------------------------------------------------------
    case2_chi_flit_unpack u_unpack (
        .FLIT_VALID   (DAT_RX_VALID),
        .REQ_FLIT     ({`C2_REQ_FLIT_W{1'b0}}),
        .RSP_FLIT     ({`C2_RSP_FLIT_W{1'b0}}),
        .SNP_FLIT     ({`C2_SNP_FLIT_W{1'b0}}),
        .DAT_FLIT     (DAT_RX),
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
        .DATAID       (dataid),
        .CCID         (ccid),
        .DBID         (DBID),
        .RETTOSRC     (rettosrc),
        .TRACETAG     (tracetag),
        .BE           (BE),
        .DATA         (RDATA),
        .FLIT_IS_REQ  (is_req),
        .FLIT_IS_RSP  (is_rsp),
        .FLIT_IS_SNP  (is_snp),
        .FLIT_IS_DAT  (is_dat)
    );

    //------------------------------------------------------------------
    // 写数据缓冲：库宏单元 RAM_DP（位置连接）
    //------------------------------------------------------------------
    RAM_DP #(.AW(`C2_TAG_RAM_AW), .DW(`C2_TAG_RAM_DW), .DEPTH(`C2_TAG_RAM_DEPTH)) u_wdata_ram (
        CLK,
        wd_a_cen,
        wd_a_wen,
        wd_addr,
        wd_d,
        wd_q,
        wd_b_cen,
        wd_b_wen,
        wd_addr,
        wd_b_d,
        wd_q
    );

    //------------------------------------------------------------------
    // DBID / 描述符 FIFO
    //------------------------------------------------------------------
    case2_sync_fifo u_wdata_fifo (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .WR_DATA    (DAT_RX[`C2_BUF_RAM_DW-1:0]),
        .WR_EN      (DAT_RX_VALID),
        .WR_READY   (),
        .RD_DATA    (fifo_rd),
        .RD_EN      (DAT_RX_READY),
        .RD_VALID   (),
        .FIFO_LEVEL (),
        .FIFO_FULL  (wd_full),
        .FIFO_EMPTY (wd_empty)
    );

    assign DAT_TX       = DAT_RX;
    assign DAT_TX_VALID = DAT_RX_VALID & (~DAT_TX_READY);

endmodule
