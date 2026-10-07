# case3 — SIMD 计算簇引擎（10 叶子功能模块）

TOP: `case3_engine_top`

## 主题

一个可配置的 SIMD 计算引擎：**2 cluster x 2 slice x 4 lane**。每条 lane 里是一个小型功能单元
农场（乘法 / 加法 / 移位 / 比较 / 饱和），外加私有寄存器堆、地址生成器、访存对齐器和程序计数
通路；后端由多 bank scratchpad、DMA 描述符读取器和性能计数器支撑。

设计目标不是功能正确，而是**结构丰富**：层次深、generate 嵌套多、同一模块多次例化、库单元
（RAM_SP / RAM_DP / RAM_2P / RAM_SP_BE）在树的最底层直接出现。

- 宏前缀：`C3_`，唯一定义文件 `rtl/common/defines/case3_define.v`（109 个 `define`）
- 端口/信号向量位宽 **100% 宏化**（全部来自 `` `C3_* `` / `` `LIB_RAM_* ``）
- 库单元只读复用 case1：`../case1/rtl/common/lib/lib_ram_cells.v`

## 目录

```
test_cases/case3/
├── README.md
├── filelist.f
├── expected_hierarchy.json            (verify_cases.py 生成，供 mapper 结果对比)
└── rtl/
    ├── common/defines/case3_define.v  全部位宽/编码/计数/地址映射宏
    ├── common/case3_sync_2ff.v        叶子：两级同步器
    ├── common/case3_clk_gate.v        叶子：ICG 时钟门控
    ├── common/case3_perf_counter.v    叶子：性能计数器
    ├── common/case3_cnt_wrap.v        包装层（generate-if 内例化 perf_counter / sync_2ff）
    ├── common/case3_sync_fifo.v       RAM_SP_BE 存储体 + 指针同步
    ├── top/case3_engine_top.v         TOP
    ├── cluster/                       阵列/簇/slice/命令译码/共享 RF/监测
    ├── lane/                          lane 与其 8 个功能子块
    ├── mem/                           scratchpad / bank / 仲裁
    ├── xbar/                          交叉开关（两级 for-generate）
    ├── dma/                           DMA 引擎与描述符读取
    └── cfg/                           配置寄存器组
```

## 例化层级（verify_cases.py 实测输出，depth 7）

