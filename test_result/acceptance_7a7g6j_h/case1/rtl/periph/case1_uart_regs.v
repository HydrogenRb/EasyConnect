//==========================================================================
//  case1_uart_regs.v
//  UART 寄存器组（叶子模块，内部无任何例化）
//
//  寄存器：CTRL / BAUD / STATUS / TXDATA / RXDATA / INT_EN / INT_STAT
//  含波特率分频计数、TX/RX FIFO 水位与中断汇聚。
//
//  Ref: 16550/PL011 风格的 UART 寄存器组（APB 外设叶子）。
//==========================================================================
`include "case1_define.v"

module case1_uart_regs (
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

    parameter BASE_ADDR  = `C1_PERIPH_BASE;
    parameter OVERSAMPLE = 16;

    reg [`C1_REG_DATA_W-1:0]     reg_ctrl;
    reg [`C1_UART_BAUD_W-1:0]    reg_baud;
    reg [`C1_REG_DATA_W-1:0]     reg_int_en;
    reg [`C1_REG_DATA_W-1:0]     reg_int_stat;
    reg [`C1_UART_FIFO_W-1:0]    tx_fifo [0:`C1_FIFO_DEPTH-1];
    reg [`C1_UART_FIFO_W-1:0]    rx_fifo [0:`C1_FIFO_DEPTH-1];
    reg [`C1_FIFO_PTR_W-1:0]     tx_wptr;
    reg [`C1_FIFO_PTR_W-1:0]     rx_wptr;
    reg [`C1_UART_OVS_W-1:0]     ovs_cnt;
    reg [`C1_UART_BAUD_W-1:0]    baud_cnt;
    reg [`C1_FIFO_CNT_W-1:0]     tx_level;
    reg [`C1_FIFO_CNT_W-1:0]     rx_level;
    reg                          uart_busy;
    integer                      i;

    initial begin
        for (i = 0; i < `C1_FIFO_DEPTH; i = i + 1) begin
            tx_fifo[i] = {`C1_UART_FIFO_W{1'b0}};
            rx_fifo[i] = {`C1_UART_FIFO_W{1'b0}};
        end
    end

    //------------------------------------------------------------------
    // 波特率分频
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            baud_cnt <= {`C1_UART_BAUD_W{1'b0}};
            ovs_cnt  <= {`C1_UART_OVS_W{1'b0}};
            uart_busy <= 1'b0;
        end else if (reg_ctrl[0] == 1'b1) begin
            if (baud_cnt >= reg_baud) begin
                baud_cnt <= {`C1_UART_BAUD_W{1'b0}};
                ovs_cnt  <= ovs_cnt + 1'b1;
                uart_busy <= ~uart_busy;
            end else begin
                baud_cnt <= baud_cnt + 1'b1;
            end
        end else begin
            baud_cnt  <= {`C1_UART_BAUD_W{1'b0}};
            uart_busy <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // 寄存器读写 + 中断汇聚
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_ctrl     <= {`C1_REG_DATA_W{1'b0}};
            reg_baud     <= {`C1_UART_BAUD_W{1'b0}};
            reg_int_en   <= {`C1_REG_DATA_W{1'b0}};
            reg_int_stat <= {`C1_REG_DATA_W{1'b0}};
            tx_wptr      <= {`C1_FIFO_PTR_W{1'b0}};
            rx_wptr      <= {`C1_FIFO_PTR_W{1'b0}};
            tx_level     <= {`C1_FIFO_CNT_W{1'b0}};
            rx_level     <= {`C1_FIFO_CNT_W{1'b0}};
            REG_RDATA    <= {`C1_REG_DATA_W{1'b0}};
            REG_TXN_CNT  <= {`C1_MON_CNT_W{1'b0}};
            REG_IRQ      <= 1'b0;
        end else begin
            if (REG_WR_EN) begin
                REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                case (REG_ADDR[`C1_PERIPH_TYPE_W-1:0])
                    4'h0: reg_ctrl   <= REG_WDATA;
                    4'h1: reg_baud   <= REG_WDATA[`C1_UART_BAUD_W-1:0];
                    4'h2: begin
                        tx_fifo[tx_wptr] <= REG_WDATA[`C1_UART_FIFO_W-1:0];
                        tx_wptr          <= tx_wptr + 1'b1;
                        tx_level         <= tx_level + 1'b1;
                    end
                    4'h3: reg_int_en <= REG_WDATA;
                    default: reg_int_en <= reg_int_en;
                endcase
            end else if (REG_RD_EN) begin
                REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                case (REG_ADDR[`C1_PERIPH_TYPE_W-1:0])
                    4'h0: REG_RDATA <= reg_ctrl;
                    4'h1: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_UART_BAUD_W){1'b0}}, reg_baud};
                    4'h4: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_UART_FIFO_W){1'b0}},
                                        rx_fifo[rx_wptr]};
                    4'h5: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_FIFO_CNT_W){1'b0}}, rx_level};
                    4'h6: REG_RDATA <= reg_int_stat;
                    default: REG_RDATA <= reg_ctrl;
                endcase
            end

            if (uart_busy && (rx_level < `C1_FIFO_DEPTH)) begin
                rx_level <= rx_level + 1'b1;
                rx_wptr  <= rx_wptr + 1'b1;
            end

            reg_int_stat[0] <= (rx_level >= `C1_FIFO_AFULL_TH);
            reg_int_stat[1] <= (tx_level <= `C1_FIFO_AEMPTY_TH);
            REG_IRQ         <= |(reg_int_stat & reg_int_en);
        end
    end

endmodule
