//==========================================================================
//  case2_chi_flit_unpack.v
//  REQ / RSP / SNP / DAT flit -> CHI 字段拆包（纯组合）
//
//  与 case2_chi_flit_pack 共用同一套 `C2_*_FIELD_* 位置宏。无例化，叶子。
//
//  Ref: 链路层 flit 到 CHI 协议层字段的 unpacker（RCU/NCU 前面的那一级）。
//==========================================================================
`include "case2_define.v"

module case2_chi_flit_unpack (
    input  wire                            FLIT_VALID,
    input  wire [`C2_REQ_FLIT_W-1:0]       REQ_FLIT,
    input  wire [`C2_RSP_FLIT_W-1:0]       RSP_FLIT,
    input  wire [`C2_SNP_FLIT_W-1:0]       SNP_FLIT,
    input  wire [`C2_DAT_FLIT_W-1:0]       DAT_FLIT,
    output wire [`C2_CHI_QOS_W-1:0]        QOS,
    output wire [`C2_CHI_NODEID_W-1:0]     SRCID,
    output wire [`C2_CHI_NODEID_W-1:0]     TGTID,
    output wire [`C2_CHI_NODEID_W-1:0]     RETURNID,
    output wire [`C2_CHI_NODEID_W-1:0]     FWDNID,
    output wire [`C2_CHI_TXNID_W-1:0]      TXNID,
    output wire [`C2_CHI_TXNID_W-1:0]      FWDTXNID,
    output wire [`C2_CHI_OPCODE_W-1:0]     REQ_OPCODE,
    output wire [`C2_CHI_OPCODE_W-1:0]     RSP_OPCODE,
    output wire [`C2_CHI_OPCODE_W-1:0]     SNP_OPCODE,
    output wire [`C2_CHI_OPCODE_W-1:0]     DAT_OPCODE,
    output wire [`C2_CHI_SIZE_W-1:0]       SIZE,
    output wire [`C2_CHI_ADDR_W-1:0]       ADDR,
    output wire                            NS,
    output wire [`C2_CHI_MEMATTR_W-1:0]    MEMATTR,
    output wire [`C2_CHI_SNPATTR_W-1:0]    SNPATTR,
    output wire [`C2_CHI_EXPCOMPACK_W-1:0] EXPCOMPACK,
    output wire [`C2_CHI_TAG_W-1:0]        TAG,
    output wire [`C2_CHI_LPID_W-1:0]       LPID,
    output wire [`C2_CHI_MPAM_W-1:0]       MPAM,
    output wire [`C2_CHI_PCRDTYPE_W-1:0]   PCRDTYPE,
    output wire [`C2_CHI_ALLOWRETRY_W-1:0] ALLOWRETRY,
    output wire [`C2_CHI_ORDER_W-1:0]      ORDER,
    output wire [`C2_CHI_RESP_W-1:0]       RESP,
    output wire [`C2_CHI_RESPERR_W-1:0]    RESPERR,
    output wire [`C2_CHI_FWDSTATE_W-1:0]   FWDSTATE,
    output wire [`C2_CHI_DATASOURCE_W-1:0] DATASOURCE,
    output wire [`C2_CHI_CBUSY_W-1:0]      CBUSY,
    output wire [`C2_CHI_DATAID_W-1:0]     DATAID,
    output wire [`C2_CHI_CCID_W-1:0]       CCID,
    output wire [`C2_CHI_DBID_W-1:0]       DBID,
    output wire [`C2_CHI_RETTOSRC_W-1:0]   RETTOSRC,
    output wire [`C2_CHI_TRACETAG_W-1:0]   TRACETAG,
    output wire [`C2_CHI_BE_W-1:0]         BE,
    output wire [`C2_CHI_DATA_W-1:0]       DATA,
    output wire                            FLIT_IS_REQ,
    output wire                            FLIT_IS_RSP,
    output wire                            FLIT_IS_SNP,
    output wire                            FLIT_IS_DAT
);

    //------------------------------------------------------------------
    // REQ flit 字段
    //------------------------------------------------------------------
    assign QOS        = REQ_FLIT[`C2_REQ_FIELD_QOS_MSB:`C2_REQ_FIELD_QOS_LSB];
    assign TGTID      = REQ_FLIT[`C2_REQ_FIELD_TGTID_MSB:`C2_REQ_FIELD_TGTID_LSB];
    assign SRCID      = REQ_FLIT[`C2_REQ_FIELD_SRCID_MSB:`C2_REQ_FIELD_SRCID_LSB];
    assign TXNID      = REQ_FLIT[`C2_REQ_FIELD_TXNID_MSB:`C2_REQ_FIELD_TXNID_LSB];
    assign RETURNID   = REQ_FLIT[`C2_REQ_FIELD_RETURNID_MSB:`C2_REQ_FIELD_RETURNID_LSB];
    assign REQ_OPCODE = REQ_FLIT[`C2_REQ_FIELD_OPCODE_MSB:`C2_REQ_FIELD_OPCODE_LSB];
    assign SIZE       = REQ_FLIT[`C2_REQ_FIELD_SIZE_MSB:`C2_REQ_FIELD_SIZE_LSB];
    assign ADDR       = REQ_FLIT[`C2_REQ_FIELD_ADDR_MSB:`C2_REQ_FIELD_ADDR_LSB];
    assign NS         = REQ_FLIT[`C2_REQ_FIELD_NS_MSB];
    assign MEMATTR    = REQ_FLIT[`C2_REQ_FIELD_MEMATTR_MSB:`C2_REQ_FIELD_MEMATTR_LSB];
    assign SNPATTR    = REQ_FLIT[`C2_REQ_FIELD_SNPATTR_MSB:`C2_REQ_FIELD_SNPATTR_LSB];
    assign EXPCOMPACK = REQ_FLIT[`C2_REQ_FIELD_EXPCOMPACK_MSB:`C2_REQ_FIELD_EXPCOMPACK_LSB];
    assign TAG        = REQ_FLIT[`C2_REQ_FIELD_TAG_MSB:`C2_REQ_FIELD_TAG_LSB];
    assign LPID       = REQ_FLIT[`C2_REQ_FIELD_LPID_MSB:`C2_REQ_FIELD_LPID_LSB];
    assign MPAM       = REQ_FLIT[`C2_REQ_FIELD_MPAM_MSB:`C2_REQ_FIELD_MPAM_LSB];
    assign PCRDTYPE   = REQ_FLIT[`C2_REQ_FIELD_PCRDTYPE_MSB:`C2_REQ_FIELD_PCRDTYPE_LSB];
    assign ALLOWRETRY = REQ_FLIT[`C2_REQ_FIELD_ALLOWRETRY_MSB:`C2_REQ_FIELD_ALLOWRETRY_LSB];
    assign ORDER      = REQ_FLIT[`C2_REQ_FIELD_ORDER_MSB:`C2_REQ_FIELD_ORDER_LSB];

    //------------------------------------------------------------------
    // RSP / SNP / DAT flit 字段
    //------------------------------------------------------------------
    assign RSP_OPCODE = RSP_FLIT[`C2_RSP_FIELD_OPCODE_MSB:`C2_RSP_FIELD_OPCODE_LSB];
    assign RESP       = RSP_FLIT[`C2_RSP_FIELD_RESP_MSB:`C2_RSP_FIELD_RESP_LSB];
    assign RESPERR    = RSP_FLIT[`C2_RSP_FIELD_RESPERR_MSB:`C2_RSP_FIELD_RESPERR_LSB];
    assign FWDSTATE   = RSP_FLIT[`C2_RSP_FIELD_FWDSTATE_MSB:`C2_RSP_FIELD_FWDSTATE_LSB];
    assign DATASOURCE = RSP_FLIT[`C2_RSP_FIELD_DATASOURCE_MSB:`C2_RSP_FIELD_DATASOURCE_LSB];
    assign CBUSY      = RSP_FLIT[`C2_RSP_FIELD_CBUSY_MSB:`C2_RSP_FIELD_CBUSY_LSB];
    assign TRACETAG   = RSP_FLIT[`C2_RSP_FIELD_TRACETAG_MSB:`C2_RSP_FIELD_TRACETAG_LSB];
    assign RETTOSRC   = RSP_FLIT[`C2_RSP_FIELD_RETTOSRC_MSB:`C2_RSP_FIELD_RETTOSRC_LSB];
    assign CCID       = RSP_FLIT[`C2_RSP_FIELD_CCID_MSB:`C2_RSP_FIELD_CCID_LSB];

    assign SNP_OPCODE = SNP_FLIT[`C2_SNP_FIELD_OPCODE_MSB:`C2_SNP_FIELD_OPCODE_LSB];
    assign FWDNID     = SNP_FLIT[`C2_SNP_FIELD_FWDNID_MSB:`C2_SNP_FIELD_FWDNID_LSB];
    assign FWDTXNID   = SNP_FLIT[`C2_SNP_FIELD_FWDTXNID_MSB:`C2_SNP_FIELD_FWDTXNID_LSB];

    assign DAT_OPCODE = DAT_FLIT[`C2_DAT_FIELD_OPCODE_MSB:`C2_DAT_FIELD_OPCODE_LSB];
    assign DATAID     = DAT_FLIT[`C2_DAT_FIELD_DATAID_MSB:`C2_DAT_FIELD_DATAID_LSB];
    assign DBID       = DAT_FLIT[`C2_DAT_FIELD_DBID_MSB:`C2_DAT_FIELD_DBID_LSB];
    assign BE         = DAT_FLIT[`C2_DAT_FIELD_BE_MSB:`C2_DAT_FIELD_BE_LSB];
    assign DATA       = DAT_FLIT[`C2_DAT_FIELD_DATA_MSB:`C2_DAT_FIELD_DATA_LSB];

    //------------------------------------------------------------------
    // 通道类型译码
    //------------------------------------------------------------------
    assign FLIT_IS_REQ = FLIT_VALID & (REQ_OPCODE != {`C2_CHI_OPCODE_W{1'b0}});
    assign FLIT_IS_RSP = FLIT_VALID & (RSP_OPCODE != {`C2_CHI_OPCODE_W{1'b0}});
    assign FLIT_IS_SNP = FLIT_VALID & (SNP_OPCODE != {`C2_CHI_OPCODE_W{1'b0}});
    assign FLIT_IS_DAT = FLIT_VALID & (|DAT_FLIT[`C2_DAT_FIELD_BE_MSB:`C2_DAT_FIELD_BE_LSB]);

endmodule
