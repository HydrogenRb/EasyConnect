//==========================================================================
//  lib_define.v
//  共享库单元（RAM 宏单元）位宽定义
//
//  这些宏供 rtl/common/lib/lib_ram_cells.v 中的 RAM_SP / RAM_DP /
//  RAM_2P / RAM_SP_BE 使用。各 case 的 *_define.v 可以在此之前先定义
//  同名宏来覆盖默认值（`ifndef 保护）。
//
//  模仿真实工艺库 memory compiler 的输出：一个固定几何的宏单元，
//  使用时由 wrapper 去做位宽适配。
//==========================================================================
`ifndef LIB_DEFINE_V
`define LIB_DEFINE_V

//------------------------------------------------------------------
// 1. 单口 RAM（RAM_SP / RAM_SP_BE）
//------------------------------------------------------------------
`ifndef LIB_RAM_ADDR_W
`define LIB_RAM_ADDR_W       10      // 1024 words
`endif
`ifndef LIB_RAM_ADDR_MSB
`define LIB_RAM_ADDR_MSB     9
`endif
`ifndef LIB_RAM_DATA_W
`define LIB_RAM_DATA_W       32
`endif
`ifndef LIB_RAM_DATA_MSB
`define LIB_RAM_DATA_MSB     31
`endif
`ifndef LIB_RAM_BEN_W
`define LIB_RAM_BEN_W        4       // DATA_W / 8
`endif
`ifndef LIB_RAM_DEPTH
`define LIB_RAM_DEPTH        1024
`endif

//------------------------------------------------------------------
// 2. 双口 RAM（RAM_DP / RAM_2P）
//    端口 A 与端口 B 各自独立，地址/数据位宽与单口一致
//------------------------------------------------------------------
`ifndef LIB_RAM_A_ADDR_W
`define LIB_RAM_A_ADDR_W     10
`endif
`ifndef LIB_RAM_B_ADDR_W
`define LIB_RAM_B_ADDR_W     10
`endif
`ifndef LIB_RAM_A_DATA_W
`define LIB_RAM_A_DATA_W     32
`endif
`ifndef LIB_RAM_B_DATA_W
`define LIB_RAM_B_DATA_W     32
`endif

//------------------------------------------------------------------
// 3. RAM 宏单元通用时序常数
//------------------------------------------------------------------
`ifndef LIB_RAM_WRITE_MODE
`define LIB_RAM_WRITE_MODE   "READ_FIRST"   // 读优先：写时不改写读出数据
`endif
`ifndef LIB_RAM_INIT_FILE
`define LIB_RAM_INIT_FILE    "ram_init.hex"
`endif

`endif // LIB_DEFINE_V
