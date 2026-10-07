//==========================================================================
//  case2_noc_xbar.v
//  5x5 crossbar：每个 (输出端口, VC) 一个 u_out[o][v]（嵌套 for-generate）
//
//  输入 = 各端口收到的 flit（port RX），输出 = 各端口要发出的 flit（port TX）。
//  grant 汇总回每个输入端口的 ready。VC1 的 flit 出口先落在内部总线上，
//  本样本只用 VC0 的出口驱动端口（VC 仲裁的简化）。
//==========================================================================
`include "case2_define.v"

module case2_noc_xbar (
    input  wire                        CLK,
    input  wire                        RST_N,
    input  wire [`C2_ROUTER_REQ_W-1:0] REQ_IN,
    input  wire [`C2_PORT_NUM-1:0]     REQ_IN_VALID,
    output wire [`C2_PORT_NUM-1:0]     REQ_IN_READY,
    output wire [`C2_ROUTER_REQ_W-1:0] REQ_OUT,
    output wire [`C2_PORT_NUM-1:0]     REQ_OUT_VALID,
    input  wire [`C2_PORT_NUM-1:0]     REQ_OUT_READY,
    input  wire [`C2_ROUTER_RSP_W-1:0] RSP_IN,
    input  wire [`C2_PORT_NUM-1:0]     RSP_IN_VALID,
    output wire [`C2_PORT_NUM-1:0]     RSP_IN_READY,
    output wire [`C2_ROUTER_RSP_W-1:0] RSP_OUT,
    output wire [`C2_PORT_NUM-1:0]     RSP_OUT_VALID,
    input  wire [`C2_PORT_NUM-1:0]     RSP_OUT_READY,
    input  wire [`C2_ROUTER_SNP_W-1:0] SNP_IN,
    input  wire [`C2_PORT_NUM-1:0]     SNP_IN_VALID,
    output wire [`C2_PORT_NUM-1:0]     SNP_IN_READY,
    output wire [`C2_ROUTER_SNP_W-1:0] SNP_OUT,
    output wire [`C2_PORT_NUM-1:0]     SNP_OUT_VALID,
    input  wire [`C2_PORT_NUM-1:0]     SNP_OUT_READY,
    input  wire [`C2_ROUTER_DAT_W-1:0] DAT_IN,
    input  wire [`C2_PORT_NUM-1:0]     DAT_IN_VALID,
    output wire [`C2_PORT_NUM-1:0]     DAT_IN_READY,
    output wire [`C2_ROUTER_DAT_W-1:0] DAT_OUT,
    output wire [`C2_PORT_NUM-1:0]     DAT_OUT_VALID,
    input  wire [`C2_PORT_NUM-1:0]     DAT_OUT_READY,
    input  wire [`C2_PORT_NUM-1:0]     CREDIT_REQ,
    input  wire [`C2_PORT_NUM-1:0]     CREDIT_RSP,
    input  wire [`C2_PORT_NUM-1:0]     CREDIT_SNP,
    input  wire [`C2_PORT_NUM-1:0]     CREDIT_DAT,
    output wire [`C2_PORT_NUM-1:0]     OUT_BUSY
);

    wire [`C2_PORT_NUM*`C2_VC_NUM*`C2_PORT_NUM-1:0] req_gnt_flat;
    wire [`C2_PORT_NUM*`C2_VC_NUM-1:0]              req_out_valid;
    wire [`C2_PORT_NUM*`C2_VC_NUM-1:0]              req_out_busy;
    wire [`C2_VC_NUM*`C2_ROUTER_REQ_W-1:0]          req_vc_flit;
    wire [`C2_VC_NUM*`C2_ROUTER_RSP_W-1:0]          rsp_vc_flit;
    wire [`C2_VC_NUM*`C2_ROUTER_SNP_W-1:0]          snp_vc_flit;
    wire [`C2_VC_NUM*`C2_ROUTER_DAT_W-1:0]          dat_vc_flit;

    reg [`C2_PORT_NUM-1:0] req_ready_c;
    reg [`C2_PORT_NUM-1:0] rsp_ready_c;
    reg [`C2_PORT_NUM-1:0] snp_ready_c;
    reg [`C2_PORT_NUM-1:0] dat_ready_c;
    reg [`C2_PORT_NUM-1:0] busy_c;

    integer oi;
    integer vi;
    integer ii;

    //------------------------------------------------------------------
    // grant 汇总：每个输入端口被任一输出端口/VC 选中即可发送
    //------------------------------------------------------------------
    always @(*) begin
        req_ready_c = {`C2_PORT_NUM{1'b0}};
        for (ii = 0; ii < `C2_PORT_NUM; ii = ii + 1) begin
            for (oi = 0; oi < `C2_PORT_NUM; oi = oi + 1) begin
                for (vi = 0; vi < `C2_VC_NUM; vi = vi + 1) begin
                    req_ready_c[ii] = req_ready_c[ii] |
                        req_gnt_flat[(oi*`C2_VC_NUM + vi)*`C2_PORT_NUM + ii];
                end
            end
        end
    end

    always @(*) begin
        busy_c = {`C2_PORT_NUM{1'b0}};
        for (oi = 0; oi < `C2_PORT_NUM; oi = oi + 1) begin
            for (vi = 0; vi < `C2_VC_NUM; vi = vi + 1) begin
                busy_c[oi] = busy_c[oi] | req_out_busy[oi*`C2_VC_NUM + vi];
            end
        end
    end

    // 本样本 RSP/SNP/DAT 与 REQ 共用同一份 grant 汇总（简化）
    always @(*) begin
        rsp_ready_c = req_ready_c;
        snp_ready_c = req_ready_c;
        dat_ready_c = req_ready_c;
    end

    assign REQ_IN_READY  = req_ready_c;
    assign RSP_IN_READY  = rsp_ready_c;
    assign SNP_IN_READY  = snp_ready_c;
    assign DAT_IN_READY  = dat_ready_c;
    assign OUT_BUSY      = busy_c;
    assign REQ_OUT       = req_vc_flit[0*`C2_ROUTER_REQ_W +: `C2_ROUTER_REQ_W];
    assign RSP_OUT       = rsp_vc_flit[0*`C2_ROUTER_RSP_W +: `C2_ROUTER_RSP_W];
    assign SNP_OUT       = snp_vc_flit[0*`C2_ROUTER_SNP_W +: `C2_ROUTER_SNP_W];
    assign DAT_OUT       = dat_vc_flit[0*`C2_ROUTER_DAT_W +: `C2_ROUTER_DAT_W];
    assign REQ_OUT_VALID = req_out_valid[0*`C2_PORT_NUM +: `C2_PORT_NUM];
    assign RSP_OUT_VALID = {`C2_PORT_NUM{1'b0}};
    assign SNP_OUT_VALID = {`C2_PORT_NUM{1'b0}};
    assign DAT_OUT_VALID = {`C2_PORT_NUM{1'b0}};

    //------------------------------------------------------------------
    // 输出阵列：u_out[o][v]（10 个实例）
    //------------------------------------------------------------------
    genvar go;
    genvar gv;
    generate
        for (go = 0; go < `C2_PORT_NUM; go = go + 1) begin : g_out_port
            for (gv = 0; gv < `C2_VC_NUM; gv = gv + 1) begin : g_out_vc
                case2_noc_xbar_out #(.OUT_PORT(go), .OUT_VC(gv)) u_out (
                    .CLK          (CLK),
                    .RST_N        (RST_N),
                    .REQ_IN       (REQ_IN),
                    .REQ_IN_VALID (REQ_IN_VALID),
                    .REQ_GNT      (req_gnt_flat[(go*`C2_VC_NUM + gv)*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .REQ_OUT      (req_vc_flit[gv*`C2_ROUTER_REQ_W + go*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]),
                    .REQ_OUT_VALID(req_out_valid[go*`C2_VC_NUM + gv]),
                    .REQ_OUT_READY(REQ_OUT_READY[go]),
                    .RSP_IN       (RSP_IN),
                    .RSP_IN_VALID (RSP_IN_VALID),
                    .RSP_GNT      (),
                    .RSP_OUT      (rsp_vc_flit[gv*`C2_ROUTER_RSP_W + go*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]),
                    .RSP_OUT_VALID(),
                    .RSP_OUT_READY(RSP_OUT_READY[go]),
                    .SNP_IN       (SNP_IN),
                    .SNP_IN_VALID (SNP_IN_VALID),
                    .SNP_GNT      (),
                    .SNP_OUT      (snp_vc_flit[gv*`C2_ROUTER_SNP_W + go*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]),
                    .SNP_OUT_VALID(),
                    .SNP_OUT_READY(SNP_OUT_READY[go]),
                    .DAT_IN       (DAT_IN),
                    .DAT_IN_VALID (DAT_IN_VALID),
                    .DAT_GNT      (),
                    .DAT_OUT      (dat_vc_flit[gv*`C2_ROUTER_DAT_W + go*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                    .DAT_OUT_VALID(),
                    .DAT_OUT_READY(DAT_OUT_READY[go]),
                    .CREDIT_REQ   (CREDIT_REQ),
                    .CREDIT_RSP   (CREDIT_RSP),
                    .CREDIT_SNP   (CREDIT_SNP),
                    .CREDIT_DAT   (CREDIT_DAT),
                    .OUT_BUSY     (req_out_busy[go*`C2_VC_NUM + gv]),
                    .OUT_SRC_IDX  ()
                );
            end
        end
    endgenerate

endmodule
