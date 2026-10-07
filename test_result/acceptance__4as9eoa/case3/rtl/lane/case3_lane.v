//==========================================================================
//  case3_lane.v
//  SIMD lane：一个功能单元农场（mul/alu/shf/cmp/sat）+ 私有寄存器堆 +
//  地址生成器 + 访存对齐器。整个层次树的扇出点。
//
//  Ref: Vision-P6 / Hexagon 的 vector lane（VLIW 风格 FU farm + lane RF），
//       以及 NVDLA 每个 MAC lane 的 datapath 组织方式。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_lane (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire [`C3_DATA_W-1:0]      LANE_OPA,
    input  wire [`C3_DATA_W-1:0]      LANE_OPB,
    input  wire [`C3_ACC_W-1:0]       LANE_ACC_IN,
    input  wire [`C3_OP_W-1:0]        LANE_OP,
    input  wire [`C3_LANE_AW-1:0]     LANE_ID,
    input  wire [`C3_REG_ADDR_W-1:0]  LANE_RD_ADDR_A,
    input  wire [`C3_REG_ADDR_W-1:0]  LANE_RD_ADDR_B,
    input  wire [`C3_REG_ADDR_W-1:0]  LANE_WR_ADDR,
    input  wire [`C3_DATA_W-1:0]      LANE_WR_DATA,
    input  wire                       LANE_WR_EN,
    input  wire [`C3_ADDR_W-1:0]      LANE_AGU_BASE,
    input  wire [`C3_ADDR_W-1:0]      LANE_AGU_OFF,
    input  wire [`C3_ADDR_W-1:0]      LANE_AGU_STRIDE,
    input  wire [`C3_LANE_W-1:0]      LANE_SHIFT_AMT,
    input  wire [`C3_ROUND_W-1:0]     LANE_ROUND,
    input  wire                       LANE_STEP,
    output wire [`C3_DATA_W-1:0]      LANE_RESULT,
    output wire [`C3_ACC_W-1:0]       LANE_ACC_OUT,
    output wire [`C3_FLAG_W-1:0]      LANE_FLAGS,
    output wire [`C3_ADDR_W-1:0]      LANE_MEM_ADDR,
    output wire [`C3_DATA_W-1:0]      LANE_MEM_WDATA,
    output wire [`C3_LANE_NUM-1:0]    LANE_BEN,
    output wire                       LANE_MEM_REQ,
    output wire                       LANE_MEM_WR,
    output wire                       LANE_BUSY
);

    parameter LANE_IDX      = 0;
    parameter LANE_PIPE_DEP = `C3_PIPE_STAGE;

    // ---- FU 输出 ----
    wire [`C3_ACC_W-1:0]   mul_y;
    wire                   mul_valid;
    wire [`C3_FLAG_W-1:0]  mul_flags;
    wire [`C3_DATA_W-1:0]  alu_y;
    wire                   alu_cout;
    wire [`C3_FLAG_W-1:0]  alu_flags;
    wire [`C3_DATA_W-1:0]  shf_y;
    wire [`C3_DATA_W-1:0]  shf_sticky;
    wire                   shf_ovf;
    wire [`C3_DATA_W-1:0]  cmp_y;
    wire [`C3_FLAG_W-1:0]  cmp_flags;
    wire [`C3_LANE_AW-1:0] cmp_idx;
    wire [`C3_DATA_W-1:0]  sat_y;
    wire [`C3_FLAG_W-1:0]  sat_flags;
    wire                   sat_hit;

    // ---- RF / AGU / aligner ----
    wire [`C3_DATA_W-1:0]  rf_rd_a;
    wire [`C3_DATA_W-1:0]  rf_rd_b;
    wire                   rf_busy;
    wire [`C3_ADDR_W-1:0]  agu_addr;
    wire                   agu_wrap;
    wire                   agu_req;
    wire [`C3_BANK_AW-1:0] agu_bank;
    wire [`C3_SCRATCH_ADDR_W-1:0] agu_local;
    wire [`C3_DATA_W-1:0]  aln_data;
    wire [`C3_BANK_NUM-1:0] aln_ben;
    wire [`C3_LANE_NUM-1:0] aln_mask;
    wire [`C3_FLAG_W-1:0]  aln_flags;

    // ---- 流水整流 ----
    wire                   pipe_req_s0;
    wire                   pipe_vld_s1;
    wire                   pipe_ovf_s2;
    wire                   pipe_stk_s3;
    wire [`C3_FLAG_W-1:0]  lane_flags_w;
    wire [`C3_PE_W-1:0]    hi_limit_w;
    wire [`C3_PE_W-1:0]    lo_limit_w;
    wire [`C3_DATA_W-1:0]  lane_res_mux;

    assign hi_limit_w = rf_rd_a[`C3_PE_MSB:0];
    assign lo_limit_w = rf_rd_b[`C3_PE_MSB:0];

    assign lane_flags_w = mul_flags | alu_flags | sat_flags | cmp_flags | aln_flags;
    assign LANE_FLAGS   = lane_flags_w |
                          {(shf_sticky[`C3_FLAG_STICKY] | pipe_stk_s3), {(`C3_FLAG_W-1){1'b0}}};

    assign lane_res_mux = (LANE_OP == `C3_OP_CMP) ? cmp_y :
                          (LANE_OP == `C3_OP_SLL) ? shf_y : sat_y;

    assign LANE_RESULT   = lane_res_mux;
    assign LANE_ACC_OUT  = mul_y;
    assign LANE_MEM_ADDR = agu_addr | {{(`C3_ADDR_W-`C3_SCRATCH_ADDR_W){1'b0}}, agu_local};
    assign LANE_MEM_WDATA = aln_data;
    assign LANE_BEN      = aln_ben | {{(`C3_LANE_NUM-`C3_LANE_AW){1'b0}}, cmp_idx};
    assign LANE_MEM_REQ  = (agu_req & (|aln_mask));
    assign LANE_MEM_WR   = (LANE_OP == `C3_OP_ST) & pipe_vld_s1;
    assign LANE_BUSY     = rf_busy | agu_wrap | pipe_req_s0 | pipe_ovf_s2 |
                           alu_cout | mul_valid | sat_hit;

    case3_lane_mul u_mul (
        .CLK      (CLK),
        .RST_N    (RST_N),
        .MUL_EN   (LANE_OP != `C3_OP_NOP),
        .OPA      (LANE_OPA),
        .OPB      (LANE_OPB),
        .ACC_IN   (LANE_ACC_IN),
        .MODE     (LANE_OP),
        .ROUND    (LANE_ROUND),
        .Y        (mul_y),
        .Y_VALID  (mul_valid),
        .FLAGS    (mul_flags)
    );

    case3_lane_alu u_alu (
        .A     (LANE_OPA),
        .B     (LANE_OPB),
        .CIN   (1'b0),
        .MODE  (LANE_OP),
        .Y     (alu_y),
        .COUT  (alu_cout),
        .FLAGS (alu_flags)
    );

    case3_lane_shf u_shf (
        .A         (LANE_OPA),
        .AMT       (LANE_SHIFT_AMT),
        .MODE      (LANE_OP),
        .ROUND     (LANE_ROUND),
        .Y         (shf_y),
        .STICKY    (shf_sticky),
        .SHIFT_OVF (shf_ovf)
    );

    case3_lane_cmp u_cmp (
        .A        (LANE_OPA),
        .B        (LANE_OPB),
        .MODE     (LANE_OP),
        .LANE_IDX (LANE_ID),
        .REF_MIN  (rf_rd_b),
        .Y        (cmp_y),
        .FLAGS    (cmp_flags),
        .MIN_IDX  (cmp_idx)
    );

    case3_lane_sat u_sat (
        .ACC_IN    (LANE_ACC_IN),
        .HI_LIMIT  (hi_limit_w),
        .LO_LIMIT  (lo_limit_w),
        .MODE      (LANE_OP),
        .Y         (sat_y),
        .SAT_FLAGS (sat_flags),
        .SAT_HIT   (sat_hit)
    );

    case3_lane_regfile u_regfile (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .RD_ADDR_A (LANE_RD_ADDR_A),
        .RD_ADDR_B (LANE_RD_ADDR_B),
        .RD_DATA_A (rf_rd_a),
        .RD_DATA_B (rf_rd_b),
        .WR_ADDR   (LANE_WR_ADDR),
        .WR_DATA   (LANE_WR_DATA),
        .WR_EN     (LANE_WR_EN),
        .RD_EN_A   (LANE_WR_EN | (LANE_OP != `C3_OP_NOP)),
        .RD_EN_B   (LANE_STEP),
        .RF_BUSY   (rf_busy)
    );

    case3_lane_agu u_agu (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .BASE       (LANE_AGU_BASE),
        .OFFSET     (LANE_AGU_OFF),
        .STRIDE     (LANE_AGU_STRIDE),
        .MODE       (LANE_OP),
        .STEP       (LANE_STEP),
        .ADDR       (agu_addr),
        .WRAP       (agu_wrap),
        .REQ        (agu_req),
        .BANK_SEL   (agu_bank),
        .LOCAL_ADDR (agu_local)
    );

    case3_lane_aligner u_aligner (
        .DATA_IN    (rf_rd_a),
        .OFFSET     (agu_bank),
        .MODE       (LANE_OP),
        .LANE_SEL   (LANE_SHIFT_AMT),
        .DATA_OUT   (aln_data),
        .BEN        (aln_ben),
        .LANE_MASK  (aln_mask),
        .ALIGN_FLAGS(aln_flags)
    );

    // 流水打拍：位置端口连接（小单元统一风格）
    case3_sync_2ff u_pipe_s0 (CLK, RST_N, agu_req,   pipe_req_s0);
    case3_sync_2ff u_pipe_s1 (CLK, RST_N, mul_valid, pipe_vld_s1);
    case3_sync_2ff u_pipe_s2 (CLK, RST_N, shf_ovf,   pipe_ovf_s2);
    case3_sync_2ff u_pipe_s3 (CLK, RST_N, alu_cout,  pipe_stk_s3);

endmodule
