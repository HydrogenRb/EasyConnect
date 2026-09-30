# EasyConnect 1.0.3

用 Python 标准库为 Verilog / SystemVerilog 工程跨层级连线，提供建图、增加、修改、删除和事务恢复。支持 `.v` 文件按 SystemVerilog 语法使用；Python 要求 **3.8 或以上**，不需要安装第三方 Python 包。

使用时保留 `EasyConnect.py` 与同级的 `easyconnect/` 目录即可；它们共同构成工具，不能只复制入口文件。无需 `pip install`。

实现重点是保留宏表达式、多维 packed / unpacked 数组、按实例路径修改，以及可恢复的源码编辑。它是保守的源码变换工具，不是完整的 SystemVerilog 编译器或 elaborator。

## 快速开始

假设层级如下，`fifo_rd` 是 `C` 中已经声明并由现有 RTL 驱动的信号：

```text
top (A)
├── U_B (B)
│   └── U_C (C)  fifo_rd
└── U_D (D)      fifo_rd_in
```

先把 `test/fixtures/basic/` 复制到自己的试验目录，或直接将 `--src` 指向待编辑 RTL 目录：

```powershell
python EasyConnect.py --version
python EasyConnect.py map --src ./my_rtl --top top
python EasyConnect.py add U_C.fifo_rd U_D.fifo_rd_in --src ./my_rtl --top top --name fifo_route --dry-run
python EasyConnect.py add U_C.fifo_rd U_D.fifo_rd_in --src ./my_rtl --top top --name fifo_route
python EasyConnect.py list --src ./my_rtl
python EasyConnect.py remove fifo_route --src ./my_rtl
```

`--dry-run` 输出 unified diff，不写 RTL、状态文件或锁文件。没有 `--dry-run` 时执行编辑。未指定 `--src` 时使用当前工作目录；从其他目录运行脚本时，应给脚本本身提供正确路径。全局参数可以放在子命令前或后。

## 错误定位和过程日志

失败时默认输出命令、RTL 根目录、处理阶段链和具体原因。重放连接时会标明连接 ID 与源/目标路径；解析错误还包括相对文件路径、行、列、模块名、源码片段和 `^` 指示。例如：

```text
EasyConnect error
Command: add
Source root: .../rtl
Stage: execute add -> prepare add operation -> replay connection fifo (...) -> parse source RTL -> parse RTL file block.v -> scan module top structure
Reason: block.v:12:17 [module top]: unmatched begin while locating block boundary; expected end before module end
      always @(*) begin
                  ^
```

可加 `--verbose` 实时查看扫描、解析、实例解析、形状检查和写入等阶段。日志走 stderr，不污染 `map` / `list --json` 的 stdout：

```powershell
python EasyConnect.py add U_C.fifo_rd U_D.fifo_rd_in --src ./my_rtl --name fifo --dry-run --verbose
```

`map` 输出 JSON，展示模块、实例和未知模块（CBB）。存在唯一顶层时可以省略 `--top`；多个可能的顶层必须明确指定。`U_C.fifo_rd` 这样的短路径仅在唯一匹配时接受；有歧义时使用 `top.U_B.U_C.fifo_rd` 完整实例路径。路径里的名字是**例化名**，不是模块类型名。

工具沿源端到目标端的路径找到最近公共祖先，并执行：

1. 在源模块导出现有信号，建立 output 和必要的局部连接。
2. 向上经过中间模块时补充 output 与例化连接。
3. 在公共祖先中声明连接线，将两侧例化接到同一条线上。
4. 向下经过中间模块时补充 input；最后连接目标信号或创建缺失的目标 input。若目标就是公共祖先且该信号尚未声明，则新建 output 并驱动它，适合向顶层导出信号。

源端、目标端可以使用不同信号名。生成的端口/线网使用连接名称作为前缀，命令结果给出实际处理路径。源信号必须存在；工具不会猜测 FIFO 等业务逻辑，也不会自动生成缺失的逻辑驱动。

## 增删改命令

