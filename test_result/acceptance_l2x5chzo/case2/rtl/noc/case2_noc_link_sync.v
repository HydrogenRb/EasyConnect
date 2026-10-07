//==========================================================================
//  case2_noc_link_sync.v
//  mesh link 握手同步级：valid 打拍、link_active 过滤、指针跨域采样
//
//  Ref: 片内 link 的 TXVALID/TXREADY 握手与 LINKACTIVE 保护。
//       为了保持它是层次树叶子，同步行为在这里用触发器直接描述。
//==========================================================================
`include "case2_define.v"

module case2_noc_link_sync (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire                       LINK_UP,
    input  wire [`C2_FLIT_KIND_W-1:0] KIND,
    input  wire                       VALID_IN,
    output wire                       READY_IN,
    output wire                       VALID_OUT,
    input  wire                       READY_OUT,
    output reg  [`C2_BUF_PTR_W-1:0]   PTR_OUT,
    input  wire [`C2_BUF_PTR_W-1:0]   PTR_IN,
    output wire                       SYNC_ERR
);

    reg                        valid_meta;
    reg                        valid_sync;
    reg [`C2_FLIT_KIND_W-1:0]  kind_sync;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            valid_meta <= 1'b0;
            valid_sync <= 1'b0;
            kind_sync  <= {`C2_FLIT_KIND_W{1'b0}};
            PTR_OUT    <= {`C2_BUF_PTR_W{1'b0}};
        end else begin
            valid_meta <= VALID_IN & LINK_UP;
            valid_sync <= valid_meta;
            kind_sync  <= KIND;
            PTR_OUT    <= PTR_IN;
        end
    end

    assign VALID_OUT = valid_sync & LINK_UP;
    assign READY_IN  = READY_OUT | (~LINK_UP);
    assign SYNC_ERR  = valid_sync & (~LINK_UP);

endmodule
