//==========================================================================
//  case1_pulse_sync.v
//  单 bit 脉冲跨时钟域同步器（叶子模块，内部无任何例化）
//
//  A 域脉冲 → 电平翻转 → B 域两级同步 → 边沿检测还原成单拍脉冲。
//
//  Ref: 脉冲同步器（toggle + 2FF + edge detect），
//       常见的 CDC 握手小单元。
//==========================================================================
`include "case1_define.v"

module case1_pulse_sync (
    input  wire CLK_A,
    input  wire RST_A_N,
    input  wire CLK_B,
    input  wire RST_B_N,
    input  wire PULSE_IN,
    output reg  PULSE_OUT
);

    reg toggle_a;
    reg sync_b0;
    reg sync_b1;
    reg sync_b2;

    // A 域：把脉冲换成电平翻转
    always @(posedge CLK_A or negedge RST_A_N) begin
        if (!RST_A_N) begin
            toggle_a <= 1'b0;
        end else if (PULSE_IN) begin
            toggle_a <= ~toggle_a;
        end
    end

    // B 域：两级同步 + 边沿检测
    always @(posedge CLK_B or negedge RST_B_N) begin
        if (!RST_B_N) begin
            sync_b0   <= 1'b0;
            sync_b1   <= 1'b0;
            sync_b2   <= 1'b0;
            PULSE_OUT <= 1'b0;
        end else begin
            sync_b0   <= toggle_a;
            sync_b1   <= sync_b0;
            sync_b2   <= sync_b1;
            PULSE_OUT <= sync_b1 ^ sync_b2;
        end
    end

endmodule
