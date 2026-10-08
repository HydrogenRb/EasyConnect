//==========================================================================
//  case1_cpu_tracker.v
//  CPU 事务跟踪表（叶子模块，内部无任何例化）
//
//  维护 `C1_TRACKER_DEPTH 条在途事务（地址/读写/ID/延迟），给出计数、
//  最大延迟与满标志；用作 CPU 侧总线行为的可观测性探针。
//
//  Ref: 处理器 trace/跟踪探针（对比 ISS trace 的硬件侧 tracker），
//       见 rtl/sub_module/cpu_tracker.v 的同类实现。
//==========================================================================
`include "case1_define.v"

module case1_cpu_tracker (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire                          TRK_VALID,
    input  wire [`C1_AHB_ADDR_W-1:0]     TRK_ADDR,
    input  wire                          TRK_WRITE,
    input  wire [`C1_TXN_ID_W-1:0]       TRK_ID,
    input  wire                          TRK_DONE,
    output reg  [`C1_MON_CNT_W-1:0]      TRK_CNT,
    output reg  [`C1_LATENCY_W-1:0]      TRK_LAT_MAX,
    output reg                           TRK_FULL,
    output reg  [`C1_TRACKER_PTR_W-1:0]  TRK_PTR
);

    parameter TRACK_DEPTH = `C1_TRACKER_DEPTH;
    parameter CPU_ID      = 0;

    reg [`C1_AHB_ADDR_W-1:0]   entry_addr [0:`C1_TRACKER_DEPTH-1];
    reg                        entry_wr   [0:`C1_TRACKER_DEPTH-1];
    reg [`C1_TXN_ID_W-1:0]     entry_id   [0:`C1_TRACKER_DEPTH-1];
    reg [`C1_LATENCY_W-1:0]    entry_lat  [0:`C1_TRACKER_DEPTH-1];
    reg [(`C1_TRACKER_PTR_W+1)-1:0] occupancy;
    reg [`C1_LATENCY_W-1:0]    lat_cnt;
    integer                    i;

    initial begin
        for (i = 0; i < `C1_TRACKER_DEPTH; i = i + 1) begin
            entry_addr[i] = {`C1_AHB_ADDR_W{1'b0}};
            entry_wr[i]   = 1'b0;
            entry_id[i]   = {`C1_TXN_ID_W{1'b0}};
            entry_lat[i]  = {`C1_LATENCY_W{1'b0}};
        end
    end

    //------------------------------------------------------------------
    // 事务入表 / 出表
    //------------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            TRK_PTR     <= {`C1_TRACKER_PTR_W{1'b0}};
            TRK_CNT     <= {`C1_MON_CNT_W{1'b0}};
            TRK_LAT_MAX <= {`C1_LATENCY_W{1'b0}};
            TRK_FULL    <= 1'b0;
            occupancy   <= {(`C1_TRACKER_PTR_W+1){1'b0}};
            lat_cnt     <= {`C1_LATENCY_W{1'b0}};
        end else begin
            if (TRK_VALID && (TRK_FULL == 1'b0)) begin
                entry_addr[TRK_PTR] <= TRK_ADDR;
                entry_wr[TRK_PTR]   <= TRK_WRITE;
                entry_id[TRK_PTR]   <= TRK_ID;
                entry_lat[TRK_PTR]  <= lat_cnt;
                TRK_PTR             <= TRK_PTR + 1'b1;
                TRK_CNT             <= TRK_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                occupancy           <= occupancy + 1'b1;
                lat_cnt             <= {`C1_LATENCY_W{1'b0}};
            end else begin
                lat_cnt <= lat_cnt + 1'b1;
            end

            if (TRK_DONE && (occupancy != {(`C1_TRACKER_PTR_W+1){1'b0}})) begin
                occupancy <= occupancy - 1'b1;
                if (entry_lat[TRK_PTR] > TRK_LAT_MAX) begin
                    TRK_LAT_MAX <= entry_lat[TRK_PTR];
                end
            end

            TRK_FULL <= (occupancy >= `C1_TRACKER_DEPTH);
        end
    end

endmodule
