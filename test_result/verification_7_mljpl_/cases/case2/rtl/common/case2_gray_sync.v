//==========================================================================
//  case2_gray_sync.v
//  格雷码指针同步器：crossbar / link FIFO 的读写指针跨时钟域采样
//
//  Ref: 异步 FIFO 用格雷码指针跨域；本样本所有 mesh link 的 credit 指针
//       都经过该单元后再参与 credit 计数。无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_gray_sync (
    input  wire                     CLK,
    input  wire                     RST_N,
    input  wire [`C2_BUF_PTR_W-1:0] PTR_IN,
    output reg  [`C2_BUF_PTR_W-1:0] PTR_OUT
);

    reg [`C2_BUF_PTR_W-1:0] gray_in;
    reg [`C2_BUF_PTR_W-1:0] gray_pipe;

    always @(*) begin
        gray_in = PTR_IN ^ {1'b0, PTR_IN[`C2_BUF_PTR_W-1:1]};
    end

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            gray_pipe <= {`C2_BUF_PTR_W{1'b0}};
        end else begin
            gray_pipe <= gray_in;
        end
    end

    always @(*) begin
        PTR_OUT = gray_pipe;
    end

endmodule
