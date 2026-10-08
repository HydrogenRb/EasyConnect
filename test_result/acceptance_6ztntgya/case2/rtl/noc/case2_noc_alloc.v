//==========================================================================
//  case2_noc_alloc.v
//  VC 分配器：每个输入端口一个仲裁器，竞争 `C2_VC_NUM 个 VC
//
//  同一模块 case2_noc_arbiter 在 for-generate 里例化 `C2_PORT_NUM 次，
//  路径形如 u_alloc.g_port_arb[3].u_port_arb。
//==========================================================================
`include "case2_define.v"

module case2_noc_alloc (
    input  wire                    CLK,
    input  wire                    RST_N,
    input  wire [`C2_PORT_NUM-1:0] REQ_VALID,
    input  wire [`C2_PORT_NUM-1:0] CREDIT_VEC,
    input  wire [`C2_VC_NUM-1:0]   VC_FREE,
    output wire [`C2_PORT_NUM-1:0] VC_ALLOC,
    output wire [`C2_PORT_NUM-1:0] ALLOC_FAIL,
    output wire [`C2_PORT_AW-1:0]  GNT_IDX,
    output wire [`C2_PORT_NUM-1:0] REQ_HOLD
);

    wire [`C2_PORT_NUM*`C2_PORT_AW-1:0] gnt_idx_flat;

    assign GNT_IDX  = gnt_idx_flat[0 +: `C2_PORT_AW];
    assign REQ_HOLD = VC_ALLOC;

    genvar gp;
    generate
        for (gp = 0; gp < `C2_PORT_NUM; gp = gp + 1) begin : g_port_arb
            case2_noc_arbiter u_port_arb (
                .CLK        (CLK),
                .RST_N      (RST_N),
                .REQ        (REQ_VALID),
                .CREDIT     (CREDIT_VEC),
                .HOLD       (~VC_FREE[gp % `C2_VC_NUM]),
                .GNT        (),
                .GNT_IDX    (gnt_idx_flat[gp*`C2_PORT_AW +: `C2_PORT_AW]),
                .GNT_VALID  (VC_ALLOC[gp]),
                .ALLOC_FAIL (ALLOC_FAIL[gp])
            );
        end
    endgenerate

endmodule
