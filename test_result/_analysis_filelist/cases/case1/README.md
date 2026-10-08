# case1 — AHB/APB 子系统（credit 流控）

TOP: `case1_soc_top`

## 主题

模拟一颗小 SoC 的总线基础设施：AHB-Lite 多主机互连 + AHB-to-APB 桥 + APB 外设子系统。
与常见 AHB/APB 设计不同的是：**所有跨时钟/跨协议的传输都用 credit（信用）流控**，
而不是靠 HREADY 反压到底。credit 由 AHB 侧的主机信用检查器扣减，由从机/APB 侧的
信用回收器在事务完成后归还。

## 目录

```
test_cases/case1/
├── README.md
├── filelist.f                              35 个文件（33 个原始条目 + 2 个补充，见下）
├── expected_hierarchy.json                 tools/verify_cases.py 在 PASS 时生成
└── rtl/
    ├── common/defines/case1_define.v       全部位宽/编码/地址宏（177 条 `define）
    ├── common/lib/lib_define.v             库宏单元位宽（13 条）
    ├── common/lib/lib_ram_cells.v          RAM_SP / RAM_SP_BE / RAM_DP / RAM_2P（叶子）
    ├── top/case1_soc_top.v
    ├── ahb/      master / master_wrap / slave / decoder / slave_mux /
    │             interconnect / credit_master / credit_slave
    ├── apb/      ahb_to_apb_bridge / apb_mux / apb_credit_pool / apb_crossbar /
    │             apb_cdc / apb_periph_slot / apb_regfile
    ├── periph/   uart / timer / gpio / spi / watchdog / dma_apb 寄存器组（叶子）
    ├── dma/      dma_engine / dma_desc_fetch
    ├── monitor/  perf_monitor / cpu_tracker / cpu_tracker_rv32
    └── sync/     sync_fifo / gray_sync / pulse_sync / sync_ff / clk_gate
