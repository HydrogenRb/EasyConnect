//==========================================================================
//  case2_define.v
//  case2 (CHI-based 2x2 mesh NoC) 全局宏定义
//
//  内容分区：
//    1. CHI 字段位宽 / 位序
//    2. REQ flit 布局        (128 bit)
//    3. RSP flit 布局        ( 64 bit)
//    4. SNP flit 布局        ( 64 bit)
//    5. DAT flit 布局        (320 bit)
//    6. Opcode 编码表
//    7. Resp / RespErr / FwdState / DataSource 编码
//    8. NoC 几何 / VC / credit / buffer
//    9. 节点与链路数量
//   10. RAM 宏单元几何
//   11. 配置空间地址
//   12. 由上面推导出来的平坦总线位宽
//
//  Ref: Arm CHI (AMBA 5) 通道命名 REQ/RSP/SNP/DAT 与字段命名
//       (QoS/TgtID/SrcID/TxnID/ReturnNID/Opcode/Size/Addr/NS/MemAttr/
//        SnpAttr/ExpCompAck/Tag/RespErr/Resp/FwdState/DataSource/
//        DataID/CCID/BE/Data/DBID/P-Credit/CBusy/FwdNID/FwdTxnID/
//        RetToSrc/TraceTag)，编码值为本样本自用的示意值。
//==========================================================================
`ifndef CASE2_DEFINE_V
`define CASE2_DEFINE_V

//------------------------------------------------------------------
// 1. CHI 字段位宽
//------------------------------------------------------------------
`define C2_CHI_NODEID_W        7
`define C2_CHI_NODEID_MSB      6
`define C2_CHI_TXNID_W         8
`define C2_CHI_TXNID_MSB       7
`define C2_CHI_QOS_W           4
`define C2_CHI_QOS_MSB         3
`define C2_CHI_OPCODE_W        6
`define C2_CHI_OPCODE_MSB      5
`define C2_CHI_SIZE_W          3
`define C2_CHI_SIZE_MSB        2
`define C2_CHI_MEMATTR_W       4
`define C2_CHI_MEMATTR_MSB     3
`define C2_CHI_SNPATTR_W       1
`define C2_CHI_SNPATTR_MSB     0
`define C2_CHI_RESP_W          3
`define C2_CHI_RESP_MSB        2
`define C2_CHI_RESPERR_W       2
`define C2_CHI_RESPERR_MSB     1
`define C2_CHI_FWDSTATE_W      3
`define C2_CHI_FWDSTATE_MSB    2
`define C2_CHI_DATASOURCE_W    3
`define C2_CHI_DATASOURCE_MSB  2
`define C2_CHI_BE_W            32
`define C2_CHI_BE_MSB          31
`define C2_CHI_ADDR_W          44
`define C2_CHI_ADDR_MSB        43
`define C2_CHI_DATA_W          256
`define C2_CHI_DATA_MSB        255
`define C2_CHI_DATAID_W        2
`define C2_CHI_DATAID_MSB      1
`define C2_CHI_TAG_W           4
`define C2_CHI_TAG_MSB         3
`define C2_CHI_DBID_W          8
`define C2_CHI_DBID_MSB        7
`define C2_CHI_CCID_W          2
`define C2_CHI_CCID_MSB        1
`define C2_CHI_LPID_W          5
`define C2_CHI_LPID_MSB        4
`define C2_CHI_MPAM_W          2
`define C2_CHI_MPAM_MSB        1
`define C2_CHI_PCRDTYPE_W      2
`define C2_CHI_PCRDTYPE_MSB    1
`define C2_CHI_RETTOSRC_W      1
`define C2_CHI_RETTOSRC_MSB    0
`define C2_CHI_EXPCOMPACK_W    1
`define C2_CHI_EXPCOMPACK_MSB  0
`define C2_CHI_CBUSY_W         2
`define C2_CHI_CBUSY_MSB       1
`define C2_CHI_TRACETAG_W      4
`define C2_CHI_TRACETAG_MSB    3
`define C2_CHI_ALLOWRETRY_W    1
`define C2_CHI_ALLOWRETRY_MSB  0
`define C2_CHI_ORDER_W         3
`define C2_CHI_ORDER_MSB       2
`define C2_CHI_SPARE_W         18

//------------------------------------------------------------------
// 2. REQ flit : 128 bit
//------------------------------------------------------------------
`define C2_REQ_FLIT_W          128
`define C2_REQ_FLIT_MSB        127
`define C2_REQ_FLIT_SPARE_W    18
`define C2_REQ_FIELD_QOS_MSB        127
`define C2_REQ_FIELD_QOS_LSB        124
`define C2_REQ_FIELD_TGTID_MSB      123
`define C2_REQ_FIELD_TGTID_LSB      117
`define C2_REQ_FIELD_SRCID_MSB      116
`define C2_REQ_FIELD_SRCID_LSB      110
`define C2_REQ_FIELD_TXNID_MSB      109
`define C2_REQ_FIELD_TXNID_LSB      102
`define C2_REQ_FIELD_RETURNID_MSB   101
`define C2_REQ_FIELD_RETURNID_LSB   95
`define C2_REQ_FIELD_OPCODE_MSB     94
`define C2_REQ_FIELD_OPCODE_LSB     89
`define C2_REQ_FIELD_SIZE_MSB       88
`define C2_REQ_FIELD_SIZE_LSB       86
`define C2_REQ_FIELD_ADDR_MSB       85
`define C2_REQ_FIELD_ADDR_LSB       42
`define C2_REQ_FIELD_NS_MSB         41
`define C2_REQ_FIELD_NS_LSB         41
`define C2_REQ_FIELD_MEMATTR_MSB    40
`define C2_REQ_FIELD_MEMATTR_LSB    37
`define C2_REQ_FIELD_SNPATTR_MSB    36
`define C2_REQ_FIELD_SNPATTR_LSB    36
`define C2_REQ_FIELD_EXPCOMPACK_MSB 35
`define C2_REQ_FIELD_EXPCOMPACK_LSB 35
`define C2_REQ_FIELD_TAG_MSB        34
`define C2_REQ_FIELD_TAG_LSB        31
`define C2_REQ_FIELD_LPID_MSB       30
`define C2_REQ_FIELD_LPID_LSB       26
`define C2_REQ_FIELD_MPAM_MSB       25
`define C2_REQ_FIELD_MPAM_LSB       24
`define C2_REQ_FIELD_PCRDTYPE_MSB   23
`define C2_REQ_FIELD_PCRDTYPE_LSB   22
`define C2_REQ_FIELD_ALLOWRETRY_MSB 21
`define C2_REQ_FIELD_ALLOWRETRY_LSB 21
`define C2_REQ_FIELD_ORDER_MSB      20
`define C2_REQ_FIELD_ORDER_LSB      18

