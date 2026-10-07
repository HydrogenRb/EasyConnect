//==========================================================================
//  case3_scratch_arb.v
//  scratchpad bank 仲裁器：多端口竞争同一个 bank 时的授权逻辑。
//  内部例化一个 clk_gate（位置端口连接）。
//
//  Ref: 多端口 SRAM 的 bank arbiter（Vision P6 VMEM 的 bank conflict 仲裁）。
//==========================================================================
`include "case3_define.v"

module case3_scratch_arb (
    input  wire                    CLK,
    input  wire                    RST_N,
    input  wire [`C3_BANK_NUM-1:0] REQ_VEC,
    input  wire [`C3_BANK_AW-1:0]  PORT_ID,
    output wire [`C3_BANK_NUM-1:0] GRANT_VEC,
    output wire [`C3_BANK_AW-1:0]  ARB_SEL,
    output wire                    ARB_BUSY,
    output wire                    ARB_CLK
);

    parameter ARB_ID    = 0;
    parameter ARB_MODE  = `C3_XBAR_ROUND_ROBIN;

    reg                      arb_en;
    reg  [`C3_BANK_NUM-1:0]  grant_r;
    reg  [`C3_BANK_AW-1:0]   sel_r;

    assign ARB_BUSY = |REQ_VEC;
    assign GRANT_VEC = grant_r;

    always @(*) begin
        arb_en = |REQ_VEC;
        case (ARB_MODE)
            `C3_XBAR_ROUND_ROBIN: begin
                grant_r = REQ_VEC & ~sel_r;
                if (~|grant_r) begin
                    grant_r = REQ_VEC;
                end
            end
            `C3_XBAR_FIXED_PRIO: begin
                grant_r = (REQ_VEC & ({{(`C3_BANK_NUM-1){1'b0}}, 1'b1} << PORT_ID));
            end
            default: begin
                grant_r = REQ_VEC;
            end
        endcase
    end

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            sel_r <= {`C3_BANK_AW{1'b0}};
        end else if (|REQ_VEC) begin
            sel_r <= sel_r + {{(`C3_BANK_AW-1){1'b0}}, 1'b1};
        end
    end

    assign ARB_SEL = sel_r;

    // 仲裁通路时钟门控（位置端口连接）
    case3_clk_gate u_arb_gate (CLK, arb_en, ARB_CLK);

endmodule
