//==========================================================================
//  case1_apb_regfile.v
//  16 × 32bit APB 寄存器堆（RAM_DP 双口实现）+ 外设叶子选择
//
//  A 口：APB 写/读（PSEL/PENABLE 产生的写使能）；
//  B 口：外设逻辑侧的寄存器读数（REG_ADDR/REG_RDATA）。
//  按 parameter PERIPH_TYPE 用 generate-case 只选通一个外设叶子寄存器组：
//  UART / TIMER / GPIO / SPI / WATCHDOG / DMA_APB —— 六个叶子各自
//  驱动一组独立的读数据线，最后按 PERIPH_TYPE 回选。
//
//  Ref: APB 外设寄存器堆（RAM_DP 实现的双口 regfile）+
//       generate-case 选择外设类型的标准写法。
//==========================================================================
`include "case1_define.v"

module case1_apb_regfile (
    input  wire                          PCLK,
    input  wire                          PRESETn,
    input  wire [`C1_APB_ADDR_W-1:0]     PADDR,
    input  wire                          PSEL,
    input  wire                          PENABLE,
    input  wire                          PWRITE,
    input  wire [`C1_APB_DATA_W-1:0]     PWDATA,
    input  wire [`C1_APB_STRB_W-1:0]     PSTRB,
    output wire [`C1_APB_DATA_W-1:0]     PRDATA,
    output wire                          PREADY,
    output wire                          PSLVERR,
    output wire                          REGFILE_BUSY,
    output wire [`C1_PERIPH_TYPE_W-1:0]  PERIPH_ID,
    output wire [`C1_MON_CNT_W-1:0]      REG_TXN_CNT
);

    parameter PERIPH_TYPE = `C1_PERIPH_UART;
    parameter REG_NUM     = `C1_REG_NUM;

    //------------------------------------------------------------------
    // 寄存器索引与读写使能
    //------------------------------------------------------------------
    wire [`C1_REG_ADDR_W-1:0] reg_index;
    wire [`C1_REG_DATA_W-1:0] reg_wdata;
    wire [`C1_REG_DATA_W-1:0] reg_rdata;
    wire                      reg_wr_en;
    wire                      reg_rd_en;
    wire [`C1_REG_ADDR_W-1:0] reg_addr;
    wire                      reg_hi_sel;
    wire                      pwrite_n;

    assign reg_index = PADDR[`C1_REG_ADDR_W-1:0];
    assign reg_addr  = reg_index;
    assign reg_wdata = PWDATA;
    assign reg_wr_en = PSEL & PENABLE & PWRITE;
    assign pwrite_n  = ~PWRITE;
    assign reg_rd_en = PSEL & PENABLE & pwrite_n;
    assign reg_hi_sel = reg_index[`C1_REG_ADDR_W-1];

    //------------------------------------------------------------------
    // 寄存器堆本体：RAM_DP（库单元叶子，位置连接）
    //------------------------------------------------------------------
    wire [`C1_RAM_ADDR_W-1:0] mem_a_addr;
    wire [`C1_RAM_ADDR_W-1:0] mem_b_addr;
    wire [`C1_RAM_DATA_W-1:0] mem_a_q;
    wire [`C1_RAM_DATA_W-1:0] mem_b_q;
    wire [`C1_RAM_DATA_W-1:0] mem_a_d;
    wire [`C1_RAM_DATA_W-1:0] mem_b_d;

    assign mem_a_addr = {{(`C1_RAM_ADDR_W-`C1_REG_ADDR_W){1'b0}}, reg_index};
    assign mem_b_addr = {{(`C1_RAM_ADDR_W-`C1_REG_ADDR_W){1'b0}}, reg_addr};
    assign mem_a_d    = reg_wdata;
    assign mem_b_d    = {`C1_RAM_DATA_W{1'b0}};

    RAM_DP u_reg_mem (PCLK,
                      ~PSEL, ~reg_wr_en, mem_a_addr, mem_a_d, mem_a_q,
                      ~PSEL, 1'b1, mem_b_addr, mem_b_d, mem_b_q);

    //------------------------------------------------------------------
    // 外设叶子选择（generate-case：六个叶子各挂一组独立读数据线）
    //------------------------------------------------------------------
    wire [`C1_REG_DATA_W-1:0] uart_rdata;
    wire [`C1_REG_DATA_W-1:0] timer_rdata;
    wire [`C1_REG_DATA_W-1:0] gpio_rdata;
    wire [`C1_REG_DATA_W-1:0] spi_rdata;
    wire [`C1_REG_DATA_W-1:0] wdt_rdata;
    wire [`C1_REG_DATA_W-1:0] dma_rdata;
    wire [`C1_MON_CNT_W-1:0]  uart_txn;
    wire [`C1_MON_CNT_W-1:0]  timer_txn;
    wire [`C1_MON_CNT_W-1:0]  gpio_txn;
    wire [`C1_MON_CNT_W-1:0]  spi_txn;
    wire [`C1_MON_CNT_W-1:0]  wdt_txn;
    wire [`C1_MON_CNT_W-1:0]  dma_txn;
    wire                      uart_irq;
    wire                      timer_irq;
    wire                      gpio_irq;
    wire                      spi_irq;
    wire                      wdt_irq;
    wire                      dma_irq;

    wire [`C1_REG_DATA_W-1:0] periph_rdata;
    wire [`C1_MON_CNT_W-1:0]  periph_txn;
    wire                      periph_irq;

    generate
        case (PERIPH_TYPE)
            `C1_PERIPH_UART: begin : g_periph_uart
                case1_uart_regs #(
                    .BASE_ADDR (`C1_PERIPH_BASE),
                    .OVERSAMPLE (16)
                ) u_uart_regs (
                    .PCLK        (PCLK),
                    .PRESETn     (PRESETn),
                    .REG_ADDR    (reg_addr),
                    .REG_WDATA   (reg_wdata),
                    .REG_WR_EN   (reg_wr_en),
                    .REG_RD_EN   (reg_rd_en),
                    .REG_RDATA   (uart_rdata),
                    .REG_TXN_CNT (uart_txn),
                    .REG_IRQ     (uart_irq)
                );
                assign periph_rdata = uart_rdata;
                assign periph_txn   = uart_txn;
                assign periph_irq   = uart_irq;
            end
            `C1_PERIPH_TIMER: begin : g_periph_timer
                case1_timer_regs #(
                    .BASE_ADDR (`C1_PERIPH_BASE)
                ) u_timer_regs (
                    .PCLK        (PCLK),
                    .PRESETn     (PRESETn),
                    .REG_ADDR    (reg_addr),
                    .REG_WDATA   (reg_wdata),
                    .REG_WR_EN   (reg_wr_en),
                    .REG_RD_EN   (reg_rd_en),
                    .REG_RDATA   (timer_rdata),
                    .REG_TXN_CNT (timer_txn),
                    .REG_IRQ     (timer_irq)
                );
                assign periph_rdata = timer_rdata;
                assign periph_txn   = timer_txn;
                assign periph_irq   = timer_irq;
            end
            `C1_PERIPH_GPIO: begin : g_periph_gpio
                case1_gpio_regs #(
                    .BASE_ADDR (`C1_PERIPH_BASE)
                ) u_gpio_regs (
                    .PCLK        (PCLK),
                    .PRESETn     (PRESETn),
                    .REG_ADDR    (reg_addr),
                    .REG_WDATA   (reg_wdata),
                    .REG_WR_EN   (reg_wr_en),
                    .REG_RD_EN   (reg_rd_en),
                    .REG_RDATA   (gpio_rdata),
                    .REG_TXN_CNT (gpio_txn),
                    .REG_IRQ     (gpio_irq)
                );
                assign periph_rdata = gpio_rdata;
                assign periph_txn   = gpio_txn;
                assign periph_irq   = gpio_irq;
            end
            `C1_PERIPH_SPI: begin : g_periph_spi
                case1_spi_regs #(
                    .BASE_ADDR (`C1_PERIPH_BASE)
                ) u_spi_regs (
                    .PCLK        (PCLK),
                    .PRESETn     (PRESETn),
                    .REG_ADDR    (reg_addr),
                    .REG_WDATA   (reg_wdata),
                    .REG_WR_EN   (reg_wr_en),
                    .REG_RD_EN   (reg_rd_en),
                    .REG_RDATA   (spi_rdata),
                    .REG_TXN_CNT (spi_txn),
                    .REG_IRQ     (spi_irq)
                );
                assign periph_rdata = spi_rdata;
                assign periph_txn   = spi_txn;
                assign periph_irq   = spi_irq;
            end
            `C1_PERIPH_WDT: begin : g_periph_wdt
                case1_watchdog_regs #(
                    .BASE_ADDR (`C1_PERIPH_BASE)
                ) u_watchdog_regs (
                    .PCLK        (PCLK),
                    .PRESETn     (PRESETn),
                    .REG_ADDR    (reg_addr),
                    .REG_WDATA   (reg_wdata),
                    .REG_WR_EN   (reg_wr_en),
                    .REG_RD_EN   (reg_rd_en),
                    .REG_RDATA   (wdt_rdata),
                    .REG_TXN_CNT (wdt_txn),
                    .REG_IRQ     (wdt_irq)
                );
                assign periph_rdata = wdt_rdata;
                assign periph_txn   = wdt_txn;
                assign periph_irq   = wdt_irq;
            end
            `C1_PERIPH_DMA: begin : g_periph_dma
                case1_dma_apb_regs #(
                    .BASE_ADDR (`C1_PERIPH_BASE)
                ) u_dma_apb_regs (
                    .PCLK        (PCLK),
                    .PRESETn     (PRESETn),
                    .REG_ADDR    (reg_addr),
                    .REG_WDATA   (reg_wdata),
                    .REG_WR_EN   (reg_wr_en),
                    .REG_RD_EN   (reg_rd_en),
                    .REG_RDATA   (dma_rdata),
                    .REG_TXN_CNT (dma_txn),
                    .REG_IRQ     (dma_irq)
                );
                assign periph_rdata = dma_rdata;
                assign periph_txn   = dma_txn;
                assign periph_irq   = dma_irq;
            end
            default: begin : g_periph_none
                assign periph_rdata = mem_b_q;
                assign periph_txn   = {`C1_MON_CNT_W{1'b0}};
                assign periph_irq   = 1'b0;
            end
        endcase
    endgenerate

    //------------------------------------------------------------------
    // APB 响应
    //------------------------------------------------------------------
    assign PRDATA       = reg_hi_sel ? mem_b_q : periph_rdata;
    assign PREADY       = PSEL & PENABLE;
    assign PSLVERR      = (PERIPH_TYPE == `C1_PERIPH_NONE);
    assign REGFILE_BUSY = PSEL;
    assign PERIPH_ID    = PERIPH_TYPE;
    assign REG_TXN_CNT  = periph_txn;

endmodule