```powershell
# 不写 --name 时自动生成 c001、c002 等连接 ID。
python EasyConnect.py add top.U_B.U_C.fifo_rd top.U_D.fifo_rd_in --src ./my_rtl

# 连接名称同时是管理 ID 和生成信号前缀。
python EasyConnect.py add top.U_B.U_C.fifo_rd top.U_D.fifo_rd_in --name fifo_route --src ./my_rtl

# 修改已有连接，保持原 ID。未给出的宽度等选项沿用原值。
python EasyConnect.py change fifo_route top.U_B.U_C.fifo_rd top.U_E.fifo_rd_in --src ./my_rtl --dry-run
python EasyConnect.py change fifo_route top.U_B.U_C.fifo_rd top.U_E.fifo_rd_in --src ./my_rtl

python EasyConnect.py list --src ./my_rtl --json
python EasyConnect.py remove fifo_route --src ./my_rtl --dry-run
python EasyConnect.py remove fifo_route --src ./my_rtl
```

`remove` 也可写成 `rm` / `delete`；`change` 也可写成 `update` / `modify`。这些命令管理通过 EasyConnect 添加的连接，不会按字符串搜索并删除任意已有 RTL 逻辑。

目标端口已经连接时，默认拒绝覆盖。明确需要重新绑定时可加 `--replace`；已有连续赋值、声明初始化和子模块输出连接等结构上可见的驱动冲突仍会拒绝。请检查 diff 中被替换的连接。

`always@(*)`、`always @*`、`always_comb`、`always_ff`、`always_latch` 等过程块只定位边界并整体跳过，既不分析内部赋值，也不改变原文；`initial` / `final` 同样处理。工具关注模块、端口、声明和例化连接，不检查过程逻辑内部的驱动关系。因此已有过程赋值造成的冲突不会由本工具检出，需由工程编译/lint 检查。

**条件 generate 同样整体跳过。** 对 `generate if / else if / else` 和 `generate case`，只匹配块边界，不求条件真假，也不遍历里面的过程逻辑、声明或实例。仅存在这些结构不会阻止对同一模块其他位置的连线。`map` 的 `ignored_regions` 和连线结果的 `warnings` 会列出被跳过的位置；若请求的实例在这些分支内，会明确提示路径不可见及跳过位置。

