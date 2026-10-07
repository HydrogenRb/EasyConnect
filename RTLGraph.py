"""EasyConnect 1.0 RTL source graph, using only the Python standard library.

This is a source graph, not an elaborator: generate bodies and instance array
suffixes are retained once, exactly as written. Offsets always refer to the
original file, including comments and CRLFs.
"""
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from dataclasses import dataclass, field


class EasyConnectError(Exception):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_source(path):
    raw = Path(path).read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig"), "utf-8-sig"
    try:
        return raw.decode("utf-8"), "utf-8"
    except UnicodeDecodeError:
        try:
            return raw.decode("gb18030"), "gb18030"
        except UnicodeDecodeError as exc:
            raise EasyConnectError("无法读取源码编码: %s" % path) from exc


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
    """The checked-in golden cases are never an editing destination."""
    golden = Path(__file__).resolve().parent / "test_cases"
    try:
        Path(path).resolve().relative_to(golden)
        return True
    except ValueError:
        return False


def blank(text):
    return re.sub(r"[^\r\n]", " ", text)


COMMENT_STRING = re.compile(r'//[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"')


def mask_comments(text, strings=False):
    return COMMENT_STRING.sub(
        lambda m: blank(m.group()) if strings or not m.group().startswith('"') else m.group(), text)


@dataclass
class Token:
    value: str
    start: int
    end: int


TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\\[^\s]+|`?[A-Za-z_$][\w$]*|'
                   r"\d+(?:'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+)?|"
                   r"'?[01xXzZ]|<=|>=|==|!=|\+:|-:|::|<<|>>|[^\s]")


def tokenize(text):
    return [Token(m.group(), m.start(), m.end()) for m in TOKEN.finditer(text)]


def pairs(tokens):
    result, stack = {}, []
    for index, token in enumerate(tokens):
        if token.value in ("(", "[", "{"):
            stack.append(index)
        elif token.value in (")", "]", "}"):
            if not stack or tokens[stack[-1]].value != {")": "(", "]": "[", "}": "{"}[token.value]:
                raise EasyConnectError("括号不匹配，源码字符位置 %d" % token.start)
            opening = stack.pop()
            result[opening] = index
    if stack:
        raise EasyConnectError("括号未闭合，源码字符位置 %d" % tokens[stack[-1]].start)
    return result


def split_tokens(tokens, delimiter=","):
    groups, current, depth = [], [], 0
    for token in tokens:
        if token.value == delimiter and depth == 0:
            groups.append(current)
            current = []
        else:
            current.append(token)
            depth += token.value in ("(", "[", "{")
            depth -= token.value in (")", "]", "}")
    if current:
        groups.append(current)
    return groups


def split_expressions(text):
    tokens = tokenize(text)
    return [text[group[0].start:group[-1].end].strip() for group in split_tokens(tokens) if group]


@dataclass
class Declaration:
    name: str
    direction: str
    kind: str
    ranges: tuple
    unpacked: bool = False
    initialized: bool = False


@dataclass
class Instance:
    module: str
    name: str
    start: int
    end: int
    opening: int
    closing: int
    parameters: str = ""
    named: bool = True
    bindings: dict = field(default_factory=dict)
    ordinal: int = 0


@dataclass
class Module:
    name: str
    file: str
    text: str
    masked: str
    start: int
    end: int
    header_end: int
    opening: object
    closing: object
    ansi: bool
    declarations: dict = field(default_factory=dict)
    instances: list = field(default_factory=list)
    parameters: dict = field(default_factory=dict)
    io_start: object = None
    io_end: object = None

    @property
    def newline(self):
        return "\r\n" if "\r\n" in self.text else "\n"

    def line(self, position):
        return self.text.count("\n", 0, position) + 1


IDENTIFIER = re.compile(r"^[A-Za-z_$][\w$]*$")
DIRECTIONS = {"input", "output", "inout"}
TYPES = {"wire", "reg", "logic", "bit", "tri", "uwire", "integer", "int", "signed", "unsigned"}


def parse_declarations(tokens, text, ansi=False):
    result = {}
    direction, kind, ranges = "", "wire", ()
    for group in split_tokens(tokens):
        if not group:
            continue
        fresh = group[0].value in DIRECTIONS or group[0].value in TYPES
        if fresh:
            direction = group[0].value if group[0].value in DIRECTIONS else ""
            kind = next((t.value for t in group if t.value in TYPES and t.value not in ("signed", "unsigned")), "wire")
            ranges = ()
        elif not ansi and not result:
            continue
        index = 0
        local_ranges = []
        while index < len(group) and (group[index].value in DIRECTIONS or group[index].value in TYPES):
            index += 1
        while index < len(group) and group[index].value == "[":
            close = index + 1
            while close < len(group) and group[close].value != "]":
                close += 1
            if close == len(group):
                break
            local_ranges.append(text[group[index].end:group[close].start].strip())
            index = close + 1
        if fresh:
            ranges = tuple(local_ranges)
        if index >= len(group) or not IDENTIFIER.fullmatch(group[index].value):
            continue
        name = group[index].value
        result[name] = Declaration(name, direction, kind, ranges,
                                   index + 1 < len(group) and group[index + 1].value == "[",
                                   any(t.value == "=" for t in group[index + 1:]))
    return result


def parse_file(path, text, processed=None):
    masked = mask_comments(text) if processed is None else mask_comments(processed)
    # No macro expansion is performed. Directive bodies cannot be declarations.
    masked = re.sub(r"(?m)^[ \t]*`(?:include|define|undef|ifdef|ifndef|else|elsif|endif|timescale|default_nettype|resetall|celldefine|endcelldefine)\b[^\r\n]*(?:\\\r?\n[^\r\n]*)*", lambda m: blank(m.group()), masked)
    tokens = tokenize(masked)
    matching = pairs(tokens)
    modules, index = [], 0
    while index < len(tokens):
        if tokens[index].value != "module":
            index += 1
            continue
        start_index = index
        index += 1
        if index < len(tokens) and tokens[index].value in ("automatic", "static"):
            index += 1
        if index >= len(tokens) or not IDENTIFIER.fullmatch(tokens[index].value):
            raise EasyConnectError("不支持的 module 声明: %s" % path)
        name = tokens[index].value
        index += 1
        param_groups = []
        if index < len(tokens) and tokens[index].value == "#":
            index += 1
            if tokens[index].value != "(":
                raise EasyConnectError("无法定位参数列表: " + name)
            close = matching[index]
            param_groups.extend(split_tokens(tokens[index + 1:close]))
            index = close + 1
        opening = closing = None
        header_tokens = []
        if tokens[index].value == "(":
            close = matching[index]
            opening, closing = tokens[index].start, tokens[close].start
            header_tokens = tokens[index + 1:close]
            index = close + 1
        if tokens[index].value != ";":
            raise EasyConnectError("无法定位 module 端口列表: " + name)
        header_end = tokens[index].end
        body_start = index + 1
        ending = body_start
        while ending < len(tokens) and tokens[ending].value != "endmodule":
            ending += 1
        if ending == len(tokens):
            raise EasyConnectError("缺少 endmodule: " + name)
        ansi = any(t.value in DIRECTIONS for t in header_tokens) or not header_tokens
        mod = Module(name, str(Path(path).resolve()), text, masked,
                     tokens[start_index].start, tokens[ending].end, header_end,
                     opening, closing, ansi)
        mod.io_start = opening if opening is not None else mod.start
        mod.io_end = closing if closing is not None else header_end
        if ansi:
            mod.declarations.update(parse_declarations(header_tokens, text, True))
        scan = body_start
        scope = 0
        while scan < ending:
            value = tokens[scan].value
            if value in ("function", "task"):
                scope += 1
            elif value in ("endfunction", "endtask"):
                scope -= 1
            if not scope and value in DIRECTIONS | TYPES:
                finish = scan
                while finish < ending and tokens[finish].value != ";":
                    finish += 1
                decls = parse_declarations(tokens[scan:finish], text)
                if not ansi and value in DIRECTIONS:
                    if mod.io_start == opening: mod.io_start = tokens[scan].start
                    mod.io_end = tokens[finish].end
                for key, decl in decls.items():
                    if key in mod.declarations:
                        previous = mod.declarations[key]
                        # Non-ANSI output followed by a separate reg declaration.
                        if previous.direction and not decl.direction:
                            decl.direction = previous.direction
                    mod.declarations[key] = decl
                scan = finish
            if not scope and value in ("parameter", "localparam"):
                finish = scan
                while finish < ending and tokens[finish].value != ";":
                    finish += 1
                param_groups.extend(split_tokens(tokens[scan + 1:finish]))
            scan += 1
        for group in param_groups:
            equal = next((i for i, t in enumerate(group) if t.value == "="), None)
            if equal is not None and equal > 0 and equal + 1 < len(group):
                mod.parameters[group[equal - 1].value] = text[group[equal + 1].start:group[-1].end]
        # First pass stores candidate statements; known-module filtering follows.
        scan = body_start
        while scan < ending:
            if not IDENTIFIER.fullmatch(tokens[scan].value):
                scan += 1
                continue
            statement_start, type_name = tokens[scan].start, tokens[scan].value
            cursor, parameters = scan + 1, ""
            if cursor < ending and tokens[cursor].value == "#":
                cursor += 1
                if tokens[cursor].value != "(":
                    scan += 1
                    continue
                close = matching[cursor]
                parameters = text[tokens[cursor].end:tokens[close].start]
                cursor = close + 1
            candidates = []
            while cursor + 1 < ending and IDENTIFIER.fullmatch(tokens[cursor].value):
                name_start = cursor
                cursor += 1
                while cursor < ending and tokens[cursor].value == "[":
                    cursor = matching[cursor] + 1
                inst_name = re.sub(r"\s+", "", text[tokens[name_start].start:tokens[cursor - 1].end])
                if tokens[cursor].value != "(":
                    break
                close = matching[cursor]
                groups = split_tokens(tokens[cursor + 1:close])
                named, bindings = True, {}
                for group in groups:
                    if not group:
                        continue
                    if len(group) < 4 or group[0].value != "." or group[2].value != "(" or group[-1].value != ")":
                        named = False
                        continue
                    port = group[1].value
                    if port in bindings:
                        raise EasyConnectError("重复例化端口 %s.%s: %s" % (inst_name, port, path))
                    bindings[port] = (text[group[2].end:group[-1].start].strip(), group[2].end, group[-1].start)
                candidates.append(Instance(type_name, inst_name, statement_start,
                                           tokens[close].end, tokens[cursor].start,
                                           tokens[close].start, parameters, named, bindings))
                cursor = close + 1
                if cursor < ending and tokens[cursor].value == ",":
                    cursor += 1
                    continue
                break
            if candidates and cursor < ending and tokens[cursor].value == ";":
                for inst in candidates:
                    inst.end = tokens[cursor].end
                    mod.instances.append(inst)
                scan = cursor + 1
            else:
                scan += 1
        modules.append(mod)
        index = ending + 1
    return modules


