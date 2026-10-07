//==========================================================================
//  case2_chi_sn_pipe.v
//  SN 请求/响应流水：REQ 拆包 -> 存储访问 -> RSP/DAT 打包
//
//  Ref: CHI slave node（SN-F）的协议流水，数据缓冲用 RAM_SP_BE wrapper。
//==========================================================================
`include "case2_define.v"

module case2_chi_sn_pipe (
    input  wire                        CLK,
    input  wire                        RST_N,
    input  wire [`C2_CHI_NODEID_W-1:0] NODEID,
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
    output wire [`C2_CHI_DBID_W-1:0]   DBID,
    output wire [`C2_CHI_DATA_W-1:0]   DATA,
    output wire [`C2_CHI_BE_W-1:0]     BE,
    output wire                        SN_PIPE_IDLE
);

    wire [`C2_CHI_QOS_W-1:0]        qos;
    wire [`C2_CHI_NODEID_W-1:0]     srcid;
    wire [`C2_CHI_NODEID_W-1:0]     returnid;
    wire [`C2_CHI_NODEID_W-1:0]     fwdnid;
    wire [`C2_CHI_TXNID_W-1:0]      txnid;
    wire [`C2_CHI_TXNID_W-1:0]      fwdtxnid;
    wire [`C2_CHI_OPCODE_W-1:0]     opcode;
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
    wire [`C2_CHI_DATA_W-1:0]       wdata;
    wire [`C2_CHI_BE_W-1:0]         wbe;
    wire                            is_req;
    wire                            is_rsp;
    wire                            is_snp;
    wire                            is_dat;
    wire [`C2_RSP_FLIT_W-1:0]       packed_rsp;
    wire [`C2_DAT_FLIT_W-1:0]       packed_dat;
    wire [`C2_FLIT_W-1:0]           ram_flit;
    wire [`C2_FLIT_W-1:0]           ram_flit_out;
    wire [`C2_BUF_PTR_W-1:0]        ram_wr_ptr;
    wire [`C2_BUF_PTR_W-1:0]        ram_rd_ptr;
    wire [`C2_CREDIT_W-1:0]         ram_credit;
    wire                            ram_ready;
    wire [`C2_BUF_RAM_DW-1:0]       ram_word;
    wire [`C2_BUF_RAM_DW-1:0]       fifo_rd;
    wire                            fifo_empty;
    wire [`C2_CHI_DBID_W-1:0]       dbid_alloc;
    wire                            dbid_valid;
    wire [`C2_CHI_DBID_W-1:0]       dbid_cnt;
    wire [`C2_CHI_CBUSY_W-1:0]      dbid_cbusy;

    assign SN_PIPE_IDLE = ~(REQ_RX_VALID | RSP_TX_VALID | DAT_TX_VALID);
    assign REQ_RX_READY = ~fifo_empty;
    assign DBID         = dbid_alloc;
    assign DATA         = ram_flit_out[`C2_CHI_DATA_MSB:`C2_CHI_DATA_LSB];
    assign BE           = ram_word[`C2_CHI_BE_MSB:`C2_CHI_BE_LSB];

    //------------------------------------------------------------------
    // REQ flit 拆包
    //------------------------------------------------------------------
    case2_chi_flit_unpack u_unpack (
        .FLIT_VALID   (REQ_RX_VALID),
        .REQ_FLIT     (REQ_RX),
        .RSP_FLIT     ({`C2_RSP_FLIT_W{1'b0}}),
        .SNP_FLIT     ({`C2_SNP_FLIT_W{1'b0}}),
        .DAT_FLIT     (DAT_RX),
        .QOS          (qos),
        .SRCID        (srcid),
        .TGTID        (),
        .RETURNID     (returnid),
        .FWDNID       (fwdnid),
        .TXNID        (txnid),
        .FWDTXNID     (fwdtxnid),
        .REQ_OPCODE   (opcode),
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
        .DBID         (),
        .RETTOSRC     (rettosrc),
        .TRACETAG     (tracetag),
        .BE           (wbe),
        .DATA         (wdata),
        .FLIT_IS_REQ  (is_req),
        .FLIT_IS_RSP  (is_rsp),
        .FLIT_IS_SNP  (is_snp),
        .FLIT_IS_DAT  (is_dat)
    );

    //------------------------------------------------------------------
    // 存储数据缓冲（内部例化 RAM_SP_BE）
    //------------------------------------------------------------------
    case2_noc_buf_ram_wrap u_sn_ram (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .FLIT_WR   (REQ_RX_VALID),
        .FLIT_IN   (ram_flit),
        .WR_PTR    (ram_wr_ptr),
        .RD_PTR    (ram_rd_ptr),
        .FLIT_OUT  (ram_flit_out),
        .RAM_READY (ram_ready),
        .RAM_CREDIT(ram_credit),
        .RAM_Q_WORD(ram_word)
    );

    //------------------------------------------------------------------
    // DBID 分配
    //------------------------------------------------------------------
    case2_chi_dbid_alloc u_sn_dbid (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .DBID_REQ   (REQ_RX_VALID),
        .DBID_FREE  (DAT_TX_READY),
        .DBID_IN    (dbid_cnt),
        .DBID       (dbid_alloc),
        .DBID_CNT   (dbid_cnt),
        .DBID_VALID (dbid_valid),
        .DBID_CBUSY (dbid_cbusy)
    );

    //------------------------------------------------------------------
    // 描述符 FIFO
    //------------------------------------------------------------------
    case2_sync_fifo u_sn_fifo (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .WR_DATA    (REQ_RX[`C2_BUF_RAM_DW-1:0]),
        .WR_EN      (REQ_RX_VALID),
        .WR_READY   (),
        .RD_DATA    (fifo_rd),
        .RD_EN      (REQ_RX_READY),
        .RD_VALID   (),
        .FIFO_LEVEL (),
        .FIFO_FULL  (),
        .FIFO_EMPTY (fifo_empty)
    );

    assign ram_flit      = {{`C2_RSP_PAD_W{1'b0}}, packed_rsp};
    assign ram_wr_ptr    = REQ_RX[`C2_BUF_PTR_W-1:0];
    assign ram_rd_ptr    = DBID[`C2_BUF_PTR_W-1:0];

    //------------------------------------------------------------------
    // RSP / DAT 打包
    //------------------------------------------------------------------
    case2_chi_flit_pack u_pack (
        .CHI_VALID   (REQ_RX_VALID),
        .QOS         (qos),
        .SRCID       (NODEID),
        .TGTID       (srcid),
        .RETURNID    (returnid),
        .FWDNID      (fwdnid),
        .TXNID       (txnid),
        .FWDTXNID    (fwdtxnid),
        .OPCODE      (`C2_OP_COMP_DATA),
        .SIZE        (size),
        .ADDR        (addr),
        .NS          (ns),
        .MEMATTR     (memattr),
        .SNPATTR     (snpattr),
        .EXPCOMPACK  (expcompack),
        .TAG         (tag),
        .LPID        (lpid),
        .MPAM        (mpam),
        .PCRDTYPE    (pcrdtype),
        .ALLOWRETRY  (allowretry),
        .ORDER       (order),
        .RESP        (`C2_RESP_UD_PD),
        .RESPERR     (`C2_RESPERR_OKAY),
        .FWDSTATE    (fwdstate),
        .DATASOURCE  (datasource),
        .CBUSY       (cbusy),
        .DATAID      (dataid),
        .CCID        (ccid),
        .DBID        (dbid_alloc),
        .RETTOSRC    (rettosrc),
        .TRACETAG    (tracetag),
        .BE          (wbe),
        .DATA        (wdata),
        .REQ_FLIT    (),
        .RSP_FLIT    (packed_rsp),
        .SNP_FLIT    (),
        .DAT_FLIT    (packed_dat)
    );

    assign RSP_TX       = packed_rsp;
    assign DAT_TX       = packed_dat;
    assign RSP_TX_VALID = REQ_RX_VALID & (~RSP_TX_READY);
    assign DAT_TX_VALID = REQ_RX_VALID & (~DAT_TX_READY);
    assign DAT_RX_READY = ~REQ_RX_VALID;

endmodule
