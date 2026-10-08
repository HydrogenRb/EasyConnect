//==========================================================================
//  case2_clk_gate.v
//  低电平锁存式时钟门控（ICG）：给空闲 router port / SN 阵列关时钟
//
//  Ref: 综合库 ICG cell 的行为模型（latch + and）。无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_clk_gate (
    input  wire                    CLK,
    input  wire                    RST_N,
    input  wire                    EN,
    output wire                    GCLK
);

    reg en_latch;

    always @(*) begin
        if (!RST_N) begin
            en_latch = 1'b0;
        end else if (!CLK) begin
            en_latch = EN;
        end
    end

    assign GCLK = CLK & en_latch;

endmodule
