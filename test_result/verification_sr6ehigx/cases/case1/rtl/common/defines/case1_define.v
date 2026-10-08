//==========================================================================
//  case1_define.v
//  case1（AHB/APB 子系统 + credit 流控）统一宏定义文件
//
//  收纳内容：
//    (1) AHB-Lite 位宽 / 字段编码
//    (2) APB    位宽 / 状态编码
//    (3) credit 流控参数（水位、类别、归还缓冲）
//    (4) 地址映射（SLV0..SLV3 / 外设窗口）
//    (5) 外设 slot / 寄存器 / FIFO 几何参数
//    (6) CDC 同步器与 monitor / tracker 参数
//
//  Ref: AHB-Lite 多主机互连（ARM IHI0033）、APB4 桥（ARM IHI0024）、
//       以及 NoC/桥链路里的 credit-based link flow control 实现。
//
//  约定：所有 RTL 端口/信号的向量上下界都只能引用本文件的宏，
//        不允许出现裸数字（见 STYLE_GUIDE.md §2）。
//==========================================================================
`ifndef CASE1_DEFINE_V
// 注意：include guard 宏带一个非空值 1（而不是空值）——空值 `define 会让
// 简单的文本级宏提取器把下一行也吞进本宏的值里（见 tools/verify_cases.py
// 的 extract_macros：`^\s*`define\s+NAME\s*(.*)$` 会跨行匹配空白）。
`define CASE1_DEFINE_V       1

//------------------------------------------------------------------
// 1. AHB-Lite 位宽（rtl/ahb/*, rtl/top/case1_soc_top.v）
//------------------------------------------------------------------
`define C1_AHB_ADDR_W        32      // 传输地址宽度
`define C1_AHB_ADDR_MSB      31
`define C1_AHB_ADDR_LSB      0
`define C1_AHB_DATA_W        32      // 数据总线宽度
`define C1_AHB_DATA_MSB      31
`define C1_AHB_DATA_LSB      0
`define C1_AHB_STRB_W        4       // 写字节选通宽度 = DATA_W/8
`define C1_AHB_STRB_MSB      3
`define C1_AHB_BYTE_W        8       // 单字节宽度
`define C1_AHB_MASTER_NUM    2       // AHB 主机数（CPU + DMA）
`define C1_AHB_MASTER_AW     1
`define C1_AHB_SLAVE_NUM     4       // AHB 从机数（3 个存储器 + 1 个桥）
`define C1_AHB_SLAVE_AW      2
`define C1_AHB_HTRANS_W      2       // HTRANS 字段
`define C1_AHB_HSIZE_W       3       // HSIZE 字段
`define C1_AHB_HBURST_W      3       // HBURST 字段
`define C1_AHB_HPROT_W       4       // HPROT 字段
`define C1_AHB_HRESP_W       2       // HRESP 字段
`define C1_AHB_HMASTLOCK_W   1       // HMASTLOCK 字段
`define C1_AHB_STATE_W       2       // master/slave FSM 状态宽度

//------------------------------------------------------------------
// 2. AHB 字段编码（case 选择用）
//------------------------------------------------------------------
`define C1_AHB_HTRANS_IDLE   2'b00
`define C1_AHB_HTRANS_BUSY   2'b01
`define C1_AHB_HTRANS_NONSEQ 2'b10
`define C1_AHB_HTRANS_SEQ    2'b11
`define C1_AHB_HRESP_OKAY    2'b00
`define C1_AHB_HRESP_ERROR   2'b01
`define C1_AHB_HRESP_RETRY   2'b10
`define C1_AHB_HRESP_SPLIT   2'b11
`define C1_AHB_HSIZE_BYTE    3'b000
`define C1_AHB_HSIZE_HALF    3'b001
`define C1_AHB_HSIZE_WORD    3'b010
`define C1_AHB_HBURST_SINGLE 3'b000
`define C1_AHB_HBURST_INCR   3'b001
`define C1_AHB_HBURST_WRAP4  3'b010
`define C1_AHB_HBURST_INCR4  3'b011
`define C1_AHB_HBURST_INCR8  3'b101
`define C1_AHB_HPROT_DATA    4'b0011
`define C1_AHB_HPROT_INST    4'b0110
`define C1_AHB_HPROT_PRIV    4'b0001

