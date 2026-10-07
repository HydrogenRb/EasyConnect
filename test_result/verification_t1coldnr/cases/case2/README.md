# case2 — CHI 一致性 NoC（2x2 mesh + credit 流控）

TOP: `case2_chi_noc_top`

## 主题

模拟一颗 Arm CHI 风格的一致性互连：**2x2 mesh NoC**，4 个 request node（RN）、
1 个 home node（HN）、8 个 slave node（SN）。CHI 的四个通道 REQ/RSP/SNP/DAT 被
打包成 flit（128/64/64/320 bit），每条 link 都做 credit 流控
（`credit_on_*` / `cr_*`），每个 router port 有 2 个 virtual channel，
所有路径都是 flit-based。

设计要点（与 `docs/specs/case2_spec.md` 对应）：

* `case2_chi_flit_pack` / `case2_chi_flit_unpack` 是唯一使用 flit 字段位置宏的地方，
  字段名与公开 CHI 文档一致：`QoS / TgtID / SrcID / TxnID / ReturnNID / Opcode /
  Size / Addr / NS / MemAttr / SnpAttr / ExpCompAck / Tag / RespErr / Resp /
  FwdState / DataSource / DataID / CCID / BE / Data / DBID / P-Credit / CBusy /
  FwdNID / FwdTxnID / RetToSrc / TraceTag`。
* Opcode / Resp / RespErr 编码只在 `case2_define.v` 里定义一张表，其它文件全部引用宏。
* 每个 router 的 local port（port `C2_LOCAL_PORT` = 4）由 **RN lane** 与
  **共享 SN drop ring** 共用：REQ/DAT 收 RN，RSP/SNP 收 SN ring，发出的 flit 按
  route 结果（`PORT_ROUTE`）决定回 RN 还是送 SN。
* mesh 的边界 lane：`N lane0` 接 HN，其余 7 条 lane 本样本保留未用
  （`N lane1` 显式接零，`S/E/W` 三组端口不接线）。
* credit 预算表 `case2_router_credit_mgr` 管 16 条 link：
  4 条 RN local lane + 8 条 mesh 边界 lane + 4 段 SN drop ring。

## 目录

```
test_cases/case2/
├── README.md
├── filelist.f
└── rtl/
    ├── common/
    │   ├── defines/case2_define.v   全部位宽 / 字段位置 / 编码 / 地址宏（约 240 条）
    │   ├── case2_sync_fifo.v        描述符 FIFO（内部例化 RAM_SP_BE）
    │   ├── case2_sync_2ff.v         两级触发器同步器（叶子）
    │   ├── case2_gray_sync.v        格雷码指针同步（叶子）
    │   └── case2_clk_gate.v         时钟门控 ICG（叶子）
    ├── noc/
    │   ├── case2_router_mesh.v      2x2 mesh 顶层（嵌套 for-generate [y][x] + link 阵列）
    │   ├── case2_noc_router.v       单个 router（5 个 port + route + alloc + xbar）
    │   ├── case2_noc_router_port.v  端口（per-channel input buf + VC + output buf + credit）
    │   ├── case2_noc_vc.v           单 VC（vc_buf + credit + ptr）
    │   ├── case2_noc_vc_buf.v       VC flit 缓冲（defparam 调 RAM_SP_BE）
    │   ├── case2_noc_input_buf.v    IB（头部 FIFO + 宽 payload RAM）
    │   ├── case2_noc_output_buf.v   OB（输出寄存 + ICG）
    │   ├── case2_noc_credit_ctrl.v  credit 记账（叶子）
    │   ├── case2_noc_link_sync.v    link 握手同步（叶子）
    │   ├── case2_noc_route.v        XY 维序路由（叶子）
    │   ├── case2_noc_alloc.v        VC 分配（for-generate 5 个仲裁器）
    │   ├── case2_noc_arbiter.v      轮询仲裁器（叶子）
    │   ├── case2_noc_xbar.v         5x5 crossbar（嵌套 for-generate [o][v]）
    │   ├── case2_noc_xbar_out.v     输出端口 × VC（4 个通道各一个仲裁器）
    │   ├── case2_noc_buf_ram_wrap.v 宽 flit 缓冲（内部例化 RAM_SP_BE）
    │   └── case2_alloc_ptr.v        指针 / 水位（叶子）
    ├── mesh/
    │   ├── case2_mesh_link.v        物理 flit link（FIFO + 同步 + credit）
    │   └── case2_router_credit_mgr.v credit 预算表（嵌套 for-generate [y][x]）
    ├── ni/                          CHI <-> flit 适配与 RN 协议层
    │   ├── case2_chi_rn.v / case2_chi_req_gen.v / case2_chi_rsp_track.v
    │   ├── case2_chi_snp_handle.v / case2_chi_dat_path.v（内部例化 RAM_DP）
    │   ├── case2_chi_to_noc.v / case2_noc_to_chi.v
    │   └── case2_chi_flit_pack.v / case2_chi_flit_unpack.v /
    │       case2_chi_txnid_alloc.v / case2_chi_credit_release.v / case2_chi_rsp_order.v
    ├── hnf/                         home node：目录 + 请求/响应/数据流水
    │   ├── case2_chi_hn.v / case2_hn_snoop_filter.v（内部例化 RAM_DP）
    │   ├── case2_hn_req_pipe.v / case2_hn_rsp_gen.v / case2_hn_dat_pipe.v
    ├── snf/                         slave node：协议流水 + 存储缓冲 + DBID
    │   ├── case2_chi_sn.v / case2_chi_sn_pipe.v / case2_chi_dbid_alloc.v
    ├── node/                        节点外壳
    │   ├── case2_rn_wrap.v / case2_hn_wrap.v / case2_sn_wrap.v
    └── top/case2_chi_noc_top.v      顶层
```

