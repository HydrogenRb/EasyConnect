"""Conservative, offset-preserving Verilog/SystemVerilog source frontend.

This is a lexical frontend, not an elaborator. It retains macro expressions and
all packed/unpacked dimensions. Constructs requiring elaboration are surfaced
in ``Module.unsafe`` so callers can refuse edits rather than guess.
"""

from dataclasses import dataclass, field
from pathlib import Path
import os
import re
from typing import Dict, List, Optional, Set, Tuple

from .diagnostics import step


class RTLException(ValueError):
    pass


IDENT = re.compile(r"(?:[A-Za-z_$][A-Za-z0-9_$]*|\\\S+)\Z")
TOKEN = re.compile(
    r"\\\S+|`[A-Za-z_][A-Za-z0-9_$]*|[A-Za-z_$][A-Za-z0-9_$]*|"
    r"(?:\d[\d_]*)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+|"
    r"'[01xXzZ]|\d[\d_]*|\+\+|--|<=|>=|==|!=|\+=|-=|::|\S"
)
HIDDEN = re.compile(r'//[^\n]*|/\*[\s\S]*?(?:\*/|\Z)|"(?:\\[\s\S]|[^"\\])*(?:"|\Z)')
DIRECTIVE = re.compile(
    r"^[ \t]*`(?:define|undef|include|ifdef|ifndef|elsif|else|endif|"
    r"timescale|default_nettype|resetall|celldefine|endcelldefine|line|"
    r"pragma|unconnected_drive|nounconnected_drive|begin_keywords|end_keywords)\b"
)
DIRECTIONS = {"input", "output", "inout"}
KINDS = {"wire", "tri", "tri0", "tri1", "wand", "wor", "triand", "trior",
         "uwire", "supply0", "supply1", "logic", "reg", "bit"}
UNSUPPORTED_KINDS = {"byte", "shortint", "int", "longint", "integer", "time",
                     "real", "shortreal", "realtime", "string", "event",
                     "struct", "union", "enum", "ref", "interconnect"}
QUALIFIERS = {"signed", "unsigned", "var", "const", "automatic", "static"}
NON_TYPES = DIRECTIONS | KINDS | UNSUPPORTED_KINDS | QUALIFIERS | set("""
assign deassign force release defparam parameter localparam genvar
typedef virtual import export return break continue disable assert assume cover
restrict property sequence function task class clocking modport let bind specify
specparam if else for foreach while repeat forever wait case casex casez begin end
generate endgenerate always always_comb always_ff always_latch initial final
unique unique0 priority endcase endfunction endtask endclass endproperty
endsequence endspecify endclocking fork join join_any join_none
""".split())
EXTENSIONS = {".v", ".sv", ".vh", ".svh"}
SKIP_DIRS = {".git", ".svn", ".hg", ".easyconnect", ".validation", "__pycache__", "node_modules",
             ".venv", "venv", "obj_dir", "simv", "simv.daidir", "csrc"}
TOOL_TEST_ROOT = Path(__file__).resolve().parents[1] / "test"


def _blank(text):
    return re.sub(r"[^\r\n]", " ", text)


def mask(source):
    """Mask comments, strings and compiler directives, preserving every offset."""
    cleaned = HIDDEN.sub(lambda match: _blank(match.group()), source)
    lines = cleaned.splitlines(keepends=True)
    originals = source.splitlines(keepends=True)
    continuation = False
    for index, line in enumerate(lines):
        if continuation or DIRECTIVE.match(line):
            continuation = originals[index].rstrip("\r\n").rstrip().endswith("\\")
            lines[index] = _blank(line)
    return "".join(lines)


@dataclass
class Signal:
    name: str
    direction: Optional[str] = None
    width: str = ""
    signed: bool = False
    kind: str = "wire"
    declaration: Optional[Tuple[int, int]] = None
    unpacked: str = ""
    unsupported: Optional[str] = None


@dataclass
class Loop:
    var: str
    lower: str
    upper: str
    step: int
    label: str