//------------------------------------------------------------------
// 3. AHB master / slave FSM 状态编码
//------------------------------------------------------------------
`define C1_AHB_ST_IDLE       2'b00
`define C1_AHB_ST_ADDR       2'b01
`define C1_AHB_ST_DATA       2'b10
`define C1_AHB_ST_RESP       2'b11

//------------------------------------------------------------------
// 4. 一 hot 从机选择（decoder 输出 / slave_mux 输入）
//------------------------------------------------------------------
`define C1_HSEL_SLV0         4'b0001
`define C1_HSEL_SLV1         4'b0010
`define C1_HSEL_SLV2         4'b0100
`define C1_HSEL_SLV3         4'b1000
`define C1_HSEL_NONE         4'b0000

//------------------------------------------------------------------
// 5. APB4 位宽与状态编码（rtl/apb/*）
//------------------------------------------------------------------
`define C1_APB_ADDR_W        32
`define C1_APB_ADDR_MSB      31
`define C1_APB_DATA_W        32
`define C1_APB_DATA_MSB      31
`define C1_APB_STRB_W        4
`define C1_APB_PROT_W        3
`define C1_APB_SLV_NUM       4       // APB slot 数
`define C1_APB_SLV_AW        2
`define C1_APB_STATE_W       2
`define C1_APB_SETUP         1'b0
`define C1_APB_ACCESS        1'b1
`define C1_APB_ST_IDLE       2'b00
`define C1_APB_ST_SETUP      2'b01
`define C1_APB_ST_ACCESS     2'b10
`define C1_APB_ST_DONE       2'b11
`define C1_APB_PPROT_DATA    3'b010
`define C1_APB_PPROT_PRIV    3'b001
`define C1_APB_PSTRB_ALL     4'b1111

//------------------------------------------------------------------
// 6. credit 流控参数（rtl/ahb/case1_ahb_credit_*.v, rtl/apb/*）
//------------------------------------------------------------------
`define C1_CR_CNT_W          4       // credit 计数器宽度
`define C1_CR_CNT_MSB        3
`define C1_CR_MAX            8       // 链路最大未完成事务数
`define C1_CR_INIT           4       // 复位后的初始 credit
`define C1_CR_LOW_WM         2       // 低水位
`define C1_CR_HIGH_WM        6       // 高水位
`define C1_CR_CLASS_NUM      4       // credit 类别数（按 QoS 分级）
`define C1_CR_CLASS_AW       2
`define C1_CR_RET_BUF_DEPTH  8       // 归还缓冲深度
`define C1_CR_RET_PTR_W      3
`define C1_CR_RET_CNT_W      4
`define C1_CR_TIMEOUT_W      8
`define C1_CR_EMPTY          1'b1
`define C1_CR_FULL           1'b1

//------------------------------------------------------------------
// 7. 地址映射（decoder / 桥 / slot 译码）
//------------------------------------------------------------------
`define C1_SLV0_BASE         32'h0000_0000
`define C1_SLV1_BASE         32'h1000_0000
`define C1_SLV2_BASE         32'h2000_0000
`define C1_SLV3_BASE         32'h4000_0000
`define C1_SLV0_MASK         32'hF000_0000
`define C1_SLV1_MASK         32'hF000_0000
`define C1_SLV2_MASK         32'hF000_0000
`define C1_SLV3_MASK         32'hF000_0000
`define C1_SLV_DECODE_W      4
`define C1_SLV_DECODE_MSB    31
`define C1_SLV_DECODE_LSB    28
`define C1_SLV0_DECODE       4'h0
`define C1_SLV1_DECODE       4'h1
`define C1_SLV2_DECODE       4'h2
`define C1_SLV3_DECODE       4'h4
`define C1_SLV0_IDX          2'd0
`define C1_SLV1_IDX          2'd1
`define C1_SLV2_IDX          2'd2
`define C1_SLV3_IDX          2'd3
`define C1_SLV_APB_IDX       2'd3      // 索引 3 = APB 桥窗口
`define C1_PERIPH_BASE       32'h4000_0000
`define C1_PERIPH_SIZE       32'h0001_0000
`define C1_APB_SLOT_STRIDE   32'h0000_1000
`define C1_APB_SLOT_LSB      12

//------------------------------------------------------------------
// 8. 外设 slot / 寄存器 / FIFO 几何参数
//------------------------------------------------------------------
`define C1_SLOT_NUM          4
`define C1_SLOT_AW           2
`define C1_REG_ADDR_W        8
`define C1_REG_DATA_W        32
`define C1_REG_NUM           16
`define C1_REG_AW            4
`define C1_REG_IDX_MSB       3
`define C1_FIFO_DEPTH        16
`define C1_FIFO_PTR_W        4
`define C1_FIFO_CNT_W        5
`define C1_FIFO_AFULL_TH     12
`define C1_FIFO_AEMPTY_TH    2
`define C1_FIFO_FLAG_W       2