def constant(expression, environment=None, depth=0):
    """Evaluate only a small, bounded integer grammar; never eval RTL text."""
    if depth > 20:
        return None
    environment = environment or {}
    value = expression.strip()
    value = re.sub(r"`([A-Za-z_]\w*)", r"\1", value)
    def literal(match):
        try:
            return str(int(match.group(2).replace("_", ""), {"b": 2, "o": 8, "d": 10, "h": 16}[match.group(1).lower()]))
        except ValueError:
            return match.group()
    value = re.sub(r"\d+'[sS]?([bBoOdDhH])([\da-fA-F_]+)", literal, value)
    try:
        tree = ast.parse(value, mode="eval")
        count = [0]
        def visit(node):
            count[0] += 1
            if count[0] > 100:
                raise ValueError()
            if isinstance(node, ast.Constant) and type(node.value) is int:
                return node.value
            if isinstance(node, ast.Name) and node.id in environment:
                result = constant(str(environment[node.id]), environment, depth + 1)
                if result is None:
                    raise ValueError()
                return result
            if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub, ast.Invert)):
                number = visit(node.operand)
                return number if isinstance(node.op, ast.UAdd) else -number if isinstance(node.op, ast.USub) else ~number
            if isinstance(node, ast.BinOp):
                left, right = visit(node.left), visit(node.right)
                if max(abs(left), abs(right)) > 10**12:
                    raise ValueError()
                if isinstance(node.op, ast.Add): return left + right
                if isinstance(node.op, ast.Sub): return left - right
                if isinstance(node.op, ast.Mult): return left * right
                if isinstance(node.op, (ast.Div, ast.FloorDiv)): return left // right
                if isinstance(node.op, ast.Mod): return left % right
                if isinstance(node.op, ast.LShift) and 0 <= right < 64: return left << right
                if isinstance(node.op, ast.RShift) and 0 <= right < 64: return left >> right
                if isinstance(node.op, ast.BitAnd): return left & right
                if isinstance(node.op, ast.BitOr): return left | right
                if isinstance(node.op, ast.BitXor): return left ^ right
            raise ValueError()
        return visit(tree.body)
    except (SyntaxError, ValueError, TypeError, ZeroDivisionError, RecursionError):
        return None


