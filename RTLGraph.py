"""Offline RTL graph: collect modules, then regex-search each file for instances.

Only headers, declarations and connection lists are parsed. Source offsets
always refer to the original file, including comments, encoding and CRLFs.
"""
import ast
import hashlib
import json
import operator
import os
from pathlib import Path
import re
import tempfile
from collections import namedtuple
from types import SimpleNamespace


class EasyConnectError(Exception):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_source(path):
    try:
        raw = Path(path).read_bytes()
        for encoding in ("utf-8-sig",) if raw.startswith(b"\xef\xbb\xbf") else ("utf-8", "gb18030"):
            try:
                return raw.decode(encoding), encoding
            except UnicodeDecodeError:
                continue
    except OSError as exc:
        raise EasyConnectError("无法读取源码 %s: %s" % (path, exc)) from exc
    raise EasyConnectError("无法读取源码编码: %s" % path)


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def atomic_write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".easyconnect-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def protected(path):
    try:
        Path(path).resolve().relative_to(Path(__file__).resolve().parent / "test_cases")
        return True
    except ValueError:
        return False


def blank(text):
    return re.sub(r"[^\r\n]", " ", text)


COMMENT_STRING = re.compile(r'\\[^\s]+|//[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\[\s\S]|[^"\\])*"|\(\*(?!\))[\s\S]*?\*\)')


def mask_comments(text, strings=False):
    return COMMENT_STRING.sub(lambda m: blank(m.group()) if m.group().startswith(("//", "/*", "(*"))
                             or strings and m.group().startswith('"') else m.group(), text)


def line_column(text, position):
    return text.count("\n", 0, position) + 1, position - text.rfind("\n", 0, position)