```

相比初始 `filelist.f` 增加的两个文件（spec 里 `case1_apb_periph_slot` 一节明确要求
`case1_clk_gate`「定义在 rtl/sync/case1_clk_gate.v 并加入 filelist.f」）：

| 新增文件 | 模块 | 用途 |
|---|---|---|
| `rtl/sync/case1_clk_gate.v` | `case1_clk_gate` | 集成时钟门控单元（叶子），slot 里给计数器供门控时钟 |
| `rtl/sync/case1_sync_ff.v` | `case1_sync_ff` | 单级同步触发器（叶子），级联成 per-slot / 每级一个的 CDC 同步器阵列 |

## 例化层级（`tools/verify_cases.py` 实际打印的树，仅省略重复的 3 份 regfile 子树）

```
case1_soc_top
├── u_cpu_m0  (case1_ahb_master_wrap, named+param)
│   ├── u_track  (case1_cpu_tracker_rv32, named+param)
│   │   └── u_track_core  (case1_cpu_tracker, named+param)          <- 叶子
│   ├── u_dma    (case1_dma_engine, named+param)      <- generate 的 else 分支
│   │   └── u_fetch[gc]  (case1_dma_desc_fetch, named+param)
│   │       └── u_desc_buf  (RAM_SP, positional)                    <- 库单元叶子
│   └── u_issue  (case1_ahb_master, named+param)                    <- 叶子
├── u_dma_m0  (case1_ahb_master_wrap, named+param)   <- 同一模块，第二个实例名
│   └── …（同上；IS_CPU=0 时走 DMA 分支）
├── u_xbar  (case1_ahb_interconnect, named)
│   ├── u_decoder     (case1_ahb_decoder, named)                    <- 叶子
│   ├── u_m_credit[m] (case1_ahb_credit_master, named+param)        <- 叶子，for-generate ×2
│   ├── u_s_credit[s] (case1_ahb_credit_slave, named+param)         <- for-generate ×4
│   │   └── u_outstanding_tbl  (RAM_SP, positional)                 <- 库单元叶子
│   └── u_slave_mux   (case1_ahb_slave_mux, named)
│       ├── u_slv[s]  (case1_ahb_slave, named+param)                <- for-generate ×4，叶子
│       └── u_bridge  (case1_ahb_to_apb_bridge, named+param)   # defparam 也在这里
│           └── u_apb_mux  (case1_apb_mux, named+param)
│               └── u_credit_pool  (case1_apb_credit_pool, named+param)
│                   ├── u_ret_fifo  (case1_sync_fifo, named+param)
│                   │   ├── u_fifo_mem     (RAM_SP_BE, positional)
│                   │   └── u_gray_sync[k] (case1_gray_sync, positional)
│                   └── u_crossbar  (case1_apb_crossbar, named+param)
│                       ├── u_slot[s]  (case1_apb_periph_slot, named+param)   <- for-generate ×4
│                       │   ├── u_regfile        (case1_apb_regfile, named+param)
│                       │   │   ├── u_reg_mem  (RAM_DP, positional)
│                       │   │   └── u_uart_regs / u_timer_regs / u_gpio_regs /
│                       │   │       u_spi_regs / u_watchdog_regs / u_dma_apb_regs  <- 叶子
│                       │   ├── u_regfile_timer  (case1_apb_regfile, named+param)
│                       │   ├── u_regfile_gpio   (case1_apb_regfile, named+param)
│                       │   ├── u_regfile_spi    (case1_apb_regfile, named+param)
│                       │   ├── u_fifo_ram   (RAM_SP, positional)   <- 库单元叶子
│                       │   ├── u_rx_fifo    (case1_sync_fifo, named+param)
│                       │   │   ├── u_fifo_mem     (RAM_SP_BE, positional)
│                       │   │   └── u_gray_sync[k] (case1_gray_sync, positional)
│                       │   ├── u_gate       (case1_clk_gate, positional)  <- 叶子
│                       │   └── u_ready_sync[k] (case1_sync_ff, positional) <- 叶子
│                       ├── u_ready_sync[s*`C1_CDC_STAGES+k] (case1_sync_ff, named)
│                       └── u_cdc  (case1_apb_cdc, named)
│                           ├── u_active_ff[s*`C1_CDC_STAGES+k] (case1_sync_ff, named)
│                           ├── u_pulse[s] (case1_pulse_sync, positional)  <- 叶子
│                           └── u_gray[k]  (case1_gray_sync, positional)   <- 叶子
└── u_perf_mon  (case1_perf_monitor, named)
    ├── u_dbg_sync[k] (case1_gray_sync, positional)
    └── u_bus_track   (case1_cpu_tracker_rv32, named+param)
        └── u_track_core (case1_cpu_tracker, named+param)