class SourceProject:
    def __init__(self, files, top, defines=None, include_dirs=None, texts=None):
        self.files = [str(Path(p).resolve()) for p in files]
        self.top = top
        self.initial_defines = dict(defines or {})
        self.include_dirs = [str(Path(p).resolve()) for p in include_dirs or []]
        self.texts, self.encodings, self.modules = {}, {}, {}
        self.file_macros = {}
        self.compilation_views, self.module_macros = {}, {}
        self.macros = dict(self.initial_defines)
        for file in self.files:
            content, encoding = read_source(file)
            self.texts[file] = texts[file] if texts is not None and file in texts else content
            self.encodings[file] = encoding
        for file in self.files:
            self.preprocess(file, [])
        for file in self.files:
            processed = self.compilation_views[file][0]
            for mod in parse_file(file, self.texts[file], processed):
                if mod.name in self.modules:
                    raise EasyConnectError("重复模块 %s: %s 和 %s；请检查 filelist/条件宏" %
                                           (mod.name, self.modules[mod.name].file, file))
                self.modules[mod.name] = mod
                self.module_macros[mod.name] = self.compilation_views[file][1]
        if top not in self.modules:
            raise EasyConnectError("顶层模块不存在: " + top)
        self.filter_instances()

    def resolve_include(self, file, name):
        for directory in [str(Path(file).parent)] + self.include_dirs:
            candidate = str((Path(directory) / name).resolve())
            if candidate in self.texts:
                return candidate
        matches = [p for p in self.files if Path(p).name == name]
        if len(matches) == 1:
            return matches[0]
        raise EasyConnectError("无法唯一定位 include %s (来自 %s)；使用 -I 指定目录" % (name, file))

    def preprocess(self, file, ancestry):
        if file in ancestry:
            raise EasyConnectError("循环 include: " + file)
        self.file_macros.setdefault(file, dict(self.macros))
        text = self.texts[file]
        clean = mask_comments(text)
        result, stack, active, continuation = [], [], True, False
        for original, line in zip(text.splitlines(True), clean.splitlines(True)):
            directive = re.match(r"\s*`(\w+)\b(.*)", line)
            if continuation:
                result.append(blank(original))
                continuation = line.rstrip().endswith("\\")
                continue
            if directive:
                command, body = directive.groups()
                if command in ("ifdef", "ifndef"):
                    symbol = body.strip().split()[0]
                    condition = symbol in self.macros
                    if command == "ifndef": condition = not condition
                    stack.append([active, condition, False])
                    active = active and condition
                elif command in ("else", "elsif"):
                    if not stack or stack[-1][2]:
                        raise EasyConnectError("条件编译指令不匹配: " + file)
                    parent, used, _ = stack[-1]
                    condition = not used and (command == "else" or body.strip().split()[0] in self.macros)
                    stack[-1][1] = used or condition
                    stack[-1][2] = command == "else"
                    active = parent and condition
                elif command == "endif":
                    if not stack:
                        raise EasyConnectError("多余 endif: " + file)
                    active = stack.pop()[0]
                elif active and command == "define":
                    definition = re.match(r"\s*([A-Za-z_]\w*)(.*)", body)
                    if definition:
                        self.macros[definition.group(1)] = definition.group(2).strip() or "1"
                elif active and command == "undef":
                    self.macros.pop(body.strip(), None)
                elif active and command == "include":
                    match = re.search(r'"([^"\r\n]+)"', body)
                    if not match:
                        raise EasyConnectError("不支持宏展开的 include: " + file)
                    self.preprocess(self.resolve_include(file, match.group(1)), ancestry + [file])
                if command in ("include", "define", "undef", "ifdef", "ifndef", "else", "elsif", "endif", "timescale", "default_nettype", "resetall", "celldefine", "endcelldefine"):
                    result.append(blank(original))
                    continuation = line.rstrip().endswith("\\")
                    continue
            result.append(original if active else blank(original))
        if stack:
            raise EasyConnectError("条件编译块未闭合: " + file)
        processed = "".join(result)
        previous = self.compilation_views.get(file)
        has_modules = bool(re.search(r"\bmodule\b", mask_comments(processed, True)))
        if previous is None or has_modules:
            if previous and has_modules and re.search(r"\bmodule\b", mask_comments(previous[0], True)) and previous[0] != processed:
                raise EasyConnectError("同一源码在不同编译宏上下文中包含不同模块定义，1.0 无法可靠编辑: " + file)
            self.compilation_views[file] = (processed, dict(self.macros))
        return processed

    def filter_instances(self):
        for mod in self.modules.values():
            mod.instances = [inst for inst in mod.instances if inst.module in self.modules]
            for ordinal, inst in enumerate(mod.instances):
                inst.ordinal = ordinal

    def refresh(self, file):
        # Edits change module items, never compilation directives. Reparse the
        # affected file using its original compilation-unit macro environment.
        saved = self.macros
        self.macros = dict(self.file_macros[file])
        self.compilation_views.pop(file, None)
        try:
            processed = self.preprocess(file, [])
        finally:
            self.macros = saved
        replacements = parse_file(file, self.texts[file], processed)
        retained = {name: mod for name, mod in self.modules.items() if mod.file != file}
        for mod in replacements:
            if mod.name in retained: raise EasyConnectError("重复模块: " + mod.name)
            retained[mod.name] = mod
            self.module_macros[mod.name] = self.compilation_views[file][1]
        self.modules = retained
        self.filter_instances()

    def graph(self, rtl_root, state=None):
        modules = {}
        for name, mod in self.modules.items():
            io_start = mod.line(mod.io_start)
            io_end = mod.line(mod.io_end)
            records = []
            for inst in mod.instances:
                child = self.modules[inst.module]
                records.append({
                    "module": inst.module, "instance": inst.name, "style": "normal", "status": "normal",
                    "start_line": mod.line(inst.start), "end_line": mod.line(inst.end - 1),
                    "instance_start_line": mod.line(inst.start), "instance_end_line": mod.line(inst.end - 1),
                    "module_start_line": child.line(child.start), "module_end_line": child.line(child.end - 1),
                    "port_start_line": child.line(child.io_start),
                    "port_end_line": child.line(child.io_end),
                    "parent_port_start_line": io_start, "parent_port_end_line": io_end,
                    "file": mod.file, "module_file": child.file,
                    "start_offset": inst.start, "end_offset": inst.end,
                    "connection_start_offset": inst.opening, "connection_end_offset": inst.closing,
                    "ordinal": inst.ordinal, "named_ports": inst.named,
                    "parameter_override": bool(inst.parameters)
                })
            modules[name] = {"file": mod.file, "start_line": mod.line(mod.start),
                             "end_line": mod.line(mod.end - 1), "port_start_line": io_start,
                             "port_end_line": io_end, "instantiations": records}
        result = {
            "schema_version": "1.0", "view": "source_hierarchy", "elaborated": False,
            "frontend": {"name": "EasyConnect", "version": "1.0"},
            "input_config": {"rtl_folder": str(Path(rtl_root).resolve()), "top": self.top,
                             "files": self.files, "include_dirs": self.include_dirs,
                             "defines": self.initial_defines},
            "roots": [self.top], "modules": modules,
            "sources": {p: {"sha256": digest(self.texts[p].encode(self.encodings[p])),
                            "encoding": self.encodings[p]} for p in self.files},
            "note": "Source references only; for/generate are not identified or expanded. style/status are normal."
        }
        if state is not None:
            result["_easyconnect"] = state
        return result


