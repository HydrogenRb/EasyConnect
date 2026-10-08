//==========================================================================
//  case1_sync_ff.v
//  单级同步触发器（叶子模块，内部无任何例化）
//
//  级联 N 个即构成 N 级 CDC 同步器；case1_apb_cdc / case1_apb_crossbar /
//  case1_apb_periph_slot 里的嵌套 for-generate 就是按"每 slot、每级一个"
//  的方式例化本单元。
//
//  Ref: 2-FF synchronizer 的单级实现（CDC 同步器阵列的基本单元）。
//==========================================================================
`include "case1_define.v"

module case1_sync_ff (
    input  wire CLK,
    input  wire RST_N,
    input  wire D_IN,
    output reg  D_OUT
);

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            D_OUT <= 1'b0;
        end else begin
            D_OUT <= D_IN;
        end
    end

endmodule
