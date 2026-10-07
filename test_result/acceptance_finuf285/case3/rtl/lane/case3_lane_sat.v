//==========================================================================
//  case3_lane_sat.v
//  饱和 / 限幅单元：把 40 位累加器结果限幅到 16 位上下限，输出 32 位打包结果。
//  叶子模块（内部没有任何例化）。
//
//  Ref: DSP 的 saturate / pack 指令（TI C6x .L 单元的 SAT、Hexagon vpack）。
//==========================================================================
`include "case3_define.v"

module case3_lane_sat (
    input  wire [`C3_ACC_W-1:0]    ACC_IN,
    input  wire [`C3_PE_W-1:0]     HI_LIMIT,
    input  wire [`C3_PE_W-1:0]     LO_LIMIT,
    input  wire [`C3_OP_W-1:0]     MODE,
    output reg  [`C3_DATA_W-1:0]   Y,
    output reg  [`C3_FLAG_W-1:0]   SAT_FLAGS,
    output reg                     SAT_HIT
);

    reg [`C3_ACC_W-1:0]   sat_tmp;
    reg [`C3_DATA_W-1:0]  hi_ext;
    reg [`C3_DATA_W-1:0]  lo_ext;
    reg [`C3_ACC_W-1:0]   hi_acc;
    reg [`C3_ACC_W-1:0]   lo_acc;

    always @(*) begin
        hi_ext  = {{(`C3_DATA_W-`C3_PE_W){1'b0}}, HI_LIMIT};
        lo_ext  = {{(`C3_DATA_W-`C3_PE_W){1'b0}}, LO_LIMIT};
        hi_acc  = {{(`C3_ACC_W-`C3_DATA_W){1'b0}}, hi_ext};
        lo_acc  = {{(`C3_ACC_W-`C3_DATA_W){1'b0}}, lo_ext};
        sat_tmp = ACC_IN;
        SAT_HIT = 1'b0;
        case (MODE)
            `C3_OP_SAT: begin
                if (ACC_IN > hi_acc) begin
                    sat_tmp = hi_acc;
                    SAT_HIT = 1'b1;
                end else if (ACC_IN < lo_acc) begin
                    sat_tmp = lo_acc;
                    SAT_HIT = 1'b1;
                end
            end
            `C3_OP_MAC: begin
                sat_tmp = {ACC_IN[`C3_ACC_MSB],
                           ACC_IN[`C3_ACC_MSB-1:`C3_MUL_LAT]};
                SAT_HIT = ACC_IN[`C3_ACC_MSB];
            end
            default: begin
                sat_tmp = ACC_IN;
                SAT_HIT = 1'b0;
            end
        endcase
        Y = sat_tmp[`C3_DATA_MSB:0];
        SAT_FLAGS = {`C3_FLAG_W{1'b0}};
        SAT_FLAGS[`C3_FLAG_SAT]    = SAT_HIT;
        SAT_FLAGS[`C3_FLAG_STICKY] = (sat_tmp[`C3_ACC_MSB] != sat_tmp[`C3_DATA_MSB]);
    end

endmodule
