//==========================================================================
//  case2_chi_snp_handle.v
//  RN 侧 snoop 处理：拆 SNP flit、判定 snoop 类型、生成 RSP 响应
//
//  Ref: CHI RN 的 snoop handler（SnpUnique/SnpShared/SnpClean/SnpOnce）。
//==========================================================================
`include "case2_define.v"

module case2_chi_snp_handle (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire [`C2_SNP_FLIT_W-1:0]     SNP_RX,
    input  wire                          SNP_RX_VALID,
    output wire                          SNP_RX_READY,
    output wire [`C2_RSP_FLIT_W-1:0]     RSP_TX,
    output wire                          RSP_TX_VALID,
    input  wire                          RSP_TX_READY,
    output wire [`C2_CHI_OPCODE_W-1:0]   SNP_OPCODE,
    output wire [`C2_CHI_TXNID_W-1:0]    SNP_TXNID,
    output wire [`C2_CHI_NODEID_W-1:0]   FWDNID,
    output wire [`C2_CHI_FWDSTATE_W-1:0] FWDSTATE,
    output wire                          SNP_HIT,
    output wire                          SNP_CLEAN
);

    wire [`C2_CHI_QOS_W-1:0]        qos;
    wire [`C2_CHI_NODEID_W-1:0]     srcid;
    wire [`C2_CHI_NODEID_W-1:0]     tgtid;
    wire [`C2_CHI_NODEID_W-1:0]     returnid;
    wire [`C2_CHI_TXNID_W-1:0]      fwdtxnid;
    wire [`C2_CHI_OPCODE_W-1:0]     req_opcode;
    wire [`C2_CHI_OPCODE_W-1:0]     rsp_opcode;
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
    wire [`C2_CHI_DATASOURCE_W-1:0] datasource;
    wire [`C2_CHI_CBUSY_W-1:0]      cbusy;
    wire [`C2_CHI_DATAID_W-1:0]     dataid;
    wire [`C2_CHI_CCID_W-1:0]       ccid;
    wire [`C2_CHI_DBID_W-1:0]       dbid;
    wire [`C2_CHI_RETTOSRC_W-1:0]   rettosrc;
    wire [`C2_CHI_TRACETAG_W-1:0]   tracetag;
    wire [`C2_CHI_BE_W-1:0]         be;
    wire [`C2_CHI_DATA_W-1:0]       data;
    wire                            is_req;
    wire                            is_rsp;
    wire                            is_snp;
    wire                            is_dat;
    wire [`C2_RSP_FLIT_W-1:0]       packed_rsp;
    wire [`C2_CHI_RESP_W-1:0]       snp_resp;
    wire [`C2_PORT_NUM-1:0]         snp_gnt;
    wire [`C2_PORT_AW-1:0]          snp_gnt_idx;

    assign SNP_TXNID  = SNP_RX[`C2_SNP_FIELD_TXNID_MSB:`C2_SNP_FIELD_TXNID_LSB];
    assign SNP_OPCODE = SNP_RX[`C2_SNP_FIELD_OPCODE_MSB:`C2_SNP_FIELD_OPCODE_LSB];
    assign FWDNID     = SNP_RX[`C2_SNP_FIELD_FWDNID_MSB:`C2_SNP_FIELD_FWDNID_LSB];
    assign FWDSTATE   = {`C2_CHI_FWDSTATE_W{1'b0}};
    assign SNP_RX_READY = ~SNP_HIT;
    assign SNP_HIT    = SNP_RX_VALID & is_snp;
    assign SNP_CLEAN  = (SNP_OPCODE == `C2_OP_SNP_CLEAN) | (SNP_OPCODE == `C2_OP_SNP_ONCE);

    always @(*) begin
        case (SNP_OPCODE)
            `C2_OP_SNP_UNIQUE: snp_resp = `C2_RESP_UC;
            `C2_OP_SNP_SHARED: snp_resp = `C2_RESP_SC;
            `C2_OP_SNP_CLEAN:  snp_resp = `C2_RESP_UD_PD;
            `C2_OP_SNP_ONCE:   snp_resp = `C2_RESP_UD_PD;
            default:           snp_resp = `C2_RESP_I_PD;
        endcase
    end

    //------------------------------------------------------------------
    // SNP flit 拆包
    //------------------------------------------------------------------
    case2_chi_flit_unpack u_unpack (
        .FLIT_VALID   (SNP_RX_VALID),
        .REQ_FLIT     ({`C2_REQ_FLIT_W{1'b0}}),
        .RSP_FLIT     ({`C2_RSP_FLIT_W{1'b0}}),
        .SNP_FLIT     (SNP_RX),
        .DAT_FLIT     ({`C2_DAT_FLIT_W{1'b0}}),
        .QOS          (qos),
        .SRCID        (srcid),
        .TGTID        (tgtid),
        .RETURNID     (returnid),
        .FWDNID       (),
        .TXNID        (),
        .FWDTXNID     (fwdtxnid),
        .REQ_OPCODE   (req_opcode),
        .RSP_OPCODE   (rsp_opcode),
        .SNP_OPCODE   (),
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
        .FWDSTATE     (),
        .DATASOURCE   (datasource),
        .CBUSY        (cbusy),
        .DATAID       (dataid),
        .CCID         (ccid),
        .DBID         (dbid),
        .RETTOSRC     (rettosrc),
        .TRACETAG     (tracetag),
        .BE           (be),
        .DATA         (data),
        .FLIT_IS_REQ  (is_req),
        .FLIT_IS_RSP  (is_rsp),
        .FLIT_IS_SNP  (is_snp),
        .FLIT_IS_DAT  (is_dat)
    );

    //------------------------------------------------------------------
    // snoop 响应打包
    //------------------------------------------------------------------
    case2_chi_flit_pack u_pack (
        .CHI_VALID   (SNP_HIT),
        .QOS         (qos),
        .SRCID       (tgtid),
        .TGTID       (srcid),
        .RETURNID    (returnid),
        .FWDNID      (FWDNID),
        .TXNID       (SNP_TXNID),
        .FWDTXNID    (fwdtxnid),
        .OPCODE      (`C2_OP_SNP_RESP),
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
        .RESP        (snp_resp),
        .RESPERR     (`C2_RESPERR_OKAY),
        .FWDSTATE    (FWDSTATE),
        .DATASOURCE  (datasource),
        .CBUSY       (cbusy),
        .DATAID      (dataid),
        .CCID        (ccid),
        .DBID        (dbid),
        .RETTOSRC    (rettosrc),
        .TRACETAG    (tracetag),
        .BE          (be),
        .DATA        (data),
        .REQ_FLIT    (),
        .RSP_FLIT    (packed_rsp),
        .SNP_FLIT    (),
        .DAT_FLIT    ()
    );

    assign RSP_TX       = packed_rsp;
    assign RSP_TX_VALID = SNP_HIT & (~RSP_TX_READY);

    //------------------------------------------------------------------
    // snoop 响应通道的仲裁（与普通响应共用 RSP 通道）
    //------------------------------------------------------------------
    case2_noc_arbiter u_snp_arb (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REQ       ({{(`C2_PORT_NUM-2){1'b0}}, RSP_TX_READY, SNP_HIT}),
        .CREDIT    ({`C2_PORT_NUM{1'b1}}),
        .HOLD      (1'b0),
        .GNT       (snp_gnt),
        .GNT_IDX   (snp_gnt_idx),
        .GNT_VALID (),
        .ALLOC_FAIL()
    );

endmodule
