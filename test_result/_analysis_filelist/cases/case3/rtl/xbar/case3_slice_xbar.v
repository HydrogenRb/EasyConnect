//==========================================================================
//  case3_slice_xbar.v
//  slice 内部交叉开关：两级 for-generate（lane x bank）展开 16 个
//  case3_xbar_cell u_cell[i][j]。
//
//  Ref: 向量机内部 lane 到 bank 的 crossbar（Vision P6 VMEM 交换网络）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_slice_xbar (
    input  wire                    CLK,
    input  wire                    RST_N,
    input  wire                    XBAR_CLK,
    input  wire [`C3_LANE_NUM-1:0] LANE_REQ,
    input  wire [`C3_LANE_AW-1:0]  LANE_SEL,
    input  wire [`C3_DATA_W-1:0]   LANE_DATA,
    output wire [`C3_DATA_W-1:0]   XBAR_DATA,
    output wire [`C3_LANE_NUM-1:0] LANE_GRANT,
    output wire                    SLICE_XBAR_BUSY
);

    parameter XBAR_ARB_MODE = `C3_XBAR_ROUND_ROBIN;

    genvar i;
    genvar j;

    wire [`C3_DATA_W-1:0] cell_data_a [0:(`C3_LANE_NUM*`C3_BANK_NUM)-1];
    wire [(`C3_LANE_NUM*`C3_BANK_NUM)-1:0] cell_busy_vec_w;
    wire [(`C3_LANE_NUM*`C3_BANK_NUM)-1:0] cell_grant_vec_w;
    wire                   xbar_clk_r;

    assign SLICE_XBAR_BUSY = |cell_busy_vec_w;
    assign LANE_GRANT      = cell_grant_vec_w[`C3_LANE_NUM-1:0];
    assign XBAR_DATA       = cell_data_a[0]  ^ cell_data_a[1]  ^ cell_data_a[2]  ^ cell_data_a[3]  ^
                             cell_data_a[4]  ^ cell_data_a[5]  ^ cell_data_a[6]  ^ cell_data_a[7]  ^
                             cell_data_a[8]  ^ cell_data_a[9]  ^ cell_data_a[10] ^ cell_data_a[11] ^
                             cell_data_a[12] ^ cell_data_a[13] ^ cell_data_a[14] ^ cell_data_a[15];

    generate
        for (i = 0; i < `C3_LANE_NUM; i = i + 1) begin : g_lane_row
            for (j = 0; j < `C3_BANK_NUM; j = j + 1) begin : g_bank_col
                wire                   cell_req_w;
                wire                   cell_grant_w;
                wire                   cell_busy_w;
                wire [`C3_LANE_AW-1:0] cell_sel_w;

                assign cell_req_w = LANE_REQ[i] & ~xbar_clk_r;
                assign cell_sel_w = LANE_SEL;

                case3_xbar_cell u_cell[i][j] (
                    .CLK          (XBAR_CLK),
                    .RST_N        (RST_N),
                    .CELL_REQ     (cell_req_w),
                    .CELL_SEL     (cell_sel_w),
                    .CELL_DATA_IN (LANE_DATA),
                    .CELL_DATA_OUT(cell_data_a[(i*`C3_BANK_NUM)+j]),
                    .CELL_GRANT   (cell_grant_w),
                    .CELL_BUSY    (cell_busy_w)
                );

                assign cell_busy_vec_w[(i*`C3_BANK_NUM)+j]  = cell_busy_w;
                assign cell_grant_vec_w[(i*`C3_BANK_NUM)+j] = cell_grant_w;
            end
        end
    endgenerate

    case3_sync_2ff u_xbar_clk_sync (CLK, RST_N, LANE_SEL[0], xbar_clk_r);

endmodule