被跳过的分支不参与实例树，因此工具不能向其中的实例布线。若这些分支引用了独立模块定义，自动顶层推断可能出现多个候选，此时显式指定 `--top`。为避免修改普通实例的模块定义时连带影响被跳过分支，存在此类分支时，选中的非根实例会保守地使用专用模块副本。预处理的 `` `ifdef `` 与语言级 generate-if 不同，仍保持原有的未展开诊断。

## 宏位宽和多维数组

宏及数组范围保留为 RTL 表达式，不强制求值成整数。支持多个 packed 维度、多个 unpacked 维度，以及 `signed`：

```systemverilog
`define DATA_W 32
`define ROWS 4
`define COLS 8

wire signed [`DATA_W-1:0][1:0] payload [0:`ROWS-1][0:`COLS-1];
```

默认从源声明推导 packed 维度、unpacked 维度和 signedness，贯穿生成的端口、线网和例化连接：

```powershell
python EasyConnect.py add top.U_C.payload top.U_D.received --src ./my_rtl --name payload_route
```

也可以显式指定并核验形状：

```powershell
python EasyConnect.py add top.U_C.payload top.U_D.received --src ./my_rtl --name payload_route --width '[`DATA_W-1:0][1:0]' --unpacked '[0:`ROWS-1][0:`COLS-1]' --signed --dry-run
```

PowerShell / Bash 中应使用**单引号**包住带反引号的宏表达式，防止 shell 将宏符号作为转义或命令替换处理。`--width` 接受完整 packed 范围，如 `'[31:0]'`，不是整数 `32`；`--unpacked` 接受变量名后面的数组范围。

显式形状与源声明不符，或目标形状 / signedness 不兼容时，工具会停止，不自动截断、扩展或重排数组。模块参数在需要跨作用域时按实例参数覆盖解析；能安全替换的常量表达式会被提升，无法确定的作用域引用会拒绝。宏需要在受影响编译单元中本来就可见；工具不代替工程的 include 路径、文件顺序或宏配置。

支持固定元素/切片端点，例如 `'top.U_C.matrix[2][1]'`、`'top.U_C.data[7:0]'`；下标可以是常量、宏或可解析参数。动态变量下标会拒绝。范围和 signedness 使用保守比较，因此相同位数但范围不同（如 `[7:4]` 与 `[3:0]`）也可能需要先在 RTL 中显式适配。packed 位选/部分选择按 SV 规则视为 unsigned；unpacked 元素保持其元素类型。

## 同模块多次例化

修改一个模块定义会影响它的所有实例。为使某一路连接只作用于选中实例，EasyConnect 会在需要时**复制并重命名模块定义**，再把选中实例改为引用专用副本。副本留在原 `.v` / `.sv` 文件中，名称包含 `__ec_`，并随受管连接的删除而恢复。

因此，可以用两条命令连接两组独立的 APB 信号，也可以重复将同一个源信号接到多个目标，形成 fanout。同一源的多目标 fanout 可能产生多组辅助端口和线网；工具优先保证实例隔离，不做跨命令的线网合并优化。模块副本可能影响基于模块类型名的 lint、bind、约束或层次检查，集成时应检查 diff 和原有工程验证结果。

## generate：共用信号和逐 lane 信号

支持带名字的 `for` generate；逐 lane 模式要求递增且步长为 1：

```systemverilog
for (genvar i = 0; i < `LANES; i = i + 1) begin : g_lane
    leaf U_LEAF (.clk(clk));
end
```

路径中的 `[i]` 表示整个生成族的符号索引。建议使用完整路径，并在 shell 中给这种路径加单引号。

**共用信号：** 普通信号广播到各 lane，使用默认的 `shared`：

```powershell
python EasyConnect.py add top.enable 'top.g_lane[i].U_LEAF.enable' --src ./my_rtl --name enable_route --mode shared
```

**逐 lane 信号：** 顶层信号声明对应的 lane 维度，再使用 `indexed`。例如 unpacked 数组：

```systemverilog
logic [`DATA_W-1:0] lane_data [0:`LANES-1];
```

```powershell
python EasyConnect.py add top.lane_data 'top.g_lane[i].U_LEAF.data' --src ./my_rtl --name lane_route --mode indexed
python EasyConnect.py add 'top.g_lane[i].U_SRC.data' 'top.g_lane[i].U_DST.data' --src ./my_rtl --name lane_pair --mode indexed
```

常见的 packed 控制向量也支持：

```systemverilog
logic [`LANES-1:0] lane_enable;
logic [`LANES-1:0][`DATA_W-1:0] packed_data;
```

```powershell
python EasyConnect.py add top.lane_enable 'top.g_lane[i].U_LEAF.enable' --src ./my_rtl --name bits --mode indexed
```

工具根据端点形状自动选择 packed 或 unpacked lane 维度，例化连接使用 `[i]`；嵌套循环对应 `[i][j]`。也可用 `--lane-kind packed` 或 `--lane-kind unpacked` 明确指定。两端都是生成族且没有既有父级数组约束时默认使用 unpacked。自动生成的 unpacked lane 范围为 `[lower:upper-1]`，packed lane 范围为 `[upper-1:lower]`，与已有数组方向不一致时拒绝猜测映射。

原信号自身的多维 packed / unpacked 维度仍然保留。如果 payload 本身有 unpacked 维度，外层 lane 也必须用 unpacked，以保证 `signal[i]` 先选择 lane。来自生成族的多个 output 不允许接到 shared 单根线上；请用 indexed 避免多驱动。

当前不支持仅修改某个具体生成 lane，例如 `g_lane[3]`。条件 generate 整体跳过，普通 for-generate 仍参与索引布线。indexed 的降序、非单位步长、重复 genvar 名、依赖外层索引的非矩形循环，以及未命名循环需要先改成受支持形式，或增加显式 wrapper。

## CBB / 黑盒模块

没有 RTL 源码的模块只能绑定**已经存在的端口**，不能新建黑盒端口或修改内部逻辑。通过 JSON 明确声明端口信息：

```json
{
  "modules": {
    "ExternalIP": {
      "ports": {
        "data_in": {
          "direction": "input",
          "width": "[`DATA_W-1:0]",
          "unpacked": "[0:`LANES-1]",
          "signed": false
        },
        "data_out": {
          "direction": "output",
          "width": "[`DATA_W-1:0]"
        }
      }
    }
  }
}
```

```powershell
python EasyConnect.py add top.U_C.payload top.U_IP.data_in --src ./my_rtl --cbb ./cbb.json --name to_ip
```

源 CBB 端口必须是 output，目标 CBB 端口必须是 input。元数据会随连接保存，后续重放不依赖 JSON 文件仍在原路径。端口的实际形状必须与 IP 相符。

## 文件保护与恢复

扫描 `.v`、`.sv`、`.vh`、`.svh`，递归进入子目录；忽略 `.git`、`.easyconnect`、虚拟环境等工具目录。不跟随目录符号链接，拒绝编辑符号链接 RTL。源文件要求 UTF-8，允许 BOM。

从工具所在目录扫描时，会跳过工具自带的 `test/` 示例，避免不同测试中的同名 `top` 污染用户工程。用 `--src test/fixtures/basic` 等参数显式指向具体示例，仍可正常使用；用户工程中其他位置的 `test` 文件夹不会被一概忽略。

首次写入连接时，在源目录下的 `.easyconnect/state.json` 保存原始文件快照、生成结果哈希和连接列表。每次增加、修改、删除都从原快照重放剩余连接；删除最后一条后恢复原始字节并清除状态文件，包含 BOM、CRLF 和末尾换行情况。

有受管连接期间，如果任何已扫描 RTL 被外部编辑、删除，或出现新 RTL 文件，后续写操作会拒绝覆盖。请先通过项目版本管理恢复到最近一次 EasyConnect 输出，再管理连接；或者先删除受管连接，再进行人工 RTL 编辑。不要手动删除状态文件来绕过保护，它包含精确删除和恢复需要的基线。

写入使用独占锁、事务日志和逐文件原子替换；普通写入失败会回滚。进程异常退出留下 `pending.json` 时：

```powershell
python EasyConnect.py recover --src ./my_rtl
```

恢复会退回事务开始前的状态；若发现中断后又发生人工改动，会拒绝覆盖并保留日志。活动进程持有的锁不会被抢占。恢复中断事务不等于删除全部已成功添加的连接。

## 支持边界

支持普通 module、ANSI / non-ANSI 端口、显式命名端口连接、常见 `wire` / `reg` / `logic` 声明、命名实例参数覆盖、宏范围以及固定多维数组。接口/modport 类型和已有端口列表按不透明源码保留；逗号并列实例在需要特化时会拆成独立声明，保留各自连接。并非任意合法 SV 都能自动修改。

为避免猜测连线方向，遇到无法定位源/目标或无法生成安全连接时会停止并给出原因。位置式端口连接/参数覆盖、`.*`、需要替换的简写端口、实例数组、需要遍历的 for-generate 内局部信号/参数声明、复杂宏展开、动态数组 / 队列 / 关联数组和 inout 路由仍属于编辑边界；接口/modport、重复端口名、重复连接名和端口列表中的其他合法性由用户的编译器检查，EasyConnect 不因这些内容退出。条件 generate 按上述规则跳过；预处理条件分支和工程编译选项不会被完整执行。编辑时 `--top` 必须是扫描范围内没有被例化的实际根模块，不能以一个被多处使用的子模块冒充根模块。

源代码驱动检查是静态保守检查，不能代替编译器的全部语义分析。连接完成后，应运行工程原来的 SystemVerilog 编译、lint、仿真以及必要的综合检查。

## 测试和项目结构

```powershell
python -m unittest discover -s test -v
```

测试覆盖层级、重复实例、CBB、generate、宏位宽、多维数组、增删改、失败保护、事务恢复以及 BOM / CRLF 字节恢复。测试使用临时副本；环境中有 `iverilog` 时部分正向用例还会调用 `iverilog -g2012`，没有时仍可执行 Python 回归。更多说明见 `test/README.md`。

开发验证另支持可选的 [slang SystemVerilog 编译前端](https://www.sv-lang.com/user-manual.html)，进行解析、类型检查和 elaboration；该工具不是 EasyConnect 的运行依赖。需求的四种路径角色与六种例化情况如何组合，见 [设计说明](docs/设计说明.md)。

```text
EasyConnect.py          命令行入口与版本
easyconnect/rtl.py      词法扫描、声明和实例解析
easyconnect/engine.py   层级、路径、类型与源码变换
easyconnect/state.py    快照重放、冲突保护和可恢复事务
easyconnect/diagnostics.py  阶段错误上下文和可选过程日志
test/                  测试及可复制 RTL 示例
help_tool/             需求原有的参考建图脚本
```
