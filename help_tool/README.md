# EasyMapper

单文件 RTL 例化关系提取器，Python 3.8+，只使用标准库。所有处理均在本地完成，不调用网络、编译器或第三方工具。

## 使用

```console
python rtl2map.py --src sample/rtl --top system_fpga -o map.json
python rtl2map.py --src sample/rtl --top multicore
python rtl2map.py --src sample/rtl -o all-roots.json
python rtl2map.py --help
python rtl2map.py --version
```

- `--src` 必填，递归扫描 `.v`、`.sv`、`.vh`、`.svh`，扩展名不区分大小写。
- `--top` 可选，名称区分大小写。省略时，所有未被其他模块或自身例化的模块作为根节点。
- `-o` / `--output` 可选，直接写入 UTF-8 JSON；父目录需已存在。默认输出到 stdout，可重定向到文件。
- 每次执行解析都会在 **stderr** 打印 `EasyMapper 1.0.0`，不会混入 stdout 的 JSON。
- 无源码目录、无模块定义、找不到顶层或文件读写失败时退出码为 2；正常完成为 0。
- 跳过 `.git`、`.svn`、`.hg`、`obj_dir`、`simv`、`simv.daidir`、`csrc`、`__pycache__`、`node_modules`、`.venv`、`venv` 目录及符号链接文件/目录。

PRD 的标题使用 `rtlMapper.py`，命令行示例使用 `rtl2map.py`；本项目采用命令行示例的文件名。

## JSON 字段

基础结构与 `sample/format.json` 一致，另有源码位置和诊断信息：

| 字段 | 含义 |
| --- | --- |
| `schema_version` | `"1.0"` |
| `frontend` | `{"name": "EasyMapper", "version": "1.0.0"}` |
| `view` / `line_reference` / `elaborated` | `""` / `""` / `false` |
| `input_config.source_file` | 空字符串，与格式样例一致 |
| `input_config.top` | 指定顶层时为模块名字符串；自动推断时为与 `roots` 一致的数组 |
| `roots` | 指定顶层时为 `["顶层名"]`，否则为按名称排序的自动根列表 |
| `modules` | 仅保留从根可达的、实际找到定义的模块，按模块名排序 |
| `instantiations` | 按源码顺序排列；叶模块为空数组；重复实例不合并、不去重 |
| `module` / `instance` | 原文大小写；循环追加符号索引，实例数组保留声明维度 |
| `status` | 普通实例为 `normal`；genvar 循环中的实例为 `for_generated` |
| `times` | 仅循环实例存在，整数或符号字符串 |
| `source_file` / `source_line` | 相对 `--src` 的路径（正斜杠）、从 1 开始的例化语句行号 |
| `warnings` | 被丢弃的未知类型、重复定义、不完整候选、不能识别的循环等诊断 |

诊断中的 `code`、`message` 始终存在；可定位时附带文件和行号。诊断覆盖整个扫描目录，包括被裁剪模块中的问题。同一语句中以逗号分隔的实例使用该语句类型名所在行号。

## 循环和 PRD 歧义处理

PRD 同时写了“全部模块”和“必须裁剪”，本实现遵守后者：收集全部定义用于白名单，再仅输出从 roots 可达的模块，包括可达叶模块。

PRD 中“展开 N 条／输出两条”与第 5 节的单条 JSON 示例不一致。本实现遵循第 5 节及 `sample/format.json`：每个字面实例只产生一条记录，用符号索引和 `times` 描述循环，不做硬件展开。例如：

```systemverilog
localparam NUM = `CORE_NUM;
genvar i;
generate for (i = 0; i < NUM; i++) begin : g
  sub u_s (.a(a[i]));
end endgenerate
```

```json
{"module": "sub", "instance": "u_s[i]", "status": "for_generated", "times": "`CORE_NUM"}
```

支持显式 `generate`、省略 `generate` 的 genvar 循环、循环头内声明 genvar、嵌套循环、有名或无名 begin/end 及单语句循环体。支持 `<`、`<=`、`>`、`>=` 与单位递增/递减（`i++`、`++i`、`i+=1`、`i=i+1` 等）。

- 只对整数字面量做循环次数的直接计数；从 0 到符号上界的 `<` 循环，`times` 保留上界原文。
- 简单 parameter/localparam 别名按当前词法作用域替换为声明默认值文本，支持别名链；不展开宏、不求表达式值、不应用父模块参数覆盖。
- 非零起点或含端点的符号循环保留 `max(0, (上界) - (起点) + 1)` 等描述字符串，不求值。
- 嵌套循环保留 `u[i][j]`，次数为各层计数之积；符号因子保留为字符串。内层边界依赖外层变量时也只是符号描述，不保证代表总实例数。
- 不支持的步长/条件保留 `for (...)` 原文作为 `times` 并产生 `unsupported_loop_count` 警告；无法识别为 genvar 循环时跳过其循环体并警告。
- 零次循环保留一条 `times: 0` 的词法记录；它的模块边也参与可达性。输出明确标记 `elaborated: false`。

## 已知限制

- 这是容错的词法提取器，不是 SystemVerilog 编译器；不建立语法树，不验证完整语法，不分析位宽、端口连接、参数值或跨模块符号。
- 不展开宏、不解析 include 内容，也不验证 include 是否存在。目录中单独存在的头文件照常扫描，因此缺少 include 不致命。宏续行会整体屏蔽，避免宏定义中的文本成为假模块/假实例。
- 条件编译、generate-if、generate-case 的所有可见分支均保留；不求条件真假。只在宏展开后才出现的模块/实例无法识别。
- 唯一类型白名单是扫描到的 module 定义。未找到定义的类型（包括外部 IP、原语等）丢弃并警告；没有接口名称或后缀特判。
- 重复模块定义按相对文件路径排序，保留第一个定义并警告。不同编译配置的同名模块应分目录运行。
- 可处理普通/参数化/跨行/多实例语句、模块头 import、嵌套括号、实例数组和转义标识符。数组不展开，generate 块名不加入实例名，因此相同名字的记录可能重复。
- 过程块、function/task 等不视为模块例化区域；bind 不处理。不完整语句被跳过，严重语法缺损可能使后续语句无法恢复。
- 自动根推断不为纯循环依赖分量虚构根。若所有模块均被例化，返回空 roots/modules 并警告；用 `--top` 可提取指定循环图。
- 源码默认 UTF-8（可带 BOM）；非法字节用替换字符读取并警告，建议预先将其他编码转换为 UTF-8。

## 验证

```console
python -m unittest discover -s tests -v
```

测试包括 `sample/format.json` 同构比对、sample 全量 JSON 固定基准及每个顶层的裁剪、三类例化、循环嵌套与作用域、缺失 include、注释/字符串/宏续行、白名单过滤、过程语句排除、跨行参数/端口括号、多实例声明、排序和命令行行为。

`tests/expected_sample.json` 是经过源码核对的固定基准，不在测试中由解析器动态生成。Python 3.8 的语法兼容性另有检查；实际运行环境的版本以执行测试时为准。