@dataclass
class Instance:
    module: str
    name: str
    start: int
    end: int
    type_start: int
    type_end: int
    open: int
    close: int
    connections: Dict[str, str] = field(default_factory=dict)
    connection_spans: Dict[str, Tuple[int, int]] = field(default_factory=dict)
    scopes: Tuple[str, ...] = ()
    loops: Tuple[Loop, ...] = ()
    arrays: str = ""
    positional: bool = False
    wildcard: bool = False
    parameters: Dict[str, str] = field(default_factory=dict)
    shorthand: Set[str] = field(default_factory=set)
    declaration_count: int = 1
    name_start: int = 0
    name_end: int = 0
    decl_start: int = 0
    decl_end: int = 0
    member_start: int = 0
    member_end: int = 0
    param_text: str = ""
    positional_parameters: bool = False

    @property
    def full_name(self):
        return ".".join(self.scopes + (self.name,))


@dataclass
class Module:
    name: str
    path: str
    text: str
    start: int
    end: int
    name_start: int
    name_end: int
    header_end: int
    ports_open: Optional[int]
    ports_close: Optional[int]
    body_start: int
    body_end: int
    ansi: bool
    ports: Dict[str, Signal] = field(default_factory=dict)
    signals: Dict[str, Signal] = field(default_factory=dict)
    instances: List[Instance] = field(default_factory=list)
    unsafe: List[str] = field(default_factory=list)
    driven: Set[str] = field(default_factory=set)
    parameters: Dict[str, str] = field(default_factory=dict)
    ignored_regions: List[dict] = field(default_factory=list)


class _Source:
    def __init__(self, path, raw, structure_only=False):
        self.structure_only = structure_only
        self.path, self.raw, self.clean = path, raw, mask(raw)
        matches = list(TOKEN.finditer(self.clean))
        self.t = [match.group() for match in matches]
        self.a = [match.start() for match in matches]
        self.b = [match.end() for match in matches]
        self.pairs = {}
        stack = []
        closing = {")": "(", "]": "[", "}": "{"}
        for i, token in enumerate(self.t):
            if token in ("(", "[", "{"):
                stack.append(i)
            elif token in closing:
                if not stack or self.t[stack[-1]] != closing[token]:
                    self.error(i, "unmatched closing delimiter {!r}".format(token))
                opening = stack.pop()
                self.pairs[opening] = i
                self.pairs[i] = opening
        if stack:
            self.error(stack[-1], "unmatched opening delimiter {!r}".format(self.t[stack[-1]]))

    def error(self, i, message):
        offset = self.a[i] if i < len(self.a) else len(self.raw)
        line = self.raw.count("\n", 0, offset) + 1
        line_start = self.raw.rfind("\n", 0, offset) + 1
        column = offset - line_start + 1
        line_end = self.raw.find("\n", offset)
        line_end = len(self.raw) if line_end < 0 else line_end
        context_start = max(line_start, offset - 60)
        prefix = "..." if context_start > line_start else ""
        snippet = prefix + self.raw[context_start:min(line_end, context_start + 160)].expandtabs(4).rstrip("\r")
        caret = len(prefix + self.raw[context_start:offset].expandtabs(4))
        module = " [module {}]".format(self.module) if hasattr(self, "module") else ""
        raise RTLException("{}:{}:{}{}: {}\n  {}\n  {}^".format(
            self.path, line, column, module, message, snippet, " " * caret))

    def frag(self, start, end):
        if start >= end:
            return ""
        return self.raw[self.a[start]:self.b[end - 1]].strip()

    def split(self, start, end, delimiter=","):
        result = []
        first, pos = start, start
        while pos < end:
            if self.t[pos] == delimiter:
                result.append((first, pos))
                first = pos + 1
            if self.t[pos] in ("(", "[", "{"):
                pos = self.pairs[pos] + 1
            else:
                pos += 1
        return result + [(first, end)]

    def semi(self, start, end):
        pos = start
        while pos < end:
            if self.t[pos] == ";":
                return pos + 1
            if self.t[pos] in ("(", "[", "{"):
                pos = self.pairs[pos] + 1
            else:
                pos += 1
        self.error(start, "missing ';'")

    def statement_end(self, start, stop):
        """Return the token after one procedural/generate statement."""
        if start >= stop:
            return stop
        t, pos = self.t, start
        word = t[pos]
        if word in ("unique", "unique0", "priority"):
            return self.statement_end(pos + 1, stop)
        if word in ("begin", "fork", "case", "casex", "casez", "randcase"):
            # Balance only the relevant block keywords. Do not recursively
            # parse each statement inside an opaque procedural/generate block.
            openings, endings = ({"begin"}, {"end"}) if word == "begin" else (
                ({"fork"}, {"join", "join_any", "join_none"}) if word == "fork" else
                ({"case", "casex", "casez", "randcase"}, {"endcase"}))
            depth, pos = 1, pos + 1
            while pos < stop:
                if t[pos] in openings and not (t[pos] == "fork" and t[pos - 1] in ("wait", "disable")):
                    depth += 1
                elif t[pos] in endings:
                    depth -= 1
                    if depth == 0:
                        pos += 1
                        if pos < stop and t[pos] == ":":
                            pos += 2
                        return pos
                pos += 1
            self.error(start, "unmatched {} while locating block boundary; expected {} before module end".format(
                word, "/".join(sorted(endings))))
        if word in ("always", "always_comb", "always_ff", "always_latch", "initial", "final"):
            return self.statement_end(pos + 1, stop)
        if word in ("if", "for", "foreach", "while", "repeat", "wait"):
            pos += 1
            if pos < stop and t[pos] == "(":
                pos = self.pairs[pos] + 1
            pos = self.statement_end(pos, stop)
            if word == "if" and pos < stop and t[pos] == "else":
                pos = self.statement_end(pos + 1, stop)
            return pos
        if word in ("@", "#"):
            pos += 1
            if pos < stop and t[pos] == "(":
                pos = self.pairs[pos] + 1
            elif pos < stop:
                pos += 1
            return self.statement_end(pos, stop)
        if word == "forever":
            return self.statement_end(pos + 1, stop)
        return self.semi(pos, stop)


