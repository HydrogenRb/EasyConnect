//==========================================================================
//  case1_ahb_slave_mux.v
//  AHB 从机侧：默认从机阵列 + 读数据/响应回选 + 归还 credit 聚合 + APB 桥
//
//  从机 0..2 是存储器类默认从机（case1_ahb_slave），索引 3 是 APB 窗口：
//  该位置例化 case1_ahb_to_apb_bridge u_bridge，用 #(.APB_SLOT_NUM(...))
//  覆盖 slot 数、用 defparam 覆盖 CR_MAX。返回的 credit 用一条移位流水
//  （ret_sr）整形后送回桥的 CR_RET_* 端口，并与各默认从机的 CR_RETURN
//  一起聚合成 S_CR_RET_VALID / S_CR_RET_CNT 给互连的 credit 通道。
//
//  Ref: AHB-Lite 从机复用（slave mux）+ AHB2APB 桥 + credit return shaper。
//==========================================================================
`include "case1_define.v"

module case1_ahb_slave_mux (
    input  wire                                          HCLK,
    input  wire                                          PCLK,
    input  wire                                          HRESETn,
    input  wire                                          PRESETn,
    input  wire [`C1_AHB_ADDR_W-1:0]                     S_HADDR,
    input  wire [`C1_AHB_HTRANS_W-1:0]                   S_HTRANS,
    input  wire [`C1_AHB_HSIZE_W-1:0]                    S_HSIZE,
    input  wire [`C1_AHB_HBURST_W-1:0]                   S_HBURST,
    input  wire [`C1_AHB_HPROT_W-1:0]                    S_HPROT,
    input  wire                                          S_HWRITE,
    input  wire [`C1_AHB_DATA_W-1:0]                     S_HWDATA,
    input  wire [`C1_AHB_STRB_W-1:0]                     S_HWSTRB,
    input  wire [`C1_AHB_SLAVE_NUM-1:0]                  S_HSEL,
    output wire [`C1_AHB_SLAVE_NUM-1:0]                  S_HREADY,
    output wire [`C1_AHB_SLAVE_NUM*`C1_AHB_DATA_W-1:0]   S_HRDATA,
    output wire [`C1_AHB_SLAVE_NUM*`C1_AHB_HRESP_W-1:0]  S_HRESP,
    output wire [`C1_AHB_SLAVE_NUM-1:0]                  S_CR_RET_VALID,
    output wire [`C1_AHB_SLAVE_NUM*`C1_CR_CNT_W-1:0]     S_CR_RET_CNT,
    output wire                                          APB_BRIDGE_BUSY,
    output wire [`C1_MON_CNT_W-1:0]                      MUX_LATENCY_MAX
);

    // 默认从机的等待周期（每个索引可不同）
    parameter SLV0_WAIT = 2;
    parameter SLV1_WAIT = 1;
    parameter SLV2_WAIT = 3;

    wire [`C1_AHB_DATA_W-1:0]   slv_hrdata [0:`C1_AHB_SLAVE_NUM-1];
    wire [`C1_AHB_HRESP_W-1:0]  slv_hresp  [0:`C1_AHB_SLAVE_NUM-1];
    wire                        slv_hready [0:`C1_AHB_SLAVE_NUM-1];
    wire                        slv_ret    [0:`C1_AHB_SLAVE_NUM-1];
    wire [`C1_MON_CNT_W-1:0]    slv_latency[0:`C1_AHB_SLAVE_NUM-1];

    // APB 桥（索引 3）对外信号
    wire [`C1_AHB_DATA_W-1:0]   br_hrdata;
    wire                        br_hready;
    wire [`C1_AHB_HRESP_W-1:0]  br_hresp;
    wire [`C1_CR_CNT_W-1:0]     br_cr_issued;
    wire                        br_cr_req;

    // AHB 侧返回 credit 整形流水
    reg  [`C1_CR_RET_PTR_W-1:0] ret_sr;
    reg                         ret_valid_r;
    reg  [`C1_CR_CNT_W-1:0]     ret_cnt_r;
    wire                        apb_ret_valid;
    wire [`C1_CR_CNT_W-1:0]     apb_ret_cnt;
    integer                     k;

    assign apb_ret_valid = ret_valid_r;
    assign apb_ret_cnt   = ret_cnt_r;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            ret_sr      <= {`C1_CR_RET_PTR_W{1'b0}};
            ret_valid_r <= 1'b0;
            ret_cnt_r   <= {`C1_CR_CNT_W{1'b0}};
        end else begin
            ret_sr      <= {ret_sr[`C1_CR_RET_PTR_W-2:0], (br_cr_issued != {`C1_CR_CNT_W{1'b0}})};
            ret_valid_r <= ret_sr[`C1_CR_RET_PTR_W-1] | br_cr_req;
            ret_cnt_r   <= (ret_sr[`C1_CR_RET_PTR_W-1] | br_cr_req)
                           ? {{(`C1_CR_CNT_W-1){1'b0}}, 1'b1}
                           : {`C1_CR_CNT_W{1'b0}};
        end
    end

    //------------------------------------------------------------------
    // 默认从机阵列（for-generate，4 个实例名 u_slv[s]）
    //------------------------------------------------------------------
    genvar s;
    generate
        for (s = 0; s < `C1_AHB_SLAVE_NUM; s = s + 1) begin : g_slave
            case1_ahb_slave #(
                .SLAVE_ID    (s),
                .WAIT_CYCLES (SLV0_WAIT),
                .BASE_ADDR   (`C1_SLV0_BASE)
            ) u_slv[s] (
                .HCLK        (HCLK),
                .HRESETn     (HRESETn),
                .HSEL        (S_HSEL[s]),
                .HADDR       (S_HADDR),
                .HTRANS      (S_HTRANS),
                .HSIZE       (S_HSIZE),
                .HBURST      (S_HBURST),
                .HPROT       (S_HPROT),
                .HWRITE      (S_HWRITE),
                .HWDATA      (S_HWDATA),
                .HWSTRB      (S_HWSTRB),
                .HREADYOUT   (slv_hready[s]),
                .HRESP       (slv_hresp[s]),
                .HRDATA      (slv_hrdata[s]),
                .CR_RETURN   (slv_ret[s]),
                .LATENCY_CNT (slv_latency[s])
            );

            // 索引 3 的响应由 APB 桥接管，其余来自默认从机
            assign S_HREADY[s] = (s == `C1_SLV_APB_IDX) ? br_hready : slv_hready[s];
            assign S_HRDATA[s*`C1_AHB_DATA_W +: `C1_AHB_DATA_W] =
                       (s == `C1_SLV_APB_IDX) ? br_hrdata : slv_hrdata[s];
            assign S_HRESP[s*`C1_AHB_HRESP_W +: `C1_AHB_HRESP_W] =
                       (s == `C1_SLV_APB_IDX) ? br_hresp : slv_hresp[s];
            assign S_CR_RET_VALID[s] =
                       (s == `C1_SLV_APB_IDX) ? ret_valid_r : slv_ret[s];
            assign S_CR_RET_CNT[s*`C1_CR_CNT_W +: `C1_CR_CNT_W] =
                       (S_CR_RET_VALID[s]) ? {{(`C1_CR_CNT_W-1){1'b0}}, 1'b1}
                                           : {`C1_CR_CNT_W{1'b0}};
        end
    endgenerate

    //------------------------------------------------------------------
    // APB 桥（AHB 从机索引 3）：#(.APB_SLOT_NUM(...)) + defparam
    //------------------------------------------------------------------
    case1_ahb_to_apb_bridge #(
        .APB_SLOT_NUM (`C1_APB_SLV_NUM),
        .ADDR_LSB     (`C1_APB_SLOT_LSB)
    ) u_bridge (
        .HCLK         (HCLK),
        .HRESETn      (HRESETn),
        .PCLK         (PCLK),
        .PRESETn      (PRESETn),
        .HADDR        (S_HADDR),
        .HTRANS       (S_HTRANS),
        .HSIZE        (S_HSIZE),
        .HBURST       (S_HBURST),
        .HPROT        (S_HPROT),
        .HWRITE       (S_HWRITE),
        .HWDATA       (S_HWDATA),
        .HWSTRB       (S_HWSTRB),
        .HSEL         (S_HSEL[`C1_SLV_APB_IDX]),
        .HRDATA       (br_hrdata),
        .HREADY       (br_hready),
        .HRESP        (br_hresp),
        .CR_RET_CNT   (apb_ret_cnt),
        .CR_RET_VALID (apb_ret_valid),
        .CR_ISSUED    (br_cr_issued),
        .CR_REQ       (br_cr_req),
        .BRIDGE_BUSY  (APB_BRIDGE_BUSY)
    );

    // 桥内部 credit 类别上限由 defparam 覆盖（与 #() 覆盖的参数不同）
    defparam u_bridge.CR_MAX = `C1_CR_MAX;

    //------------------------------------------------------------------
    // 从机延迟统计
    //------------------------------------------------------------------
    reg [`C1_MON_CNT_W-1:0] latency_max_r;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            latency_max_r <= {`C1_MON_CNT_W{1'b0}};
        end else begin
            for (k = 0; k < `C1_AHB_SLAVE_NUM; k = k + 1) begin
                if (slv_latency[k] > latency_max_r) begin
                    latency_max_r <= slv_latency[k];
                end
            end
        end
    end

    assign MUX_LATENCY_MAX = latency_max_r;

endmodule