共享库单元 `RAM_SP / RAM_SP_BE / RAM_DP / RAM_2P` 来自 case1：
`../case1/rtl/common/lib/lib_ram_cells.v`（连同 `lib_define.v` 一起写进 `filelist.f`，
本 case 不复制、不修改它们）。RAM 宏单元一律用**位置连接**，并按
`#( .AW(..), .DW(..), .DEPTH(..) )` 覆盖参数。

## CHI 通道 / flit 表

| 通道 | flit 位宽 | 主要字段（MSB→LSB） |
|---|---|---|
| REQ | 128 (`C2_REQ_FLIT_W`) | QoS, TgtID, SrcID, TxnID, ReturnNID, Opcode, Size, Addr[43:0], NS, MemAttr, SnpAttr, ExpCompAck, Tag, LPID, MPAM, PCrdType, AllowRetry, Order |
| RSP | 64 (`C2_RSP_FLIT_W`) | QoS, TgtID, SrcID, TxnID, Opcode, RespErr, Resp, FwdState, DataSource, DBID, CBusy, Tag, TraceTag, RetToSrc, CCID |
| SNP | 64 (`C2_SNP_FLIT_W`) | QoS, SrcID, TxnID, FwdNID, FwdTxnID, Opcode, Addr 片段, NS, RetToSrc, CBusy |
| DAT | 320 (`C2_DAT_FLIT_W`) | QoS, Opcode, Resp, RespErr, DataSource, CBusy, DataID, CCID, DBID, BE[31:0], Data[255:0] |

物理链路层把四个通道都搬到 320 bit 的 `C2_FLIT_W` 总线上（窄通道补零，
补零宽度用 `C2_REQ_PAD_W / C2_RSP_PAD_W / C2_SNP_PAD_W` 宏），
所以 `case2_noc_vc` / `case2_noc_vc_buf` / `case2_mesh_link` 只需要一套位宽。

## 例化层级（`tools/verify_cases.py` 打印的树，节选）

