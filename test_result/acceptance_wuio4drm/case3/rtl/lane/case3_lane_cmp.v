//==========================================================================
//  case3_lane_cmp.v
//  比较单元：相等 / 大小比较 / 最小值索引（用于 argmin 归约）。
//  叶子模块（内部没有任何例化）。
//
//  Ref: SIMD 归约树里的 compare-select 单元（Vision P6 vcmp + vminidx）。
//==========================================================================
`include "case3_define.v"

module case3_lane_cmp (
    input  wire [`C3_DATA_W-1:0]    A,
    input  wire [`C3_DATA_W-1:0]    B,
    input  wire [`C3_OP_W-1:0]      MODE,
    input  wire [`C3_LANE_AW-1:0]   LANE_IDX,
    input  wire [`C3_DATA_W-1:0]    REF_MIN,
    output reg  [`C3_DATA_W-1:0]    Y,
    output reg  [`C3_FLAG_W-1:0]    FLAGS,
    output reg  [`C3_LANE_AW-1:0]   MIN_IDX
);

    reg [`C3_DATA_W-1:0] diff;
    reg [`C3_DATA_W-1:0] min_sel;

    always @(*) begin
        diff    = A - B;
        min_sel = (A < REF_MIN) ? A : REF_MIN;
        Y       = {`C3_DATA_W{1'b0}};
        FLAGS   = {`C3_FLAG_W{1'b0}};
        MIN_IDX = LANE_IDX;
        case (MODE)
            `C3_OP_CMP: begin
                if (A == B) begin
                    Y = {`C3_DATA_W{1'b0}};
                    FLAGS[`C3_FLAG_ZERO] = 1'b1;
                end else if (A > B) begin
                    Y = {{(`C3_DATA_W-1){1'b0}}, 1'b1};
                    MIN_IDX = LANE_IDX;
                end else begin
                    Y = {`C3_DATA_W{1'b1}};
                    FLAGS[`C3_FLAG_NEG] = 1'b1;
                end
                FLAGS[`C3_FLAG_STICKY] = |diff;
            end
            `C3_OP_SAT: begin
                Y = min_sel;
                FLAGS[`C3_FLAG_OVF] = (A < REF_MIN);
            end
            default: begin
                Y = diff;
                FLAGS[`C3_FLAG_OVF] = diff[`C3_DATA_MSB];
                FLAGS[`C3_FLAG_NEG] = B[`C3_DATA_MSB];
            end
        endcase
    end

endmodule
