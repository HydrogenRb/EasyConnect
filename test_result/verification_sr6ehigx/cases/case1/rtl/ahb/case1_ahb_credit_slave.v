//==========================================================================
//  case1_ahb_credit_slave.v
//  每个 AHB 从机端口的 credit 归还生成器 + 未完成事务表
//
//  每次从机完成一个数据相位（S_TXN_START & S_HREADY），未完成计数减一，
//  并按 CR_RET_CNT 归还 credit 给主机侧。未完成事务表放在 RAM_SP 里
//  （深度 `C1_TRACKER_DEPTH，通过 `C1_RAM_ADDR_W 地址适配到库单元），
//  这样 RAM_SP 直接成为层次树里的叶子。
//
//  Ref: 桥/NoC 接收侧的 credit return generator + outstanding transaction
//       table（credit-based flow control 的"接收端归还"实现）。
//==========================================================================
`include "case1_define.v"

module case1_ahb_credit_slave (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire                          S_HSEL,
    input  wire                          S_HREADY,
    input  wire                          S_TXN_START,
    output reg                           CR_RET_VALID,
    output reg  [`C1_CR_CNT_W-1:0]       CR_RET_CNT,
    output reg  [`C1_CR_CNT_W-1:0]       OUTSTANDING,
    output reg  [`C1_MON_CNT_W-1:0]      CREDIT_STAT,
    output wire                          TBL_BUSY
);

    // 从机索引 / 未完成事务表深度
    parameter SLV_IDX     = 0;
    parameter TRACK_DEPTH = `C1_TRACKER_DEPTH;

    reg  [`C1_TRACKER_PTR_W-1:0]  entry_ptr;
    reg  [`C1_TRACKER_PTR_W-1:0]  ret_ptr;
    reg  [`C1_CR_CNT_W-1:0]       out_cnt_r;
    reg                           valid_r;
    reg                           kind_r;
    reg  [`C1_TXN_ID_W-1:0]       txn_id_r;
    reg  [`C1_MON_CNT_W-1:0]      ret_total_r;

    wire [`C1_RAM_ADDR_W-1:0]     tbl_addr;
    wire [`C1_RAM_DATA_W-1:0]     tbl_d;
    wire [`C1_RAM_DATA_W-1:0]     tbl_q;
    wire [`C1_RAM_BEN_W-1:0]      tbl_ben;
    wire                          tbl_cen;
    wire                          tbl_wen;
    wire [`C1_TRACKER_ENTRY_W-1:0] entry_data;

    assign TBL_BUSY = (out_cnt_r != {`C1_CR_CNT_W{1'b0}});
    assign tbl_cen  = 1'b0;
    assign tbl_wen  = S_TXN_START ? `C1_RAM_WR_EN : 1'b1;
    assign tbl_ben  = {`C1_RAM_BEN_W{1'b0}};

    // 指针（3bit）零扩展到库单元地址宽度（10bit）
    assign tbl_addr = {{(`C1_RAM_ADDR_W-`C1_TRACKER_PTR_W){1'b0}}, entry_ptr};

    assign entry_data = {{(`C1_TRACKER_ENTRY_W-`C1_CR_CNT_W-2){1'b0}},
                         out_cnt_r, kind_r, valid_r};
    assign tbl_d      = {{(`C1_RAM_DATA_W-`C1_TRACKER_ENTRY_W){1'b0}}, entry_data};

    // 未完成事务表：库单元 RAM_SP（叶子，位置连接）
    RAM_SP u_outstanding_tbl (HCLK, tbl_cen, tbl_wen, tbl_ben, tbl_addr, tbl_d, tbl_q);

    //------------------------------------------------------------------
    // 未完成计数与归还生成
    //------------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            entry_ptr    <= {`C1_TRACKER_PTR_W{1'b0}};
            ret_ptr      <= {`C1_TRACKER_PTR_W{1'b0}};
            out_cnt_r    <= {`C1_CR_CNT_W{1'b0}};
            valid_r      <= 1'b0;
            kind_r       <= `C1_TXN_KIND_RD;
            txn_id_r     <= {`C1_TXN_ID_W{1'b0}};
            ret_total_r  <= {`C1_MON_CNT_W{1'b0}};
            CR_RET_VALID <= 1'b0;
            CR_RET_CNT   <= {`C1_CR_CNT_W{1'b0}};
            OUTSTANDING  <= {`C1_CR_CNT_W{1'b0}};
            CREDIT_STAT  <= {`C1_MON_CNT_W{1'b0}};
        end else begin
            CR_RET_VALID <= 1'b0;
            CR_RET_CNT   <= {`C1_CR_CNT_W{1'b0}};

            if (S_TXN_START) begin
                entry_ptr   <= entry_ptr + 1'b1;
                out_cnt_r   <= (out_cnt_r == `C1_CR_MAX) ? out_cnt_r
                                                         : (out_cnt_r + 1'b1);
                valid_r     <= 1'b1;
                kind_r      <= `C1_TXN_KIND_WR;
                txn_id_r    <= txn_id_r + 1'b1;
            end else if (S_HSEL && S_HREADY && (out_cnt_r != {`C1_CR_CNT_W{1'b0}})) begin
                // 事务完成：归还一个 credit
                out_cnt_r    <= out_cnt_r - 1'b1;
                ret_ptr      <= ret_ptr + 1'b1;
                CR_RET_VALID <= 1'b1;
                CR_RET_CNT   <= {{(`C1_CR_CNT_W-1){1'b0}}, 1'b1};
                ret_total_r  <= ret_total_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                valid_r      <= (out_cnt_r > {{(`C1_CR_CNT_W-1){1'b0}}, 1'b1});
            end

            OUTSTANDING <= out_cnt_r;
            CREDIT_STAT <= ret_total_r;
        end
    end

endmodule