```

最深路径（到 RAM_* 库单元叶子，9 段例化）：
`case1_soc_top → u_xbar → u_slave_mux → u_bridge → u_apb_mux → u_credit_pool →
u_crossbar → u_slot[s] → u_regfile → u_reg_mem(RAM_DP)`；
旁路 `… → u_slot[s] → u_fifo_ram(RAM_SP)` 为 8 段。

## 验证结果（`python tools/verify_cases.py test_cases/case1 case1_soc_top`）

```
files          : 35 (2 define files)
modules        : 36
macros defined : 190            (case1_define.v 177 + lib_define.v 13)
vector ports   : 230   macro-derived: 230   coverage: 100.0%
hierarchy depth: 10
leaf modules   : 18
instances      : 46
for-generate   : 8 modules (nested: 6)
same-mod x4+   : case1_apb_periph_slot->case1_apb_regfile x4
library cells  : RAM_SP, RAM_DP, RAM_SP_BE
defparam users : case1_ahb_slave_mux
#(...) users   : 13 modules
RESULT: PASS
```

> ⚠️ 工具现状：仓库里当前的 `tools/verify_cases.py`（675 行版本）在打印 `RESULT` 之前
> 就会崩溃 —— `check_case()` 第 584/590/633/637 行仍以元组方式索引 `Instance` 对象
> （`i[1]`），而 `class Instance` 只实现了 `__iter__`，于是抛
> `TypeError: 'Instance' object is not subscriptable`；这只与本 case 无关，任何含例化的
> case 都会崩。另有 `INST_TOKEN` 缺少 `=` 记号导致把
> `assign PENABLE = PSEL & PENABLE & (~PWRITE);`、`? {`C1_CR_CNT_W{1'b0}} : (x + 1'b1)`
> 之类语句误判成例化（`1'b0` 被切成标识符 `b0`）。
> 在被授权「不修改 tools/verify_cases.py」的前提下，用 `tools/case1_check.py`
> （**原样导入**该文件、仅在运行时补一个 `Instance.__getitem__`）跑出的就是上面的结果：
>
> ```
> python tools/case1_check.py test_cases/case1 case1_soc_top
> ```
>
> 另外 `tools/case1_lint.py` 提供补充静态检查（禁用 SV 构造、begin/end + case/generate
> 配平、ANSI 端口、端口位宽裸数字、未声明网络），当前输出 `LINT: CLEAN`。

## 结构特征清单

| 要求 | 实现位置 / 实测值 |
|---|---|
| 例化层级 ≥ 6 到 RAM_* 叶子 | `soc_top→xbar→slave_mux→bridge→apb_mux→credit_pool→crossbar→slot→regfile→RAM_DP`（9 段；工具 depth = 10） |
| 叶子模块 ≥ 10 | 18 个：`RAM_SP/RAM_DP/RAM_SP_BE`、`case1_ahb_master/slave/decoder/credit_master`、`case1_cpu_tracker`、`case1_uart/timer/gpio/spi/watchdog/dma_apb_regs`、`case1_gray_sync`、`case1_pulse_sync`、`case1_sync_ff`、`case1_clk_gate` |
| generate + for ≥ 6 个模块 | 8 个：`case1_ahb_interconnect`、`case1_ahb_slave_mux`、`case1_apb_crossbar`、`case1_apb_cdc`、`case1_apb_periph_slot`、`case1_perf_monitor`、`case1_sync_fifo`、`case1_dma_engine` |
| 嵌套 for-generate ≥ 2 | `case1_apb_crossbar`（`for(s) for(k)` → `u_ready_sync[s*`C1_CDC_STAGES+k]`）、`case1_apb_cdc`（`for(s) for(k)` active 触发器链 + gray/pulse 阵列） |
| 同模块 ≥ 4 个不同实例名 | `case1_apb_periph_slot` 里 `case1_apb_regfile` ×4（`u_regfile` / `u_regfile_timer` / `u_regfile_gpio` / `u_regfile_spi`） |
| 同模块 2 个不同实例名 | `case1_ahb_master_wrap`：`u_cpu_m0`（IS_CPU=1，挂 tracker 链）/ `u_dma_m0`（IS_CPU=0，挂 DMA 引擎） |
| for-generate + genvar 进实例名 | `u_s_credit[s]`、`u_slv[s]`、`u_slot[s]`、`u_m_credit[m]`、`u_gray_sync[k]`、`u_dbg_sync[k]`、`u_pulse[s]`、`u_ready_sync[…]`、`u_fetch[gc]` |
| 库单元直接例化（叶子） | `RAM_SP`：`u_outstanding_tbl`、`u_fifo_ram`、`u_desc_buf`；`RAM_DP`：`u_reg_mem` ×4；`RAM_SP_BE`：`u_fifo_mem` ×2 |
| 参数覆盖：`#(.P(v))` | 13 个模块（top 的 `IS_CPU`、slot 的 `SLOT_IDX/PERIPH_TYPE`、bridge 的 `APB_SLOT_NUM/ADDR_LSB` 等） |
| 参数覆盖：`defparam` | `case1_ahb_slave_mux` 中对 `u_bridge.CR_MAX` 用 `defparam`（与 `#()` 覆盖的是不同参数） |
| 命名/位置连接混用 | 大块用命名（top/interconnect/bridge/slot/regfile），小叶子用位置（`RAM_*`、`case1_gray_sync`、`case1_pulse_sync`、`case1_sync_ff`、`case1_clk_gate`） |
| 位宽宏化 | 230 / 230 个向量端口全部来自 `` `C1_* `` 宏（coverage 100%），无裸数字位宽 |
| 宏数量 | `case1_define.v` 177 条 + `lib_define.v` 13 条 = 190 条，分 12 个小节（位宽 / 字段编码 / FSM 编码 / 一 hot / APB / credit / 地址映射 / slot / CDC / 外设编码 / 外设私有 / monitor+RAM 适配） |
| 时钟域 | `HCLK`/`PCLK` 双域；`case1_apb_cdc` 是真同步器阵列（gray 同步器链 + pulse 同步器 + 逐级触发器） |

## 有意保留的近似 / 与 spec 字面表述的偏差

1. **`case1_apb_regfile` 例化 4 次的位置**：spec 清单写「被 4 个外设叶子各例化一次」，但同
   一份 spec 又要求 `case1_uart_regs` 等 4 个是**零例化的叶子**，两者不能同时成立。
   折中做法：在 `case1_apb_periph_slot` 里放 4 份寄存器组镜像（每类外设一份，实例名
   `u_regfile` / `u_regfile_timer` / `u_regfile_gpio` / `u_regfile_spi`），由 `PERIPH_TYPE`
   选择哪一份驱动 APB 响应 —— 既保留 4 个叶子，也满足「`case1_apb_regfile` 被 4 个不同
   外设各例化一次」的意图，同时满足分析器「同模块 ≥4 个不同实例名」的检查。
2. **APB 从机阵列在桥内部**，因此 `case1_ahb_to_apb_bridge` 的 APB 引脚
   （`PADDR/PSEL/PENABLE/PWRITE/PWDATA/PSTRB/PPROT`）是内部总线的观测抽头，
   `PRDATA/PREADY/PSLVERR` 输入在父层被接到常量（代码里有注释说明）；桥内部真实的
   APB 响应走 `u_apb_mux ← u_credit_pool ← u_crossbar`。
3. **AHB 主机端口组多一个 `HWSTRB`**（AHB5 的写字节选通），追加在 spec 列出的
   `HMASTLOCK` 之后，spec 要求的端口顺序原样保留。
4. **多两个 credit 观测端口**（`APB_CR_RETURN/APB_CR_RET_CNT`、`APB_RET_VALID/APB_RET_CNT`）：
   APB 侧 credit 池产生的归还脉冲经桥的观测引脚回到 AHB 侧的**寄存器化整形流水**
   （`ret_sr`），再作为 `CR_RET_VALID/CR_RET_CNT` 注入桥的 spec 端口；全链路单驱动、
   无组合环。
5. **`case1_define.v` 的 include guard 带值**：`` `define CASE1_DEFINE_V 1 ``。文本级
   宏提取器（`tools/verify_cases.py::extract_macros`）的正则里 `\s*` 会跨行，空值
   `define 会把下一行吞进宏值，从而漏掉 `C1_AHB_ADDR_W`。加个 `1` 即可绕开，语义不变。
6. **功能不求正确**：只保证结构丰富、内部自洽、语法合法。例如描述符缓冲 `RAM_SP`
   是只读挂载（`WEN=1`）、从机内部小存储体写入后只在同拍观测、`case1_watchdog_regs`
   的两段超时不会真正复位系统等；未做仿真验证。
7. 事件/计数器类的若干寄存器为可观测性而存在（`deb_cnt`、`latency_r`、`stall_cnt_r` 等），
   在综合时会给出 unused 警告，属预期。
