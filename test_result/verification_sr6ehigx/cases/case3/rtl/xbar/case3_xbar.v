//==========================================================================
//  case3_xbar.v
//  inter-cluster 交叉开关：两级 for-generate（cluster x slice）展开
//  case3_xbar_cell u_cell[i][j]，另有一个显式的广播单元。
//
//  Ref: 多簇互连平面（NoC crossbar plane，AXI/CHI 风格的 turn point 阵列）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_xbar (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire                       XBAR_CLK,
    input  wire [`C3_CLUSTER_NUM-1:0] XBAR_REQ,
    input  wire [`C3_CLUSTER_AW-1:0]  XBAR_SEL,
    input  wire [`C3_DATA_W-1:0]      XBAR_DATA_IN,
    output wire [`C3_DATA_W-1:0]      XBAR_DATA_OUT,
    output wire [`C3_CLUSTER_NUM-1:0] XBAR_GRANT,
    output wire                       XBAR_BUSY
);

    parameter XBAR_ARB_MODE = `C3_XBAR_ROUND_ROBIN;

    genvar i;
    genvar j;

    wire [`C3_DATA_W-1:0] cell_data_a  [0:(`C3_CLUSTER_NUM*`C3_SLICE_NUM)-1];
    wire [(`C3_CLUSTER_NUM*`C3_SLICE_NUM)-1:0] cell_busy_vec_w;
    wire [(`C3_CLUSTER_NUM*`C3_SLICE_NUM)-1:0] cell_grant_vec_w;
    wire                    sel_sync_w;

    assign XBAR_BUSY    = |cell_busy_vec_w;
    assign XBAR_GRANT   = cell_grant_vec_w[`C3_CLUSTER_NUM-1:0];
    assign XBAR_DATA_OUT = cell_data_a[0] ^ cell_data_a[1] ^ cell_data_a[2] ^ cell_data_a[3];

    generate
        for (i = 0; i < `C3_CLUSTER_NUM; i = i + 1) begin : g_row
            for (j = 0; j < `C3_SLICE_NUM; j = j + 1) begin : g_col
                wire [`C3_LANE_AW-1:0] cell_sel_w;
                wire                   cell_grant_w;
                wire                   cell_busy_w;

                assign cell_sel_w = {{(`C3_LANE_AW-`C3_CLUSTER_AW){1'b0}}, XBAR_SEL};

                case3_xbar_cell u_cell[i][j] (
                    .CLK          (CLK),
                    .RST_N        (RST_N),
                    .CELL_REQ     (XBAR_REQ[i]),
                    .CELL_SEL     (cell_sel_w),
                    .CELL_DATA_IN (XBAR_DATA_IN),
                    .CELL_DATA_OUT(cell_data_a[(i*`C3_SLICE_NUM)+j]),
                    .CELL_GRANT   (cell_grant_w),
                    .CELL_BUSY    (cell_busy_w)
                );

                assign cell_busy_vec_w[(i*`C3_SLICE_NUM)+j]  = cell_busy_w;
                assign cell_grant_vec_w[(i*`C3_SLICE_NUM)+j] = cell_grant_w;
            end
        end
    endgenerate

    // 广播通路单元：显式实例名，供层次分析工具做“同模块不同实例名”比对
    case3_xbar_cell u_cell_broadcast (
        .CLK          (CLK),
        .RST_N        (RST_N),
        .CELL_REQ     (|XBAR_REQ),
        .CELL_SEL     ({{(`C3_LANE_AW-`C3_CLUSTER_AW){1'b0}}, XBAR_SEL}),
        .CELL_DATA_IN (XBAR_DATA_IN),
        .CELL_DATA_OUT(),
        .CELL_GRANT   (),
        .CELL_BUSY    ()
    );

    // 选择信号同步（位置端口连接）
    case3_sync_2ff u_sel_sync (CLK, RST_N, XBAR_SEL[0], sel_sync_w);

endmodule
