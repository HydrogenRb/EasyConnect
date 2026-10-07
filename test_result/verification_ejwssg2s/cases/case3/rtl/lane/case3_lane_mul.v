//==========================================================================
//  case3_lane_mul.v
//  乘法单元：32x32 乘加器 + 3 级流水（`C3_MUL_LAT），支持 MUL / MAC / ADD 模式。
//  叶子模块（内部没有任何例化）。
//
//  Ref: DSP48E1 / DSP58 这类硬核乘法器外面那层 mul_mac_pipe，
//       常见于 Vision-P6、NVDLA 的卷积 datapath。
//==========================================================================
`include "case3_define.v"

module case3_lane_mul (
    input  wire                     CLK,
    input  wire                     RST_N,
    input  wire                     MUL_EN,
    input  wire [`C3_DATA_W-1:0]    OPA,
    input  wire [`C3_DATA_W-1:0]    OPB,
    input  wire [`C3_ACC_W-1:0]     ACC_IN,
    input  wire [`C3_OP_W-1:0]      MODE,
    input  wire [`C3_ROUND_W-1:0]   ROUND,
    output wire [`C3_ACC_W-1:0]     Y,
    output wire                     Y_VALID,
    output wire [`C3_FLAG_W-1:0]    FLAGS
);

    parameter MUL_LATENCY = `C3_MUL_LAT;
    parameter PIPE_ENABLE = `C3_PERF_WRAP_EN;

    reg  [`C3_ACC_W-1:0]   acc_p0;
    reg  [`C3_ACC_W-1:0]   acc_p1;
    reg  [`C3_ACC_W-1:0]   acc_p2;
    reg  [`C3_OP_W-1:0]    mode_p0;
    reg  [`C3_OP_W-1:0]    mode_p1;
    reg  [`C3_ROUND_W-1:0] rnd_p1;
    reg                    vld_p0;
    reg                    vld_p1;
    reg                    vld_p2;
    reg  [`C3_FLAG_W-1:0]  flags_p2;
    wire [`C3_ACC_W-1:0]   mult_full;
    wire [`C3_ACC_W-1:0]   mult_round;

    assign mult_full  = (OPA * OPB) + ACC_IN;
    assign mult_round = mult_full + {{(`C3_ACC_W-`C3_ROUND_W){1'b0}}, ROUND};

    // 第一级：乘法 / 乘加
    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            acc_p0  <= {`C3_ACC_W{1'b0}};
            mode_p0 <= {`C3_OP_W{1'b0}};
            vld_p0  <= 1'b0;
        end else if (MUL_EN) begin
            mode_p0 <= MODE;
            vld_p0  <= 1'b1;
            case (MODE)
                `C3_OP_MUL: acc_p0 <= mult_full;
                `C3_OP_MAC: acc_p0 <= mult_round;
                `C3_OP_ADD: acc_p0 <= {OPA, {`C3_DATA_HALF_W{1'b0}}} + ACC_IN;
                `C3_OP_SUB: acc_p0 <= ACC_IN - {OPB, {`C3_DATA_HALF_W{1'b0}}};
                default:    acc_p0 <= mult_full;
            endcase
        end else begin
            vld_p0 <= 1'b0;
        end
    end

    // 第二 / 第三级：流水对齐
    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            acc_p1   <= {`C3_ACC_W{1'b0}};
            acc_p2   <= {`C3_ACC_W{1'b0}};
            mode_p1  <= {`C3_OP_W{1'b0}};
            rnd_p1   <= {`C3_ROUND_W{1'b0}};
            vld_p1   <= 1'b0;
            vld_p2   <= 1'b0;
            flags_p2 <= {`C3_FLAG_W{1'b0}};
        end else begin
            acc_p1  <= acc_p0;
            acc_p2  <= acc_p1;
            mode_p1 <= mode_p0;
            rnd_p1  <= ROUND;
            vld_p1  <= vld_p0;
            vld_p2  <= vld_p1;
            flags_p2[`C3_FLAG_OVF]    <= (acc_p1[`C3_ACC_MSB] != acc_p2[`C3_ACC_MSB]);
            flags_p2[`C3_FLAG_SAT]    <= (mode_p1 == `C3_OP_MAC) & (|rnd_p1);
            flags_p2[`C3_FLAG_STICKY] <= vld_p1 & vld_p2;
        end
    end

    assign Y       = acc_p2;
    assign Y_VALID = vld_p2;
    assign FLAGS   = flags_p2;

endmodule