def _parameters(s, first, last, output):
    for start, end in s.split(first, last):
        pieces = s.split(start, end, "=")
        if len(pieces) != 2:
            continue
        left, right = pieces
        candidates = [s.t[i] for i in range(*left) if IDENT.fullmatch(s.t[i])]
        if candidates:
            output[candidates[-1]] = s.frag(*right)


def _surface(s, first, last):
    """Token indices outside nested expression/dimension groups."""
    pos = first
    while pos < last:
        if s.t[pos] in ("(", "[", "{"):
            pos = s.pairs[pos] + 1
        else:
            yield pos
            pos += 1


def _declarations(s, first, last, default_direction=None):
    """Extract names/shapes without validating an existing declaration list.

    In ``bus_if.host a, b, bus_if.device c`` the declarator names are a/b/c,
    not the repeated type name bus_if. Qualified/interface types remain opaque;
    their declarations are retained verbatim when adding ordinary signal ports.
    """
    direction, width, signed, kind, unsupported = default_direction, "", False, "wire", None
    result = []
    for start, end in s.split(first, last):
        if start == end:
            continue
        left, decl_end = s.split(start, end, "=")[0]
        names = [i for i in _surface(s, left, decl_end) if IDENT.fullmatch(s.t[i])]
        if not names:
            continue
        name_pos = names[-1]
        name = s.t[name_pos]
        if name in DIRECTIONS | KINDS | QUALIFIERS | UNSUPPORTED_KINDS:
            continue
        if name_pos > start:
            prefix = [s.t[i] for i in _surface(s, start, name_pos)]
            directions = [word for word in prefix if word in DIRECTIONS]
            if directions:
                direction = directions[-1]
            width, signed, kind, unsupported = "", False, "wire", None
            for word in prefix:
                if word in KINDS:
                    kind = word
                elif word in ("signed", "unsigned"):
                    signed = word == "signed"
            opaque = [word for word in prefix if word not in DIRECTIONS | KINDS | QUALIFIERS]
            if opaque:
                kind = "".join(opaque)
                unsupported = "signal shape is opaque for type {}".format(kind)
                if not directions:
                    direction = None
            pos, dims = start, []
            while pos < name_pos:
                if s.t[pos] in ("(", "[", "{"):
                    close = s.pairs[pos]
                    if s.t[pos] == "[":
                        dims.append(s.frag(pos, close + 1))
                    pos = close + 1
                else:
                    pos += 1
            width = "".join(dims)
        pos, unpacked = name_pos + 1, []
        while pos < decl_end and s.t[pos] == "[":
            close = s.pairs[pos]
            unpacked.append(s.frag(pos, close + 1))
            pos = close + 1
        result.append(Signal(name=name, direction=direction, width=width, signed=signed,
                             kind=kind, declaration=(s.a[start], s.b[end - 1]),
                             unpacked="".join(unpacked), unsupported=unsupported))
    return result


