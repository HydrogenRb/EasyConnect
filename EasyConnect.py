#!/usr/bin/env python3
"""EasyConnect 1.0: the single user entry point for graph and RTL routing."""
import argparse
import json
from pathlib import Path
import sys

from RTLGraph import EasyConnectError, build_graph, protected
from WireConnect import execute


def parser():
    result = argparse.ArgumentParser(description="EasyConnect 1.0 — 零依赖 RTL 建图与连线工具")
    modes = result.add_subparsers(dest="mode", required=True)
    graph = modes.add_parser("1", help="扫描 .v/.sv，生成源码层级 JSON")
    graph.add_argument("rtl_folder", type=Path)
    graph.add_argument("top")
    graph.add_argument("-o", "--output", type=Path, help="JSON 输出路径")
    graph.add_argument("-f", "--filelist", action="append", type=Path, help="额外编译 filelist，可多次指定")
    graph.add_argument("-I", "--include-dir", action="append", default=[], type=Path)
    graph.add_argument("-D", "--define", action="append", default=[], help="条件编译宏 NAME[=VALUE]")
    route = modes.add_parser("2", help="根据 JSON 增加、删除、修改连接")
    route.add_argument("json_file", type=Path)
    route.add_argument("action", choices=("add", "rm", "mv", "list"))
    route.add_argument("endpoints", nargs="*", help="add: SRC.sig DST.sig；rm/mv: 连接 ID")
    route.add_argument("--src", help="mv 的新源端点")
    route.add_argument("--dst", help="mv 的新目标端点")
    route.add_argument("--src-instance", help="源例化编号、例化名或 top/instance/... 路径")
    route.add_argument("--dst-instance", help="目标例化编号、例化名或完整路径")
    route.add_argument("-d", "--dimension", type=int)
    route.add_argument("-w", "--width", help="packed 各维大小，逗号分隔，例如 'a,b'")
    route.add_argument("-c", "--comment", help="附在新生成代码后的单行注释")
    route.add_argument("--dry-run", action="store_true", help="展示规划及 diff，不写入源码和 JSON")
    return result


def main(argv=None):
    arguments = parser()
    args = arguments.parse_args(argv)
    try:
        if args.mode == "1":
            output = args.output
            if output is None:
                folder = args.rtl_folder.resolve()
                if protected(folder):
                    output = Path(__file__).resolve().parent / "test_result" / folder.name / "hierarchy.json"
                else:
                    output = folder / "easyconnect_hierarchy.json"
            defines = {}
            for value in args.define:
                key, _, val = value.partition("=")
                if not key: raise EasyConnectError("-D 宏名不能为空")
                defines[key] = val or "1"
            data = build_graph(args.rtl_folder, args.top, output, args.filelist, args.include_dir, defines)
            count = sum(len(mod["instantiations"]) for mod in data["modules"].values())
            print("建图完成：%d 个模块，%d 条源码例化引用。" % (len(data["modules"]), count))
            print("JSON: " + str(output.resolve()))
        elif args.action == "list":
            data = json.loads(args.json_file.read_text(encoding="utf-8-sig"))
            connections = data.get("_easyconnect", {}).get("connections", [])
            for connection in connections:
                print("%s  %s [%s] -> %s [%s]  -w %s  -c %s" %
                      (connection["id"], connection["src"], connection["src_instance"], connection["dst"],
                       connection["dst_instance"], ",".join(connection["widths"]), connection["comment"]))
            if not connections: print("暂无受管连接。")
        else:
            if args.action == "rm" and any(value is not None for value in
                    (args.src, args.dst, args.src_instance, args.dst_instance, args.dimension, args.width, args.comment)):
                raise EasyConnectError("rm 只接受连接 ID 或原始两端点，以及 --dry-run")
            execute(args.json_file, args.action, args.endpoints, args.src, args.dst,
                    args.dimension, args.width, args.comment, args.src_instance, args.dst_instance, args.dry_run)
        return 0
    except (EasyConnectError, OSError, ValueError, KeyError) as exc:
        print("EasyConnect 错误: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
