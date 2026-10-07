//==========================================================================
//  case3_scratchpad.v
//  片上 scratchpad：`C3_BANK_NUM 个 bank（for-generate + 嵌套端口仲裁）+ 一个
//  冗余 bank（defparam 定制参数）+ 一个读回 FIFO。
//
//  Ref: GPU/NPU 的 multi-bank scratchpad（Vision P6 VMEM、Mali Tiler heap），
//       多端口访问靠 bank 仲裁 + skid FIFO 解决 bank conflict。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_scratchpad (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire                          A_CEN,
    input  wire                          A_WEN,
    input  wire [`C3_SCRATCH_ADDR_W-1:0] A_ADDR,
    input  wire [`C3_SCRATCH_DATA_W-1:0] A_D,
    output wire [`C3_SCRATCH_DATA_W-1:0] A_Q,
    input  wire                          B_CEN,
    input  wire [`C3_SCRATCH_ADDR_W-1:0] B_ADDR,
    output wire [`C3_SCRATCH_DATA_W-1:0] B_Q,
    input  wire                          C_CEN,
    input  wire                          C_WEN,
    input  wire [`C3_SCRATCH_ADDR_W-1:0] C_ADDR,
    input  wire [`C3_SCRATCH_DATA_W-1:0] C_D,
    output wire [`C3_SCRATCH_DATA_W-1:0] C_Q,
    output wire [`C3_BANK_AW-1:0]        BANK_SEL,
    output wire                          SP_BUSY,
    output wire                          SP_ECC_ERR
);

    parameter SP_MODE = `C3_BANK_MODE_RW;

    genvar b;
    genvar p;
    genvar q;

    wire [`C3_SCRATCH_DATA_W-1:0] bank_rdata_a [0:`C3_BANK_NUM-1];
    wire [`C3_SCRATCH_DATA_W-1:0] bank_aq_a    [0:`C3_BANK_NUM-1];
    wire                          bank_busy_a  [0:`C3_BANK_NUM-1];
    wire                          bank_err_a   [0:`C3_BANK_NUM-1];
    wire [(`C3_BANK_NUM*`C3_SLICE_NUM)-1:0] arb_busy_vec_w;
    wire [`C3_BANK_NUM-1:0]       arb_req_vec_w [0:`C3_SLICE_NUM-1];

    wire [`C3_SCRATCH_DATA_W-1:0] spare_rdata_w;
    wire [`C3_SCRATCH_DATA_W-1:0] spare_aq_w;
    wire                          spare_busy_w;
    wire                          spare_err_w;
    wire [`C3_SCRATCH_DATA_W-1:0] fifo_rdata_w;
    wire                          fifo_full_w;
    wire                          fifo_empty_w;
    wire                          fifo_err_w;
    wire [`C3_FIFO_CNT_W-1:0]     fifo_cnt_w;

    assign BANK_SEL   = A_ADDR[`C3_SCRATCH_MSB:`C3_BANK_ADDR_W];
    assign A_Q        = bank_aq_a[0] | bank_aq_a[1] | bank_aq_a[2] | bank_aq_a[3];
    assign B_Q        = bank_rdata_a[0] | bank_rdata_a[1] | bank_rdata_a[2] | bank_rdata_a[3];
    assign C_Q        = spare_rdata_w ^ fifo_rdata_w;
    assign SP_BUSY    = bank_busy_a[0] | bank_busy_a[1] | bank_busy_a[2] | bank_busy_a[3] |
                        (|arb_busy_vec_w) | spare_busy_w | fifo_full_w;
    assign SP_ECC_ERR = bank_err_a[0] | bank_err_a[1] | bank_err_a[2] | bank_err_a[3] |
                        spare_err_w | fifo_err_w;

    generate
        for (q = 0; q < `C3_SLICE_NUM; q = q + 1) begin : g_req
            assign arb_req_vec_w[q] = {`C3_BANK_NUM{A_CEN | C_CEN}};
        end
    endgenerate

    generate
        for (b = 0; b < `C3_BANK_NUM; b = b + 1) begin : g_bank
            wire [`C3_BANK_ADDR_W-1:0]    bank_addr_w;
            wire [`C3_SCRATCH_DATA_W-1:0] bank_wdata_w;
            wire                          bank_cen_w;
            wire                          bank_wen_w;

            assign bank_cen_w  = (A_CEN & (BANK_SEL == b));
            assign bank_wen_w  = A_WEN | C_WEN;
            assign bank_addr_w = A_ADDR[`C3_BANK_ADDR_W-1:0];
            assign bank_wdata_w = (|BANK_SEL) ? A_D : C_D;

            // bank：参数覆盖 #( .BANK_ID(b), .BANK_AW(...) )
            case3_scratch_bank #(
                .BANK_ID   (b),
                .BANK_AW   (`C3_BANK_AW),
                .BANK_MODE (`C3_BANK_MODE_RW)
            ) u_bank[b] (
                .CLK        (CLK),
                .RST_N      (RST_N),
                .BANK_CEN   (bank_cen_w),
                .BANK_WEN   (bank_wen_w),
                .BANK_ADDR  (bank_addr_w),
                .BANK_WDATA (bank_wdata_w),
                .BANK_RDATA (bank_rdata_a[b]),
                .BANK_AQ    (bank_aq_a[b]),
                .BANK_BUSY  (bank_busy_a[b]),
                .BANK_ERR   (bank_err_a[b])
            );

            for (p = 0; p < `C3_SLICE_NUM; p = p + 1) begin : g_port
                wire [`C3_BANK_AW-1:0]  arb_sel_w;
                wire                    arb_busy_w;
                wire [`C3_BANK_NUM-1:0] arb_grant_w;
                wire                    arb_clk_w;
                wire [`C3_BANK_AW-1:0]  port_id_w;

                assign port_id_w = b;

                case3_scratch_arb u_port_arb[b][p] (
                    .CLK       (CLK),
                    .RST_N     (RST_N),
                    .REQ_VEC   (arb_req_vec_w[p]),
                    .PORT_ID   (port_id_w),
                    .GRANT_VEC (arb_grant_w),
                    .ARB_SEL   (arb_sel_w),
                    .ARB_BUSY  (arb_busy_w),
                    .ARB_CLK   (arb_clk_w)
                );

                assign arb_busy_vec_w[(b*`C3_SLICE_NUM)+p] = arb_busy_w;
            end
        end
    endgenerate

    // 冗余 / 修复 bank：显式实例 + defparam 参数定制
    case3_scratch_bank u_bank_spare (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .BANK_CEN   (A_CEN & (~BANK_SEL[0])),
        .BANK_WEN   (A_WEN),
        .BANK_ADDR  (A_ADDR[`C3_BANK_ADDR_W-1:0]),
        .BANK_WDATA (A_D),
        .BANK_RDATA (spare_rdata_w),
        .BANK_AQ    (spare_aq_w),
        .BANK_BUSY  (spare_busy_w),
        .BANK_ERR   (spare_err_w)
    );

    defparam u_bank_spare.BANK_ID   = `C3_BANK_NUM;
    defparam u_bank_spare.BANK_AW   = `C3_BANK_AW;
    defparam u_bank_spare.BANK_MODE = `C3_BANK_MODE_REPAIR;

    // 读回 FIFO（跨到 lane 侧）
    case3_sync_fifo u_rd_fifo (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .WR_EN      (A_CEN & A_WEN),
        .WR_DATA    (A_D),
        .RD_EN      (B_CEN),
        .RD_DATA    (fifo_rdata_w),
        .FIFO_FULL  (fifo_full_w),
        .FIFO_EMPTY (fifo_empty_w),
        .FIFO_CNT   (fifo_cnt_w),
        .FIFO_ERR   (fifo_err_w)
    );

endmodule
