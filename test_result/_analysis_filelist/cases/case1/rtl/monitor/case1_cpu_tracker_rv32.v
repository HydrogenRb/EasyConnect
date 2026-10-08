//==========================================================================
//  case1_cpu_tracker_rv32.v
//  RV32 CPU 侧 tracker 包装：把 CPU 的 PC/retire 事件打成总线探测事务
//
//  内部例化 case1_cpu_tracker u_track_core（叶子），并按 PC 增量产生
//  TXN_ADDR/TXN_WRITE/TXN_VALID，供 AHB 主机 wrapper 的请求侧使用。
//
//  Ref: RV32 处理器 trace 探针（cpu_tracker_rv32 → cpu_tracker 两级包装），
//       对应 rtl/sub_module/cpu_tracker_rv32.v 的同名结构。
//==========================================================================
`include "case1_define.v"

module case1_cpu_tracker_rv32 (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire [`C1_AHB_ADDR_W-1:0]     PC_ADDR,
    input  wire                          RETIRE_VALID,
    input  wire                          TXN_DONE,
    output wire [`C1_AHB_ADDR_W-1:0]     TXN_ADDR,
    output wire                          TXN_WRITE,
    output wire                          TXN_VALID,
    output wire [`C1_TXN_ID_W-1:0]       TXN_ID,
    output wire [`C1_MON_CNT_W-1:0]      TRACK_CNT,
    output wire                          TRACK_FULL
);

    parameter TRACK_DEPTH = `C1_TRACKER_DEPTH;
    parameter CPU_ID      = 0;

    reg  [`C1_AHB_ADDR_W-1:0]   probe_addr_r;
    reg  [`C1_TXN_ID_W-1:0]     probe_id_r;
    reg                         probe_wr_r;
    reg                         probe_valid_r;

    wire [`C1_MON_CNT_W-1:0]    track_cnt_w;
    wire                        track_full_w;
    wire                        track_valid_w;
    wire                        track_full_n;

    assign track_full_n  = ~track_full_w;
    assign TXN_ADDR    = probe_addr_r;
    assign TXN_WRITE   = probe_wr_r;
    assign TXN_VALID   = probe_valid_r & track_full_n;
    assign TXN_ID      = probe_id_r;
    assign TRACK_CNT   = track_cnt_w;
    assign TRACK_FULL  = track_full_w;
    assign track_valid_w = probe_valid_r;

    //------------------------------------------------------------------
    // PC 增量式探测地址生成
    //------------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            probe_addr_r  <= {`C1_AHB_ADDR_W{1'b0}};
            probe_id_r    <= {`C1_TXN_ID_W{1'b0}};
            probe_wr_r    <= 1'b0;
            probe_valid_r <= 1'b0;
        end else if (RETIRE_VALID) begin
            probe_addr_r  <= PC_ADDR + {{(`C1_AHB_ADDR_W-`C1_TXN_ID_W){1'b0}},
                                        probe_id_r};
            probe_id_r    <= probe_id_r + 1'b1;
            probe_wr_r    <= ~probe_wr_r;
            probe_valid_r <= 1'b1;
        end else if (TXN_DONE) begin
            probe_valid_r <= 1'b0;
        end    end

    //------------------------------------------------------------------
    // 跟踪表本体（叶子）
    //------------------------------------------------------------------
    case1_cpu_tracker #(
        .TRACK_DEPTH (`C1_TRACKER_DEPTH),
        .CPU_ID      (CPU_ID)
    ) u_track_core (
        .HCLK        (HCLK),
        .HRESETn     (HRESETn),
        .TRK_VALID   (track_valid_w),
        .TRK_ADDR    (probe_addr_r),
        .TRK_WRITE   (probe_wr_r),
        .TRK_ID      (probe_id_r),
        .TRK_DONE    (TXN_DONE),
        .TRK_CNT     (track_cnt_w),
        .TRK_LAT_MAX (),
        .TRK_FULL    (track_full_w),
        .TRK_PTR     ()
    );

endmodule
