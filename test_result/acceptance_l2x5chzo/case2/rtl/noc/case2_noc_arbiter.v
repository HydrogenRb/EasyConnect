//==========================================================================
//  case2_noc_arbiter.v
//  轮询仲裁器：VC 分配、crossbar 输出仲裁、SN drop ring 汇聚都用它
//
//  Ref: 真实 NoC 的 round-robin arbiter（mask 轮转 + 优先级编码）。
//       纯组合选择 + 一个 mask 寄存器，无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_noc_arbiter (
    input  wire                    CLK,
    input  wire                    RST_N,
    input  wire [`C2_PORT_NUM-1:0] REQ,
    input  wire [`C2_CREDIT_W-1:0] CREDIT,
    input  wire                    HOLD,
    output wire [`C2_PORT_NUM-1:0] GNT,
    output wire [`C2_PORT_AW-1:0]  GNT_IDX,
    output wire                    GNT_VALID,
    output wire                    ALLOC_FAIL
);

    reg [`C2_PORT_NUM-1:0] gnt_c;
    reg [`C2_PORT_AW-1:0]  idx_c;
    reg [`C2_PORT_NUM-1:0] mask_r;
    integer                pi;
    integer                ri;

    // 优先级编码：低索引优先，mask_r 给出本轮允许参与的请求者
    always @(*) begin
        gnt_c = {`C2_PORT_NUM{1'b0}};
        idx_c = {`C2_PORT_AW{1'b0}};
        for (pi = `C2_PORT_NUM-1; pi >= 0; pi = pi - 1) begin
            if (REQ[pi] && CREDIT[pi] && mask_r[pi] && (~HOLD)) begin
                gnt_c = {`C2_PORT_NUM{1'b0}};
                gnt_c[pi] = 1'b1;
                idx_c = pi;
            end
        end
    end

    // 仲裁成功者从下一轮 mask 中排除，实现轮询
    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            mask_r <= {`C2_PORT_NUM{1'b1}};
        end else begin
            if (|gnt_c) begin
                mask_r <= ~gnt_c;
            end else begin
                mask_r <= mask_r;
            end
        end
    end

    assign GNT        = gnt_c;
    assign GNT_IDX    = idx_c;
    assign GNT_VALID  = |gnt_c;
    assign ALLOC_FAIL = (|REQ) && (gnt_c == {`C2_PORT_NUM{1'b0}});

endmodule
