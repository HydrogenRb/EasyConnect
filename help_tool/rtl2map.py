#!/usr/bin/env python3
"""Extract a lexical module-instantiation graph using only the Python stdlib."""

import argparse
import bisect
import json
import os
from pathlib import Path
import re
import sys


VERSION = "1.0.0"
EXTENSIONS = {".v", ".sv", ".vh", ".svh"}
SKIP_DIRS = {".git", ".svn", ".hg", "obj_dir", "simv", "simv.daidir",
             "csrc", "__pycache__", "node_modules", ".venv", "venv"}
IDENT = re.compile(r"(?:[A-Za-z_][A-Za-z0-9_$]*|\\\S+)\Z")
# Lexical alternatives consume strings/comments together so comment markers in
# strings, and quotes in comments, cannot corrupt the rest of the source.
HIDDEN = re.compile(r'//[^\n]*|/\*[\s\S]*?(?:\*/|\Z)|"(?:\\[\s\S]|[^"\\])*(?:"|\Z)')
DIRECTIVE = re.compile(
    r"(?m)^[ \t]*`(?:define|undef|include|ifdef|ifndef|elsif|else|endif|"
    r"timescale|default_nettype|resetall|celldefine|endcelldefine|"
    r"line|pragma|unconnected_drive|nounconnected_drive|begin_keywords|"
    r"end_keywords)\b[^\n]*(?:\n|$)"
)
TOKEN = re.compile(
    r"\\\S+|`[A-Za-z_][A-Za-z0-9_$]*|[A-Za-z_$][A-Za-z0-9_$]*|"
    r"(?:\d[\d_]*)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+|"
    r"'([01xXzZ])|\d[\d_]*|\+\+|--|<=|>=|==|!=|\+=|-=|::|\S"
)
NON_TYPES = set("""
assign deassign force release defparam parameter localparam genvar
input output inout ref wire tri logic reg bit byte shortint int longint
integer time real shortreal realtime string event void signed unsigned
typedef struct union enum const var automatic static virtual import export
return break continue disable assert assume cover restrict property sequence
function task class clocking modport let bind specify specparam
if else for foreach while repeat forever wait case casex casez begin end
generate endgenerate always always_comb always_ff always_latch initial final
unique unique0 priority endcase endfunction endtask endclass
""".split())


def blank(text):
    return re.sub(r"[^\n]", " ", text)


def preprocess(source):
    """Mask irrelevant text without moving any source offset or newline."""
    cleaned = HIDDEN.sub(lambda m: blank(m.group()), source)
    # A continued directive is a single logical line. Mask all physical lines
    # together, retaining their newlines for diagnostics.
    lines = cleaned.splitlines(keepends=True)
    originals = source.splitlines(keepends=True)
    continuation = False
    for index, line in enumerate(lines):
        if continuation or DIRECTIVE.match(line):
            continuation = originals[index].rstrip("\r\n").rstrip().endswith("\\")
            lines[index] = blank(line)
    return "".join(lines)