```
case2_chi_noc_top
├── u_rst_sync      : case2_sync_2ff           (位置连接)
├── u_mesh_cg       : case2_clk_gate           (位置连接)
├── g_rn[0].u_rn    : case2_rn_wrap            (for-generate, 4 个)
│   ├── u_rn        : case2_chi_rn
│   │   ├── u_req_gen   : case2_chi_req_gen
│   │   │   ├── u_txnid : case2_chi_txnid_alloc      ← 叶子
│   │   │   └── u_pack  : case2_chi_flit_pack        ← 叶子
│   │   ├── u_rsp_track : case2_chi_rsp_track
│   │   ├── u_snp       : case2_chi_snp_handle
│   │   └── u_dat       : case2_chi_dat_path
│   │       └── u_wdata_ram : RAM_DP                 ← 库单元
│   ├── u_to_noc    : case2_chi_to_noc → u_tx_fifo : case2_sync_fifo → u_fifo_ram : RAM_SP_BE
│   └── u_to_chi    : case2_noc_to_chi
├── u_mesh          : case2_router_mesh
│   └── g_router_row[0].g_router_col[0].u_router : case2_noc_router
│       ├── g_port[4].u_port : case2_noc_router_port          (5 个 port)
│       │   ├── g_ch_inbuf[0].u_inbuf : case2_noc_input_buf   (4 个通道)
│       │   │   ├── u_hdr_fifo   : case2_sync_fifo → u_fifo_ram : RAM_SP_BE
│       │   │   └── u_payload_ram: case2_noc_buf_ram_wrap → u_buf_ram : RAM_SP_BE
│       │   ├── g_vc[1].u_vc : case2_noc_vc                   (2 个 VC)
│       │   │   └── u_vc_buf : case2_noc_vc_buf → u_flit_ram : RAM_SP_BE   ← 深度 7
│       │   ├── u_outbuf  : case2_noc_output_buf
│       │   ├── u_credit  : case2_noc_credit_ctrl             ← 叶子
│       │   └── u_link_sync : case2_noc_link_sync             ← 叶子
│       ├── u_route  : case2_noc_route                        ← 叶子
│       ├── u_alloc  : case2_noc_alloc → g_port_arb[i].u_port_arb : case2_noc_arbiter
│       └── u_xbar   : case2_noc_xbar
│           └── g_out_port[o].g_out_vc[v].u_out : case2_noc_xbar_out
│               └── u_arb_req : case2_noc_arbiter             ← 叶子
│       └── g_bound_n.u_link_req : case2_mesh_link            (边界 link)
│           ├── u_link_fifo : case2_sync_fifo → u_fifo_ram : RAM_SP_BE
│           ├── u_valid_sync: case2_sync_2ff                  (位置连接)
│           ├── u_ptr_sync  : case2_gray_sync
│           └── u_link_credit: case2_noc_credit_ctrl
├── u_hn            : case2_hn_wrap
│   ├── u_hn        : case2_chi_hn
│   │   ├── u_sfilter : case2_hn_snoop_filter → u_tag_ram : RAM_DP
│   │   ├── u_req_pipe: case2_hn_req_pipe                     ← 叶子
│   │   ├── u_rsp_gen : case2_hn_rsp_gen                      ← 叶子
│   │   └── u_dat_pipe: case2_hn_dat_pipe
│   └── u_to_noc / u_to_chi : case2_chi_to_noc / case2_noc_to_chi
├── u_sn            : case2_sn_wrap
│   ├── g_sn[0..7].u_sn : case2_chi_sn                        (8 个)
│   │   ├── u_pipe     : case2_chi_sn_pipe
│   │   ├── u_ram_wrap : case2_noc_buf_ram_wrap → u_buf_ram : RAM_SP_BE
│   │   └── u_dbid     : case2_chi_dbid_alloc                 ← 叶子
│   └── u_sn_cg     : case2_clk_gate                          (位置连接)
├── u_credit_mgr    : case2_router_credit_mgr
│   ├── g_row[y].g_col[x].u_link_credit / u_sn_credit : case2_noc_credit_ctrl
│   ├── g_row[y].g_col[x].u_credit_sync : case2_gray_sync
│   ├── g_port_credit[p].u_port_credit : case2_noc_credit_ctrl
│   └── u_mgr_cg    : case2_clk_gate                          (位置连接)
├── u_dbg_ram       : case2_noc_buf_ram_wrap → u_buf_ram : RAM_SP_BE
└── u_cfg_fifo      : case2_sync_fifo → u_fifo_ram : RAM_SP_BE
```

最深路径（深度 7）：

```
case2_chi_noc_top → case2_router_mesh → case2_noc_router → case2_noc_router_port
                  → case2_noc_vc → case2_noc_vc_buf → RAM_SP_BE
```

## 结构特征清单