def _connections(s, opening, closing):
    connections, spans, shorthand = {}, {}, set()
    positional = wildcard = False
    for start, end in s.split(opening + 1, closing):
        if start == end:
            continue
        if s.t[start:end] == [".", "*"]:
            wildcard = True
            continue
        if s.t[start] != "." or start + 1 >= end or not IDENT.fullmatch(s.t[start + 1]):
            positional = True
            continue
        name = s.t[start + 1]
        if start + 2 == end:
            connections[name] = name
            shorthand.add(name)
            spans.pop(name, None)
        elif start + 2 < end and s.t[start + 2] == "(" and s.pairs[start + 2] == end - 1:
            a, b = s.b[start + 2], s.a[end - 1]
            connections[name] = s.raw[a:b].strip()
            spans[name] = (a, b)
            shorthand.discard(name)
        # Other existing forms are opaque, not a reason to reject the module.
    return connections, spans, positional, wildcard, shorthand


def _candidate(s, start, stop, scopes, loops):
    t, pos = s.t, start + 1
    parameters = {}
    positional_parameters = False
    if pos < stop and t[pos] == "#":
        pos += 1
        if pos >= stop or t[pos] != "(":
            return None
        closing = s.pairs[pos]
        if not s.structure_only:
            connections, _, positional, _, _ = _connections(s, pos, closing)
            if positional:
                positional_parameters = True
                parameters = {str(index): s.frag(a, b) for index, (a, b) in enumerate(s.split(pos + 1, closing))}
            else:
                parameters = connections
        pos = closing + 1
    param_end = pos
    instances = []
    while pos < stop and IDENT.fullmatch(t[pos]):
        name, name_pos = t[pos], pos
        pos += 1
        array_start = pos
        while pos < stop and t[pos] == "[":
            pos = s.pairs[pos] + 1
        arrays = s.frag(array_start, pos)
        if pos >= stop or t[pos] != "(":
            return None
        opening, closing = pos, s.pairs[pos]
        if s.structure_only:
            connections, spans, positional, wildcard, shorthand = {}, {}, False, False, set()
        else:
            connections, spans, positional, wildcard, shorthand = _connections(s, opening, closing)
        instances.append(Instance(module=t[start], name=name, start=s.a[name_pos], end=s.b[closing],
                                  type_start=s.a[start], type_end=s.b[start], open=s.a[opening],
                                  close=s.a[closing], connections=connections, connection_spans=spans,
                                  scopes=scopes, loops=loops, arrays=arrays, positional=positional,
                                  wildcard=wildcard, parameters=dict(parameters), shorthand=shorthand,
                                  name_start=s.a[name_pos], name_end=s.b[name_pos],
                                  member_start=s.a[name_pos], member_end=s.b[closing],
                                  param_text=s.raw[s.b[start]:s.a[param_end]],
                                  positional_parameters=positional_parameters))
        pos = closing + 1
        if pos >= stop:
            return None
        if t[pos] == ";":
            for instance in instances:
                instance.start = s.a[start]
                instance.end = s.b[pos]
                instance.decl_start = instance.start
                instance.decl_end = instance.end
                instance.declaration_count = len(instances)
            return pos + 1, instances
        if t[pos] != ",":
            return None
        pos += 1
    return None


def _loop(s, first, last, label):
    parts = s.split(first, last, ";")
    if len(parts) != 3:
        return None
    init, condition, increment = [re.sub(r"\s+", "", s.frag(a, b)) for a, b in parts]
    init = re.sub(r"^(?:genvar|integer|int)", "", init)
    match = re.fullmatch(r"([A-Za-z_$][\w$]*)=(.+)", init)
    if not match:
        return None
    var, lower = match.groups()
    match = re.fullmatch(re.escape(var) + r"(<=|<|>=|>)(.+)", condition)
    if not match:
        return None
    relation, bound = match.groups()
    if increment in (var + "++", "++" + var):
        step = 1
    elif increment in (var + "--", "--" + var):
        step = -1
    else:
        match = re.fullmatch(re.escape(var) + r"(?:([+-])=(\d+)|=" + re.escape(var) + r"([+-])(\d+))", increment)
        if not match:
            return None
        sign, count = (match.group(1), match.group(2)) if match.group(1) else (match.group(3), match.group(4))
        step = int(count) * (1 if sign == "+" else -1)
    if not step or (step > 0 and relation not in ("<", "<=")) or (step < 0 and relation not in (">", ">=")):
        return None
    upper = bound if relation in ("<", ">") else "({}){}1".format(bound, "+" if step > 0 else "-")
    return Loop(var, lower, upper, step, label)