def discover(rtl_folder, filelists=None, include_dirs=None, defines=None):
    root = Path(rtl_folder).resolve()
    if not root.is_dir():
        raise EasyConnectError("RTL 文件夹不存在: " + str(root))
    all_files = sorted(str(p.resolve()) for p in root.rglob("*") if p.is_file() and p.suffix.lower() in (".v", ".sv"))
    ordered, dirs, macros = [], list(include_dirs or []), dict(defines or {})
    visited = set()
    def read_list(path):
        path = Path(path).resolve()
        if str(path) in visited:
            return
        visited.add(str(path))
        if not path.is_file():
            raise EasyConnectError("filelist 不存在: " + str(path))
        text, _ = read_source(path)
        entries = re.findall(r'"[^"\r\n]*"|\S+', mask_comments(text, strings=False))
        index = 0
        while index < len(entries):
            entry = entries[index].strip('"')
            if entry in ("-f", "-F", "-I", "-y", "-v", "-D"):
                index += 1
                if index == len(entries): raise EasyConnectError("filelist 缺少参数: " + entry)
                value = entries[index].strip('"')
                if entry in ("-f", "-F"): read_list(path.parent / value)
                elif entry in ("-I", "-y"):
                    directory = (path.parent / value).resolve()
                    dirs.append(str(directory))
                    if entry == "-y": ordered.extend(str(p.resolve()) for p in directory.rglob("*") if p.suffix.lower() in (".v", ".sv"))
                elif entry == "-D":
                    key, _, val = value.partition("=")
                    macros[key] = val or "1"
                else: ordered.append(str((path.parent / value).resolve()))
            elif entry.startswith("+incdir+"):
                dirs.extend(str((path.parent / value).resolve()) for value in entry[len("+incdir+"):].split("+") if value)
            elif entry.startswith("+define+"):
                for value in entry[len("+define+"):].split("+"):
                    key, _, val = value.partition("=")
                    if key: macros[key] = val or "1"
            elif entry.startswith("-I"):
                dirs.append(str((path.parent / entry[2:]).resolve()))
            elif entry.lower().endswith((".v", ".sv", ".vh", ".svh")):
                ordered.append(str((path.parent / entry).resolve()))
            elif not entry.startswith(("+", "-")):
                raise EasyConnectError("无法识别 filelist 条目: " + entry)
            index += 1
    selected_lists = list(filelists or [])
    if not selected_lists:
        automatic = root / "filelist.f"
        if not automatic.exists() and root.name.lower() == "rtl": automatic = root.parent / "filelist.f"
        if automatic.exists(): selected_lists.append(automatic)
    for path in selected_lists:
        read_list(path)
    files = list(dict.fromkeys(ordered + all_files))
    dirs = list(dict.fromkeys(str(Path(p).resolve()) for p in dirs))
    for file in files:
        if not Path(file).is_file(): raise EasyConnectError("源码文件不存在: " + file)
    index = 0
    while index < len(files):
        file = files[index]
        text, _ = read_source(file)
        for name in re.findall(r'(?m)^\s*`include\s+"([^"\r\n]+)"', mask_comments(text)):
            candidates = [(Path(file).parent / name).resolve()] + [(Path(directory) / name).resolve() for directory in dirs]
            found = next((str(p) for p in candidates if p.is_file()), None)
            if found and found not in files: files.append(found)
        index += 1
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