| 要求 | 实现位置 |
|---|---|
| 层次深度 ≥ 6（实际 7） | `top → router_mesh → noc_router → noc_router_port → noc_vc → noc_vc_buf → RAM_SP_BE` |
| 嵌套 for-generate | `case2_router_mesh`（`[y][x]` + 端口/通道分支）、`case2_noc_xbar`（`[o][v]`）、`case2_router_credit_mgr`（`[y][x]`）、`case2_noc_router_port`（通道/VC） |
| 同模块 ≥ 4 个不同实例名 | `case2_noc_arbiter`：`u_arb_req/u_arb_rsp/u_arb_snp/u_arb_dat`；`case2_mesh_link`：`u_link_req/u_link_rsp/u_link_snp/u_link_dat`；`case2_noc_credit_ctrl`：`u_link_credit/u_sn_credit/u_port_credit/u_bound_*` |
| 库单元直接调用 | `RAM_SP_BE`（vc_buf / buf_ram_wrap / sync_fifo）、`RAM_DP`（chi_dat_path / hn_snoop_filter） |
| `#(...)` 参数覆盖 | `case2_noc_router`、`case2_noc_router_port`、`case2_noc_vc`、`case2_noc_xbar_out`、`RAM_*` 宏单元 |
| `defparam` | `case2_noc_vc_buf` 中对 `u_flit_ram` 的 `AW/DW/DEPTH` |
| 命名 / 位置连接混用 | 大块用命名；`case2_sync_2ff` / `case2_clk_gate` / `RAM_*` 用位置连接 |
| 叶子模块 ≥ 10 | `case2_noc_arbiter`、`case2_noc_route`、`case2_noc_credit_ctrl`、`case2_noc_link_sync`、`case2_alloc_ptr`、`case2_sync_2ff`、`case2_gray_sync`、`case2_clk_gate`、`case2_chi_flit_pack`、`case2_chi_flit_unpack`、`case2_chi_txnid_alloc`、`case2_chi_rsp_order`、`case2_chi_credit_release`、`case2_hn_req_pipe`、`case2_hn_rsp_gen`、`case2_chi_dbid_alloc` |
| 位宽宏化 ≥ 50% | 端口向量位宽全部写成 `` `C2_* `` 宏表达式，覆盖率见 checker 输出（100%） |

## 怎么分析

```bash
python tools/verify_cases.py test_cases/case2 case2_chi_noc_top
```

实测结果（本仓库当前版本）：

```
  files          : 49 (2 define files)
  modules        : 50
  macros defined : 343
  vector ports   : 617   macro-derived: 617   coverage: 100.0%
  hierarchy depth: 7
  leaf modules   : 18
  instances      : 114
  for-generate   : 8 modules (nested: 6)
  same-mod x4+   : case2_router_mesh->case2_mesh_link x4,
                   case2_noc_xbar_out->case2_noc_arbiter x4,
                   case2_router_credit_mgr->case2_noc_credit_ctrl x7
  library cells  : RAM_DP, RAM_SP_BE
  defparam users : case2_noc_vc_buf
  #(...) users   : case2_noc_router, case2_noc_router_port, case2_noc_vc_buf,
                   case2_noc_xbar, case2_noc_buf_ram_wrap, case2_chi_dat_path,
                   case2_hn_snoop_filter, case2_sync_fifo
  RESULT: PASS
```

checker 会打印文件/模块/宏数量、端口位宽宏覆盖率、层次深度、叶子模块列表、
for-generate 与参数覆盖清单，并输出前 80 行层次树；通过后同时写出
`test_cases/case2/expected_hierarchy.json`（同一套树结构的 JSON 形式，便于和
mapper 的输出做对比）。

辅助（非权威）自检脚本：`python tools/case2_lint.py`，在 checker 的解析结果上
额外检查位置连接个数、连接表达式里未声明的标识符、一文件多模块等 checker 看不到的问题。

## 本样本的近似之处

* 功能不追求正确：credit 返回值、VC 仲裁、乱序处理都做了简化，
  只要能表达结构。
* mesh 的 S/E/W 边界 lane 与 `N lane1` 未接节点（本样本只挂 HN + SN + 4 RN）。
* SN 的 RSP/DAT 汇聚用"编号最高者优先"的行为 for 循环代替真正的 round-robin。
* CHI 字段位宽取自 `case2_spec.md` 的宏表（例如 TgtID/SrcID 为 7 bit），
  与公开 CHI 规范（11 bit node ID）不同，但全设计统一使用同一套值。
* `rtl/noc/case2_noc_link_sync.v` 是相对 spec §4 文件清单**多出的一个文件**：
  spec §3 把 `case2_noc_link_sync` 列为叶子模块、并要求它出现在
  `case2_noc_router_port` 的子模块里，而 §4 的清单里没有对应文件，
  因此补一个同名文件（checker 要求"文件名 = 模块名"）。