def _driven(s, first, last):
    """Collect structural assignment/initializer LHS names; never inspect processes."""
    driven = set()
    for pos in range(first, last):
        if s.t[pos] != "=":
            continue
        i = pos - 1
        while i >= first and s.t[i] == "]":
            i = s.pairs[i] - 1
        if i >= first and IDENT.fullmatch(s.t[i]):
            driven.add(s.t[i])
        elif i >= first and s.t[i] == "}":
            opening = s.pairs[i]
            for candidate in range(opening + 1, i):
                if IDENT.fullmatch(s.t[candidate]):
                    driven.add(s.t[candidate])
    return driven


def _body(s, module, first, last):
    t = s.t

    def add_signal(signal):
        old = module.signals.get(signal.name)
        if old:
            if signal.direction is None and old.direction:
                signal.direction = old.direction
            if not signal.width and old.width:
                signal.width = old.width
            if not signal.unpacked and old.unpacked:
                signal.unpacked = old.unpacked
            if old.signed:
                signal.signed = True
        module.signals[signal.name] = signal
        if signal.direction or signal.name in module.ports:
            module.ports[signal.name] = signal

    def walk(start, stop, scopes=(), loops=()):
        pos = start
        while pos < stop:
            word = t[pos]
            if word in ("generate", "endgenerate", ";"):
                pos += 1
                continue
            if word == "begin":
                after = s.statement_end(pos, stop)
                a = pos + 1
                nested = scopes
                if a + 1 < stop and t[a] == ":":
                    nested = scopes + (t[a + 1],)
                    a += 2
                b = after - 1
                if t[b] != "end" and b >= 2 and t[b - 1] == ":":
                    b -= 2
                walk(a, b, nested, loops)
                pos = after
                continue
            if word in ("always", "always_comb", "always_ff", "always_latch", "initial", "final"):
                # Procedural bodies are opaque to hierarchy wiring. Locate their
                # extent only; do not inspect assignments or infer their drivers.
                pos = s.statement_end(pos + 1, stop)
                continue
            if word in ("function", "task", "class", "property", "sequence", "specify", "clocking"):
                closing = {"specify": "endspecify"}.get(word, "end" + word)
                end = pos + 1
                while end < stop and t[end] != closing:
                    end += 1
                if end == stop:
                    s.error(pos, "missing {}".format(closing))
                pos = end + 1
                if pos + 1 < stop and t[pos] == ":":
                    pos += 2
                continue
            if word in ("parameter", "localparam", "genvar"):
                after = s.semi(pos, stop)
                if word != "genvar" and not s.structure_only:
                    if scopes:
                        module.unsafe.append("generate-local parameters are not elaborated")
                    else:
                        _parameters(s, pos + 1, after - 1, module.parameters)
                pos = after
                continue
            if word == "for" and pos + 1 < stop and t[pos + 1] == "(":
                header_close = s.pairs[pos + 1]
                body_first = header_close + 1
                after = s.statement_end(body_first, stop)
                label = ""
                if t[body_first:body_first + 2] == ["begin", ":"]:
                    label = t[body_first + 2]
                info = _loop(s, pos + 2, header_close, label)
                if info is None or not label:
                    module.unsafe.append("unsupported or unnamed generate for loop")
                    walk(body_first, after, scopes, loops)
                else:
                    end = after - 1
                    if t[end] != "end" and end >= 2 and t[end - 1] == ":":
                        end -= 2
                    walk(body_first + 3, end, scopes + (label + "[" + info.var + "]",), loops + (info,))
                pos = after
                continue
            if word in ("if", "case", "casex", "casez"):
                after = s.statement_end(pos, stop)
                module.ignored_regions.append({
                    "kind": "conditional_generate", "file": module.path,
                    "line": s.raw.count("\n", 0, s.a[pos]) + 1,
                    "start": s.a[pos], "end": s.b[after - 1],
                    "reason": "Conditional generate is skipped without evaluating or traversing branches",
                })
                pos = after
                continue
            if word in DIRECTIONS or word in KINDS or word in UNSUPPORTED_KINDS:
                after = s.semi(pos, stop)
                if s.structure_only:
                    pos = after
                    continue
                if scopes:
                    module.unsafe.append("generate-local signal declarations are not supported")
                else:
                    for signal in _declarations(s, pos, after - 1):
                        add_signal(signal)
                module.driven.update(_driven(s, pos, after))
                pos = after
                continue
            if word in ("assign", "deassign", "force", "release"):
                after = s.semi(pos, stop)
                if not s.structure_only:
                    module.driven.update(_driven(s, pos, after))
                pos = after
                continue
            if word in ("defparam", "bind"):
                module.unsafe.append("{} requires elaboration".format(word))
                pos = s.semi(pos, stop)
                continue
            if word in ("typedef", "import", "export", "assert", "assume", "cover"):
                pos = s.semi(pos, stop)
                continue
            if IDENT.fullmatch(word) and word not in NON_TYPES:
                parsed = _candidate(s, pos, stop, scopes, loops)
                if parsed:
                    pos, instances = parsed
                    module.instances.extend(instances)
                    continue
                # Typedef-backed declarations are retained with a fail-closed flag.
                if pos + 1 < stop and IDENT.fullmatch(t[pos + 1]):
                    after = s.semi(pos, stop)
                    if not s.structure_only:
                        for signal in _declarations(s, pos, after - 1):
                            add_signal(signal)
                    pos = after
                    continue
            if word in ("(", "[", "{"):
                pos = s.pairs[pos] + 1
            else:
                pos += 1

    walk(first, last)
    module.unsafe = list(dict.fromkeys(module.unsafe))


