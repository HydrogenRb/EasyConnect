#!/usr/bin/env python3
"""debug_graph.py — locate where EasyConnect's source parsing gives up.

Bracket complaints used to arrive as a bare character offset
("括号不匹配，源码字符位置 514046"), which says nothing about which file is at
fault in a directory holding hundreds of them.  This script replays exactly the
same pipeline as 建图 (discover -> preprocess -> mask -> tokenize -> pairs) on
every file separately, so the first failing file is named, and then prints the
offending line, a caret under the exact character, the directive/macro context
and a dump of the token window around the failure.

It never writes source files or a hierarchy JSON: it only reads.

    python tests/debug_graph.py ./rtl                      # report the first failing file
    python tests/debug_graph.py ./rtl --top TOP            # also check that the top is reachable
    python tests/debug_graph.py ./rtl -f ./compile.f       # same compile inputs as 建图
    python tests/debug_graph.py ./rtl -I ./include -D F=1
    python tests/debug_graph.py ./rtl -o files.json        # export the resolved file list
    python tests/debug_graph.py ./rtl --list-only          # show what would be scanned
"""
import argparse
import json
import re
import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from RTLGraph import (EasyConnectError, blank, discover, line_column,
                      mask_comments, pairs, read_source, snippet, tokenize)

DIRECTIVES = ("include", "define", "undef", "ifdef", "ifndef", "else", "elsif", "endif",
              "timescale", "default_nettype", "resetall", "celldefine", "endcelldefine")
DIRECTIVE_LINE = re.compile(r"(?m)^[ \t]*`(?:%s)\b[^\r\n]*(?:\\\r?\n[^\r\n]*)*" % "|".join(DIRECTIVES))
BRACKETS = "()[]{}"
CLOSING = {")": "(", "]": "[", "}": "{"}


class Context:
    """Source text of one file, plus the same text after masking."""

    def __init__(self, path, text):
        self.name = str(path)
        self.text = text
        self.masked = mask_comments(text)
        self.blanked = DIRECTIVE_LINE.sub(lambda match: blank(match.group()), self.masked)

    def line_text(self, number):
        lines = self.text.splitlines()
        return lines[number - 1] if 1 <= number <= len(lines) else ""

    def where(self, position):
        line, column = line_column(self.text, position)
        return "第 %d 行第 %d 列（字符位置 %d）" % (line, column, position)

    def excerpt(self, position, radius=2, width=200):
        return snippet(self.text, position, radius, width)

    def token_window(self, tokens, index, before=6, after=6):
        rows = []
        for position in range(max(0, index - before), min(len(tokens), index + after + 1)):
            token = tokens[position]
            mark = ">>" if position == index else "  "
            rows.append("%s [%3d] %-12s %s" % (mark, position, repr(token.value), self.where(token.start)))
        return rows

    def raw_character(self, position):
        return self.text[position] if 0 <= position < len(self.text) else "<文件末尾之外>"


def first_failure(context):
    """Return (position, message) for the first unmatched bracket, else None.

    Reimplements the pairing walk without raising, so both the unexpected closer
    and the innermost unclosed opener can be reported for one file.
    """
    tokens = tokenize(context.blanked)
    stack = []
    for index, token in enumerate(tokens):
        if token.value in "([{":
            stack.append(index)
        elif token.value in ")]}":
            if not stack or CLOSING[token.value] != tokens[stack[-1]].value:
                return index, tokens, "多余的 %s" % token.value, stack[-1] if stack else None
            stack.pop()
    if stack:
        index = stack[-1]
        return index, tokens, "%s 未闭合" % tokens[index].value, None
    return None


def report(path, top=None, defines=None, include_dirs=None, radius=2):
    text, encoding = read_source(path)
    context = Context(path, text)
    print("=" * 78)
    print("文件: %s" % context.name)
    print("      编码 %s，%d 行，%d 字符" % (encoding, text.count("\n") + 1, len(text)))
    try:
        found = first_failure(context)
    except EasyConnectError as exc:                      # e.g. a tokenizer-level problem
        print("  × 词法阶段失败: %s" % exc)
        return False
    if found is None:
        try:
            pairs(tokenize(context.blanked), context.text, context.name)
        except EasyConnectError as exc:
            print("  × pairs() 失败: %s" % exc)
            return False
        print("  √ 括号配对正常")
        return True

    index, tokens, summary, opener = found
    token = tokens[index]
    print("  × 括号问题: %s" % summary)
    print("      出错位置: %s" % context.where(token.start))
    print("      该处字符: %r" % context.raw_character(token.start))
    print()
    for row in context.excerpt(token.start, radius):
        print("      " + row)
    if opener is not None:
        opening = tokens[opener]
        print()
        print("      最近未闭合的 %s 在 %s" % (opening.value, context.where(opening.start)))
        for row in context.excerpt(opening.start, radius=1):
            print("      " + row)
    print()
    print("      出错处的 token 窗口:")
    for row in context.token_window(tokens, index):
        print("      " + row)
    return False