def snippet(text, position, radius=0, width=160):
    line, column = line_column(text, position)
    lines, result = text.split("\n"), []
    left = max(0, column - width // 2)
    for number in range(max(1, line - radius), min(len(lines), line + radius) + 1):
        prefix = "%d | " % number
        result.append(prefix + lines[number - 1].rstrip("\r")[left:left + width].expandtabs(4))
        if number == line:
            result.append(" " * (len(prefix) + len(lines[number - 1][left:column - 1].expandtabs(4))) + "^")
    return result


def source_error(text, path, position, message, module=""):
    line, column = line_column(text, position)
    location = "%s:%d:%d%s" % (path, line, column, " [module %s]" % module if module else "")
    raise EasyConnectError("%s: %s\n%s" % (location, message, "\n".join(snippet(text, position))))


ID = r"(?:[A-Za-z_$][\w$]*|\\[^\s]+)"
Token = namedtuple("Token", "value start end")
TOKEN = re.compile(r'"(?:\\[\s\S]|[^"\\])*"|\\[^\s]+|\x60?[A-Za-z_$][\w$]*|'
                   r"\d+(?:'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+)?|'?[01xXzZ]|"
                   r"<=|>=|==|!=|\+:|-:|::|<<|>>|[^\s]")


def tokenize(text, start=0, end=None):
    return [Token(m.group(), m.start(), m.end()) for m in TOKEN.finditer(text, start, len(text) if end is None else end)]


def pairs(tokens, text="", path="<表达式>", module="", first_group=False):
    result, stack = {}, []
    for index, token in enumerate(tokens):
        if token.value in ("(", "[", "{"):
            stack.append((index, token))
        elif token.value in (")", "]", "}"):
            if not stack or stack[-1][1].value != {")": "(", "]": "[", "}": "{"}[token.value]:
                source_error(text, path, token.start, "括号不匹配: %s" % token.value, module)
            opening, _ = stack.pop()
            result[opening] = index
            if first_group and not stack:
                return token.start
    if stack:
        source_error(text, path, stack[-1][1].start, "括号未闭合: %s" % stack[-1][1].value, module)
    return result


def split_tokens(tokens, delimiter=","):
    groups, start, depth = [], 0, 0
    for index, token in enumerate(tokens):
        if token.value == delimiter and depth == 0:
            groups.append(tokens[start:index])
            start = index + 1
        depth += token.value in ("(", "[", "{")
        depth -= token.value in (")", "]", "}")
    return groups + [tokens[start:]]


def split_expressions(text):
    return [text[g[0].start:g[-1].end].strip() for g in split_tokens(tokenize(mask_comments(text))) if g]


Declaration = namedtuple("Declaration", "name direction kind ranges unpacked initialized", defaults=(False, False))


class Module(SimpleNamespace):
    @property
    def newline(self):
        return "\r\n" if "\r\n" in self.text else "\n"

    def line(self, position):
        return line_column(self.text, position)[0]


DIRECTIONS = {"input", "output", "inout"}
TYPES = {"wire", "reg", "logic", "bit", "tri", "uwire", "integer", "int", "signed", "unsigned", "var"}
DIRECTIVE = re.compile(r"(?m)^[ \t]*\x60(include|define|undef|ifdef|ifndef|else|elsif|endif|timescale|default_nettype|resetall|celldefine|endcelldefine)\b(?:[^\r\n]*?\\\r?\n)*[^\r\n]*")
MODULE_BOUNDARY = re.compile(r"\\\S+|(?P<keyword>(?<![\w$\x60])(?:module\b|endmodule\b))")
MODULE_NAME = re.compile(r"\s+(?:(?:automatic|static)\s+)?(" + ID + r")")
INSTANCE_TYPE = re.compile(r"(?<![\w$\x60])" + ID + r"(?![\w$])")
INSTANCE_NAME = re.compile(r"\s*(" + ID + r")\s*")
PARAMETER_LIST = re.compile(r"\s*#\s*(\()")
INSTANCE_TAIL = re.compile(r"\s*([,;])")
WHITESPACE = re.compile(r"\s*")
DECLARATION = re.compile(r"(?<![\w$\x60\\])(?:" + "|".join(sorted(DIRECTIONS | TYPES | {"parameter", "localparam"})) + r")\b[^;]*;")
DECLARATOR = re.compile(r"\s*((?:(?:" + "|".join(sorted(DIRECTIONS | TYPES)) + r")\s+)*)(\s*(?:\[[^\]]*\]\s*)*)(" + ID + r")")


def parse_declarations(tokens, text, ansi=False):
    result, direction, kind, ranges = {}, "", "wire", ()
    for group in split_tokens(tokens):
        if not group:
            continue
        value = mask_comments(text[group[0].start:group[-1].end])
        match = DECLARATOR.match(value)
        if not match or not (match[1] or ansi or result):
            continue
        if match[1]:
            qualifiers = match[1].split()
            direction = next((q for q in qualifiers if q in DIRECTIONS), "")
            kind = next((q for q in qualifiers if q in TYPES - {"signed", "unsigned", "var"}), "wire")
            ranges = tuple(re.findall(r"\[([^\]]*)\]", match[2]))
        tail = value[match.end():]
        result[match[3]] = Declaration(match[3], direction, kind, ranges, bool(re.match(r"\s*\[", tail)), "=" in tail)
    return result


def group_end(mod, opening):
    tokens = (Token(m.group(), m.start(), m.end()) for m in TOKEN.finditer(mod.masked, opening, mod.end - 9))
    return pairs(tokens, mod.text, mod.file, mod.name, first_group=True)


def parse_file(path, text, processed=None):
    lexical = mask_comments(text if processed is None else processed)
    masked = mask_comments(text if processed is None else processed, strings=True)
    masked = DIRECTIVE.sub(lambda m: blank(m.group()), masked)
    boundaries, modules = [m for m in MODULE_BOUNDARY.finditer(masked) if m.lastgroup], []
    for index in range(0, len(boundaries), 2):
        start = boundaries[index]
        name = MODULE_NAME.match(masked, start.end())
        if start.group() != "module" or name is None:
            source_error(text, path, start.start(), "无法识别 module 声明")
        if index + 1 == len(boundaries) or boundaries[index + 1].group() != "endmodule":
            source_error(text, path, start.start(), "缺少 endmodule", name[1])
        header_end = masked.find(";", name.end(), boundaries[index + 1].start())
        if header_end < 0:
            source_error(text, path, start.start(), "module 声明缺少分号", name[1])
        mod = Module(name=name[1], file=str(Path(path).resolve()), text=text, masked=masked,
                     start=start.start(), end=boundaries[index + 1].end(), header_end=header_end + 1,
                     opening=None, closing=None, ansi=True, declarations={}, instances=[], parameters={})
        header, parameters, cursor = tokenize(lexical, name.end(), header_end), [], 0
        matching = pairs(header, text, mod.file, mod.name)
        if header and header[0].value == "#" and len(header) > 1 and header[1].value == "(":
            cursor = matching[1] + 1
            parameters.extend(split_tokens(header[2:cursor - 1]))
        if cursor < len(header) and header[cursor].value == "(":
            closing = matching[cursor]
            mod.opening, mod.closing = header[cursor].start, header[closing].start
            ports = header[cursor + 1:closing]
            mod.ansi = any(t.value in DIRECTIONS for t in ports) or not ports
            if mod.ansi:
                mod.declarations.update(parse_declarations(ports, text, True))
            cursor = closing + 1
        if cursor != len(header):
            source_error(text, mod.file, header[cursor].start, "无法识别 module 参数或端口列表", mod.name)
        mod.io_start = mod.opening if mod.opening is not None else mod.start
        mod.io_end = mod.closing if mod.closing is not None else header_end
        body = re.sub(r"\b(function|task)\b[\s\S]*?\bend\1\b", lambda m: blank(m.group()), masked[mod.header_end:mod.end - 9])
        io_lines = []
        for match in DECLARATION.finditer(body):
            left, right = mod.header_end + match.start(), mod.header_end + match.end()
            tokens = tokenize(lexical, left, right - 1)
            if tokens[0].value in ("parameter", "localparam"):
                parameters.extend(split_tokens(tokens[1:]))
                continue
            for key, decl in parse_declarations(tokens, text).items():
                if key in mod.declarations and not decl.direction:
                    decl = decl._replace(direction=mod.declarations[key].direction)
                mod.declarations[key] = decl
            if not mod.ansi and tokens[0].value in DIRECTIONS:
                io_lines.append((left, right - 1))
        if io_lines:
            mod.io_start, mod.io_end = io_lines[0][0], io_lines[-1][1]
        for group in parameters:
            equal = next((i for i, t in enumerate(group) if t.value == "="), 0)
            if 0 < equal < len(group) - 1:
                mod.parameters[group[equal - 1].value] = text[group[equal + 1].start:group[-1].end]
        modules.append(mod)
    return modules


def parse_instances(mod, names):
    instances, consumed = [], mod.header_end
    for match in INSTANCE_TYPE.finditer(mod.masked, mod.header_end, mod.end - 9):
        if match.group() not in names or match.start() < consumed:
            continue
        cursor, parameters, candidates = match.end(), "", []
        parameter = PARAMETER_LIST.match(mod.masked, cursor, mod.end - 9)
        if parameter:
            opening = parameter.start(1)
            closing = group_end(mod, opening)
            parameters, cursor = mod.text[opening + 1:closing], closing + 1
        while True:
            name = INSTANCE_NAME.match(mod.masked, cursor, mod.end - 9)
            if not name:
                if candidates or parameter:
                    source_error(mod.text, mod.file, cursor, "例化缺少实例名", mod.name)
                break
            name_start, cursor = name.start(1), name.end()
            while mod.masked[cursor:cursor + 1] == "[":
                cursor = group_end(mod, cursor) + 1
                cursor = WHITESPACE.match(mod.masked, cursor, mod.end - 9).end()
            if mod.masked[cursor:cursor + 1] != "(":
                break
            closing, bindings, named = group_end(mod, cursor), {}, True
            for group in split_tokens(tokenize(mod.masked, cursor + 1, closing)):
                if not group:
                    continue
                if len(group) < 4 or group[0].value != "." or group[2].value != "(" or group[-1].value != ")":
                    named = False
                    continue
                port = group[1].value
                if port in bindings:
                    source_error(mod.text, mod.file, group[1].start, "重复例化端口: " + port, mod.name)
                bindings[port] = (mod.text[group[2].end:group[-1].start].strip(), group[2].end, group[-1].start)
            inst_name = re.sub(r"\s+", "", mod.masked[name_start:cursor])
            candidates.append(SimpleNamespace(module=match.group(), name=inst_name, start=match.start(),
                              end=closing + 1, opening=cursor, closing=closing, parameters=parameters, named=named, bindings=bindings))
            tail = INSTANCE_TAIL.match(mod.masked, closing + 1, mod.end - 9)
            if not tail:
                source_error(mod.text, mod.file, closing + 1, "例化列表后缺少逗号或分号", mod.name)
            cursor = tail.end()
            if tail[1] == ";":
                for inst in candidates:
                    inst.end, inst.ordinal = cursor, len(instances)
                    instances.append(inst)
                consumed = cursor
                break
    return instances


def constant(expression, environment=None, depth=0):
    """Evaluate bounded integer expressions without executing RTL text."""
    if depth > 20:
        return None
    operations = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
                  ast.Div: operator.floordiv, ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod,
                  ast.LShift: operator.lshift, ast.RShift: operator.rshift,
                  ast.BitAnd: operator.and_, ast.BitOr: operator.or_, ast.BitXor: operator.xor,
                  ast.UAdd: operator.pos, ast.USub: operator.neg, ast.Invert: operator.invert}
    def visit(node):
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.Name) and node.id in (environment or {}):
            result = constant(str(environment[node.id]), environment, depth + 1)
            if result is not None:
                return result
        if isinstance(node, (ast.UnaryOp, ast.BinOp)) and type(node.op) in operations:
            args = [visit(node.operand)] if isinstance(node, ast.UnaryOp) else [visit(node.left), visit(node.right)]
            if max(map(abs, args)) <= 10**12 and (not isinstance(node.op, (ast.LShift, ast.RShift)) or 0 <= args[1] < 64):
                return operations[type(node.op)](*args)
        raise ValueError()
    try:
        value = re.sub(r"\x60([A-Za-z_]\w*)", r"\1", expression.strip())
        value = re.sub(r"\d+'[sS]?([bBoOdDhH])([\da-fA-F_]+)",
                       lambda m: str(int(m[2].replace("_", ""), {"b": 2, "o": 8, "d": 10, "h": 16}[m[1].lower()])), value)
        tree = ast.parse(value, mode="eval")
        return visit(tree.body) if sum(1 for _ in ast.walk(tree)) <= 100 else None
    except (SyntaxError, ValueError, TypeError, ArithmeticError, RecursionError):
        return None