class Source:
    def __init__(self, path, relative, source, warnings):
        self.path = path
        self.relative = relative
        self.text = preprocess(source)
        matches = list(TOKEN.finditer(self.text))
        self.tokens = [m.group() for m in matches]
        self.offsets = [m.start() for m in matches]
        self.newlines = [i for i, ch in enumerate(self.text) if ch == "\n"]
        self.warnings = warnings
        self.pairs = {}
        stack = []
        closing = {")": "(", "]": "[", "}": "{"}
        for i, token in enumerate(self.tokens):
            if token in ("(", "[", "{"):
                stack.append(i)
            elif token in closing:
                if stack and self.tokens[stack[-1]] == closing[token]:
                    self.pairs[stack.pop()] = i
                else:
                    self.warn(i, "unbalanced_delimiter", "Unmatched closing delimiter")
        for i in stack:
            self.warn(i, "unbalanced_delimiter", "Unmatched opening delimiter")

    def location(self, index):
        offset = self.offsets[index] if index < len(self.offsets) else len(self.text)
        return {"source_file": self.relative,
                "source_line": bisect.bisect_left(self.newlines, offset) + 1}

    def warn(self, index, code, message, **extra):
        self.warnings.append(dict(self.location(index), code=code,
                                  message=message, **extra))

    def fragment(self, start, end):
        if start >= end:
            return ""
        stop = self.offsets[end - 1] + len(self.tokens[end - 1])
        return " ".join(self.text[self.offsets[start]:stop].split())

    def group_end(self, index, limit):
        end = self.pairs.get(index)
        return end + 1 if end is not None and end < limit else None

    def semicolon(self, index, limit):
        while index < limit:
            if self.tokens[index] == ";":
                return index + 1
            if self.tokens[index] in ("(", "[", "{"):
                end = self.group_end(index, limit)
                if end is None:
                    return limit
                index = end
            else:
                index += 1
        return limit

    def split(self, start, end, delimiter):
        parts = []
        first = start
        while start < end:
            if self.tokens[start] == delimiter:
                parts.append((first, start))
                first = start + 1
            if self.tokens[start] in ("(", "[", "{"):
                start = self.group_end(start, end) or end
            else:
                start += 1
        return parts + [(first, end)]

    def statement_end(self, index, limit):
        """Find control-statement extent; no expressions or AST are evaluated."""
        if index >= limit:
            return limit
        t = self.tokens
        word = t[index]
        if word in ("unique", "unique0", "priority"):
            return self.statement_end(index + 1, limit)
        if word in ("begin", "fork"):
            endings = {"end"} if word == "begin" else {"join", "join_any", "join_none"}
            pos = index + 1
            if pos < limit and t[pos] == ":":
                pos += 2
            while pos < limit and t[pos] not in endings:
                pos = self.statement_end(pos, limit)
            pos = min(pos + 1, limit)
            if pos < limit and t[pos] == ":":
                pos += 2
            return min(pos, limit)
        if word in ("case", "casex", "casez"):
            depth = 1
            pos = index + 1
            while pos < limit:
                if t[pos] in ("case", "casex", "casez"):
                    depth += 1
                elif t[pos] == "endcase":
                    depth -= 1
                    if not depth:
                        return pos + 1
                pos += 1
            return limit
        if word in ("if", "for", "foreach", "while", "repeat", "wait"):
            pos = index + 1
            if pos < limit and t[pos] == "(":
                pos = self.group_end(pos, limit) or limit
            pos = self.statement_end(pos, limit)
            if word == "if" and pos < limit and t[pos] == "else":
                pos = self.statement_end(pos + 1, limit)
            return pos
        if word in ("@", "#"):
            pos = index + 1
            if pos < limit and t[pos] == "(":
                pos = self.group_end(pos, limit) or limit
            else:
                pos += 1
            return self.statement_end(pos, limit)
        if word == "forever":
            return self.statement_end(index + 1, limit)
        return self.semicolon(index, limit)


def scan_files(root):
    files = []
    def on_error(error):
        raise error
    for directory, directories, names in os.walk(str(root), onerror=on_error):
        directories[:] = sorted(d for d in directories
                                if d.lower() not in SKIP_DIRS
                                and not (Path(directory) / d).is_symlink())
        for name in sorted(names):
            path = Path(directory) / name
            if path.suffix.lower() in EXTENSIONS and not path.is_symlink():
                files.append(path)
    return sorted(files, key=lambda p: p.relative_to(root).as_posix())


def collect_modules(source, definitions):
    t = source.tokens
    index = 0
    while index < len(t):
        if t[index] != "module":
            index += 1
            continue
        declaration = index
        index += 1
        if index < len(t) and t[index] in ("automatic", "static"):
            index += 1
        if index >= len(t) or not IDENT.fullmatch(t[index]):
            source.warn(declaration, "invalid_module", "Missing module name")
            continue
        name = t[index]
        header = index + 1
        # Stop at the next module too, allowing recovery from missing endmodule.
        limit = header
        while limit < len(t) and t[limit] not in ("module", "endmodule"):
            limit += 1
        if limit == len(t) or t[limit] != "endmodule":
            source.warn(declaration, "missing_endmodule", "Missing endmodule", module=name)
        pos = header
        # Header imports have their own semicolons, before parameter/port groups.
        while pos < limit and t[pos] == "import":
            pos = source.semicolon(pos, limit)
        body = source.semicolon(pos, limit)
        if body == limit and (limit == 0 or t[limit - 1] != ";"):
            source.warn(declaration, "invalid_header", "Unterminated module header", module=name)
        if name in definitions:
            source.warn(declaration, "duplicate_module", "Duplicate definition; first definition kept",
                        module=name)
        else:
            definitions[name] = (source, header, body, limit)
        index = limit + (limit < len(t) and t[limit] == "endmodule")


def parameters(source, start, end, aliases):
    """Read default RHS text only; never evaluate parameter expressions."""
    for first, last in source.split(start, end, ","):
        for pos in range(first + 1, last):
            if source.tokens[pos] == "=" and IDENT.fullmatch(source.tokens[pos - 1]):
                aliases[source.tokens[pos - 1]] = source.fragment(pos + 1, last)
                break


def resolve_alias(value, aliases):
    visited = set()
    while value in aliases and value not in visited:
        visited.add(value)
        value = aliases[value]
    return value


def integer_literal(value):
    value = value.replace("_", "")
    if re.fullmatch(r"[+-]?\d+", value):
        return int(value)
    return None