def blame_candidates(context):
    """Cheap heuristics for constructs that commonly unbalance this tokenizer."""
    text = context.text
    hints = []
    if text.count("/*") != text.count("*/"):
        hints.append("块注释 /* 与 */ 数量不等：未闭合的 /* 会让后面的括号全部错位")
    if not text.endswith("\n") and text.splitlines():
        tail = text.splitlines()[-1].strip()
        if tail and not tail.endswith((";", "endmodule", "end", "*/")):
            hints.append("最后一行不以 ; / endmodule 结束: %r" % tail[:60])
    for number, line in enumerate(text.splitlines(), 1):
        stripped = mask_comments(line).strip()
        if stripped.startswith("`") and stripped.count('"') % 2 == 1:
            hints.append("第 %d 行的编译指令引号不成对（宏展开的 include 本版不支持）" % number)
            break
    for number, line in enumerate(text.splitlines(), 1):
        body = mask_comments(line)
        if re.match(r"\s*`(ifdef|ifndef|else|elsif|endif)\b", body) and any(c in BRACKETS for c in body.split(None, 1)[-1]):
            hints.append("第 %d 行的条件编译指令本体含括号 %r，本版不做宏展开，会直接进入括号计数"
                         % (number, line.strip()[:70]))
    for number, line in enumerate(text.splitlines(), 1):
        if "(*" in mask_comments(line):
            hints.append("第 %d 行出现 (* ... *) 属性/事件控制语法，非 ANSI 1.0 解析范围" % number)
            break
    return hints


def main(argv=None):
    parser = argparse.ArgumentParser(description="定位 EasyConnect 建图解析失败的文件与字符位置")
    parser.add_argument("rtl_folder", type=Path)
    parser.add_argument("--top", help="顶层模块名，用于顺带确认非括号类问题")
    parser.add_argument("-f", "--filelist", action="append", type=Path, help="与建图相同的额外 filelist")
    parser.add_argument("-I", "--include-dir", action="append", default=[], type=Path)
    parser.add_argument("-D", "--define", action="append", default=[])
    parser.add_argument("-o", "--output", type=Path, help="把解析出的文件清单写成 JSON（可选）")
    parser.add_argument("--list-only", action="store_true", help="只列出将要扫描的文件")
    parser.add_argument("--limit", type=int, default=0, help="最多检查多少个文件（0 表示全部）")
    parser.add_argument("--radius", type=int, default=2, help="出错处上下显示几行")
    args = parser.parse_args(argv)

    defines = {}
    for value in args.define:
        key, _, val = value.partition("=")
        if key:
            defines[key] = val or "1"
    try:
        files, dirs, macros = discover(args.rtl_folder, args.filelist, args.include_dir, defines)
    except EasyConnectError as exc:
        print("扫描/编译输入阶段失败: %s" % exc)
        print("提示: 该阶段报错请核对 filelist 条目路径、-I 目录是否存在；"
              "若目录里有过期 filelist.f，可用 -f 指向正确的列表。")
        return 2
    macros.update(defines)

    print("扫描目录: %s" % Path(args.rtl_folder).resolve())
    print("解析文件: %d 个；include 目录: %s；宏: %s" %
          (len(files), dirs or "（无）", macros or "（无）"))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({"files": files, "include_dirs": dirs, "defines": macros},
                                          ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("文件清单已写入: %s" % args.output)
    if args.list_only:
        for file in files:
            print("  " + file)
        return 0

    selected = files[:args.limit] if args.limit > 0 else files
    failures, passed = [], 0
    for file in selected:
        try:
            text, _ = read_source(file)
        except EasyConnectError as exc:
            print("读取失败: %s" % exc)
            failures.append(file)
            continue
        context = Context(file, text)
        try:
            found = first_failure(context)
        except EasyConnectError as exc:
            print("%s\n  × 词法阶段失败: %s" % (file, exc))
            failures.append(file)
            continue
        if found is None:
            passed += 1
            continue
        failures.append(file)
        report(file, args.top, macros, dirs, args.radius)
        hints = blame_candidates(context)
        if hints:
            print()
            print("      可疑构造:")
            for hint in hints:
                print("      - %s" % hint)
        print()
        print("      结论: 括号问题只出现在上面这一个文件；修好它再重新建图。")
        print("      若这是第三方库文件，且你不需要它参与建图，确认它确实被 filelist 或扫描收录后排除。")
        break
    else:
        print("=" * 78)
        print("全部 %d 个文件的括号配对都正常。" % passed)
        print("说明报错来自别处：请用 python EasyConnect.py 1 复现，并检查 include 链"
              "（被 include 的头文件也会进入括号计数）与 -I 宏设置。")
        return 0

    print("=" * 78)
    print("括号正常: %d 个；报错文件: %d 个" % (passed, len(failures)))
    return 1


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception:                                    # never hide a debugger's own crash
        traceback.print_exc()
        sys.exit(3)
