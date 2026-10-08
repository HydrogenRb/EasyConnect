//==========================================================================
//  case2_sn_wrap.v
//  SN 节点外壳：`C2_SN_NUM 个 `case2_chi_sn` 阵列 + CHI<->flit 适配
//
//  阵列用 for-generate 展开（u_sn[0] .. u_sn[7]），REQ 按地址位选片，
//  RSP/DAT 用行为 for 循环做优先级汇聚（最高编号优先）。
//  整个 SN 阵列共用一条到 mesh 的 SN drop ring（router port 4）。
//
//  Ref: 共享 slave node 子系统（多片 SN-F + 片上存储）。
//==========================================================================
`include "case2_define.v"

module case2_sn_wrap (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire [`C2_CHI_NODEID_W-1:0]   NODEID,
    input  wire [`C2_REQ_FLIT_W-1:0]     REQ_RX,
    input  wire                          REQ_RX_VALID,
    output wire                          REQ_RX_READY,
    output wire [`C2_REQ_FLIT_W-1:0]     REQ_TX,
    output wire                          REQ_TX_VALID,
    input  wire                          REQ_TX_READY,
    output wire [`C2_RSP_FLIT_W-1:0]     RSP_TX,
    output wire                          RSP_TX_VALID,
    input  wire                          RSP_TX_READY,
    input  wire [`C2_RSP_FLIT_W-1:0]     RSP_RX,
    input  wire                          RSP_RX_VALID,
    output wire                          RSP_RX_READY,
    output wire [`C2_SNP_FLIT_W-1:0]     SNP_TX,
    output wire                          SNP_TX_VALID,
    input  wire                          SNP_TX_READY,
    input  wire [`C2_SNP_FLIT_W-1:0]     SNP_RX,
    input  wire                          SNP_RX_VALID,
    output wire                          SNP_RX_READY,
    output wire [`C2_DAT_FLIT_W-1:0]     DAT_TX,
    output wire                          DAT_TX_VALID,
    input  wire                          DAT_TX_READY,
    input  wire [`C2_DAT_FLIT_W-1:0]     DAT_RX,
    input  wire                          DAT_RX_VALID,
    output wire                          DAT_RX_READY,
    output wire [`C2_CREDIT_W-1:0]       CREDIT_ON,
    input  wire [`C2_CREDIT_W-1:0]       CREDIT_RET,
    output wire [`C2_SN_NUM-1:0]         SN_ACTIVE,
    output wire                          SN_IDLE
);

    wire [`C2_SN_NUM-1:0]                    sn_sel;
    wire [`C2_SN_NUM-1:0]                    sn_rsp_valid;
    wire [`C2_SN_NUM-1:0]                    sn_dat_valid;
    wire [`C2_SN_NUM*`C2_RSP_FLIT_W-1:0]     sn_rsp_flit;
    wire [`C2_SN_NUM*`C2_DAT_FLIT_W-1:0]     sn_dat_flit;
    wire [`C2_SN_NUM*`C2_CHI_DATA_W-1:0]     sn_data;
    wire [`C2_SN_NUM*`C2_CHI_BE_W-1:0]       sn_be;
    wire [`C2_SN_NUM*`C2_CHI_DBID_W-1:0]     sn_dbid;
    wire                                     sn_rsp_active;
    wire                                     sn_dat_active;
    wire                                     adapter_req_valid;
    wire                                     adapter_req_ready;
    wire                                     adapter_dat_valid;
    wire                                     adapter_dat_ready;
    wire [`C2_REQ_FLIT_W-1:0]                adapter_req_flit;
    wire [`C2_DAT_FLIT_W-1:0]                adapter_dat_flit;
    wire [`C2_CHI_OPCODE_W-1:0]              adapter_opcode;
    wire [`C2_CHI_TXNID_W-1:0]               adapter_txnid_out;
    wire [`C2_CHI_TXNID_W-1:0]               adapter_txnid_in;
    wire [`C2_CHI_RESP_W-1:0]                adapter_resp;
    wire [`C2_CHI_RESPERR_W-1:0]             adapter_resperr;
    wire [`C2_CHI_DATA_W-1:0]                adapter_data;
    wire [`C2_CHI_BE_W-1:0]                  adapter_be;
    wire [`C2_CHI_DBID_W-1:0]                adapter_dbid;
    wire                                     adapter_chi_valid;
    wire                                     adapter_order_err;
    wire                                     adapter_chi_last;
    wire [`C2_VC_NUM-1:0]                    adapter_vc_free;
    wire                                     sn_gclk;

    reg [`C2_REQ_FLIT_W-1:0] sn_req_mux;
    reg [`C2_RSP_FLIT_W-1:0] sn_rsp_mux;
    reg [`C2_DAT_FLIT_W-1:0] sn_dat_mux;

    integer si;
    genvar  gs;

    assign SN_IDLE      = ~(sn_rsp_active | sn_dat_active | REQ_RX_VALID);
    assign REQ_RX_READY = ~sn_rsp_active;
    assign RSP_RX_READY = 1'b1;
    assign SNP_RX_READY = 1'b1;
    assign DAT_RX_READY = ~sn_dat_active;
    assign RSP_TX       = sn_rsp_mux;
    assign RSP_TX_VALID = sn_rsp_active & (~RSP_TX_READY);
    assign DAT_TX       = sn_dat_mux;
    assign DAT_TX_VALID = sn_dat_active & (~DAT_TX_READY);
    assign SNP_TX       = SNP_RX;
    assign SNP_TX_VALID = SNP_RX_VALID;
    assign REQ_TX       = adapter_req_flit;
    assign REQ_TX_VALID = adapter_req_valid;
    assign adapter_req_ready = REQ_TX_READY;
    assign adapter_dat_ready = 1'b1;
    assign CREDIT_ON    = CREDIT_RET;

    //------------------------------------------------------------------
    // REQ 源选择：mesh 来的请求优先，其次是本 SN 子系统的旁路请求
    //------------------------------------------------------------------
    always @(*) begin
        if (REQ_RX_VALID) begin
            sn_req_mux = REQ_RX;
        end else begin
            sn_req_mux = adapter_req_flit;
        end
    end

    //------------------------------------------------------------------
    // SN 阵列：u_sn[0] .. u_sn[`C2_SN_NUM-1]（8 个实例）
    //------------------------------------------------------------------
    generate
        for (gs = 0; gs < `C2_SN_NUM; gs = gs + 1) begin : g_sn
            assign sn_sel[gs] =
                   (sn_req_mux[`C2_REQ_FIELD_ADDR_LSB+5:`C2_REQ_FIELD_ADDR_LSB+3] == gs);

            case2_chi_sn u_sn (
                .CLK          (sn_gclk),
                .RST_N        (RST_N),
                .SN_ID        (NODEID + gs),
                .REQ_RX       (sn_req_mux),
                .REQ_RX_VALID (sn_sel[gs] & (REQ_RX_VALID | adapter_req_valid)),
                .REQ_RX_READY (),
                .RSP_TX       (sn_rsp_flit[gs*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]),
                .RSP_TX_VALID (sn_rsp_valid[gs]),
                .RSP_TX_READY (RSP_TX_READY),
                .DAT_TX       (sn_dat_flit[gs*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                .DAT_TX_VALID (sn_dat_valid[gs]),
                .DAT_TX_READY (DAT_TX_READY),
                .DAT_RX       (DAT_RX),
                .DAT_RX_VALID (DAT_RX_VALID & sn_sel[gs]),
                .DAT_RX_READY (),
                .SN_DATA      (sn_data[gs*`C2_CHI_DATA_W +: `C2_CHI_DATA_W]),
                .SN_BE        (sn_be[gs*`C2_CHI_BE_W +: `C2_CHI_BE_W]),
                .SN_DBID      (sn_dbid[gs*`C2_CHI_DBID_W +: `C2_CHI_DBID_W]),
                .SN_ACTIVE    (SN_ACTIVE[gs])
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // RSP / DAT 汇聚：编号最高的有效 SN 优先（实际设计里需要 round-robin）
    //------------------------------------------------------------------
    always @(*) begin
        sn_rsp_mux = {`C2_RSP_FLIT_W{1'b0}};
        for (si = 0; si < `C2_SN_NUM; si = si + 1) begin
            if (sn_rsp_valid[si]) begin
                sn_rsp_mux = sn_rsp_flit[si*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
            end
        end
    end

    always @(*) begin
        sn_dat_mux = {`C2_DAT_FLIT_W{1'b0}};
        for (si = 0; si < `C2_SN_NUM; si = si + 1) begin
            if (sn_dat_valid[si]) begin
                sn_dat_mux = sn_dat_flit[si*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
            end
        end
    end

    assign sn_rsp_active = |sn_rsp_valid;
    assign sn_dat_active = |sn_dat_valid;

    //------------------------------------------------------------------
    // 阵列时钟门控（位置连接风格）
    //------------------------------------------------------------------
    case2_clk_gate u_sn_cg (CLK, RST_N, ~SN_IDLE, sn_gclk);

    //------------------------------------------------------------------
    // CHI <-> flit 适配（旁路请求 + 读回 CHI 字段）
    //------------------------------------------------------------------
    case2_chi_to_noc u_to_noc (
        .CLK         (CLK),
        .RST_N       (RST_N),
        .OPCODE      (adapter_opcode),
        .ADDR        (adapter_data[`C2_CHI_ADDR_MSB:`C2_CHI_ADDR_LSB]),
        .SIZE        ({`C2_CHI_SIZE_W{1'b0}}),
        .QOS         ({`C2_CHI_QOS_W{1'b0}}),
        .MEMATTR     ({`C2_CHI_MEMATTR_W{1'b0}}),
        .SNPATTR     (1'b0),
        .SRCID       (NODEID),
        .TGTID       (NODEID),
        .DATA        (adapter_data),
        .BE          (adapter_be),
        .CHI_VALID   (adapter_chi_valid),
        .CHI_READY   (),
        .TXNID       (adapter_txnid_out),
        .TAG         (),
        .REQ_TX      (adapter_req_flit),
        .REQ_TX_VALID(adapter_req_valid),
        .REQ_TX_READY(adapter_req_ready),
        .DAT_TX      (adapter_dat_flit),
        .DAT_TX_VALID(adapter_dat_valid),
        .DAT_TX_READY(adapter_dat_ready),
        .CREDIT_RET  (CREDIT_RET),
        .CREDIT_ON   (),
        .VC_FREE     (adapter_vc_free)
    );

    case2_noc_to_chi u_to_chi (
        .CLK         (CLK),
        .RST_N       (RST_N),
        .RSP_RX      (RSP_RX),
        .RSP_RX_VALID(RSP_RX_VALID),
        .RSP_RX_READY(),
        .DAT_RX      (DAT_RX),
        .DAT_RX_VALID(DAT_RX_VALID),
        .DAT_RX_READY(),
        .OPCODE      (adapter_opcode),
        .TXNID       (adapter_txnid_in),
        .RESP        (adapter_resp),
        .RESPERR     (adapter_resperr),
        .FWDSTATE    (),
        .DATA        (adapter_data),
        .BE          (adapter_be),
        .DBID        (adapter_dbid),
        .DATAID      (),
        .CHI_VALID   (adapter_chi_valid),
        .ORDER_ERR   (adapter_order_err),
        .CHI_LAST    (adapter_chi_last)
    );

endmodule