class SourceProject:
    def __init__(self, files, top, defines=None, include_dirs=None, texts=None):
        self.files = list(dict.fromkeys(str(Path(p).resolve()) for p in files))
        self.top, self.initial_defines = top, dict(defines or {})
        self.include_dirs = [str(Path(p).resolve()) for p in include_dirs or []]
        self.texts, self.encodings, self.modules = {}, {}, {}
        self.compilation_views, self.module_macros = {}, {}
        self.macros = dict(self.initial_defines)
        for file in self.files:
            content, self.encodings[file] = read_source(file)
            self.texts[file] = texts.get(file, content) if texts is not None else content
        for file in self.files:
            self.preprocess(file, [])
        for file in self.files:
            self.load_modules(file)
        if top not in self.modules:
            raise EasyConnectError("顶层模块不存在: " + top)
        self.filter_instances()

    def resolve_include(self, file, name):
        candidates = [str((Path(d) / name).resolve()) for d in [Path(file).parent] + self.include_dirs]
        found = next((p for p in candidates if p in self.texts), None)
        matches = [p for p in self.files if Path(p).name == name]
        if found or len(matches) == 1:
            return found or matches[0]
        raise EasyConnectError("无法唯一定位 include %s (来自 %s)；使用 -I 指定目录" % (name, file))

    def preprocess(self, file, ancestry):
        if file in ancestry:
            raise EasyConnectError("循环 include: " + " -> ".join(ancestry + [file]))
        text, stack, active, result, cursor = self.texts[file], [], True, [], 0
        for match in DIRECTIVE.finditer(mask_comments(text)):
            result.append(text[cursor:match.start()] if active else blank(text[cursor:match.start()]))
            command, body = match[1], match.group().split(match[1], 1)[1].strip()
            symbol = body.split()[0] if body else ""
            if command in ("ifdef", "ifndef"):
                if not symbol:
                    source_error(text, file, match.start(), "条件编译指令缺少宏名")
                condition = (symbol in self.macros) == (command == "ifdef")
                stack.append([active, condition, False, match.start()])
                active = active and condition
            elif command in ("else", "elsif"):
                if not stack or stack[-1][2] or command == "elsif" and not symbol:
                    source_error(text, file, match.start(), "条件编译指令不匹配")
                parent, used, _, opening = stack[-1]
                condition = not used and (command == "else" or symbol in self.macros)
                stack[-1], active = [parent, used or condition, command == "else", opening], parent and condition
            elif command == "endif":
                if not stack:
                    source_error(text, file, match.start(), "多余 endif")
                active = stack.pop()[0]
            elif active and command == "define":
                definition = re.match(r"([A-Za-z_$][\w$]*)([\s\S]*)", body)
                if definition:
                    self.macros[definition[1]] = definition[2].strip() or "1"
            elif active and command == "undef":
                self.macros.pop(symbol, None)
            elif active and command == "include":
                include = re.fullmatch(r'"([^"\r\n]+)"', body)
                try:
                    if not include:
                        raise EasyConnectError("不支持宏展开的 include")
                    self.preprocess(self.resolve_include(file, include[1]), ancestry + [file])
                except EasyConnectError as exc:
                    source_error(text, file, match.start(), str(exc))
            result.append(blank(text[match.start():match.end()]))
            cursor = match.end()
        result.append(text[cursor:] if active else blank(text[cursor:]))
        if stack:
            source_error(text, file, stack[-1][3], "条件编译块未闭合")
        processed, previous = "".join(result), self.compilation_views.get(file)
        has_modules = any(m.lastgroup for m in MODULE_BOUNDARY.finditer(mask_comments(processed, True)))
        if previous is None or has_modules:
            if previous and has_modules and any(m.lastgroup for m in MODULE_BOUNDARY.finditer(mask_comments(previous[0], True))) and previous[0] != processed:
                raise EasyConnectError("同一源码在不同编译宏上下文中包含不同模块定义，无法可靠编辑: " + file)
            self.compilation_views[file] = (processed, dict(self.macros))
        return processed

    def load_modules(self, file):
        for mod in parse_file(file, self.texts[file], self.compilation_views[file][0]):
            if mod.name in self.modules:
                other = self.modules[mod.name]
                source_error(mod.text, file, mod.start, "重复模块 %s；另一处定义: %s:%d" % (mod.name, other.file, other.line(other.start)), mod.name)
            self.modules[mod.name], self.module_macros[mod.name] = mod, self.compilation_views[file][1]

    def filter_instances(self):
        for mod in self.modules.values():
            mod.instances = parse_instances(mod, self.modules)

    def refresh(self, file):
        # Replay the same input order, including include guards and macro state.
        self.__init__(self.files, self.top, self.initial_defines, self.include_dirs, self.texts)

    def graph(self, rtl_root, state=None):
        modules = {}
        for name, mod in self.modules.items():
            records = []
            for inst in mod.instances:
                child = self.modules[inst.module]
                records.append({"module": inst.module, "instance": inst.name, "style": "normal", "status": "normal",
                    "start_line": mod.line(inst.start), "end_line": mod.line(inst.end - 1),
                    "instance_start_line": mod.line(inst.start), "instance_end_line": mod.line(inst.end - 1),
                    "module_start_line": child.line(child.start), "module_end_line": child.line(child.end - 1),
                    "port_start_line": child.line(child.io_start), "port_end_line": child.line(child.io_end),
                    "parent_port_start_line": mod.line(mod.io_start), "parent_port_end_line": mod.line(mod.io_end),
                    "file": mod.file, "module_file": child.file, "start_offset": inst.start, "end_offset": inst.end,
                    "connection_start_offset": inst.opening, "connection_end_offset": inst.closing,
                    "ordinal": inst.ordinal, "named_ports": inst.named, "parameter_override": bool(inst.parameters),
                    "connections": {p: b[0] for p, b in inst.bindings.items()} if inst.named else split_expressions(mod.text[inst.opening + 1:inst.closing])})
            modules[name] = {"file": mod.file, "start_line": mod.line(mod.start), "end_line": mod.line(mod.end - 1),
                             "port_start_line": mod.line(mod.io_start), "port_end_line": mod.line(mod.io_end),
                             "ports": [p for p, d in mod.declarations.items() if d.direction], "instantiations": records}
        result = {"schema_version": "1.0", "view": "source_hierarchy", "elaborated": False,
                  "frontend": {"name": "EasyConnect", "version": "1.0"}, "roots": [self.top], "modules": modules,
                  "input_config": {"rtl_folder": str(Path(rtl_root).resolve()), "top": self.top,
                                   "files": self.files, "include_dirs": self.include_dirs, "defines": self.initial_defines},
                  "sources": {p: {"sha256": digest(self.texts[p].encode(self.encodings[p])), "encoding": self.encodings[p]} for p in self.files},
                  "note": "Source references only; for/generate are not expanded. style/status are normal."}
        if state is not None:
            result["_easyconnect"] = state
        return result