//------------------------------------------------------------------
// 3. RSP flit : 64 bit
//------------------------------------------------------------------
`define C2_RSP_FLIT_W          64
`define C2_RSP_FLIT_MSB        63
`define C2_RSP_FIELD_QOS_MSB         63
`define C2_RSP_FIELD_QOS_LSB         60
`define C2_RSP_FIELD_TGTID_MSB       59
`define C2_RSP_FIELD_TGTID_LSB       53
`define C2_RSP_FIELD_SRCID_MSB       52
`define C2_RSP_FIELD_SRCID_LSB       46
`define C2_RSP_FIELD_TXNID_MSB       45
`define C2_RSP_FIELD_TXNID_LSB       38
`define C2_RSP_FIELD_OPCODE_MSB      37
`define C2_RSP_FIELD_OPCODE_LSB      32
`define C2_RSP_FIELD_RESPERR_MSB     31
`define C2_RSP_FIELD_RESPERR_LSB     30
`define C2_RSP_FIELD_RESP_MSB        29
`define C2_RSP_FIELD_RESP_LSB        27
`define C2_RSP_FIELD_FWDSTATE_MSB    26
`define C2_RSP_FIELD_FWDSTATE_LSB    24
`define C2_RSP_FIELD_DATASOURCE_MSB  23
`define C2_RSP_FIELD_DATASOURCE_LSB  21
`define C2_RSP_FIELD_DBID_MSB        20
`define C2_RSP_FIELD_DBID_LSB        13
`define C2_RSP_FIELD_CBUSY_MSB       12
`define C2_RSP_FIELD_CBUSY_LSB       11
`define C2_RSP_FIELD_TAG_MSB         10
`define C2_RSP_FIELD_TAG_LSB         7
`define C2_RSP_FIELD_TRACETAG_MSB    6
`define C2_RSP_FIELD_TRACETAG_LSB    3
`define C2_RSP_FIELD_RETTOSRC_MSB    2
`define C2_RSP_FIELD_RETTOSRC_LSB    2
`define C2_RSP_FIELD_CCID_MSB        1
`define C2_RSP_FIELD_CCID_LSB        0

