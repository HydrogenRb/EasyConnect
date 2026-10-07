//==========================================================================
//  case2_noc_vc_buf.v
//  单个 VC 的 flit 缓冲：库宏单元 RAM_SP_BE + flit 高位寄存器
//
//  例化 RAM_SP_BE 之后用 defparam 微调宏单元参数（真实项目里常见的
//  老式写法，本样本用它满足"#() 与 defparam 都要出现"的要求）。
//==========================================================================
`include "case2_define.v"

module case2_noc_vc_buf (
    input  wire                           CLK,
    input  wire                           RST_N,
    input  wire [`C2_FLIT_W-1:0]          FLIT_IN,
    input  wire                           FLIT_WR,
    input  wire [`C2_BUF_PTR_W-1:0]       WR_PTR,
    input  wire [`C2_BUF_PTR_W-1:0]       RD_PTR,
    output wire [`C2_FLIT_W-1:0]          FLIT_OUT,
    output wire                           BUF_FULL,
    output wire [`C2_CREDIT_W-1:0]        CREDIT_LEVEL
);

    wire [`C2_BUF_RAM_AW-1:0] ram_addr;
    wire [`C2_BUF_RAM_DW-1:0] ram_d;
    wire [`C2_BUF_RAM_DW-1:0] ram_q;
    wire                      ram_cen;
    wire                      ram_wen;
    wire [`C2_RAM_BEN_W-1:0]  ram_ben;

    reg [`C2_FLIT_W-`C2_BUF_RAM_DW-1:0] flit_tail_r;

    assign ram_cen  = ~FLIT_WR;
    assign ram_wen  = ~FLIT_WR;
    assign ram_ben  = {`C2_RAM_BEN_W{1'b0}};
    assign ram_d    = FLIT_IN[`C2_BUF_RAM_DW-1:0];
    assign ram_addr = {{(`C2_BUF_RAM_AW-`C2_BUF_PTR_W){1'b0}}, WR_PTR};

    assign FLIT_OUT     = {flit_tail_r, ram_q};
    assign BUF_FULL     = (WR_PTR == (RD_PTR - {{(`C2_BUF_PTR_W-1){1'b0}}, 1'b1}));
    assign CREDIT_LEVEL = {{(`C2_CREDIT_W-`C2_BUF_PTR_W){1'b0}}, WR_PTR - RD_PTR};

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            flit_tail_r <= {(`C2_FLIT_W-`C2_BUF_RAM_DW){1'b0}};
        end else if (FLIT_WR) begin
            flit_tail_r <= FLIT_IN[`C2_FLIT_W-1:`C2_BUF_RAM_DW];
        end
    end

    //------------------------------------------------------------------
    // 库宏单元：RAM_SP_BE（位置连接）
    //------------------------------------------------------------------
    RAM_SP_BE #(.AW(`C2_BUF_RAM_AW), .DW(`C2_BUF_RAM_DW), .DEPTH(`C2_BUF_RAM_DEPTH)) u_flit_ram (
        CLK,
        ram_cen,
        ram_wen,
        ram_ben,
        ram_addr,
        ram_d,
        ram_q
    );

    defparam u_flit_ram.AW    = `C2_BUF_RAM_AW;
    defparam u_flit_ram.DW    = `C2_BUF_RAM_DW;
    defparam u_flit_ram.DEPTH = `C2_BUF_RAM_DEPTH;

endmodule