def _parse_file(path, raw, structure_only=False):
    s = _Source(path, raw, structure_only=structure_only)
    t, modules, pos = s.t, [], 0
    # A conditional around a module also changes the design and must be visible.
    conditional_directives = bool(re.search(r"(?m)^[ \t]*`(?:ifdef|ifndef|elsif|else|endif)\b", HIDDEN.sub(lambda m: _blank(m.group()), raw)))
    while pos < len(t):
        if t[pos] != "module":
            pos += 1
            continue
        start = pos
        pos += 1
        if pos < len(t) and t[pos] in ("automatic", "static"):
            pos += 1
        if pos >= len(t) or not IDENT.fullmatch(t[pos]):
            s.error(pos, "missing module name")
        name_pos, name = pos, t[pos]
        s.module = name
        pos += 1
        parameters = {}
        while pos < len(t) and t[pos] == "import":
            pos = s.semi(pos, len(t))
        if pos < len(t) and t[pos] == "#":
            pos += 1
            if pos >= len(t) or t[pos] != "(":
                s.error(pos, "expected parameter list")
            closing = s.pairs[pos]
            if not structure_only:
                _parameters(s, pos + 1, closing, parameters)
            pos = closing + 1
        port_open = port_close = None
        port_tokens = None
        if pos < len(t) and t[pos] == "(":
            closing = s.pairs[pos]
            port_open, port_close = s.a[pos], s.a[closing]
            port_tokens = (pos + 1, closing)
            pos = closing + 1
        if pos >= len(t) or t[pos] != ";":
            s.error(pos, "expected ';' after module header")
        header_end = s.b[pos]
        body_first = pos + 1
        end = body_first
        while end < len(t) and t[end] not in ("module", "endmodule"):
            end += 1
        if end == len(t) or t[end] != "endmodule":
            s.error(start, "missing endmodule for {}".format(name))
        after = end + 1
        if after + 1 < len(t) and t[after] == ":":
            if t[after + 1] != name:
                s.error(after + 1, "endmodule label differs from module name")
            after += 2
        ansi = bool(port_tokens and (
            any(word in DIRECTIONS for word in t[port_tokens[0]:port_tokens[1]]) or
            any(sum(bool(IDENT.fullmatch(t[i])) for i in _surface(s, a, b)) > 1
                or (a < b and t[a].startswith("`")) for a, b in s.split(*port_tokens))))
        module = Module(name, path, raw, s.a[start], s.b[after - 1], s.a[name_pos], s.b[name_pos],
                        header_end, port_open, port_close, header_end, s.a[end], ansi,
                        parameters=parameters)
        if conditional_directives:
            module.unsafe.append("conditional preprocessing directives require elaboration")
        if port_tokens and not structure_only:
            if ansi:
                for signal in _declarations(s, *port_tokens):
                    module.ports[signal.name] = signal
                    module.signals[signal.name] = signal
            else:
                for a, b in s.split(*port_tokens):
                    if a == b:
                        continue
                    if b - a != 1 or not IDENT.fullmatch(t[a]):
                        continue
                    signal = Signal(t[a])
                    module.ports[signal.name] = signal
                    module.signals[signal.name] = signal
        step("scan module {} structure".format(name), _body, s, module, body_first, end)
        for signal in module.ports.values():
            if signal.direction is None:
                signal.unsupported = signal.unsupported or "port direction is not declared"
        modules.append(module)
        pos = after
    return modules


