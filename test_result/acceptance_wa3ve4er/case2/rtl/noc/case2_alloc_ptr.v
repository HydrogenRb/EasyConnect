//==========================================================================
//  case2_alloc_ptr.v
//  buffer 指针 / 水位管理：alloc-free 指针 + 一级 one-hot 指针向量
//
//  Ref: NoC input buffer、FIFO wrapper 里的指针与水位逻辑。
//       只做指针运算，无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_alloc_ptr (
    input  wire                     CLK,
    input  wire                     RST_N,
    input  wire                     ALLOC_REQ,
    input  wire                     FREE_REQ,
    input  wire [`C2_BUF_PTR_W-1:0] FREE_PTR,
    output reg  [`C2_BUF_PTR_W-1:0] ALLOC_PTR,
    output reg  [`C2_BUF_PTR_W-1:0] WR_PTR,
    output wire [`C2_BUF_DEPTH-1:0] PTR_VEC,
    output wire                     FULL,
    output wire                     EMPTY
);

    reg [`C2_BUF_PTR_W-1:0] level;
    reg                     alloc_ok;
    reg                     free_ok;

    assign FULL      = (level == {`C2_BUF_PTR_W{1'b1}});
    assign EMPTY     = (level == {`C2_BUF_PTR_W{1'b0}});
    assign PTR_VEC   = ({{(`C2_BUF_DEPTH-1){1'b0}}, 1'b1} << ALLOC_PTR);

    always @(*) begin
        alloc_ok = ALLOC_REQ & (~FULL);
        free_ok  = FREE_REQ & (~EMPTY);
    end

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            ALLOC_PTR <= {`C2_BUF_PTR_W{1'b0}};
            WR_PTR    <= {`C2_BUF_PTR_W{1'b0}};
            level     <= {`C2_BUF_PTR_W{1'b0}};
        end else begin
            if (alloc_ok) begin
                ALLOC_PTR <= ALLOC_PTR + {{(`C2_BUF_PTR_W-1){1'b0}}, 1'b1};
                WR_PTR    <= WR_PTR + {{(`C2_BUF_PTR_W-1){1'b0}}, 1'b1};
            end
            if (free_ok) begin
                ALLOC_PTR <= FREE_PTR;
            end
            if (alloc_ok & (~free_ok)) begin
                level <= level + {{(`C2_BUF_PTR_W-1){1'b0}}, 1'b1};
            end else if (free_ok & (~alloc_ok)) begin
                level <= level - {{(`C2_BUF_PTR_W-1){1'b0}}, 1'b1};
            end
        end
    end

endmodule
