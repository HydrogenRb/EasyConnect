//==========================================================================
//  case1_clk_gate.v
//  集成时钟门控单元（叶子模块，内部无任何例化）
//
//  低电平有效的锁存使能 + 与门，保证门控时钟不产生毛刺；
//  TEST_EN 为扫描/测试旁路。
//
//  Ref: SoC 里的 integrated clock gating cell（ICG / latch-based clock gate）。
//==========================================================================
`include "case1_define.v"

module case1_clk_gate (
    input  wire CLK,
    input  wire RST_N,
    input  wire EN,
    input  wire TEST_EN,
    output wire GATED_CLK
);

    reg en_latch;
    wire rst_n_inv;

    assign rst_n_inv = ~RST_N;

    // 低电平锁存使能，避免在时钟高电平期间改变门控
    always @(*) begin
        if (CLK == 1'b0) begin
            en_latch = EN | TEST_EN | rst_n_inv;
        end
    end

    assign GATED_CLK = CLK & en_latch;

endmodule
