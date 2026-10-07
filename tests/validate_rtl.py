"""Optional slang compiler verification, separate from zero-dependency runtime.

Install a binary pyslang wheel in test_result/_tools or your test environment.
Usage: python tests/validate_rtl.py path/to/hierarchy.json [-o report.json]
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "test_result" / "_tools"))


def compile_files(files, top, defines=None, include_dirs=None):
    try:
        import pyslang
        from pyslang.driver import Driver
        from pyslang import DiagnosticEngine
    except ImportError as exc:
        raise RuntimeError("可选编译器未安装：pip install --target test_result/_tools pyslang") from exc
    driver = Driver()
    driver.addStandardArgs()
    # Compiler arguments are passed as data to its parser, never to a shell.
    def quote(value): return '"' + str(value).replace("\\", "/").replace('"', '\\"') + '"'
    directories = list(dict.fromkeys(list(include_dirs or []) + [str(Path(p).parent) for p in files]))
    arguments = "--single-unit --top " + top
    for directory in directories: arguments += " -I " + quote(directory)
    for key, value in (defines or {}).items(): arguments += " -D " + quote(key + "=" + value)
    arguments += " " + " ".join(quote(file) for file in files)
    if not driver.parseCommandLine(arguments) or not driver.processOptions():
        raise RuntimeError("编译器参数无效")
    driver.parseAllSources()
    compilation = driver.createCompilation()
    diagnostics = compilation.getAllDiagnostics()
    errors = [diag for diag in diagnostics if diag.isError()]
    report = DiagnosticEngine.reportAll(driver.sourceManager, diagnostics)
    # Identify regression categories independently of shifted source line numbers.
    signatures = Counter(str(diag.code) for diag in errors)
    error_records = []
    for diag in errors:
        location = driver.sourceManager.getFullyOriginalLoc(diag.location)
        error_records.append({"code": str(diag.code), "file": str(driver.sourceManager.getFileName(location)),
                              "line": driver.sourceManager.getLineNumber(location),
                              "args": [str(value) for value in diag.args]})
    return {"compiler": "slang " + pyslang.__version__, "top": top,
            "files": len(files), "errors": len(errors), "warnings": len(diagnostics) - len(errors),
            "error_codes": dict(signatures), "error_records": error_records,
            "diagnostics": report, "passed": not errors}


def compile_graph(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    config = data["input_config"]
    return compile_files(config["files"], config["top"], config.get("defines"), config.get("include_dirs"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("graph", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args()
    report = compile_graph(args.graph)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(report["diagnostics"])
    print("%s: %d errors, %d warnings" % (report["compiler"], report["errors"], report["warnings"]))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
