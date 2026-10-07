"""Run all verification and keep reviewable three-case artifacts in test_result.

python tests/run_acceptance.py [--compile]
The compiler is optional. Runtime and functional tests need only Python 3.8+.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from RTLGraph import SourceProject, build_graph, discover
from WireConnect import execute, hierarchy_paths, path_name
from test_easyconnect import hashes
from validate_rtl import compile_graph


def error_signatures(report):
    return Counter((r["code"], Path(r["file"]).name, tuple(r["args"])) for r in report["error_records"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compile", action="store_true")
    args = parser.parse_args()
    result_root = ROOT / "test_result"
    result_root.mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="verification_", dir=result_root))
    baseline_hashes = hashes(ROOT / "test_cases")
    environment = dict(os.environ, PYTHONIOENCODING="utf-8")
    summary = {"requirements": "docs/1.0版本需求文档.md", "run_folder": str(run), "cases": []}
    for script in ["test_easyconnect.py"] + (["test_compiler.py"] if args.compile else []):
        started = time.monotonic()
        process = subprocess.run([sys.executable, str(ROOT / "tests" / script)], capture_output=True,
                                 encoding="utf-8", env=environment)
        (run / (script + ".log")).write_text(process.stdout + process.stderr, encoding="utf-8")
        print("%s: %s (%.1fs)" % (script, "passed" if process.returncode == 0 else "FAILED", time.monotonic() - started), flush=True)
        count = re.search(r"Ran (\d+) tests", process.stderr)
        summary[script] = {"passed": process.returncode == 0, "tests": int(count.group(1)) if count else None,
                           "log": str(run / (script + ".log"))}
        if process.returncode != 0:
            print(process.stderr)
            return process.returncode
    cases = run / "cases"
    for index in (1, 2, 3):
        shutil.copytree(ROOT / "test_cases" / ("case%d" % index), cases / ("case%d" % index))
    tops = {1: "case1_soc_top", 2: "case2_chi_noc_top", 3: "case3_engine_top"}
    routes = {1: ("case1_dma_desc_fetch.ec_debug[gc]", "case1_perf_monitor.ec_debug_in"),
              2: ("case2_hn_req_pipe.ec_debug", "case2_chi_req_gen.ec_debug_in"),
              3: ("case3_dma_desc_fetch.ec_debug", "case3_config_regs.ec_debug_in")}
    for index in (1, 2, 3):
        case = cases / ("case%d" % index)
        reports = run / "reports" / ("case%d" % index)
        reports.mkdir(parents=True)
        graph_path = reports / "hierarchy.json"
        data = build_graph(case, tops[index], graph_path)
        originals = {p: p.read_bytes() for p in case.rglob("*.v")}
        files, dirs, defines = discover(case)
        project = SourceProject(files, tops[index], defines, dirs)
        paths = hierarchy_paths(project)
        src, dst = routes[index]
        source = path_name(paths[src.split(".")[0]][0])
        target = path_name(paths[dst.split(".")[0]][0])
        case_report = {"case": index, "modules": len(data["modules"]),
                       "instances": sum(len(m["instantiations"]) for m in data["modules"].values()),
                       "src_instance": source, "dst_instance": target}
        compiles = {}
        if args.compile: compiles["baseline"] = compile_graph(graph_path)
        messages = []
        added = execute(graph_path, "add", (src, dst), width="8", comment="EasyConnect 1.0 验收",
                        src_instance=source, dst_instance=target, printer=messages.append)
        (reports / "add.diff.txt").write_text("\n".join(messages), encoding="utf-8")
        if args.compile: compiles["add"] = compile_graph(graph_path)
        execute(graph_path, "mv", (added["id"],), width="16", comment="修改为16位总线", printer=lambda value: None)
        if args.compile: compiles["mv"] = compile_graph(graph_path)
        execute(graph_path, "rm", (added["id"],), printer=lambda value: None)
        if args.compile: compiles["rm"] = compile_graph(graph_path)
        case_report["rtl_restored"] = all(p.read_bytes() == raw for p, raw in originals.items())
        assert case_report["rtl_restored"], "rm failed to restore RTL"
        if args.compile:
            baseline = error_signatures(compiles["baseline"])
            case_report["baseline_compile_errors"] = compiles["baseline"]["errors"]
            case_report["compiler_new_errors"] = {}
            for stage, report in compiles.items():
                (reports / ("compile_" + stage + ".json")).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
                if stage != "baseline":
                    extra = error_signatures(report) - baseline
                    case_report["compiler_new_errors"][stage] = sum(extra.values())
                    assert not extra, "compiler regression in case%d %s: %s" % (index, stage, extra)
        # Retain a final live connection and a refreshed, renderable hierarchy.
        execute(graph_path, "add", (src, dst), width="8", comment="EasyConnect 1.0 验收",
                src_instance=source, dst_instance=target, printer=lambda value: None)
        html = subprocess.run([sys.executable, str(ROOT / "test_cases/test_python/hierarchy_to_html.py"), str(graph_path),
                               "-o", str(reports / "hierarchy.html"), "--top", tops[index]], capture_output=True,
                              encoding="utf-8", env=environment)
        assert html.returncode == 0, html.stderr
        case_report["html"] = str(reports / "hierarchy.html")
        case_report["graph_add_mv_rm"] = "passed"
        summary["cases"].append(case_report)
        print("case%d: %d modules / %d source instances; graph + HTML + add/mv/rm passed" %
              (index, case_report["modules"], case_report["instances"]), flush=True)
    summary["golden_unchanged"] = baseline_hashes == hashes(ROOT / "test_cases")
    assert summary["golden_unchanged"], "test_cases changed"
    summary["passed"] = True
    (run / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (result_root / "latest_verification.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    total = sum(summary[s]["tests"] or 0 for s in ("test_easyconnect.py", "test_compiler.py") if s in summary)
    lines = ["# EasyConnect 1.0 测试报告", "", "需求基准：`docs/1.0版本需求文档.md` 及其引用的连线 PLAN。", "",
             "本轮 %d 项自动测试通过；三个 case 均通过建图、HTML、add/mv/rm 验收，rm 后 RTL 字节恢复一致。" % total,
             "所有可变测试在 `test_result/` 副本中进行，`test_cases/` 全部文件的 SHA-256 比较一致。", "",
             "| case | 模块 | 源码例化 | 原始编译错误 | add/mv/rm 新增错误 |", "| --- | ---: | ---: | ---: | --- |"]
    for case in summary["cases"]:
        errors = case.get("compiler_new_errors")
        lines.append("| case%d | %d | %d | %s | %s |" %
                     (case["case"], case["modules"], case["instances"], case.get("baseline_compile_errors", "未执行"),
                      "/".join(str(errors[s]) for s in ("add", "mv", "rm")) if errors else "未执行"))
    lines.extend(["", "原始工程的编译错误已单独记录，没有改动 golden 代码。合法的小工程使用独立 slang 编译器检查；源码编辑成功和整个原始工程编译通过分别报告。", "",
                  "验证命令：`python tests/run_acceptance.py" + (" --compile`" if args.compile else "`"), "",
                  "产物：", "", "- [验收汇总](%s/summary.json)" % run.name])
    for script in ("test_easyconnect.py", "test_compiler.py"):
        if script in summary:
            lines.append("- [%s：%d 项通过](%s/%s.log)" % (script, summary[script]["tests"], run.name, script))
    for case in summary["cases"]:
        prefix = "%s/reports/case%d" % (run.name, case["case"])
        lines.append("- case%d：[层级 JSON](%s/hierarchy.json)、[HTML](%s/hierarchy.html)、[连线 diff](%s/add.diff.txt)" %
                     (case["case"], prefix, prefix, prefix))
    lines.extend(["", "`%s/cases/` 保留三个 case 修改后的 RTL 副本和跨 case 库依赖；每份 JSON 内保存当前连接 ID，可继续执行 list、dry-run、mv 或 rm。" % run.name, ""])
    (result_root / "测试报告.md").write_text("\n".join(lines), encoding="utf-8")
    print("Report: " + str(run / "summary.json"))
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