//------------------------------------------------------------------
// 4. SNP flit : 64 bit
//------------------------------------------------------------------
`define C2_SNP_FLIT_W          64
`define C2_SNP_FLIT_MSB        63
`define C2_SNP_FIELD_QOS_MSB         63
`define C2_SNP_FIELD_QOS_LSB         60
`define C2_SNP_FIELD_SRCID_MSB       59
`define C2_SNP_FIELD_SRCID_LSB       53
`define C2_SNP_FIELD_TXNID_MSB       52
`define C2_SNP_FIELD_TXNID_LSB       45
`define C2_SNP_FIELD_FWDNID_MSB      44
`define C2_SNP_FIELD_FWDNID_LSB      38
`define C2_SNP_FIELD_FWDTXNID_MSB    37
`define C2_SNP_FIELD_FWDTXNID_LSB    30
`define C2_SNP_FIELD_OPCODE_MSB      29
`define C2_SNP_FIELD_OPCODE_LSB      24
`define C2_SNP_FIELD_ADDR_MSB        23
`define C2_SNP_FIELD_ADDR_LSB        4
`define C2_SNP_FIELD_NS_MSB          3
`define C2_SNP_FIELD_NS_LSB          3
`define C2_SNP_FIELD_RETTOSRC_MSB    2
`define C2_SNP_FIELD_RETTOSRC_LSB    2
`define C2_SNP_FIELD_CBUSY_MSB       1
`define C2_SNP_FIELD_CBUSY_LSB       0

//------------------------------------------------------------------
// 5. DAT flit : 320 bit
//    [255:0] Data / [287:256] BE / 其余为 header
//------------------------------------------------------------------
`define C2_DAT_FLIT_W          320
`define C2_DAT_FLIT_MSB        319
`define C2_DAT_FIELD_QOS_MSB         319
`define C2_DAT_FIELD_QOS_LSB         316
`define C2_DAT_FIELD_OPCODE_MSB      315
`define C2_DAT_FIELD_OPCODE_LSB      310
`define C2_DAT_FIELD_RESP_MSB        309
`define C2_DAT_FIELD_RESP_LSB        307
`define C2_DAT_FIELD_RESPERR_MSB     306
`define C2_DAT_FIELD_RESPERR_LSB     305
`define C2_DAT_FIELD_DATASOURCE_MSB  304
`define C2_DAT_FIELD_DATASOURCE_LSB  302
`define C2_DAT_FIELD_CBUSY_MSB       301
`define C2_DAT_FIELD_CBUSY_LSB       300
`define C2_DAT_FIELD_DATAID_MSB      299
`define C2_DAT_FIELD_DATAID_LSB      298
`define C2_DAT_FIELD_CCID_MSB        297
`define C2_DAT_FIELD_CCID_LSB        296
`define C2_DAT_FIELD_DBID_MSB        295
`define C2_DAT_FIELD_DBID_LSB        288
`define C2_DAT_FIELD_BE_MSB          287
`define C2_DAT_FIELD_BE_LSB          256
`define C2_DAT_FIELD_DATA_MSB        255
`define C2_DAT_FIELD_DATA_LSB        0

