//==========================================================================
//  case1_timer_regs.v
//  Timer 寄存器组（叶子模块，内部无任何例化）
//
//  寄存器：LOAD / COUNT / CTRL / INT_STAT / COMPARE
//  含自由运行/周期两种模式的下行计数器与比较中断。
//
//  Ref: ARM Dual-Timer / SP804 风格的定时器寄存器组（APB 外设叶子）。
//==========================================================================
`include "case1_define.v"

module case1_timer_regs (
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

    reg [`C1_TIMER_CNT_W-1:0] reg_load;
    reg [`C1_TIMER_CNT_W-1:0] reg_count;
    reg [`C1_REG_DATA_W-1:0]  reg_ctrl;
    reg [`C1_TIMER_CNT_W-1:0] reg_compare;
    reg [`C1_REG_DATA_W-1:0]  reg_int_stat;
    reg [`C1_TIMER_DIV_W-1:0] prescale_r;

    //------------------------------------------------------------------
    // 预分频 + 计数器
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            prescale_r <= {`C1_TIMER_DIV_W{1'b0}};
            reg_count  <= {`C1_TIMER_CNT_W{1'b0}};
            reg_int_stat <= {`C1_REG_DATA_W{1'b0}};
        end else if (reg_ctrl[0] == 1'b1) begin
            if (prescale_r >= reg_ctrl[`C1_TIMER_DIV_W-1:0]) begin
                prescale_r <= {`C1_TIMER_DIV_W{1'b0}};
                if (reg_count == {`C1_TIMER_CNT_W{1'b0}}) begin
                    reg_count    <= (reg_ctrl[1] == 1'b1) ? reg_load
                                                          : {`C1_TIMER_CNT_W{1'b1}};
                    reg_int_stat[0] <= 1'b1;
                end else begin
                    reg_count <= reg_count - 1'b1;
                end
            end else begin
                prescale_r <= prescale_r + 1'b1;
            end
        end else begin
            prescale_r <= {`C1_TIMER_DIV_W{1'b0}};
        end
    end

    //------------------------------------------------------------------
    // 寄存器读写
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_load    <= {`C1_TIMER_CNT_W{1'b0}};
            reg_ctrl    <= {`C1_REG_DATA_W{1'b0}};
            reg_compare <= {`C1_TIMER_CNT_W{1'b0}};
            REG_RDATA   <= {`C1_REG_DATA_W{1'b0}};
            REG_TXN_CNT <= {`C1_MON_CNT_W{1'b0}};
            REG_IRQ     <= 1'b0;
        end else begin
            if (REG_WR_EN) begin
                REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                case (REG_ADDR[`C1_PERIPH_TYPE_W-1:0])
                    4'h0: reg_load    <= REG_WDATA[`C1_TIMER_CNT_W-1:0];
                    4'h1: begin
                        reg_ctrl <= REG_WDATA;
                        REG_IRQ  <= 1'b0;
                    end
                    4'h2: reg_compare <= REG_WDATA[`C1_TIMER_CNT_W-1:0];
                    4'h3: reg_int_stat <= {`C1_REG_DATA_W{1'b0}};
                    default: reg_load <= reg_load;
                endcase
            end else if (REG_RD_EN) begin
                REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                case (REG_ADDR[`C1_PERIPH_TYPE_W-1:0])
                    4'h0: REG_RDATA <= reg_load;
                    4'h1: REG_RDATA <= reg_ctrl;
                    4'h4: REG_RDATA <= reg_count;
                    4'h5: REG_RDATA <= reg_compare;
                    4'h6: REG_RDATA <= reg_int_stat;
                    default: REG_RDATA <= reg_count;
                endcase
            end

            if (reg_count == reg_compare) begin
                reg_int_stat[1] <= 1'b1;
            end
            REG_IRQ <= (reg_int_stat[0] | reg_int_stat[1]) & reg_ctrl[2];
        end
    end

endmodule
