//==========================================================================
//  case3_cluster_array.v
//  计算簇阵列：两级 for-generate（cluster x slice 端口）展开 `C3_CLUSTER_NUM
//  个 case3_cluster，并在同一 generate 内例化端口同步器；阵列外面挂一个
//  inter-cluster 交叉开关 case3_xbar。
//
//  Ref: 多簇向量引擎的 cluster array + plane xbar（Ascend mini / NVDLA 大核）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_cluster_array (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire                          ARRAY_CLK,
    input  wire [`C3_CFG_DATA_W-1:0]     CFG_CTRL,
    input  wire [`C3_CFG_DATA_W-1:0]     CFG_MASK,
    input  wire [`C3_ADDR_W-1:0]         CFG_BASE,
    input  wire                          CFG_GO,
    input  wire [`C3_MON_SEL_W-1:0]      MON_SEL,
    input  wire [`C3_DESC_W-1:0]         DESC_DATA,
    input  wire                          DESC_VALID,
    output wire                          DESC_READY,
    input  wire [`C3_TXN_ID_W-1:0]       TXN_ID,
    output wire [`C3_STATUS_W-1:0]       CL_STATUS,
    output wire [`C3_CNT_W-1:0]          CL_CYCLES,
    output wire                          CL_BUSY,
    output wire [`C3_XFER_ID_W-1:0]      XFER_ID,
    output wire                          XFER_VALID,
    output wire                          SP_A_CEN,
    output wire                          SP_A_WEN,
    output wire [`C3_SCRATCH_ADDR_W-1:0] SP_A_ADDR,
    output wire [`C3_SCRATCH_DATA_W-1:0] SP_A_D,
    input  wire [`C3_SCRATCH_DATA_W-1:0] SP_A_Q,
    output wire                          SP_B_CEN,
    output wire [`C3_SCRATCH_ADDR_W-1:0] SP_B_ADDR,
    input  wire [`C3_SCRATCH_DATA_W-1:0] SP_B_Q
);

    parameter ARRAY_PIPE = `C3_PIPE_STAGE;

    genvar c;
    genvar p;

    wire                      plane_busy_w;
    wire [`C3_DATA_W-1:0]     plane_data_w;
    wire [`C3_CLUSTER_NUM-1:0] plane_grant_w;
    wire [`C3_STATUS_W-1:0]   cl_status_w  [0:`C3_CLUSTER_NUM-1];
    wire [`C3_CNT_W-1:0]      cl_cycles_w  [0:`C3_CLUSTER_NUM-1];
    wire                      cl_busy_w    [0:`C3_CLUSTER_NUM-1];
    wire                      cl_desc_rdy_w[0:`C3_CLUSTER_NUM-1];
    wire                      cl_a_cen_w   [0:`C3_CLUSTER_NUM-1];
    wire                      cl_a_wen_w   [0:`C3_CLUSTER_NUM-1];
    wire [`C3_SCRATCH_ADDR_W-1:0] cl_a_addr_w [0:`C3_CLUSTER_NUM-1];
    wire [`C3_SCRATCH_DATA_W-1:0] cl_a_d_w    [0:`C3_CLUSTER_NUM-1];
    wire                      cl_b_cen_w   [0:`C3_CLUSTER_NUM-1];
    wire [`C3_SCRATCH_ADDR_W-1:0] cl_b_addr_w [0:`C3_CLUSTER_NUM-1];
    wire [(`C3_CLUSTER_NUM*`C3_SLICE_NUM)-1:0] port_req_w;
    wire [(`C3_CLUSTER_NUM*`C3_SLICE_NUM)-1:0] port_req_sync_w;

    assign SP_A_CEN   = cl_a_cen_w[0] | cl_a_cen_w[1];
    assign SP_A_WEN   = cl_a_wen_w[0] | cl_a_wen_w[1];
    assign SP_A_ADDR  = cl_a_addr_w[0] | cl_a_addr_w[1];
    assign SP_A_D     = cl_a_d_w[0] | cl_a_d_w[1];
    assign SP_B_CEN   = cl_b_cen_w[0] | cl_b_cen_w[1];
    assign SP_B_ADDR  = cl_b_addr_w[0] | cl_b_addr_w[1];
    assign CL_STATUS  = cl_status_w[0] | cl_status_w[1];
    assign CL_CYCLES  = cl_cycles_w[0] + cl_cycles_w[1];
    assign CL_BUSY    = cl_busy_w[0] | cl_busy_w[1] | plane_busy_w;
    assign DESC_READY = cl_desc_rdy_w[0] & cl_desc_rdy_w[1];
    assign XFER_ID    = TXN_ID[`C3_XFER_ID_W-1:0];
    assign XFER_VALID = (CL_BUSY | (|plane_grant_w));

    generate
        for (c = 0; c < `C3_CLUSTER_NUM; c = c + 1) begin : g_cluster
            wire [`C3_CLUSTER_AW-1:0] cluster_id_w;
            wire [`C3_ADDR_W-1:0]     cluster_stride_w;
            wire [`C3_CFG_DATA_W-1:0] cluster_mask_w;

            assign cluster_id_w     = c;
            assign cluster_stride_w = {{(`C3_ADDR_W-`C3_CLUSTER_AW){1'b0}}, c};
            assign cluster_mask_w   = CFG_MASK | {`C3_CFG_DATA_W{1'b0}};

            case3_cluster u_cluster[c] (
                .CLK          (CLK),
                .RST_N        (RST_N),
                .CLUSTER_CLK  (ARRAY_CLK),
                .CL_CTRL      (CFG_CTRL),
                .CL_MASK      (cluster_mask_w),
                .CL_BASE      (CFG_BASE + cluster_stride_w),
                .CL_GO        (CFG_GO),
                .CLUSTER_ID   (cluster_id_w),
                .MON_SEL      (MON_SEL),
                .DESC_DATA    (DESC_DATA),
                .DESC_VALID   (DESC_VALID),
                .DESC_READY   (cl_desc_rdy_w[c]),
                .TXN_ID       (TXN_ID),
                .XFER_ID      (XFER_ID),
                .CL_STATUS    (cl_status_w[c]),
                .CL_CYCLES    (cl_cycles_w[c]),
                .CL_BUSY      (cl_busy_w[c]),
                .SP_A_CEN     (cl_a_cen_w[c]),
                .SP_A_WEN     (cl_a_wen_w[c]),
                .SP_A_ADDR    (cl_a_addr_w[c]),
                .SP_A_D       (cl_a_d_w[c]),
                .SP_A_Q       (SP_A_Q),
                .SP_B_CEN     (cl_b_cen_w[c]),
                .SP_B_ADDR    (cl_b_addr_w[c]),
                .SP_B_Q       (SP_B_Q)
            );

            for (p = 0; p < `C3_SLICE_NUM; p = p + 1) begin : g_port
                // 端口请求同步器（位置端口连接）
                case3_sync_2ff u_req_sync[c][p] (
                    CLK, RST_N, port_req_w[(c*`C3_SLICE_NUM)+p],
                    port_req_sync_w[(c*`C3_SLICE_NUM)+p]
                );
            end
        end
    endgenerate

    assign port_req_w = {`C3_CLUSTER_NUM{`C3_SLICE_NUM{CFG_GO}}};

    case3_xbar u_plane_xbar (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .XBAR_CLK   (ARRAY_CLK),
        .XBAR_REQ   (port_req_sync_w[`C3_CLUSTER_NUM-1:0]),
        .XBAR_SEL   (TXN_ID[`C3_CLUSTER_AW-1:0]),
        .XBAR_DATA_IN(DESC_DATA[`C3_DATA_MSB:0]),
        .XBAR_DATA_OUT(plane_data_w),
        .XBAR_GRANT (plane_grant_w),
        .XBAR_BUSY  (plane_busy_w)
    );

endmodule
