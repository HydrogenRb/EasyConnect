//==========================================================================
//  case1_gray_sync.v
//  多 bit 格雷码跨时钟域同步器（叶子模块，内部无任何例化）
//
//  CLK_A 域的格雷码指针逐级打入 CLK_B 域，并给出二进制形式输出。
//  格雷码保证跨域只有 1 bit 变化，避免多 bit 同时翻转采样出错。
//
//  Ref: async FIFO 的 gray-code pointer crossing（Cummings 风格同步器）。
//==========================================================================
`include "case1_define.v"

module case1_gray_sync (
    input  wire                     CLK_A,
    input  wire                     RST_A_N,
    input  wire                     CLK_B,
    input  wire                     RST_B_N,
    input  wire [`C1_GRAY_W-1:0]    GRAY_IN,
    output reg  [`C1_GRAY_W-1:0]    GRAY_OUT,
    output wire [`C1_GRAY_W-1:0]    BIN_OUT
);

    parameter STAGES = `C1_CDC_STAGES;

    reg [`C1_GRAY_W-1:0] gray_stage;
    reg [`C1_GRAY_W-1:0] bin_r;
    integer              b;

    // A 域：把二进制指针编码成格雷码（这里输入已是格雷码，仅做寄存）
    always @(posedge CLK_A or negedge RST_A_N) begin
        if (!RST_A_N) begin
            gray_stage <= {`C1_GRAY_W{1'b0}};
        end else begin
            gray_stage <= GRAY_IN;
        end
    end

    // B 域：两级同步 + 格雷码转二进制
    always @(posedge CLK_B or negedge RST_B_N) begin
        if (!RST_B_N) begin
            GRAY_OUT <= {`C1_GRAY_W{1'b0}};
            bin_r    <= {`C1_GRAY_W{1'b0}};
        end else begin
            GRAY_OUT <= gray_stage;
            bin_r[`C1_GRAY_W-1] <= GRAY_OUT[`C1_GRAY_W-1];
            for (b = `C1_GRAY_W-2; b >= 0; b = b - 1) begin
                bin_r[b] <= bin_r[b+1] ^ GRAY_OUT[b];
            end
        end
    end

    assign BIN_OUT = bin_r;

endmodule
