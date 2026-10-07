//==========================================================================
//  case1_spi_regs.v
//  SPI 主控寄存器组（叶子模块，内部无任何例化）
//
//  寄存器：CTRL / CLK_DIV / STATUS / TXDATA / RXDATA / CS_CTRL
//  含移位引擎、时钟分频与 FIFO 水位统计。
//
//  Ref: ARM PrimeCell PL022 风格的 SPI 寄存器组（APB 外设叶子）。
//==========================================================================
`include "case1_define.v"

module case1_spi_regs (
    input  wire                          PCLK,
    input  wire                          PRESETn,
    input  wire [`C1_REG_ADDR_W-1:0]     REG_ADDR,
    input  wire [`C1_REG_DATA_W-1:0]     REG_WDATA,
    input  wire                          REG_WR_EN,
    input  wire                          REG_RD_EN,
    output reg  [`C1_REG_DATA_W-1:0]     REG_RDATA,
    output reg  [`C1_MON_CNT_W-1:0]      REG_TXN_CNT,
    output reg                           REG_IRQ
);

    parameter BASE_ADDR = `C1_PERIPH_BASE;

    reg [`C1_REG_DATA_W-1:0]  reg_ctrl;
    reg [`C1_SPI_CLK_DIV_W-1:0] reg_clk_div;
    reg [`C1_REG_DATA_W-1:0]  reg_cs;
    reg [`C1_REG_DATA_W-1:0]  reg_int_stat;
    reg [`C1_SPI_FIFO_W-1:0]  shift_reg;
    reg [`C1_SPI_FIFO_W-1:0]  rx_shadow;
    reg [`C1_SPI_CLK_DIV_W-1:0] div_cnt;
    reg [`C1_SPI_MODE_W-1:0]  mode_r;
    reg [`C1_FIFO_CNT_W-1:0]  tx_level;
    reg [`C1_FIFO_CNT_W-1:0]  rx_level;
    reg                       sclk_r;
    reg                       spi_busy;

    //------------------------------------------------------------------
    // 时钟分频与移位引擎
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            div_cnt    <= {`C1_SPI_CLK_DIV_W{1'b0}};
            sclk_r     <= 1'b0;
            shift_reg  <= {`C1_SPI_FIFO_W{1'b0}};
            rx_shadow  <= {`C1_SPI_FIFO_W{1'b0}};
            spi_busy   <= 1'b0;
            mode_r     <= {`C1_SPI_MODE_W{1'b0}};
        end else if (reg_ctrl[0] == 1'b1) begin
            if (div_cnt >= reg_clk_div) begin
                div_cnt   <= {`C1_SPI_CLK_DIV_W{1'b0}};
                sclk_r    <= ~sclk_r;
                shift_reg <= {shift_reg[`C1_SPI_FIFO_W-2:0], rx_shadow[0]};
                rx_shadow <= {rx_shadow[`C1_SPI_FIFO_W-2:0], shift_reg[`C1_SPI_FIFO_W-1]};
                spi_busy  <= 1'b1;
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end
        end else begin
            div_cnt  <= {`C1_SPI_CLK_DIV_W{1'b0}};
            spi_busy <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // 寄存器读写
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_ctrl     <= {`C1_REG_DATA_W{1'b0}};
            reg_clk_div  <= {`C1_SPI_CLK_DIV_W{1'b0}};
            reg_cs       <= {`C1_REG_DATA_W{1'b0}};
            reg_int_stat <= {`C1_REG_DATA_W{1'b0}};
            tx_level     <= {`C1_FIFO_CNT_W{1'b0}};
            rx_level     <= {`C1_FIFO_CNT_W{1'b0}};
            REG_RDATA    <= {`C1_REG_DATA_W{1'b0}};
            REG_TXN_CNT  <= {`C1_MON_CNT_W{1'b0}};
            REG_IRQ      <= 1'b0;
        end else begin
            if (REG_WR_EN) begin
                REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                case (REG_ADDR[`C1_PERIPH_TYPE_W-1:0])
                    4'h0: begin
                        reg_ctrl    <= REG_WDATA;
                        mode_r      <= REG_WDATA[`C1_SPI_MODE_W-1:0];
                    end
                    4'h1: reg_clk_div <= REG_WDATA[`C1_SPI_CLK_DIV_W-1:0];
                    4'h2: begin
                        reg_cs       <= REG_WDATA;
                        reg_int_stat <= {`C1_REG_DATA_W{1'b0}};
                    end
                    4'h3: begin
                        tx_level <= tx_level + 1'b1;
                        reg_cs[0] <= 1'b0;
                    end
                    default: reg_ctrl <= reg_ctrl;
                endcase
            end else if (REG_RD_EN) begin
                REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                case (REG_ADDR[`C1_PERIPH_TYPE_W-1:0])
                    4'h0: REG_RDATA <= reg_ctrl;
                    4'h1: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_SPI_CLK_DIV_W){1'b0}},
                                        reg_clk_div};
                    4'h4: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_SPI_FIFO_W){1'b0}}, rx_shadow};
                    4'h5: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_FIFO_CNT_W){1'b0}}, tx_level};
                    4'h6: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_FIFO_CNT_W){1'b0}}, rx_level};
                    default: REG_RDATA <= reg_cs;
                endcase
            end

            if (spi_busy) begin
                rx_level <= rx_level + 1'b1;
                reg_cs[0] <= 1'b1;
            end

            reg_int_stat[0] <= (rx_level >= `C1_FIFO_AFULL_TH);
            reg_int_stat[1] <= spi_busy;
            REG_IRQ         <= (reg_int_stat[0] | reg_int_stat[1]) & reg_ctrl[1];
        end
    end

endmodule