def _connection_lhs_names(expression):
    """Identifiers driven by an output binding; select indices are only reads."""
    tokens = [match.group() for match in TOKEN.finditer(mask(expression))]
    names, bracket_depth = set(), 0
    for token in tokens:
        if token == "[":
            bracket_depth += 1
        elif token == "]":
            bracket_depth = max(0, bracket_depth - 1)
        elif not bracket_depth and IDENT.fullmatch(token):
            names.add(token)
    return names


def _mark_child_drivers(design):
    for module in design.modules.values():
        for instance in module.instances:
            child = design.modules.get(instance.module)
            if child is None:
                continue
            connections = dict(instance.connections)
            if instance.positional:
                # Positional port order is declaration order in both styles.
                source = _Source(module.path, module.text[instance.open + 1:instance.close])
                fragments = [source.frag(a, b) for a, b in source.split(0, len(source.t))]
                connections.update(zip(child.ports, fragments))
            if instance.wildcard:
                for port_name in child.ports:
                    if port_name not in connections and port_name in module.signals:
                        connections[port_name] = port_name
            for port_name, expression in connections.items():
                port = child.ports.get(port_name)
                if port is not None and port.direction in ("output", "inout"):
                    module.driven.update(_connection_lhs_names(expression))


class Design:
    """Scan source; structure_only skips interface, signal, and driver analysis.

    The default retains the strict information required by the editing engine.
    ``texts`` overlays raw relative-path source strings in either mode.
    """
    def __init__(self, root, texts=None, structure_only=False):
        self.structure_only = structure_only
        self.root = Path(root).resolve()
        if not self.root.is_dir():
            raise RTLException("RTL source root is not a directory: {}".format(root))
        self.texts = {}
        paths = []
        for directory, directories, filenames in os.walk(str(self.root)):
            directories[:] = sorted(name for name in directories if name.lower() not in SKIP_DIRS
                                     and not (Path(directory) / name).is_symlink()
                                     and (Path(directory) / name).resolve() != TOOL_TEST_ROOT)
            for filename in sorted(filenames):
                path = Path(directory) / filename
                if path.suffix.lower() in EXTENSIONS and not path.is_symlink():
                    paths.append(path)
        for path in paths:
            relative = path.relative_to(self.root).as_posix()
            try:
                with path.open("r", encoding="utf-8", newline="") as handle:
                    self.texts[relative] = handle.read()
            except UnicodeDecodeError as exc:
                raise RTLException("{}: source must be UTF-8 ({})".format(relative, exc)) from exc
        for key, value in (texts or {}).items():
            normalized = Path(key).as_posix()
            if Path(key).is_absolute():
                try:
                    normalized = Path(key).resolve().relative_to(self.root).as_posix()
                except ValueError as exc:
                    raise RTLException("overlay path is outside source root: {}".format(key)) from exc
            if ".." in Path(normalized).parts:
                raise RTLException("overlay path traverses outside source root: {}".format(key))
            if value is None:
                self.texts.pop(normalized, None)
            else:
                self.texts[normalized] = value
        self.modules = {}
        for relative, raw in sorted(self.texts.items()):
            for module in step("parse RTL file {}".format(relative), _parse_file, relative, raw,
                               structure_only=structure_only):
                if module.name in self.modules:
                    old = self.modules[module.name]
                    raise RTLException("duplicate module {!r} in {} and {}".format(module.name, old.path, relative))
                self.modules[module.name] = module
        if not self.modules:
            raise RTLException("no module definitions found in {}".format(self.root))
        if not structure_only:
            _mark_child_drivers(self)
        referenced = {instance.module for module in self.modules.values() for instance in module.instances}
        self.roots = sorted(set(self.modules) - referenced)
