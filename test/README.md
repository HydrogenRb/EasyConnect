# EasyConnect 回归测试

在项目根目录运行：

```powershell
python -m unittest discover -s test -v
```

基础测试只使用 Python 标准库。命令行用例先将 RTL 拷贝到独立临时目录，再运行 `EasyConnect.py`；解析器、路由和事务用例还直接测试各层 API，不会修改这里的 fixture 或用户 RTL。若 `iverilog` 已在 `PATH` 中，正向用例还会自动调用 `iverilog -g2012` 编译修改后的 `.v` 文件；未安装时仍执行命令行、源码与恢复测试。

独立的 SystemVerilog 类型检查和 elaboration 可选使用 pyslang。开发验证安装在隔离目录，不是产品依赖：

```powershell
python -m pip install --only-binary=:all: --no-deps --target .validation pyslang==11.0.0
$env:EASYCONNECT_SLANG_PATH = (Resolve-Path .validation).Path
python -m unittest discover -s test -v
Remove-Item Env:EASYCONNECT_SLANG_PATH
```

设置这个环境变量后，成功生成的 RTL 会交给 slang 独立解析、类型检查和 elaboration，所有 error 均导致测试失败；无该变量时不导入 pyslang。它不执行功能仿真，也不替代用户工程的真实编译配置。用 `python -S -m unittest discover -s test -v` 可以验证不加载第三方 site-packages 时的基础回归。

覆盖内容：

| 范围 | 验证内容 |
| --- | --- |
| 图与路径 | 递归扫描子文件夹、完整路径、唯一短路径、歧义拒绝 |
| 常规连接 | 跨分支、同模块、顶层输入下传、内部信号导出到顶层 |
| 端口风格 | ANSI、non-ANSI、已存在 input、自动创建目标端口 |
| 位宽和数组 | 宏位宽原样保留、有符号信号、多维 packed 与 unpacked 数组、显式形状参数 |
| 重复例化 | 只修改选中实例、两组不同信号、同一信号 fanout |
| generate | shared 广播、packed/unpacked indexed 父级数组、生成族逐 lane、嵌套 `[i][j]`、多层边界传递 |
| CBB | 无 RTL 定义时按 JSON 元数据绑定现有端口 |
| 增删改 | 添加、列出、修改、删除、先删除较早连接、全部删除后的字节级恢复 |
| 失败保护 | 路径不存在、缺失源、重复 ID、目标已有连接、修改失败、外部编辑保护 |
| 预览 | add/remove 的 dry-run 不修改或创建文件 |
| 明确边界 | concrete generate 选择拒绝、shared generate 输出的多驱动拒绝 |
| 参数和选择 | 参数覆盖、localparam 链、固定数组元素、packed 选择 unsigned 规则 |
| 实例和命名 | 逗号并列实例特化、祖先模块共享、endmodule 标签、端口注释、名称冲突 |
| 外部驱动 | 已知子模块/CBB 输出、未知 CBB 方向、隐式线网的已有驱动拒绝 |
| 过程块跳过 | always 家族、initial/final 不调用赋值分析；块后实例仍能找到；连线后 always 原文不变 |

可手动体验的 fixture：

- `fixtures/basic/`：`top.U_B.U_C.fifo_rd` 到 `top.U_D.fifo_rd_in`，对应需求中的跨层级连接。
- `fixtures/nonansi/`：相同层级的非 ANSI 端口写法。
- `fixtures/macro_arrays/`：`top.U_B.U_C.payload` 到 `top.U_D.received`，信号类型为 `wire signed [`EC_DATA_W-1:0][1:0]`，并带有 `[0:`EC_ROWS-1][0:`EC_COLS-1]` unpacked 维度。
- `fixtures/indexed_macros/`：packed `lane_enable[i]` 与带有 lane / ROWS / COLS 三层 unpacked 维度的多维 payload；可以连续添加下方两条连接，再按任意次序删除。

手动体验前请复制 fixture，然后把 `--src` 指向副本：

```powershell
python EasyConnect.py map --src <副本目录> --top top
python EasyConnect.py add top.U_B.U_C.fifo_rd top.U_D.fifo_rd_in --src <副本目录> --top top --name fifo_demo --dry-run
python EasyConnect.py add top.U_B.U_C.fifo_rd top.U_D.fifo_rd_in --src <副本目录> --top top --name fifo_demo
python EasyConnect.py list --src <副本目录>
python EasyConnect.py remove fifo_demo --src <副本目录>
```

这些测试验证受支持语法与操作的行为，不代表完整 SystemVerilog elaboration 或功能仿真。项目真实集成仍应运行原有编译和仿真流程。

`indexed_macros` 副本体验：

```powershell
python EasyConnect.py add top.lane_enable 'top.g_lane[i].U_LANE.enable' --src <副本目录> --mode indexed --name lane_enable
python EasyConnect.py add top.lane_data 'top.g_lane[i].U_LANE.payload' --src <副本目录> --mode indexed --name lane_payload
```