def loop_info(source, start, close, aliases, genvars):
    parts = source.split(start, close, ";")
    if len(parts) != 3:
        return None
    initial, condition, step = [source.fragment(a, b) for a, b in parts]
    match = re.fullmatch(r"(genvar\s+)?([A-Za-z_][\w$]*)\s*=\s*(.+)", initial)
    if not match or (not match[1] and match[2] not in genvars):
        return None
    variable = match[2]
    cond = re.fullmatch(re.escape(variable) + r"\s*(<=|>=|<|>)\s*(.+)", condition)
    compact = re.sub(r"\s+", "", step)
    direction = 1 if compact in (variable + "++", "++" + variable,
                                 variable + "+=1", variable + "=" + variable + "+1") else -1
    valid_step = direction == 1 or compact in (variable + "--", "--" + variable,
                                               variable + "-=1", variable + "=" + variable + "-1")
    if not cond or not valid_step or ((cond[1] in ("<", "<=")) != (direction == 1)):
        source.warn(start, "unsupported_loop_count", "Loop count retained as source text")
        return variable, "for (" + source.fragment(start, close) + ")"
    a = resolve_alias(match[3].strip(), aliases)
    b = resolve_alias(cond[2].strip(), aliases)
    av, bv = integer_literal(a), integer_literal(b)
    inclusive = cond[1] in ("<=", ">=")
    if av is not None and bv is not None:
        times = max(0, direction * (bv - av) + int(inclusive))
    elif direction == 1 and av == 0 and not inclusive:
        times = b
    else:
        upper, lower = (b, a) if direction == 1 else (a, b)
        times = "max(0, ({}) - ({}){})".format(upper, lower, " + 1" if inclusive else "")
    return variable, times


def candidate(source, start, limit):
    """Return (end, [(name, token_index), ...]) only for a complete statement."""
    t = source.tokens
    pos = start + 1
    if pos < limit and t[pos] == "#":
        pos += 1
        if pos >= limit or t[pos] != "(":
            return None
        pos = source.group_end(pos, limit)
        if pos is None:
            return None
    instances = []
    while pos < limit and IDENT.fullmatch(t[pos]):
        name_index = pos
        name = t[pos]
        pos += 1
        while pos < limit and t[pos] == "[":
            end = source.group_end(pos, limit)
            if end is None:
                return None
            name += source.fragment(pos, end)
            pos = end
        if pos >= limit or t[pos] != "(":
            return None
        pos = source.group_end(pos, limit)
        if pos is None or pos >= limit:
            return None
        instances.append((name, name_index))
        if t[pos] == ";":
            return pos + 1, instances
        if t[pos] != ",":
            return None
        pos += 1
    return None


def extract_instances(definition, whitelist):
    source, header, body, limit = definition
    t = source.tokens
    aliases = {}
    # Parameter defaults in #(...), never names from the port list.
    for pos in range(header, body - 1):
        if t[pos:pos + 2] == ["#", "("] and pos + 1 in source.pairs:
            parameters(source, pos + 2, source.pairs[pos + 1], aliases)
            break
    result = []

    def walk(start, stop, scope, genvars, loops):
        pos = start
        while pos < stop:
            word = t[pos]
            if word == "begin":
                end = source.statement_end(pos, stop)
                first = pos + 1
                if first < stop and t[first] == ":":
                    first += 2
                # Exclude the end token and optional end label.
                last = end - 1
                if last >= first and t[last] != "end" and end >= 3 and t[end - 2] == ":":
                    last = end - 3
                walk(first, last, dict(scope), set(genvars), loops)
                pos = end
                continue
            if word in ("always", "always_comb", "always_ff", "always_latch", "initial", "final"):
                pos = source.statement_end(pos + 1, stop)
                continue
            if word in ("function", "task", "class", "property", "sequence", "specify", "clocking"):
                closing = {"specify": "endspecify"}.get(word, "end" + word)
                end = pos + 1
                while end < stop and t[end] != closing:
                    end += 1
                pos = min(end + 1, stop)
                continue
            if word in ("parameter", "localparam", "genvar"):
                end = source.semicolon(pos, stop)
                if word == "genvar":
                    genvars.update(x for x in t[pos + 1:end - 1] if IDENT.fullmatch(x))
                else:
                    parameters(source, pos + 1, end - 1, scope)
                pos = end
                continue
            if word == "for" and pos + 1 < stop and t[pos + 1] == "(":
                end_header = source.group_end(pos + 1, stop)
                if end_header is None:
                    pos += 1
                    continue
                end = source.statement_end(end_header, stop)
                info = loop_info(source, pos + 2, end_header - 1, scope, genvars)
                if info is None:
                    source.warn(pos, "unsupported_for", "Not a recognized genvar loop; body skipped")
                else:
                    walk(end_header, end, dict(scope), set(genvars), loops + [info])
                pos = end
                continue
            if word in ("assign", "defparam", "typedef", "import", "export", "bind"):
                pos = source.semicolon(pos, stop)
                continue
            if word in ("(", "[", "{"):
                pos = source.group_end(pos, stop) or (pos + 1)
                continue
            if IDENT.fullmatch(word) and word not in NON_TYPES:
                parsed = candidate(source, pos, stop)
                if parsed:
                    end, instances = parsed
                    for name, name_index in instances:
                        if word not in whitelist:
                            source.warn(pos, "unknown_module", "Type has no module definition; candidate discarded",
                                        module=word, instance=name)
                            continue
                        edge = {"module": word, "instance": name,
                                "status": "for_generated" if loops else "normal"}
                        if loops:
                            edge["instance"] += "".join("[{}]".format(var) for var, _ in loops)
                            counts = [count for _, count in loops]
                            if all(isinstance(count, int) for count in counts):
                                times = 1
                                for count in counts:
                                    times *= count
                            else:
                                times = counts[0] if len(counts) == 1 else " * ".join("({})".format(c) for c in counts)
                            edge["times"] = times
                        edge.update(source.location(pos))
                        result.append(edge)
                    pos = end
                    continue
                if word in whitelist and pos + 1 < stop and (t[pos + 1] == "#" or IDENT.fullmatch(t[pos + 1])):
                    source.warn(pos, "incomplete_instantiation", "Known module candidate is not a complete instantiation",
                                module=word)
            pos += 1

    walk(body, limit, aliases, set(), [])
    return result


