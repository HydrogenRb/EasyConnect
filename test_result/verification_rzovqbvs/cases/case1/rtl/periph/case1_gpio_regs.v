//==========================================================================
//  case1_gpio_regs.v
//  GPIO 寄存器组（叶子模块，内部无任何例化）
//
//  寄存器：DATA_OUT / DATA_IN / DIR / INT_EN / INT_STAT / ALT_FUNC
//  含 32 个引脚的输入同步、边沿检测与中断汇聚。
//
//  Ref: ARM PrimeCell PL061 风格的 GPIO 寄存器组（APB 外设叶子）。
//==========================================================================
`include "case1_define.v"

module case1_gpio_regs (
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

    reg [`C1_GPIO_PIN_NUM-1:0] reg_data_out;
    reg [`C1_GPIO_PIN_NUM-1:0] reg_dir;
    reg [`C1_GPIO_PIN_NUM-1:0] reg_int_en;
    reg [`C1_GPIO_PIN_NUM-1:0] reg_int_stat;
    reg [`C1_GPIO_PIN_NUM-1:0] reg_alt;
    reg [`C1_GPIO_PIN_NUM-1:0] pin_sync0;
    reg [`C1_GPIO_PIN_NUM-1:0] pin_sync1;
    reg [`C1_GPIO_PIN_NUM-1:0] pin_prev;
    reg [`C1_GPIO_PIN_NUM-1:0] pin_edge;
    wire [`C1_GPIO_PIN_NUM-1:0] pin_in;
    wire [`C1_GPIO_PIN_NUM-1:0] dir_n;
    wire [`C1_GPIO_PIN_NUM-1:0] wdata_n;
    integer                     p;

    // 输入先做两级同步（片外引脚 → PCLK 域）
    assign pin_in  = pin_sync1;
    assign dir_n   = ~reg_dir;
    assign wdata_n = ~REG_WDATA[`C1_GPIO_PIN_NUM-1:0];

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            pin_sync0 <= {`C1_GPIO_PIN_NUM{1'b0}};
            pin_sync1 <= {`C1_GPIO_PIN_NUM{1'b0}};
            pin_prev  <= {`C1_GPIO_PIN_NUM{1'b0}};
            pin_edge  <= {`C1_GPIO_PIN_NUM{1'b0}};
        end else begin
            pin_sync0 <= reg_data_out & dir_n;
            pin_sync1 <= pin_sync0;
            pin_prev  <= pin_sync1;
            pin_edge  <= pin_sync1 ^ pin_prev;
        end
    end

    //------------------------------------------------------------------
    // 寄存器读写
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_data_out <= {`C1_GPIO_PIN_NUM{1'b0}};
            reg_dir      <= {`C1_GPIO_PIN_NUM{1'b0}};
            reg_int_en   <= {`C1_GPIO_PIN_NUM{1'b0}};
            reg_int_stat <= {`C1_GPIO_PIN_NUM{1'b0}};
            reg_alt      <= {`C1_GPIO_PIN_NUM{1'b0}};
            REG_RDATA    <= {`C1_REG_DATA_W{1'b0}};
            REG_TXN_CNT  <= {`C1_MON_CNT_W{1'b0}};
            REG_IRQ      <= 1'b0;
        end else begin
            if (REG_WR_EN) begin
                REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                case (REG_ADDR[`C1_GPIO_PIN_AW-1:0])
                        5'h00: reg_data_out <= REG_WDATA[`C1_GPIO_PIN_NUM-1:0];
                        5'h01: reg_dir      <= REG_WDATA[`C1_GPIO_PIN_NUM-1:0];
                        5'h02: reg_int_en   <= REG_WDATA[`C1_GPIO_PIN_NUM-1:0];
                        5'h03: reg_int_stat <= reg_int_stat & wdata_n;
                        5'h04: reg_alt      <= REG_WDATA[`C1_GPIO_PIN_NUM-1:0];
                        default: reg_data_out <= reg_data_out;
                endcase
            end else if (REG_RD_EN) begin
                REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                case (REG_ADDR[`C1_GPIO_PIN_AW-1:0])
                    5'h00: REG_RDATA <= reg_data_out;
                    5'h05: REG_RDATA <= pin_in;
                    5'h01: REG_RDATA <= reg_dir;
                    5'h06: REG_RDATA <= reg_int_stat;
                    5'h04: REG_RDATA <= reg_alt;
                    default: REG_RDATA <= pin_edge;
                endcase
            end

            for (p = 0; p < `C1_GPIO_PIN_NUM; p = p + 1) begin
                if (pin_edge[p]) begin
                    reg_int_stat[p] <= 1'b1;
                end
            end
            REG_IRQ <= |(reg_int_stat & reg_int_en);
        end
    end

endmodule
