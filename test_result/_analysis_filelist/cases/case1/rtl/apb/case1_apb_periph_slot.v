//==========================================================================
//  case1_apb_periph_slot.v
//  一个 APB 从机 slot：4 份外设寄存器组镜像 + FIFO 存储 + 同步 FIFO + 门控
//
//  层次：u_regfile / u_regfile_timer / u_regfile_gpio / u_regfile_spi
//        （case1_apb_regfile ×4，每份镜像对应一类外设，由 PERIPH_TYPE 选择
//         哪一份驱动 APB 响应 —— 这正是 case1 结构清单里
//         "case1_apb_regfile 被 4 个外设各例化一次" 的落点）
//        u_fifo_ram（RAM_SP 存储）/ u_rx_fifo（case1_sync_fifo）/
//        u_gate（case1_clk_gate）/ u_ready_sync[k]（两级同步触发器）
//
//  Ref: 外设 slot 的通用骨架（APB 寄存器堆 + TX/RX FIFO + 门控时钟），
//       与 DesignStart / SoC 外设子系统里的 slot wrapper 一致。
//==========================================================================
`include "case1_define.v"

module case1_apb_periph_slot (
    input  wire                          PCLK,
    input  wire                          PRESETn,
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire [`C1_APB_ADDR_W-1:0]     PADDR,
    input  wire                          PSEL,
    input  wire                          PENABLE,
    input  wire                          PWRITE,
    input  wire [`C1_APB_DATA_W-1:0]     PWDATA,
    input  wire [`C1_APB_STRB_W-1:0]     PSTRB,
    input  wire [`C1_APB_PROT_W-1:0]     PPROT,
    output wire [`C1_APB_DATA_W-1:0]     PRDATA,
    output wire                          PREADY,
    output wire                          PSLVERR,
    output wire                          SLOT_ACTIVE,
    output wire                          CR_RET_VALID,
    output wire [`C1_CR_CNT_W-1:0]       CR_RET_CNT,
    output wire [`C1_MON_CNT_W-1:0]      SLOT_TXN_CNT,
    output wire                          SLOT_IRQ
);

    parameter SLOT_IDX    = 0;
    parameter PERIPH_TYPE = `C1_PERIPH_UART;

    //------------------------------------------------------------------
    // APB 相位译码
    //------------------------------------------------------------------
    wire apb_write;
    wire apb_read;
    wire pwrite_n;

    assign pwrite_n      = ~PWRITE;
    assign apb_write     = PSEL & PENABLE & PWRITE;
    assign apb_read      = PSEL & PENABLE & pwrite_n;
    assign SLOT_ACTIVE   = PSEL | PENABLE;
    assign CR_RET_VALID  = PSEL & PENABLE & PREADY;
    assign CR_RET_CNT    = (CR_RET_VALID) ? {{(`C1_CR_CNT_W-1){1'b0}}, 1'b1}
                                          : {`C1_CR_CNT_W{1'b0}};

    //------------------------------------------------------------------
    // 4 份寄存器组镜像（每类外设一份），PERIPH_TYPE 选择哪份驱动响应
    //------------------------------------------------------------------
    wire [`C1_APB_DATA_W-1:0]    rf_prdata  [0:`C1_APB_SLV_NUM-1];
    wire                         rf_pready  [0:`C1_APB_SLV_NUM-1];
    wire                         rf_pslverr [0:`C1_APB_SLV_NUM-1];
    wire [`C1_MON_CNT_W-1:0]     rf_txn_cnt [0:`C1_APB_SLV_NUM-1];
    wire [`C1_PERIPH_TYPE_W-1:0] rf_id      [0:`C1_APB_SLV_NUM-1];

    reg  [`C1_APB_DATA_W-1:0]    regfile_prdata;
    reg                          regfile_pready;
    reg                          regfile_pslverr;
    reg  [`C1_MON_CNT_W-1:0]     regfile_txn_cnt;
    reg  [`C1_PERIPH_TYPE_W-1:0] periph_id;

    case1_apb_regfile #(
        .PERIPH_TYPE (`C1_PERIPH_UART),
        .REG_NUM     (`C1_REG_NUM)
    ) u_regfile (
        .PCLK          (PCLK),
        .PRESETn       (PRESETn),
        .PADDR         (PADDR),
        .PSEL          (PSEL),
        .PENABLE       (PENABLE),
        .PWRITE        (PWRITE),
        .PWDATA        (PWDATA),
        .PSTRB         (PSTRB),
        .PRDATA        (rf_prdata[0]),
        .PREADY        (rf_pready[0]),
        .PSLVERR       (rf_pslverr[0]),
        .REGFILE_BUSY  (),
        .PERIPH_ID     (rf_id[0]),
        .REG_TXN_CNT   (rf_txn_cnt[0])
    );

    case1_apb_regfile #(
        .PERIPH_TYPE (`C1_PERIPH_TIMER),
        .REG_NUM     (`C1_REG_NUM)
    ) u_regfile_timer (
        .PCLK          (PCLK),
        .PRESETn       (PRESETn),
        .PADDR         (PADDR),
        .PSEL          (PSEL),
        .PENABLE       (PENABLE),
        .PWRITE        (PWRITE),
        .PWDATA        (PWDATA),
        .PSTRB         (PSTRB),
        .PRDATA        (rf_prdata[1]),
        .PREADY        (rf_pready[1]),
        .PSLVERR       (rf_pslverr[1]),
        .REGFILE_BUSY  (),
        .PERIPH_ID     (rf_id[1]),
        .REG_TXN_CNT   (rf_txn_cnt[1])
    );

    case1_apb_regfile #(
        .PERIPH_TYPE (`C1_PERIPH_GPIO),
        .REG_NUM     (`C1_REG_NUM)
    ) u_regfile_gpio (
        .PCLK          (PCLK),
        .PRESETn       (PRESETn),
        .PADDR         (PADDR),
        .PSEL          (PSEL),
        .PENABLE       (PENABLE),
        .PWRITE        (PWRITE),
        .PWDATA        (PWDATA),
        .PSTRB         (PSTRB),
        .PRDATA        (rf_prdata[2]),
        .PREADY        (rf_pready[2]),
        .PSLVERR       (rf_pslverr[2]),
        .REGFILE_BUSY  (),
        .PERIPH_ID     (rf_id[2]),
        .REG_TXN_CNT   (rf_txn_cnt[2])
    );

    case1_apb_regfile #(
        .PERIPH_TYPE (`C1_PERIPH_SPI),
        .REG_NUM     (`C1_REG_NUM)
    ) u_regfile_spi (
        .PCLK          (PCLK),
        .PRESETn       (PRESETn),
        .PADDR         (PADDR),
        .PSEL          (PSEL),
        .PENABLE       (PENABLE),
        .PWRITE        (PWRITE),
        .PWDATA        (PWDATA),
        .PSTRB         (PSTRB),
        .PRDATA        (rf_prdata[3]),
        .PREADY        (rf_pready[3]),
        .PSLVERR       (rf_pslverr[3]),
        .REGFILE_BUSY  (),
        .PERIPH_ID     (rf_id[3]),
        .REG_TXN_CNT   (rf_txn_cnt[3])
    );

    always @(*) begin
        case (PERIPH_TYPE)
            `C1_PERIPH_UART: begin
                regfile_prdata  = rf_prdata[0];
                regfile_pready  = rf_pready[0];
                regfile_pslverr = rf_pslverr[0];
                regfile_txn_cnt = rf_txn_cnt[0];
                periph_id       = rf_id[0];
            end
            `C1_PERIPH_TIMER: begin
                regfile_prdata  = rf_prdata[1];
                regfile_pready  = rf_pready[1];
                regfile_pslverr = rf_pslverr[1];
                regfile_txn_cnt = rf_txn_cnt[1];
                periph_id       = rf_id[1];
            end
            `C1_PERIPH_GPIO: begin
                regfile_prdata  = rf_prdata[2];
                regfile_pready  = rf_pready[2];
                regfile_pslverr = rf_pslverr[2];
                regfile_txn_cnt = rf_txn_cnt[2];
                periph_id       = rf_id[2];
            end
            default: begin
                regfile_prdata  = rf_prdata[3];
                regfile_pready  = rf_pready[3];
                regfile_pslverr = rf_pslverr[3];
                regfile_txn_cnt = rf_txn_cnt[3];
                periph_id       = rf_id[3];
            end
        endcase
    end

    assign PREADY   = regfile_pready;
    assign PSLVERR  = regfile_pslverr;
    assign PRDATA   = regfile_prdata;

    //------------------------------------------------------------------
    // FIFO 存储：RAM_SP（库单元叶子，位置连接）+ case1_sync_fifo
    //------------------------------------------------------------------
    reg  [`C1_FIFO_PTR_W-1:0]  fifo_wptr;
    reg  [`C1_FIFO_PTR_W-1:0]  fifo_rptr;
    wire [`C1_RAM_ADDR_W-1:0]  fifo_ram_addr;
    wire [`C1_RAM_DATA_W-1:0]  fifo_ram_d;
    wire [`C1_RAM_DATA_W-1:0]  fifo_ram_q;
    wire [`C1_RAM_BEN_W-1:0]   fifo_ram_ben;
    wire                       fifo_ram_cen;
    wire                       fifo_ram_wen;

    wire [`C1_CDC_BUS_W-1:0]     fifo_dout;
    wire                         fifo_dout_valid;
    wire                         fifo_din_ready;
    wire [`C1_FIFO_CNT_W-1:0]    fifo_level;
    wire                         fifo_empty;
    wire                         fifo_full;
    wire                         fifo_afull;
    wire                         fifo_ae;

    assign fifo_ram_addr = {{(`C1_RAM_ADDR_W-`C1_FIFO_PTR_W){1'b0}}, fifo_wptr};
    assign fifo_ram_d    = PWDATA;
    assign fifo_ram_ben  = PSTRB;
    assign fifo_ram_cen  = ~apb_write;
    assign fifo_ram_wen  = ~apb_write;

    RAM_SP u_fifo_ram (PCLK, fifo_ram_cen, fifo_ram_wen, fifo_ram_ben,
                       fifo_ram_addr, fifo_ram_d, fifo_ram_q);

    case1_sync_fifo #(
        .DEPTH (`C1_FIFO_DEPTH),
        .ASYNC (1)
    ) u_rx_fifo (
        .CLK          (PCLK),
        .RST_N        (PRESETn),
        .DIN          (PWDATA),
        .DIN_VALID    (apb_write),
        .DIN_READY    (fifo_din_ready),
        .DOUT         (fifo_dout),
        .DOUT_VALID   (fifo_dout_valid),
        .DOUT_READY   (apb_read),
        .FLUSH        (1'b0),
        .FIFO_LEVEL   (fifo_level),
        .FIFO_EMPTY   (fifo_empty),
        .FIFO_FULL    (fifo_full),
        .FIFO_AFULL   (fifo_afull),
        .FIFO_AE      (fifo_ae)
    );

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            fifo_wptr <= {`C1_FIFO_PTR_W{1'b0}};
            fifo_rptr <= {`C1_FIFO_PTR_W{1'b0}};
        end else begin
            if (apb_write && fifo_din_ready) begin
                fifo_wptr <= fifo_wptr + 1'b1;
            end
            if (apb_read && fifo_dout_valid) begin
                fifo_rptr <= fifo_rptr + 1'b1;
            end
        end
    end

    //------------------------------------------------------------------
    // 门控时钟 + 两级同步触发器（for-generate）
    //------------------------------------------------------------------
    wire                      gated_clk;
    wire [`C1_CDC_STAGES:0]   ready_chain;
    reg  [`C1_MON_CNT_W-1:0]  slot_txn_cnt_r;

    assign ready_chain[0] = regfile_pready;
    assign SLOT_IRQ       = fifo_afull | fifo_full;

    case1_clk_gate u_gate (PCLK, PRESETn, SLOT_ACTIVE, 1'b0, gated_clk);

    genvar k;
    generate
        for (k = 0; k < `C1_CDC_STAGES; k = k + 1) begin : g_ready_sync
            case1_sync_ff u_ready_sync[k] (HCLK, HRESETn,
                                           ready_chain[k], ready_chain[k+1]);
        end
    endgenerate

    always @(posedge gated_clk or negedge PRESETn) begin
        if (!PRESETn) begin
            slot_txn_cnt_r <= {`C1_MON_CNT_W{1'b0}};
        end else if (apb_write || apb_read) begin
            slot_txn_cnt_r <= slot_txn_cnt_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
        end
    end

    assign SLOT_TXN_CNT = slot_txn_cnt_r + regfile_txn_cnt;

endmodule