//------------------------------------------------------------------
// 9. CDC 同步器参数（rtl/apb/case1_apb_cdc.v, rtl/sync/*）
//------------------------------------------------------------------
`define C1_CDC_STAGES        2
`define C1_CDC_BUS_W         32
`define C1_GRAY_W            4
`define C1_CDC_SYNC_FF       2       // 每级同步器打拍数

//------------------------------------------------------------------
// 10. 外设类型 / monitor / tracker 编码
//------------------------------------------------------------------
`define C1_PERIPH_TYPE_W     4
`define C1_PERIPH_UART       4'd0
`define C1_PERIPH_TIMER      4'd1
`define C1_PERIPH_GPIO       4'd2
`define C1_PERIPH_SPI        4'd3
`define C1_PERIPH_WDT        4'd4
`define C1_PERIPH_DMA        4'd5
`define C1_PERIPH_NONE       4'd15
`define C1_TXN_ID_W          4
`define C1_TXN_KIND_RD       1'b0
`define C1_TXN_KIND_WR       1'b1
`define C1_MON_EVT_W         4
`define C1_MON_EVT_IDLE      4'h0
`define C1_MON_EVT_ISSUE     4'h1
`define C1_MON_EVT_RETURN    4'h2
`define C1_MON_EVT_STALL     4'h3
`define C1_MON_EVT_ERROR     4'h4
`define C1_TRK_ST_IDLE       2'b00
`define C1_TRK_ST_LOOKUP     2'b01
`define C1_TRK_ST_UPDATE     2'b10
`define C1_TRK_ST_FLUSH      2'b11

//------------------------------------------------------------------
// 11. 外设私有参数（rtl/periph/*）
//------------------------------------------------------------------
`define C1_TIMER_CNT_W       32
`define C1_TIMER_DIV_W       16
`define C1_UART_BAUD_W       16
`define C1_UART_FIFO_W       8
`define C1_UART_OVS_W        4
`define C1_GPIO_PIN_NUM      32
`define C1_GPIO_PIN_AW       5
`define C1_SPI_FIFO_W        8
`define C1_SPI_CLK_DIV_W     8
`define C1_SPI_MODE_W        2
`define C1_WDT_CNT_W         16
`define C1_WDT_KEY_W         8
`define C1_DMA_DESC_W        64
`define C1_DMA_DESC_MSB      63
`define C1_DMA_LEN_W         12
`define C1_DMA_CH_NUM        4
`define C1_DMA_CH_AW         2
`define C1_DMA_SRC_W         32
`define C1_DMA_DST_W         32

//------------------------------------------------------------------
// 12. monitor / tracker / RAM 适配参数
//------------------------------------------------------------------
`define C1_MON_CNT_W         32
`define C1_MON_CNT_MSB       31
`define C1_TRACKER_DEPTH     8
`define C1_TRACKER_PTR_W     3
`define C1_TRACKER_ENTRY_W   16
`define C1_LATENCY_W         16
`define C1_BW_CNT_W          16
`define C1_RAM_ADDR_W        10      // 与 lib_define.v 的 LIB_RAM_ADDR_W 对齐
`define C1_RAM_ADDR_MSB      9
`define C1_RAM_DATA_W        32
`define C1_RAM_DATA_MSB      31
`define C1_RAM_BEN_W         4
`define C1_RAM_DEPTH         1024
`define C1_RAM_WR_EN         1'b0
`define C1_RAM_RD_EN         1'b1

`endif // CASE1_DEFINE_V