`case3_engine_top → case3_cluster_array → case3_cluster → case3_slice → case3_lane →
case3_lane_regfile → RAM_2P` 即 `` `RAM_2P `` 叶子的最短路径长度为 **7**。

```
case3_engine_top
├── u_cluster_array : case3_cluster_array
│   ├── u_cluster[c] : case3_cluster                      (for-generate, `C3_CLUSTER_NUM=2)
│   │   ├── u_cmd : case3_cmd_decoder
│   │   │   ├── u_go_sync : case3_sync_2ff                (positional)
│   │   │   └── u_cmd_gate : case3_clk_gate               (positional)
│   │   ├── u_slice[s] : case3_slice                      (for-generate, `C3_SLICE_NUM=2)
│   │   │   ├── u_lane[l] : case3_lane                    (for-generate, `C3_LANE_NUM=4)
│   │   │   │   ├── u_mul : case3_lane_mul                (叶子)
│   │   │   │   ├── u_alu : case3_lane_alu                (叶子)
│   │   │   │   ├── u_shf : case3_lane_shf                (叶子)
│   │   │   │   ├── u_cmp : case3_lane_cmp                (叶子)
│   │   │   │   ├── u_sat : case3_lane_sat                (叶子)
│   │   │   │   ├── u_regfile : case3_lane_regfile
│   │   │   │   │   ├── u_rf_bank_a : RAM_2P              (positional, 库叶子)
│   │   │   │   │   └── u_rf_bank_b : RAM_2P              (positional, 库叶子)
│   │   │   │   ├── u_agu : case3_lane_agu                (叶子)
│   │   │   │   ├── u_aligner : case3_lane_aligner        (叶子)
│   │   │   │   └── u_pipe_s0..u_pipe_s3 : case3_sync_2ff (同模块 4 个不同实例名)
│   │   │   ├── u_local_rf : case3_lane_local_rf
│   │   │   │   └── u_local_rf_ram : RAM_2P               (库叶子)
│   │   │   └── u_mon : case3_slice_monitor
│   │   │       ├── u_cnt_wrap : case3_cnt_wrap
│   │   │       │   ├── u_cnt_core : case3_perf_counter   (generate-if 分支内, 叶子)
│   │   │       │   └── u_evt_sync : case3_sync_2ff       (generate-if else 分支)
│   │   │       ├── u_lane_cnt : case3_perf_counter       (叶子)
│   │   │       └── u_ovf_sync : case3_sync_2ff
│   │   ├── u_slice_xbar : case3_slice_xbar               (嵌套 for-generate)
│   │   │   ├── u_cell[i][j] : case3_xbar_cell            (i<`C3_LANE_NUM, j<`C3_BANK_NUM → 16)
│   │   │   │   ├── u_arb_vc0..u_arb_vc3 : case3_xbar_arb (#(...) 参数覆盖 x4)
│   │   │   │   │   └── u_prio_sync : case3_sync_2ff
│   │   │   │   └── u_skid_buf : RAM_SP                   (库叶子)
│   │   │   └── u_xbar_clk_sync : case3_sync_2ff
│   │   └── u_shared_rf : case3_rf_bank
│   │       ├── u_bank_lo : case3_reg_bank                 (#( .BANK_ID(0) ))
│   │       │   ├── u_reg_ram : RAM_DP                     (库叶子)
│   │       │   └── u_reg_ready_sync : case3_sync_2ff
│   │       ├── u_bank_hi : case3_reg_bank                 (#( .BANK_ID(1) ))
│   │       │   ├── u_reg_ram : RAM_DP                     (库叶子)
│   │       │   └── u_reg_ready_sync : case3_sync_2ff
│   │       └── u_rf_ready_sync : case3_sync_2ff
│   ├── u_req_sync[c][p] : case3_sync_2ff                  (嵌套 for-generate: cluster x slice 端口)
│   └── u_plane_xbar : case3_xbar
│       ├── u_cell[i][j] : case3_xbar_cell                 (嵌套 for-generate → 4 个 cell)
│       │   ├── u_arb_vc0..u_arb_vc3 : case3_xbar_arb
│       │   └── u_skid_buf : RAM_SP
│       ├── u_cell_broadcast : case3_xbar_cell             (显式实例名，同一模块不同名字)
│       └── u_sel_sync : case3_sync_2ff
├── u_scratchpad : case3_scratchpad
│   ├── u_bank[b] : case3_scratch_bank                     (#( .BANK_ID(b) ), for-generate x4)
│   │   ├── u_bank_ram : RAM_DP                            (positional, 库叶子)
│   │   └── u_bank_busy_sync : case3_sync_2ff
│   ├── u_port_arb[b][p] : case3_scratch_arb               (嵌套 for-generate: bank x port)
│   │   └── u_arb_gate : case3_clk_gate
│   ├── u_bank_spare : case3_scratch_bank                  (defparam 定制参数: 冗余 bank)
│   │   ├── u_bank_ram : RAM_DP
│   │   └── u_bank_busy_sync : case3_sync_2ff
│   └── u_rd_fifo : case3_sync_fifo
│       ├── u_fifo_mem : RAM_SP_BE                         (positional, 库叶子)
│       ├── u_wptr_sync : case3_sync_2ff
│       └── u_rptr_sync : case3_sync_2ff
├── u_dma : case3_dma_engine
│   ├── u_desc_fetch : case3_dma_desc_fetch
│   │   ├── u_desc_mem_lo : RAM_SP                         (positional, 库叶子)
│   │   └── u_desc_mem_hi : RAM_SP                         (positional, 库叶子)
│   ├── u_tx_fifo : case3_sync_fifo                        (同模块不同实例名)
│   ├── u_rx_fifo : case3_sync_fifo                        (同模块不同实例名)
│   ├── u_desc_ring : RAM_SP                               (positional, 库叶子)
│   └── u_req_sync : case3_sync_2ff
└── u_cfg : case3_config_regs
    ├── u_reg_bank : case3_reg_bank                        (#( .BANK_ID(0) ))
    │   ├── u_reg_ram : RAM_DP
    │   └── u_reg_ready_sync : case3_sync_2ff
    ├── u_go_sync : case3_sync_2ff
    └── u_cfg_gate : case3_clk_gate
```

> 说明：`u_cell[i][j]` / `u_port_arb[b][p]` / `u_req_sync[c][p]` 是二维 generate 实例名，
> `verify_cases.py` 的文本扫描器只识别单层 `[i]`，所以上面的树里它们由 for-generate 的
> 单层实例代表；层次分析工具（EasyMapper）应把它们展开成 `u_cell[0][0] … u_cell[3][3]`。

## 结构特征清单

| 要求 | 实现位置 |
|---|---|
| 层次深度 ≥ 4（本 case 实测 **7**） | `engine_top → cluster_array → cluster[c] → slice[s] → lane[l] → lane_regfile → RAM_2P` |
| ≥ 10 个叶子模块（本 case 10 个功能叶子 + 4 个库叶子） | `lane_mul / lane_alu / lane_shf / lane_cmp / lane_sat / lane_agu / lane_aligner / perf_counter / sync_2ff / clk_gate` + `RAM_2P / RAM_DP / RAM_SP / RAM_SP_BE` |
| generate + for ≥ 6 个模块（实测 6，嵌套 4） | `cluster_array`(c×p)、`cluster`(s)、`slice`(l)、`scratchpad`(b×p)、`xbar`(i×j)、`slice_xbar`(i×j) |
| 同模块 ≥ 4 个不同实例名 | `case3_lane` 内 `u_pipe_s0..s3`（sync_2ff x4）；`case3_xbar_cell` 内 `u_arb_vc0..vc3`（xbar_arb x4）；for-generate 展开：lane x4/slice、slice x2/cluster、scratch_bank x4、xbar_cell x16 |
| 库单元直接例化（4 种全用） | `RAM_2P`（lane_regfile / lane_local_rf）、`RAM_DP`（scratch_bank / reg_bank）、`RAM_SP`（xbar_cell / dma_engine / dma_desc_fetch）、`RAM_SP_BE`（sync_fifo） |
| 命名 / 位置端口混用 | 大块用命名；`case3_sync_2ff`、`case3_clk_gate`、全部 `RAM_*` 用位置连接 |
| `#( .P(v) )` 参数覆盖 | `case3_rf_bank`、`case3_scratchpad`、`case3_xbar_cell`、`case3_config_regs` |
| `defparam` | `case3_scratchpad` 对 `u_bank_spare`（冗余 bank）做 3 处 defparam |
| 宏覆盖率 ≥ 50%（实测 **100%**） | 所有端口向量位宽来自 `` `C3_* `` 宏，库单元端口来自 `` `LIB_RAM_* `` |
| 全部例化名可解析、无重复模块 | `filelist.f` 36 个文件 / 37 个模块（含 4 个库单元） |
| 每个模块带 `// Ref:` | 所有 RTL 文件头部均有功能说明 + `Ref:` 真实设计家族 |

## 分析方式

```bash
python tools/verify_cases.py test_cases/case3 case3_engine_top     # 结构检查 + 生成 expected_hierarchy.json
python tools/case3_selfcheck.py test_cases/case3 case3_engine_top  # 同上，另加声明/驱动/端口静态一致性检查
```

`expected_hierarchy.json` 是 `verify_cases.py` 产出的参考层次（与仓库根 `format.json` 同构），
可直接与 mapper 自己的输出做 diff。