def discover(rtl_folder, filelists=None, include_dirs=None, defines=None):
    root = Path(rtl_folder).resolve()
    if not root.is_dir():
        raise EasyConnectError("RTL 文件夹不存在: " + str(root))
    def rtl_files(folder):
        return sorted(str(p.resolve()) for p in folder.rglob("*") if p.is_file() and p.suffix.lower() in (".v", ".sv"))
    files, dirs, macros, visited = [], list(include_dirs or []), {}, set()
    def read_list(path):
        path = Path(path).resolve()
        if path in visited:
            return
        visited.add(path)
        entries = iter(re.findall(r'"[^"\r\n]*"|\S+', mask_comments(read_source(path)[0])))
        for token in entries:
            entry = token.strip('"')
            if entry in ("-f", "-F", "-I", "-y", "-v", "-D"):
                value = next(entries, "").strip('"')
                if not value:
                    raise EasyConnectError("filelist %s 缺少参数: %s" % (path, entry))
                target = (path.parent / value).resolve()
                if entry in ("-f", "-F"):
                    read_list(target)
                elif entry in ("-I", "-y"):
                    dirs.append(str(target))
                    if entry == "-y":
                        files.extend(rtl_files(target))
                elif entry == "-v":
                    files.append(str(target))
                else:
                    key, _, val = value.partition("=")
                    macros[key] = val or "1"
            elif entry.startswith(("+incdir+", "-I")):
                values = entry[8:].split("+") if entry.startswith("+") else [entry[2:]]
                dirs.extend(str((path.parent / p).resolve()) for p in values if p)
            elif entry.startswith("+define+"):
                for value in entry[8:].split("+"):
                    key, _, val = value.partition("=")
                    if key:
                        macros[key] = val or "1"
            elif entry.lower().endswith((".v", ".sv", ".vh", ".svh")):
                files.append(str((path.parent / entry).resolve()))
            elif not entry.startswith(("+", "-")):
                raise EasyConnectError("无法识别 filelist %s 条目: %s" % (path, entry))
    automatic = root / "filelist.f"
    if not automatic.exists() and root.name.lower() == "rtl":
        automatic = root.parent / "filelist.f"
    for path in filelists or ([automatic] if automatic.exists() else []):
        read_list(path)
    files = list(dict.fromkeys(files + rtl_files(root)))
    dirs = list(dict.fromkeys(str(Path(p).resolve()) for p in dirs))
    for file in files:
        for name in re.findall(r'(?m)^[ \t]*\x60include\s+"([^"\r\n]+)"', mask_comments(read_source(file)[0])):
            candidates = [(Path(d) / name).resolve() for d in [Path(file).parent] + dirs]
            found = next((str(p) for p in candidates if p.is_file()), None)
            if found and found not in files:
                files.append(found)
    macros.update(defines or {})
    return files, dirs, macros


def build_graph(rtl_folder, top, output, filelists=None, include_dirs=None, defines=None):
    if protected(output):
        raise EasyConnectError("输出不可写入 test_cases；请指定 test_result 下的路径")
    files, dirs, macros = discover(rtl_folder, filelists, include_dirs, defines)
    project = SourceProject(files, top, macros, dirs)
    state = None
    if Path(output).exists():
        old = json.loads(Path(output).read_text(encoding="utf-8"))
        if "_easyconnect" in old:
            config = old.get("input_config", {})
            if config.get("top") != top or config.get("rtl_folder") != str(Path(rtl_folder).resolve()):
                raise EasyConnectError("该 JSON 管理另一个工程的连接，不能覆盖")
            state = old["_easyconnect"]
    graph = project.graph(rtl_folder, state)
    atomic_write(output, json_bytes(graph))
    return graph
