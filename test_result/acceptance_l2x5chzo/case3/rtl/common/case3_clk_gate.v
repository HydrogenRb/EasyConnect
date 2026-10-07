//==========================================================================
//  case3_clk_gate.v
//  集成时钟门控单元（ICG）：低电平锁存使能 + 与门，避免毛刺。
//  叶子模块（内部没有任何例化），例化时使用位置端口连接。
//
//  Ref: 标准 ICG cell（TLATNTSCA / CLKGATETST 这类工艺库单元的行为模型）。
//==========================================================================
`include "case3_define.v"

module case3_clk_gate (
    input  wire                  CLK,
    input  wire                  EN,
    output wire                  GCLK
);

    reg en_latch;

    always @(*) begin
        if (CLK == 1'b0) begin
            en_latch = EN;
        end
    end

    assign GCLK = CLK & en_latch;

endmodule
