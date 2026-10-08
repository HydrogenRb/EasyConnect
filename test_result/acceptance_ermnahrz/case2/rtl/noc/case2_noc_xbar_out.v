//==========================================================================
//  case2_noc_xbar_out.v
//  crossbar 的一个输出（输出端口 × VC）：4 个通道各一个仲裁器
//
//  4 个输入端口竞争同一个输出端口，u_arb_req / u_arb_rsp / u_arb_snp /
//  u_arb_dat 是同一模块 case2_noc_arbiter 的 4 个不同实例名。
//==========================================================================
`include "case2_define.v"

module case2_noc_xbar_out (
    input  wire                        CLK,
    input  wire                        RST_N,
    input  wire [`C2_ROUTER_REQ_W-1:0] REQ_IN,
    input  wire [`C2_PORT_NUM-1:0]     REQ_IN_VALID,
    output wire [`C2_PORT_NUM-1:0]     REQ_GNT,
    output wire [`C2_REQ_FLIT_W-1:0]   REQ_OUT,
    output wire                        REQ_OUT_VALID,
    input  wire                        REQ_OUT_READY,
    input  wire [`C2_ROUTER_RSP_W-1:0] RSP_IN,
    input  wire [`C2_PORT_NUM-1:0]     RSP_IN_VALID,
    output wire [`C2_PORT_NUM-1:0]     RSP_GNT,
    output wire [`C2_RSP_FLIT_W-1:0]   RSP_OUT,
    output wire                        RSP_OUT_VALID,
    input  wire                        RSP_OUT_READY,
    input  wire [`C2_ROUTER_SNP_W-1:0] SNP_IN,
    input  wire [`C2_PORT_NUM-1:0]     SNP_IN_VALID,
    output wire [`C2_PORT_NUM-1:0]     SNP_GNT,
    output wire [`C2_SNP_FLIT_W-1:0]   SNP_OUT,
    output wire                        SNP_OUT_VALID,
    input  wire                        SNP_OUT_READY,
    input  wire [`C2_ROUTER_DAT_W-1:0] DAT_IN,
    input  wire [`C2_PORT_NUM-1:0]     DAT_IN_VALID,
    output wire [`C2_PORT_NUM-1:0]     DAT_GNT,
    output wire [`C2_DAT_FLIT_W-1:0]   DAT_OUT,
    output wire                        DAT_OUT_VALID,
    input  wire                        DAT_OUT_READY,
    input  wire [`C2_PORT_NUM-1:0]     CREDIT_REQ,
    input  wire [`C2_PORT_NUM-1:0]     CREDIT_RSP,
    input  wire [`C2_PORT_NUM-1:0]     CREDIT_SNP,
    input  wire [`C2_PORT_NUM-1:0]     CREDIT_DAT,
    output wire                        OUT_BUSY,
    output wire [`C2_PORT_AW-1:0]      OUT_SRC_IDX
);

    parameter OUT_PORT = `C2_PORT_LOCAL;
    parameter OUT_VC   = 0;

    reg [`C2_REQ_FLIT_W-1:0] req_out_c;
    reg [`C2_RSP_FLIT_W-1:0] rsp_out_c;
    reg [`C2_SNP_FLIT_W-1:0] snp_out_c;
    reg [`C2_DAT_FLIT_W-1:0] dat_out_c;

    wire [`C2_PORT_NUM-1:0] req_gnt;
    wire [`C2_PORT_NUM-1:0] rsp_gnt;
    wire [`C2_PORT_NUM-1:0] snp_gnt;
    wire [`C2_PORT_NUM-1:0] dat_gnt;
    wire [`C2_PORT_AW-1:0]  req_idx;
    wire [`C2_PORT_AW-1:0]  rsp_idx;
    wire [`C2_PORT_AW-1:0]  snp_idx;
    wire [`C2_PORT_AW-1:0]  dat_idx;
    wire                    req_valid;
    wire                    rsp_valid;
    wire                    snp_valid;
    wire                    dat_valid;
    wire                    req_fail;
    wire                    rsp_fail;
    wire                    snp_fail;
    wire                    dat_fail;

    assign REQ_OUT       = req_out_c;
    assign RSP_OUT       = rsp_out_c;
    assign SNP_OUT       = snp_out_c;
    assign DAT_OUT       = dat_out_c;
    assign REQ_OUT_VALID = req_valid & REQ_OUT_READY;
    assign RSP_OUT_VALID = rsp_valid & RSP_OUT_READY;
    assign SNP_OUT_VALID = snp_valid & SNP_OUT_READY;
    assign DAT_OUT_VALID = dat_valid & DAT_OUT_READY;
    assign REQ_GNT       = req_gnt;
    assign RSP_GNT       = rsp_gnt;
    assign SNP_GNT       = snp_gnt;
    assign DAT_GNT       = dat_gnt;
    assign OUT_BUSY      = req_valid | rsp_valid | snp_valid | dat_valid;
    assign OUT_SRC_IDX   = req_idx | rsp_idx | snp_idx | dat_idx;

    //------------------------------------------------------------------
    // 4 个通道各自的输入选择
    //------------------------------------------------------------------
    always @(*) begin
        if (req_gnt[0])      req_out_c = REQ_IN[0*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
        else if (req_gnt[1]) req_out_c = REQ_IN[1*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
        else if (req_gnt[2]) req_out_c = REQ_IN[2*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
        else if (req_gnt[3]) req_out_c = REQ_IN[3*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
        else if (req_gnt[4]) req_out_c = REQ_IN[4*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
        else                 req_out_c = {`C2_REQ_FLIT_W{1'b0}};
    end

    always @(*) begin
        if (rsp_gnt[0])      rsp_out_c = RSP_IN[0*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
        else if (rsp_gnt[1]) rsp_out_c = RSP_IN[1*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
        else if (rsp_gnt[2]) rsp_out_c = RSP_IN[2*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
        else if (rsp_gnt[3]) rsp_out_c = RSP_IN[3*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
        else if (rsp_gnt[4]) rsp_out_c = RSP_IN[4*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
        else                 rsp_out_c = {`C2_RSP_FLIT_W{1'b0}};
    end

    always @(*) begin
        if (snp_gnt[0])      snp_out_c = SNP_IN[0*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
        else if (snp_gnt[1]) snp_out_c = SNP_IN[1*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
        else if (snp_gnt[2]) snp_out_c = SNP_IN[2*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
        else if (snp_gnt[3]) snp_out_c = SNP_IN[3*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
        else if (snp_gnt[4]) snp_out_c = SNP_IN[4*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
        else                 snp_out_c = {`C2_SNP_FLIT_W{1'b0}};
    end

    always @(*) begin
        if (dat_gnt[0])      dat_out_c = DAT_IN[0*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
        else if (dat_gnt[1]) dat_out_c = DAT_IN[1*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
        else if (dat_gnt[2]) dat_out_c = DAT_IN[2*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
        else if (dat_gnt[3]) dat_out_c = DAT_IN[3*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
        else if (dat_gnt[4]) dat_out_c = DAT_IN[4*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
        else                 dat_out_c = {`C2_DAT_FLIT_W{1'b0}};
    end

    //------------------------------------------------------------------
    // 4 个通道仲裁器（同名模块 4 个不同实例名）
    //------------------------------------------------------------------
    case2_noc_arbiter u_arb_req (
        .CLK(CLK), .RST_N(RST_N),
        .REQ(REQ_IN_VALID), .CREDIT(CREDIT_REQ), .HOLD(~REQ_OUT_READY),
        .GNT(req_gnt), .GNT_IDX(req_idx), .GNT_VALID(req_valid), .ALLOC_FAIL(req_fail)
    );

    case2_noc_arbiter u_arb_rsp (
        .CLK(CLK), .RST_N(RST_N),
        .REQ(RSP_IN_VALID), .CREDIT(CREDIT_RSP), .HOLD(~RSP_OUT_READY),
        .GNT(rsp_gnt), .GNT_IDX(rsp_idx), .GNT_VALID(rsp_valid), .ALLOC_FAIL(rsp_fail)
    );

    case2_noc_arbiter u_arb_snp (
        .CLK(CLK), .RST_N(RST_N),
        .REQ(SNP_IN_VALID), .CREDIT(CREDIT_SNP), .HOLD(~SNP_OUT_READY),
        .GNT(snp_gnt), .GNT_IDX(snp_idx), .GNT_VALID(snp_valid), .ALLOC_FAIL(snp_fail)
    );

    case2_noc_arbiter u_arb_dat (
        .CLK(CLK), .RST_N(RST_N),
        .REQ(DAT_IN_VALID), .CREDIT(CREDIT_DAT), .HOLD(~DAT_OUT_READY),
        .GNT(dat_gnt), .GNT_IDX(dat_idx), .GNT_VALID(dat_valid), .ALLOC_FAIL(dat_fail)
    );

endmodule
