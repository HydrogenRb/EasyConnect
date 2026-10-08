//==========================================================================
//  case1_watchdog_regs.v
//  Watchdog 寄存器组（叶子模块，内部无任何例化）
//
//  寄存器：WDOGLOAD / WDOGVALUE / WDOGCONTROL / WDOGRIS / WDOGMIS / WDOGLOCK
//  含两段式（超时 + 中断）计数与写保护解锁序列。
//
//  Ref: ARM SP805 风格的 watchdog 寄存器组（APB 外设叶子）。
//==========================================================================
`include "case1_define.v"

module case1_watchdog_regs (
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

    reg [`C1_WDT_CNT_W-1:0]   reg_load;
    reg [`C1_WDT_CNT_W-1:0]   reg_value;
    reg [`C1_REG_DATA_W-1:0]  reg_control;
    reg                       reg_ris;
    reg                       reg_mis;
    reg                       reg_locked;
    reg [`C1_WDT_KEY_W-1:0]   unlock_key;
    reg [`C1_CR_TIMEOUT_W-1:0] prescale_cnt;
    reg                       first_timeout;
    reg                       second_timeout;

    //------------------------------------------------------------------
    // 两段式超时计数
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_value      <= {`C1_WDT_CNT_W{1'b0}};
            prescale_cnt   <= {`C1_CR_TIMEOUT_W{1'b0}};
            first_timeout  <= 1'b0;
            second_timeout <= 1'b0;
            reg_ris        <= 1'b0;
        end else if (reg_control[0] == 1'b1) begin
            if (prescale_cnt >= {`C1_CR_TIMEOUT_W{1'b1}}) begin
                prescale_cnt <= {`C1_CR_TIMEOUT_W{1'b0}};
                if (reg_value == {`C1_WDT_CNT_W{1'b0}}) begin
                    if (first_timeout == 1'b0) begin
                        first_timeout <= 1'b1;
                        reg_ris       <= 1'b1;
                        reg_value     <= reg_load;
                    end else begin
                        second_timeout <= 1'b1;
                    end
                end else begin
                    reg_value <= reg_value - 1'b1;
                end
            end else begin
                prescale_cnt <= prescale_cnt + 1'b1;
            end
        end else begin
            prescale_cnt   <= {`C1_CR_TIMEOUT_W{1'b0}};
            first_timeout  <= 1'b0;
            second_timeout <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // 寄存器读写（含 0x1AC 解锁键）
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_load     <= {`C1_WDT_CNT_W{1'b1}};
            reg_control  <= {`C1_REG_DATA_W{1'b0}};
            reg_locked   <= 1'b1;
            unlock_key   <= {`C1_WDT_KEY_W{1'b0}};
            reg_mis      <= 1'b0;
            REG_RDATA    <= {`C1_REG_DATA_W{1'b0}};
            REG_TXN_CNT  <= {`C1_MON_CNT_W{1'b0}};
            REG_IRQ      <= 1'b0;
        end else begin
            if (REG_WR_EN) begin
                REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                unlock_key  <= REG_WDATA[`C1_WDT_KEY_W-1:0];
                case (REG_ADDR[`C1_PERIPH_TYPE_W-1:0])
                    4'h0: begin
                        reg_load   <= REG_WDATA[`C1_WDT_CNT_W-1:0];
                        reg_value  <= REG_WDATA[`C1_WDT_CNT_W-1:0];
                    end
                    4'h1: begin
                        reg_control <= REG_WDATA;
                        reg_locked  <= ~(unlock_key == `C1_WDT_KEY_W'h5A);
                    end
                    4'h2: begin
                        reg_ris <= 1'b0;
                        reg_mis <= 1'b0;
                        REG_IRQ <= 1'b0;
                    end
                    default: reg_control <= reg_control;
                endcase
            end else if (REG_RD_EN) begin
                REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                case (REG_ADDR[`C1_PERIPH_TYPE_W-1:0])
                    4'h0: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_WDT_CNT_W){1'b0}}, reg_load};
                    4'h3: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_WDT_CNT_W){1'b0}}, reg_value};
                    4'h1: REG_RDATA <= reg_control;
                    4'h4: REG_RDATA <= {{(`C1_REG_DATA_W-1){1'b0}}, reg_ris};
                    4'h5: REG_RDATA <= {{(`C1_REG_DATA_W-1){1'b0}}, reg_mis};
                    4'h6: REG_RDATA <= {{(`C1_REG_DATA_W-1){1'b0}}, reg_locked};
                    default: REG_RDATA <= reg_control;
                endcase
            end

            reg_mis <= reg_ris & reg_control[1];
            REG_IRQ <= reg_mis | second_timeout;
        end
    end

endmodule