def build_map(src, top=None):
    """Return a JSON-serializable map. Raise ValueError for invalid input."""
    root = Path(src).resolve()
    if not root.is_dir():
        raise ValueError("Source directory does not exist: {}".format(src))
    warnings = []
    definitions = {}
    for path in scan_files(root):
        relative = path.relative_to(root).as_posix()
        try:
            raw = path.read_text(encoding="utf-8-sig")
        except UnicodeDecodeError:
            raw = path.read_text(encoding="utf-8-sig", errors="replace")
            warnings.append({"code": "source_encoding", "source_file": relative,
                             "source_line": 1, "message": "Invalid UTF-8 replaced while reading source"})
        collect_modules(Source(path, relative, raw, warnings), definitions)
    if not definitions:
        raise ValueError("No module definitions found in source directory")
    if top is not None and top not in definitions:
        raise ValueError("Top module {!r} was not found".format(top))
    modules = {name: {"instantiations": extract_instances(definitions[name], definitions)}
               for name in sorted(definitions)}
    referenced = {edge["module"] for module in modules.values() for edge in module["instantiations"]}
    roots = [top] if top is not None else sorted(set(modules) - referenced)
    if not roots:
        warnings.append({"code": "no_roots", "message": "No uninstantiated modules; specify --top for cyclic graphs"})
    reachable = set()
    pending = list(roots)
    while pending:
        name = pending.pop()
        if name not in reachable:
            reachable.add(name)
            pending.extend(edge["module"] for edge in modules[name]["instantiations"])
    return {
        "schema_version": "1.0", "view": "", "elaborated": False,
        "frontend": {"name": "EasyMapper", "version": VERSION},
        "input_config": {"source_file": "", "top": top if top is not None else roots},
        "line_reference": "", "roots": roots,
        "modules": {name: modules[name] for name in sorted(reachable)},
        "warnings": sorted(warnings, key=lambda w: (w.get("source_file", ""),
                           w.get("source_line", 0), w["code"], w.get("instance", ""))),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description="EasyMapper: extract RTL module instantiation relationships (Python stdlib only).")
    parser.add_argument("--src", required=True, type=Path, help="RTL source root directory (recursive)")
    parser.add_argument("--top", help="Top module name; default: all uninstantiated modules")
    parser.add_argument("-o", "--output", type=Path, help="Write UTF-8 JSON to this file; default: stdout")
    parser.add_argument("--version", action="version", version="EasyMapper " + VERSION)
    args = parser.parse_args(argv)
    print("EasyMapper " + VERSION, file=sys.stderr)
    try:
        result = build_map(args.src, args.top)
        serialized = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
        if args.output:
            args.output.write_text(serialized, encoding="utf-8")
        else:
            if hasattr(sys.stdout, "reconfigure"):
                sys.stdout.reconfigure(encoding="utf-8")
            sys.stdout.write(serialized)
    except (ValueError, OSError) as error:
        parser.exit(2, "error: {}\n".format(error))
    return 0


if __name__ == "__main__":
    sys.exit(main())
