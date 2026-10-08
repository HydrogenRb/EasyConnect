//==========================================================================
//  case3_define.v  --  case3 SIMD compute-cluster engine 全局宏定义
//
//  本文件是 case3 唯一的宏定义文件：所有位宽 / 编码 / 计数 / 地址映射
//  全部集中在这里。RTL 中不允许出现裸数字作为端口或信号的向量位宽。
//
//  Ref: 模仿真实 SIMD/DSP 加速器项目（Vision-P6 / NVDLA / 小型 NPU 向量引擎）
//       里的 *_define.v —— 位宽段、字段段、opcode 段、计数段、地址映射段
//       逐段排布，前端 tool 直接文本展开即可解析。
//==========================================================================
`ifndef CASE3_DEFINE_V
`define CASE3_DEFINE_V

//------------------------------------------------------------------
// 0. 版本 / 全局开关
//------------------------------------------------------------------
`define C3_VERSION_MAJOR        1
`define C3_VERSION_MINOR        0
`define C3_RST_ACTIVE_LOW       1
`define C3_ENABLE_MONITOR       1

//------------------------------------------------------------------
// 1. DATA：数据通路位宽
//------------------------------------------------------------------
`define C3_DATA_W               32
`define C3_DATA_MSB             31
`define C3_DATA_LSB             0
`define C3_DATA_HALF_W          16
`define C3_DATA_QUART_W         8
`define C3_LANE_W               8
`define C3_LANE_MSB             7
`define C3_PE_W                 16
`define C3_PE_MSB               15
`define C3_ACC_W                40
`define C3_ACC_MSB              39
`define C3_ADDR_W               24
`define C3_ADDR_MSB             23
`define C3_BYTE_W               8
`define C3_BYTE_MSB             7

//------------------------------------------------------------------
// 2. GEOM：阵列几何
//------------------------------------------------------------------
`define C3_CLUSTER_NUM          2
`define C3_CLUSTER_AW           1
`define C3_SLICE_NUM            2
`define C3_SLICE_AW             1
`define C3_LANE_NUM             4
`define C3_LANE_AW              2
`define C3_FU_NUM               6
`define C3_FU_AW                3
`define C3_PE_NUM               2
`define C3_PIPE_NUM             3
`define C3_TOTAL_LANE_NUM       16

//------------------------------------------------------------------
// 3. OPCODE：指令编码（case 选择用）
//------------------------------------------------------------------
`define C3_OP_W                 6
`define C3_OP_ADD               6'h00
`define C3_OP_SUB               6'h01
`define C3_OP_MUL               6'h02
`define C3_OP_MAC               6'h03
`define C3_OP_SLL               6'h04
`define C3_OP_SRL               6'h05
`define C3_OP_SAT               6'h06
`define C3_OP_CMP               6'h07
`define C3_OP_LD                6'h08
`define C3_OP_ST                6'h09
`define C3_OP_NOP               6'h0A
`define C3_OP_HALT              6'h0B
`define C3_OP_RD                6'h0C
`define C3_OP_WR                6'h0D
`define C3_OP_GRP_ALU           3'b000
`define C3_OP_GRP_MUL           3'b001
`define C3_OP_GRP_MEM           3'b010

//------------------------------------------------------------------
// 4. FLAGS：状态位位置与宽度
//------------------------------------------------------------------
`define C3_FLAG_W               5
`define C3_FLAG_ZERO            0
`define C3_FLAG_NEG             1
`define C3_FLAG_OVF             2
`define C3_FLAG_SAT             3
`define C3_FLAG_STICKY          4

//------------------------------------------------------------------
// 5. REG / RF：寄存器堆
//------------------------------------------------------------------
`define C3_REG_ADDR_W           5
`define C3_REG_ADDR_MSB         4
`define C3_REG_NUM              32
`define C3_RF_RD_PORT           2
`define C3_RF_WR_PORT           1
`define C3_RF_RD_AW             1
`define C3_RF_BANK_NUM          2

//------------------------------------------------------------------
// 6. SCRATCH：片上 scratchpad
//------------------------------------------------------------------
`define C3_SCRATCH_ADDR_W       12
`define C3_SCRATCH_MSB          11
`define C3_SCRATCH_DEPTH        4096
`define C3_SCRATCH_DATA_W       32
`define C3_BANK_NUM             4
`define C3_BANK_AW              2
`define C3_BANK_ADDR_W          10
`define C3_BANK_MODE_RW         2'b00
`define C3_BANK_MODE_RO         2'b01
`define C3_BANK_MODE_REPAIR     2'b10
`define C3_LANE_STRIDE          4

//------------------------------------------------------------------
// 7. XFER：DMA / 事务
//------------------------------------------------------------------
`define C3_XFER_ID_W            4
`define C3_XFER_CNT_W           8
`define C3_XFER_LEN_W           12
`define C3_DESC_W               64
`define C3_DESC_MSB             63
`define C3_DESC_AW              6
`define C3_TXN_ID_W             8
`define C3_FIFO_DEPTH           16
`define C3_FIFO_PTR_W           4
`define C3_FIFO_CNT_W           5

//------------------------------------------------------------------
// 8. CFG：配置寄存器接口
//------------------------------------------------------------------
`define C3_CFG_ADDR_W           8
`define C3_CFG_DATA_W           32
`define C3_CFG_REG_NUM          16
`define C3_CTRL_W               8
`define C3_STATUS_W             8

//------------------------------------------------------------------
// 9. PERF：性能计数器
//------------------------------------------------------------------
`define C3_CNT_W                32
`define C3_CNT_MSB              31
`define C3_MON_SEL_W            4
`define C3_MON_NUM              8
`define C3_PERF_WRAP_EN         1
`define C3_PERF_WRAP_VAL        32'h0000FFFF

//------------------------------------------------------------------
// 10. LAT：流水线延迟
//------------------------------------------------------------------
`define C3_MUL_LAT              3
`define C3_ADD_LAT              2
`define C3_SHIFT_LAT            2
`define C3_PIPE_STAGE           3
`define C3_ROUND_W              2

//------------------------------------------------------------------
// 11. ADDRMAP：地址映射
//------------------------------------------------------------------
`define C3_ADDR_DEC_W           3
`define C3_SCRATCH_BASE         24'h000000
`define C3_SCRATCH_END          24'h00FFFF
`define C3_CFG_BASE             24'h010000
`define C3_CFG_END              24'h0100FF
`define C3_DESC_BASE            24'h020000
`define C3_DESC_END             24'h020FFF
`define C3_REGFILE_BASE         24'h030000
`define C3_PERF_BASE            24'h040000
`define C3_XBAR_ROUND_ROBIN     2'b01
`define C3_XBAR_FIXED_PRIO      2'b10

`endif // CASE3_DEFINE_V
