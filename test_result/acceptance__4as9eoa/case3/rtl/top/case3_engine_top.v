//==========================================================================
//  case3_engine_top.v
//  case3 顶层：SIMD 计算引擎。2 cluster x 2 slice x 4 lane，
//  scratchpad + DMA + 配置寄存器 + 性能计数。
//
//  Ref: 小型 NPU/DSP 加速器 top（Vision P6 / NVDLA 大核 + 系统控制块的组织方式）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_engine_top (
    input  wire                        CLK,
    input  wire                        RST_N,
    input  wire [`C3_CFG_ADDR_W-1:0]   CFG_ADDR,
    input  wire                        CFG_WR,
    input  wire                        CFG_RD,
    input  wire [`C3_CFG_DATA_W-1:0]   CFG_WDATA,
    output wire [`C3_CFG_DATA_W-1:0]   CFG_RDATA,
    output wire                        CFG_READY,
    input  wire                        XFER_REQ,
    input  wire [`C3_XFER_LEN_W-1:0]   XFER_LEN,
    output wire                        XFER_ACK,
    output wire                        XFER_DONE,
    output wire [`C3_CNT_W-1:0]        PERF_TOTAL,
    output wire                        PERF_BUSY,
    output wire                        ENGINE_IDLE
);

    parameter ENGINE_ID   = 0;
    parameter ENGINE_PIPE = `C3_PIPE_STAGE;

    // ---- 配置 / 状态 ----
    wire [`C3_CFG_DATA_W-1:0] cfg_ctrl;
    wire [`C3_CFG_DATA_W-1:0] cfg_mask;
    wire [`C3_ADDR_W-1:0]     cfg_base;
    wire                      cfg_go;
    wire                      cfg_busy;
    wire                      cfg_clk;
    wire [`C3_MON_SEL_W-1:0]  mon_sel;

    // ---- 计算阵列 ----
    wire [`C3_STATUS_W-1:0]   cl_status;
    wire [`C3_CNT_W-1:0]      cl_cycles;
    wire                      cl_busy;
    wire [`C3_XFER_ID_W-1:0]  xfer_id;
    wire                      xfer_valid;

    // ---- 描述符 / 事务 ----
    wire [`C3_DESC_W-1:0]     desc_data;
    wire                      desc_valid;
    wire                      desc_ready;
    wire [`C3_TXN_ID_W-1:0]   txn_id;

    // ---- scratchpad 端口 A（阵列写） ----
    wire                      sp_a_cen;
    wire                      sp_a_wen;
    wire [`C3_SCRATCH_ADDR_W-1:0] sp_a_addr;
    wire [`C3_SCRATCH_DATA_W-1:0] sp_a_d;
    wire [`C3_SCRATCH_DATA_W-1:0] sp_a_q;

    // ---- scratchpad 端口 B（阵列读） ----
    wire                      sp_b_cen;
    wire [`C3_SCRATCH_ADDR_W-1:0] sp_b_addr;
    wire [`C3_SCRATCH_DATA_W-1:0] sp_b_q;

    // ---- scratchpad 端口 C（DMA） ----
    wire                      sp_c_cen;
    wire                      sp_c_wen;
    wire [`C3_SCRATCH_ADDR_W-1:0] sp_c_addr;
    wire [`C3_SCRATCH_DATA_W-1:0] sp_c_d;
    wire [`C3_SCRATCH_DATA_W-1:0] sp_c_q;

    wire [`C3_BANK_AW-1:0]    sp_bank_sel;
    wire                      sp_busy;
    wire                      sp_ecc_err;

    // ---- DMA ----
    wire                      dma_busy;

    assign mon_sel     = CFG_ADDR[`C3_MON_SEL_W-1:0];
    assign PERF_TOTAL  = cl_cycles | {{(`C3_CNT_W-`C3_XFER_ID_W){1'b0}}, xfer_id} |
                         {`C3_CNT_W{xfer_valid}};
    assign PERF_BUSY   = cl_busy | dma_busy | cfg_busy | sp_busy;
    assign ENGINE_IDLE = ~(cl_busy | dma_busy | cfg_busy | sp_busy | sp_ecc_err) &
                         (~(|sp_bank_sel));

    // 计算簇阵列
    case3_cluster_array u_cluster_array (
        .CLK          (CLK),
        .RST_N        (RST_N),
        .ARRAY_CLK    (cfg_clk),
        .CFG_CTRL     (cfg_ctrl),
        .CFG_MASK     (cfg_mask),
        .CFG_BASE     (cfg_base),
        .CFG_GO       (cfg_go),
        .MON_SEL      (mon_sel),
        .DESC_DATA    (desc_data),
        .DESC_VALID   (desc_valid),
        .DESC_READY   (desc_ready),
        .TXN_ID       (txn_id),
        .CL_STATUS    (cl_status),
        .CL_CYCLES    (cl_cycles),
        .CL_BUSY      (cl_busy),
        .XFER_ID      (xfer_id),
        .XFER_VALID   (xfer_valid),
        .SP_A_CEN     (sp_a_cen),
        .SP_A_WEN     (sp_a_wen),
        .SP_A_ADDR    (sp_a_addr),
        .SP_A_D       (sp_a_d),
        .SP_A_Q       (sp_a_q),
        .SP_B_CEN     (sp_b_cen),
        .SP_B_ADDR    (sp_b_addr),
        .SP_B_Q       (sp_b_q)
    );

    // 片上 scratchpad
    case3_scratchpad u_scratchpad (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .A_CEN      (sp_a_cen),
        .A_WEN      (sp_a_wen),
        .A_ADDR     (sp_a_addr),
        .A_D        (sp_a_d),
        .A_Q        (sp_a_q),
        .B_CEN      (sp_b_cen),
        .B_ADDR     (sp_b_addr),
        .B_Q        (sp_b_q),
        .C_CEN      (sp_c_cen),
        .C_WEN      (sp_c_wen),
        .C_ADDR     (sp_c_addr),
        .C_D        (sp_c_d),
        .C_Q        (sp_c_q),
        .BANK_SEL   (sp_bank_sel),
        .SP_BUSY    (sp_busy),
        .SP_ECC_ERR (sp_ecc_err)
    );

    // DMA 引擎
    case3_dma_engine u_dma (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .XFER_REQ   (XFER_REQ),
        .XFER_LEN   (XFER_LEN),
        .CFG_CTRL   (cfg_ctrl),
        .XFER_ACK   (XFER_ACK),
        .XFER_DONE  (XFER_DONE),
        .DESC_DATA  (desc_data),
        .DESC_VALID (desc_valid),
        .DESC_READY (desc_ready),
        .TXN_ID     (txn_id),
        .DMA_BUSY   (dma_busy),
        .SP_C_CEN   (sp_c_cen),
        .SP_C_WEN   (sp_c_wen),
        .SP_C_ADDR  (sp_c_addr),
        .SP_C_D     (sp_c_d),
        .SP_C_Q     (sp_c_q)
    );

    // 配置寄存器组
    case3_config_regs u_cfg (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .CFG_ADDR  (CFG_ADDR),
        .CFG_WR    (CFG_WR),
        .CFG_RD    (CFG_RD),
        .CFG_WDATA (CFG_WDATA),
        .CFG_RDATA (CFG_RDATA),
        .CFG_READY (CFG_READY),
        .CL_STATUS (cl_status),
        .CL_CYCLES (cl_cycles),
        .CFG_CTRL  (cfg_ctrl),
        .CFG_MASK  (cfg_mask),
        .CFG_BASE  (cfg_base),
        .CFG_GO    (cfg_go),
        .CFG_BUSY  (cfg_busy),
        .CFG_CLK   (cfg_clk)
    );

endmodule