//------------------------------------------------------------------
// 6. Opcode 编码表（本样本统一使用，不再另建第二张表）
//------------------------------------------------------------------
`define C2_OP_READ_SHARED        6'h01
`define C2_OP_READ_UNIQUE        6'h03
`define C2_OP_READ_ONCE          6'h04
`define C2_OP_READ_CLEAN         6'h05
`define C2_OP_WRITE_UNIQUE       6'h12
`define C2_OP_WRITE_BACK_FULL    6'h1B
`define C2_OP_WRITE_EVICT_FULL   6'h19
`define C2_OP_WRITE_CLEAN_FULL   6'h1A
`define C2_OP_CLEAN_UNIQUE       6'h09
`define C2_OP_CLEAN_SHARED       6'h08
`define C2_OP_CLEAN_INVALID      6'h0B
`define C2_OP_MAKE_UNIQUE        6'h0C
`define C2_OP_MAKE_INVALID       6'h0D
`define C2_OP_EVICT              6'h0E
`define C2_OP_SNP_UNIQUE         6'h21
`define C2_OP_SNP_SHARED         6'h22
`define C2_OP_SNP_CLEAN          6'h23
`define C2_OP_SNP_ONCE           6'h24
`define C2_OP_COMP_DATA          6'h29
`define C2_OP_COMP               6'h28
`define C2_OP_COMP_DBID_RESP     6'h2A
`define C2_OP_DBID_RESP          6'h2B
`define C2_OP_RETRY_ACK          6'h2C
`define C2_OP_PCRD_GRANT         6'h2D
`define C2_OP_SNP_RESP           6'h2E
`define C2_OP_SNP_RESP_DATA      6'h2F
`define C2_OP_COPYBACK_WRDATA    6'h30

//------------------------------------------------------------------
// 7. Resp / RespErr / FwdState / DataSource / CBusy
//------------------------------------------------------------------
`define C2_RESP_ICO              3'b000
`define C2_RESP_SC               3'b001
`define C2_RESP_UC               3'b010
`define C2_RESP_UD_PD            3'b011
`define C2_RESP_SD_PD            3'b100
`define C2_RESP_I_PD             3'b101
`define C2_RESP_UD               3'b110
`define C2_RESP_SD               3'b111
`define C2_RESPERR_OKAY          2'b00
`define C2_RESPERR_EXOKAY        2'b01
`define C2_RESPERR_DERR          2'b10
`define C2_RESPERR_NDERR         2'b11
`define C2_FWDSTATE_I            3'b000
`define C2_FWDSTATE_SC           3'b001

//------------------------------------------------------------------
// 8. NoC 几何 / VC / credit / buffer
//------------------------------------------------------------------
`define C2_NOC_X                 2
`define C2_NOC_Y                 2
`define C2_NOC_X_W               1
`define C2_NOC_Y_W               1
`define C2_NOC_ROUTER_NUM        4
`define C2_LOCAL_PORT            4
`define C2_PORT_NUM              5
`define C2_PORT_AW               3
`define C2_DIR_NUM               4
`define C2_VC_NUM                2
`define C2_VC_AW                 1
`define C2_FLIT_W                320
`define C2_FLIT_MSB              319
`define C2_FLIT_KIND_W           2
`define C2_KIND_REQ              2'b00
`define C2_KIND_RSP              2'b01
`define C2_KIND_SNP              2'b10
`define C2_KIND_DAT              2'b11
`define C2_KIND_NUM              4
`define C2_CREDIT_W              5
`define C2_CREDIT_MAX            16
`define C2_CREDIT_INIT           8
`define C2_BUF_DEPTH             16
`define C2_BUF_PTR_W             4
`define C2_ROUTE_X               1'b0
`define C2_ROUTE_Y               1'b1

// 端口索引：0=S 1=N 2=E 3=W 4=LOCAL
`define C2_PORT_S                0
`define C2_PORT_N                1
`define C2_PORT_E                2
`define C2_PORT_W                3
`define C2_PORT_LOCAL            4

// 路由模式
`define C2_ROUTE_W               2
`define C2_ROUTE_LOCAL           2'b00
`define C2_ROUTE_X_FIRST         2'b01
`define C2_ROUTE_Y_FIRST         2'b10
`define C2_ROUTE_BCAST           2'b11

// 通道 / flit 类型编号（数组展开时使用）
`define C2_CH_REQ                0
`define C2_CH_RSP                1
`define C2_CH_SNP                2
`define C2_CH_DAT                3

// 平坦总线：mesh 端口分组
`define C2_LOCAL_LANE_NUM        4
`define C2_BOUND_LANE_NUM        2
`define C2_SN_LANE_NUM           1
`define C2_BOUND_GROUP_NUM       4
`define C2_LINK_DIR_NUM          2
`define C2_ARB_LOCAL_SRC_NUM     2

// 窄通道搬到 320bit 物理 flit 总线时的补零宽度
`define C2_REQ_PAD_W             192
`define C2_RSP_PAD_W             256
`define C2_SNP_PAD_W             256
`define C2_DAT_PAD_W             0

//------------------------------------------------------------------
// 9. 节点 / 链路数量
//------------------------------------------------------------------
`define C2_RN_NUM                4
`define C2_SN_NUM                8
`define C2_SN_AW                 3
`define C2_HN_NUM                1
`define C2_LINK_NUM              16
`define C2_DIR_IDX_W             4
`define C2_SNP_FILTER_W          64
`define C2_RN_ID_BASE            7'h00
`define C2_HN_ID_BASE            7'h10
`define C2_SN_ID_BASE            7'h18

//------------------------------------------------------------------
// 10. RAM 宏单元几何（配合 lib_ram_cells.v 的 #() 覆盖使用）
//------------------------------------------------------------------
`define C2_BUF_RAM_AW            8
`define C2_BUF_RAM_DW            32
`define C2_BUF_RAM_DEPTH         256
`define C2_TAG_RAM_AW            7
`define C2_TAG_RAM_DW            32
`define C2_TAG_RAM_DEPTH         128
`define C2_BUF_RAM_WORDS         10

