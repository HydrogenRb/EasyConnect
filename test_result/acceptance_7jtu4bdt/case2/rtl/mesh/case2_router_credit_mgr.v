//==========================================================================
//  case2_router_credit_mgr.v
//  全 mesh 的 credit 预算管理：16 条 link 各自的 credit 池
//
//    link 0..3   : 4 个 router 的 local lane（RN 侧）      -> [y][x] 嵌套 for
//    link 4..5   : N 边 link(x=0,1)      link 6..7  : S 边 link(x=0,1)
//    link 8..9   : W 边 link(y=0,1)      link 10..11: E 边 link(y=0,1)
//    link 12..15 : 4 段 SN drop ring（每 router 一段）
//  另外每个 router 端口（`C2_PORT_NUM 个）各有一个端口级 credit 池。
//
//  Ref: credit-based flow control 的全局预算表 + ICG 关空闲时钟。
//==========================================================================
`include "case2_define.v"

module case2_router_credit_mgr (
    input  wire                                 CLK,
    input  wire                                 RST_N,
    input  wire [`C2_LINK_NUM-1:0]              LINK_UP,
    input  wire [`C2_LINK_NUM*`C2_CREDIT_W-1:0] CREDIT_RET,
    output wire [`C2_LINK_NUM*`C2_CREDIT_W-1:0] CREDIT_ON,
    output wire [`C2_LINK_NUM-1:0]              CREDIT_OK,
    output wire [`C2_CREDIT_W-1:0]              CREDIT_DBG,
    output wire                                 CREDIT_EMPTY,
    output wire                                 MGR_ACTIVE
);

    wire                    mgr_gclk;
    wire [`C2_LINK_NUM-1:0] link_active;
    wire [`C2_CREDIT_W-1:0] local_credit;
    wire [`C2_CREDIT_W-1:0] sn_credit;
    wire [`C2_CREDIT_W-1:0] port_credit;
    wire                    local_ok;
    wire                    sn_ok;
    wire                    port_ok;

    assign CREDIT_DBG   = local_credit;
    assign CREDIT_EMPTY = ~(|CREDIT_OK);
    assign MGR_ACTIVE   = |link_active;

    //------------------------------------------------------------------
    // 时钟门控（位置连接风格）
    //------------------------------------------------------------------
    case2_clk_gate u_mgr_cg (CLK, RST_N, MGR_ACTIVE, mgr_gclk);

    //------------------------------------------------------------------
    // credit 池阵列
    //------------------------------------------------------------------
    genvar gy;
    genvar gx;
    genvar gp;
    generate
        for (gy = 0; gy < `C2_NOC_Y; gy = gy + 1) begin : g_row
            for (gx = 0; gx < `C2_NOC_X; gx = gx + 1) begin : g_col
                localparam L_IDX = gy*`C2_NOC_X + gx;
                localparam S_IDX = `C2_RN_NUM + 2*`C2_BOUND_LANE_NUM + L_IDX;

                // --- RN local lane（link 0..3）---
                case2_noc_credit_ctrl u_link_credit (
                    .CLK        (mgr_gclk),
                    .RST_N      (RST_N),
                    .INIT       (~RST_N),
                    .SEND       (link_active[L_IDX]),
                    .RET        (|CREDIT_RET[L_IDX*`C2_CREDIT_W +: `C2_CREDIT_W]),
                    .RET_NUM    (CREDIT_RET[L_IDX*`C2_CREDIT_W +: `C2_CREDIT_W]),
                    .CREDIT_CNT (local_credit),
                    .CREDIT_OK  (local_ok),
                    .CREDIT_ON  (CREDIT_ON[L_IDX*`C2_CREDIT_W +: `C2_CREDIT_W])
                );

                case2_gray_sync u_credit_sync (
                    .CLK     (mgr_gclk),
                    .RST_N   (RST_N),
                    .PTR_IN  (CREDIT_RET[L_IDX*`C2_CREDIT_W +: `C2_BUF_PTR_W]),
                    .PTR_OUT ()
                );

                assign link_active[L_IDX] = LINK_UP[L_IDX];
                assign CREDIT_OK[L_IDX]   = local_ok;

                // --- SN drop ring 段（link 12..15）---
                case2_noc_credit_ctrl u_sn_credit (
                    .CLK        (mgr_gclk),
                    .RST_N      (RST_N),
                    .INIT       (~RST_N),
                    .SEND       (link_active[S_IDX]),
                    .RET        (|CREDIT_RET[S_IDX*`C2_CREDIT_W +: `C2_CREDIT_W]),
                    .RET_NUM    (CREDIT_RET[S_IDX*`C2_CREDIT_W +: `C2_CREDIT_W]),
                    .CREDIT_CNT (sn_credit),
                    .CREDIT_OK  (sn_ok),
                    .CREDIT_ON  (CREDIT_ON[S_IDX*`C2_CREDIT_W +: `C2_CREDIT_W])
                );

                assign link_active[S_IDX] = LINK_UP[S_IDX];
                assign CREDIT_OK[S_IDX]   = sn_ok;

                // --- 边界 link：每个 (y,x) 负责本行/本列的两条 ---
                if (gy == 0) begin : g_n_bound
                    case2_noc_credit_ctrl u_bound_n (
                        .CLK        (mgr_gclk),
                        .RST_N      (RST_N),
                        .INIT       (~RST_N),
                        .SEND       (link_active[`C2_RN_NUM + gx]),
                        .RET        (|CREDIT_RET[(`C2_RN_NUM + gx)*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .RET_NUM    (CREDIT_RET[(`C2_RN_NUM + gx)*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_CNT (),
                        .CREDIT_OK  (CREDIT_OK[`C2_RN_NUM + gx]),
                        .CREDIT_ON  (CREDIT_ON[(`C2_RN_NUM + gx)*`C2_CREDIT_W +: `C2_CREDIT_W])
                    );
                    assign link_active[`C2_RN_NUM + gx] = LINK_UP[`C2_RN_NUM + gx];
                end

                if (gy == `C2_NOC_Y-1) begin : g_s_bound
                    case2_noc_credit_ctrl u_bound_s (
                        .CLK        (mgr_gclk),
                        .RST_N      (RST_N),
                        .INIT       (~RST_N),
                        .SEND       (link_active[`C2_RN_NUM + `C2_BOUND_LANE_NUM + gx]),
                        .RET        (|CREDIT_RET[(`C2_RN_NUM + `C2_BOUND_LANE_NUM + gx)*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .RET_NUM    (CREDIT_RET[(`C2_RN_NUM + `C2_BOUND_LANE_NUM + gx)*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_CNT (),
                        .CREDIT_OK  (CREDIT_OK[`C2_RN_NUM + `C2_BOUND_LANE_NUM + gx]),
                        .CREDIT_ON  (CREDIT_ON[(`C2_RN_NUM + `C2_BOUND_LANE_NUM + gx)*`C2_CREDIT_W +: `C2_CREDIT_W])
                    );
                    assign link_active[`C2_RN_NUM + `C2_BOUND_LANE_NUM + gx] =
                           LINK_UP[`C2_RN_NUM + `C2_BOUND_LANE_NUM + gx];
                end

                if (gx == 0) begin : g_w_bound
                    case2_noc_credit_ctrl u_bound_w (
                        .CLK        (mgr_gclk),
                        .RST_N      (RST_N),
                        .INIT       (~RST_N),
                        .SEND       (link_active[`C2_RN_NUM + 2*`C2_BOUND_LANE_NUM + gy]),
                        .RET        (|CREDIT_RET[(`C2_RN_NUM + 2*`C2_BOUND_LANE_NUM + gy)*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .RET_NUM    (CREDIT_RET[(`C2_RN_NUM + 2*`C2_BOUND_LANE_NUM + gy)*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_CNT (),
                        .CREDIT_OK  (CREDIT_OK[`C2_RN_NUM + 2*`C2_BOUND_LANE_NUM + gy]),
                        .CREDIT_ON  (CREDIT_ON[(`C2_RN_NUM + 2*`C2_BOUND_LANE_NUM + gy)*`C2_CREDIT_W +: `C2_CREDIT_W])
                    );
                    assign link_active[`C2_RN_NUM + 2*`C2_BOUND_LANE_NUM + gy] =
                           LINK_UP[`C2_RN_NUM + 2*`C2_BOUND_LANE_NUM + gy];
                end

                if (gx == `C2_NOC_X-1) begin : g_e_bound
                    case2_noc_credit_ctrl u_bound_e (
                        .CLK        (mgr_gclk),
                        .RST_N      (RST_N),
                        .INIT       (~RST_N),
                        .SEND       (link_active[`C2_RN_NUM + 3*`C2_BOUND_LANE_NUM + gy]),
                        .RET        (|CREDIT_RET[(`C2_RN_NUM + 3*`C2_BOUND_LANE_NUM + gy)*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .RET_NUM    (CREDIT_RET[(`C2_RN_NUM + 3*`C2_BOUND_LANE_NUM + gy)*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_CNT (),
                        .CREDIT_OK  (CREDIT_OK[`C2_RN_NUM + 3*`C2_BOUND_LANE_NUM + gy]),
                        .CREDIT_ON  (CREDIT_ON[(`C2_RN_NUM + 3*`C2_BOUND_LANE_NUM + gy)*`C2_CREDIT_W +: `C2_CREDIT_W])
                    );
                    assign link_active[`C2_RN_NUM + 3*`C2_BOUND_LANE_NUM + gy] =
                           LINK_UP[`C2_RN_NUM + 3*`C2_BOUND_LANE_NUM + gy];
                end
            end
        end

        // --- 每个 router 端口一个端口级 credit 池 ---
        for (gp = 0; gp < `C2_PORT_NUM; gp = gp + 1) begin : g_port_credit
            case2_noc_credit_ctrl u_port_credit (
                .CLK        (mgr_gclk),
                .RST_N      (RST_N),
                .INIT       (~RST_N),
                .SEND       (MGR_ACTIVE),
                .RET        (|CREDIT_RET[gp*`C2_CREDIT_W +: `C2_CREDIT_W]),
                .RET_NUM    (CREDIT_RET[gp*`C2_CREDIT_W +: `C2_CREDIT_W]),
                .CREDIT_CNT (port_credit),
                .CREDIT_OK  (port_ok),
                .CREDIT_ON  ()
            );
        end
    endgenerate

endmodule