//------------------------------------------------------------------
// 11. 配置空间
//------------------------------------------------------------------
`define C2_CFG_ADDR_W            12
`define C2_CFG_DATA_W            32
`define C2_CFG_NUM               8
`define C2_CFG_ADDR_NOC_CTRL     12'h000
`define C2_CFG_ADDR_CREDIT_CFG   12'h040
`define C2_CFG_ADDR_ROUTE_CFG    12'h080
`define C2_CFG_ADDR_PERF_CFG     12'h0C0
`define C2_ADDR_MEM_BASE         44'h0_0000_0000
`define C2_ADDR_MEM_SIZE         44'h0_1000_0000

//------------------------------------------------------------------
// 12. 由上面推导的平坦总线位宽
//------------------------------------------------------------------
`define C2_ROUTER_REQ_W    (`C2_PORT_NUM*`C2_REQ_FLIT_W)
`define C2_ROUTER_RSP_W    (`C2_PORT_NUM*`C2_RSP_FLIT_W)
`define C2_ROUTER_SNP_W    (`C2_PORT_NUM*`C2_SNP_FLIT_W)
`define C2_ROUTER_DAT_W    (`C2_PORT_NUM*`C2_DAT_FLIT_W)
`define C2_ROUTER_CREDIT_W (`C2_PORT_NUM*`C2_CREDIT_W)
`define C2_ROUTER_ROUTE_W  (`C2_PORT_NUM*`C2_PORT_AW)
`define C2_MESH_REQ_W      (`C2_NOC_ROUTER_NUM*`C2_ROUTER_REQ_W)
`define C2_MESH_RSP_W      (`C2_NOC_ROUTER_NUM*`C2_ROUTER_RSP_W)
`define C2_MESH_SNP_W      (`C2_NOC_ROUTER_NUM*`C2_ROUTER_SNP_W)
`define C2_MESH_DAT_W      (`C2_NOC_ROUTER_NUM*`C2_ROUTER_DAT_W)
`define C2_MESH_CREDIT_W   (`C2_NOC_ROUTER_NUM*`C2_ROUTER_CREDIT_W)
`define C2_MESH_ROUTE_W    (`C2_NOC_ROUTER_NUM*`C2_ROUTER_ROUTE_W)

//------------------------------------------------------------------
// 13. 常用 MSB 别名与内部寄存器位宽
//------------------------------------------------------------------
`define C2_CHI_NODEID_LSB     0
`define C2_CHI_TXNID_LSB      0
`define C2_CHI_OPCODE_LSB     0
`define C2_CHI_ADDR_LSB       0
`define C2_CHI_DATA_LSB       0
`define C2_CHI_BE_LSB         0
`define C2_CHI_DBID_LSB       0
`define C2_CHI_TAG_LSB        0
`define C2_CFG_ADDR_MSB       11
`define C2_CFG_DATA_MSB       31
`define C2_CFG_SEL_W          3
`define C2_PORT_MSB           4
`define C2_VC_MSB             1
`define C2_CREDIT_MSB         4
`define C2_BUF_PTR_MSB        3
`define C2_BUF_DEPTH_MSB      15
`define C2_FLIT_KIND_MSB      1
`define C2_ROUTE_MSB          1
`define C2_SNP_FILTER_MSB     63
`define C2_SYNC_STAGE_W       2
`define C2_STATE_W            4
`define C2_RAM_BEN_W          4
`define C2_BE_BYTE_W          8
`define C2_OPCODE_DEC_W       8

//------------------------------------------------------------------
// 14. mesh 边界 lane 编号（用于 mesh_link / credit 记账的平坦索引）
//     lane 0,1 = N(x=0,1)  lane 2,3 = S(x=0,1)
//     lane 4,5 = W(y=0,1)  lane 6,7 = E(y=0,1)
//------------------------------------------------------------------
`define C2_LANE_N_BASE        0
`define C2_LANE_S_BASE        2
`define C2_LANE_W_BASE        4
`define C2_LANE_E_BASE        6

`endif // CASE2_DEFINE_V
