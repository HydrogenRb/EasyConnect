"""Instance-aware, conservative RTL connection planning (no external packages)."""

import ast
from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
import re

from .rtl import Design, _connection_lhs_names


IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*\Z")


def compact(value):
    return re.sub(r"\s+", "", value or "")


def edits(text, changes):
    """Apply nonoverlapping source edits, preserving all untouched characters."""
    last = len(text) + 1
    for start, end, replacement in sorted(changes, key=lambda x: (x[0], x[1]), reverse=True):
        if end > last or start > end:
            raise ValueError("Overlapping RTL edits; no files were written")
        text = text[:start] + replacement + text[end:]
        last = start
    return text


def dimensions(value):
    value = value or ""
    result = re.findall(r"\[[^\[\]]+\]", value)
    if compact("".join(result)) != compact(value):
        raise ValueError("Only fixed-size packed/unpacked dimensions are supported: " + value)
    for dim in result:
        if any(x in dim for x in (';', '"', '\\', '//', '/*', '\n', '\r')):
            raise ValueError("Invalid array dimension: " + dim)
        if dim[1:-1].strip() in ("", "$", "*"):
            raise ValueError("Dynamic arrays, queues and associative arrays cannot be routed")
    return result


def expression_key(expr):
    """Compare constant arithmetic structurally; never execute RTL expressions."""
    expr = re.sub(r"`([A-Za-z_]\w*)", r"__macro_\1", expr.strip())
    try:
        tree = ast.parse(expr, mode="eval")
        def key(node):
            if isinstance(node, ast.Constant) and isinstance(node.value, int):
                return node.value
            if isinstance(node, ast.Name):
                return ("name", node.id)
            if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
                val = key(node.operand)
                if isinstance(val, int):
                    return -val if isinstance(node.op, ast.USub) else val
                return (type(node.op).__name__, val)
            if isinstance(node, ast.BinOp):
                left, right = key(node.left), key(node.right)
                if isinstance(left, int) and isinstance(right, int):
                    if isinstance(node.op, ast.Add): return left + right
                    if isinstance(node.op, ast.Sub): return left - right
                    if isinstance(node.op, ast.Mult): return left * right
                    if isinstance(node.op, ast.FloorDiv) and right: return left // right
                return (type(node.op).__name__, left, right)
            return ast.dump(node)
        return key(tree.body)
    except (ValueError, SyntaxError, RecursionError):
        return compact(expr)


@dataclass(frozen=True)
class Shape:
    width: str = ""
    unpacked: str = ""
    signed: bool = False

    def __post_init__(self):
        dimensions(self.width)
        dimensions(self.unpacked)

    def key(self):
        def dim_key(value):
            return tuple(tuple(expression_key(e) for e in d[1:-1].split(":"))
                         for d in dimensions(value))
        return dim_key(self.width), dim_key(self.unpacked), bool(self.signed)

    def declaration(self, name, prefix="wire"):
        return " ".join(x for x in (prefix, "signed" if self.signed else "",
                                    self.width, name, self.unpacked) if x)

    def prepend(self, value, kind="unpacked"):
        if kind == "packed":
            if value and self.unpacked:
                raise ValueError("Payload already has unpacked dimensions; use unpacked lane dimensions")
            return Shape(value + self.width, self.unpacked, self.signed)
        return Shape(self.width, value + self.unpacked, self.signed)

    def drop(self, count, kind="unpacked"):
        if kind == "packed" and count and self.unpacked:
            raise ValueError("Packed lane indexing cannot precede unpacked payload dimensions")
        dims = dimensions(self.width if kind == "packed" else self.unpacked)
        if len(dims) < count:
            raise ValueError("Indexed generate requires a {} array at its parent; "
                             "expected at least {} lane dimensions".format(kind, count))
        if kind == "packed":
            return Shape("".join(dims[count:]), self.unpacked, self.signed)
        return Shape(self.width, "".join(dims[count:]), self.signed)


@dataclass
class Node:
    path: str
    module: str
    parent: object = None
    instance: object = None


class Hierarchy:
    def __init__(self, design, top=None, cbb=None):
        self.design = design
        self.cbb = (cbb or {}).get("modules", cbb or {})
        if not isinstance(self.cbb, dict):
            raise ValueError("CBB modules must be a JSON object")
        for name, entry in self.cbb.items():
            if not isinstance(entry, dict) or not isinstance(entry.get("ports"), dict):
                raise ValueError("CBB {} requires a ports object".format(name))
            for port, info in entry["ports"].items():
                if (not isinstance(info, dict) or info.get("direction") not in ("input", "output", "inout")
                        or not isinstance(info.get("width", ""), str)
                        or not isinstance(info.get("unpacked", ""), str)
                        or not isinstance(info.get("signed", False), bool)):
                    raise ValueError("Invalid CBB port metadata for {}.{}".format(name, port))
        referenced = {i.module for m in design.modules.values() for i in m.instances}
        roots = sorted(set(design.modules) - referenced)
        roots = [r for r in roots if not any(n.startswith(r + "__ec_") for n in design.modules)]
        if top is None:
            if len(roots) != 1:
                raise ValueError("Cannot infer a unique top module ({}); specify --top".format(", ".join(roots)))
            top = roots[0]
        if top not in design.modules:
            raise ValueError("Top module not found: " + top)
        self.top = top
        self.nodes = {}
        def walk(node, ancestors):
            if node.path in self.nodes:
                raise ValueError("Ambiguous instance path: " + node.path)
            if len(self.nodes) >= 10000:
                raise ValueError("Hierarchy exceeds 10000 lexical instance paths")
            self.nodes[node.path] = node
            if node.module not in design.modules:
                return
            if node.module in ancestors:
                raise ValueError("Recursive module instantiation: " + node.module)
            for inst in design.modules[node.module].instances:
                relative = ".".join(tuple(inst.scopes) + (inst.name,))
                walk(Node(node.path + "." + relative, inst.module, node, inst), ancestors + (node.module,))
        walk(Node(top, top), ())

    def endpoint(self, value):
        # Selectors cannot contain '.' in the supported constant-expression subset.
        if "." not in value:
            raise ValueError("Use an instance path and signal name, e.g. U_C.fifo_rd")
        path, signal = value.rsplit(".", 1)
        found = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_$]*)(.*)", signal)
        if not found:
            raise ValueError("Unsupported endpoint signal: " + signal)
        dimensions(found[2])
        exact = self.nodes.get(path) or self.nodes.get(self.top + "." + path)
        matches = [exact] if exact else [n for p, n in self.nodes.items() if p.endswith("." + path)]
        if len(matches) != 1:
            choices = ", ".join(n.path for n in matches[:8])
            raise ValueError("{} endpoint instance {!r}{}; use a full symbolic path such as "
                             "top.g[i].U.pin".format("Ambiguous" if matches else "Unknown", path,
                                                       " (" + choices + ")" if choices else ""))
        return matches[0], found[1], found[2]

    def definition(self, node):
        return self.design.modules.get(node.module)


def lineage(node):
    result = []
    while node:
        result.append(node)
        node = node.parent
    return list(reversed(result))


def common_ancestor(first, second):
    common = None
    for a, b in zip(lineage(first), lineage(second)):
        if a.path != b.path: break
        common = a
    return common


def boundary_path(node, ancestor):
    result = []
    while node.path != ancestor.path:
        result.append(node)
        node = node.parent
    return result


def assert_safe(module):
    unsafe = getattr(module, "unsafe", [])
    if unsafe:
        raise ValueError("Cannot safely edit module {}: {}".format(module.name, "; ".join(map(str, unsafe))))


def change_instance_type(module, inst, new_type):
    group = [i for i in module.instances if i.type_start == inst.type_start]
    if len(group) == 1:
        return [(inst.type_start, inst.type_end, new_type)]
    if not all(hasattr(i, "member_start") for i in group):
        raise ValueError("Cannot specialize a comma-separated instance declaration")
    prefix = module.text[inst.type_end:group[0].member_start]
    statements = []
    for member in group:
        typ = new_type if member.name == inst.name else member.module
        statements.append(typ + prefix + module.text[member.member_start:member.member_end] + ";")
    nl = "\r\n" if "\r\n" in module.text else "\n"
    return [(inst.decl_start, inst.decl_end, nl.join(statements))]


def specialize(root, texts, source_path, target_path, top, cbb, name):
    """Copy only definitions shared with other instances, then retarget this path."""
    design = Design(root, texts=texts)
    hierarchy = Hierarchy(design, top, cbb)
    endpoint_nodes = [hierarchy.endpoint(source_path)[0], hierarchy.endpoint(target_path)[0]]
    paths = sorted({n.path for end in endpoint_nodes for n in lineage(end)[1:]},
                   key=lambda p: (p.count("."), p))
    details = []
    for path in paths:
        design = Design(root, texts=texts)
        hierarchy = Hierarchy(design, top, cbb)
        node = hierarchy.nodes[path]
        if node.module not in design.modules:
            continue
        # Count definitions across all roots as well as repeated ancestor occurrences.
        counts = Counter(i.module for m in design.modules.values() for i in m.instances)
        occurrences = sum(n.module == node.module for n in hierarchy.nodes.values())
        if counts[node.module] <= 1 and occurrences <= 1:
            continue
        module, parent = design.modules[node.module], hierarchy.definition(node.parent)
        assert_safe(module)
        assert_safe(parent)
        if getattr(node.instance, "arrays", ""):
            raise ValueError("Instance arrays require a wrapper or explicit generate loop")
        suffix = hashlib.sha256(path.encode("utf-8")).hexdigest()[:8]
        new_name = node.module + "__ec_" + name + "_" + suffix
        if new_name in design.modules:
            raise ValueError("Generated module name collision: " + new_name)
        body = module.text[module.start:module.end]
        clone_edits = [(module.name_start - module.start, module.name_end - module.start, new_name)]
        # A labeled endmodule must match its specialized module name.
        end_label = re.search(r"endmodule\s*:\s*" + re.escape(module.name) + r"\b", body)
        if end_label:
            begin = end_label.end() - len(module.name)
            clone_edits.append((begin, end_label.end(), new_name))
        clone = edits(body, clone_edits)
        nl = "\r\n" if "\r\n" in module.text else "\n"
        addition = nl + "// EasyConnect: instance specialization " + path + nl + clone + nl
        file_edits = defaultdict(list)
        file_edits[module.path].append((module.end, module.end, addition))
        file_edits[parent.path].extend(change_instance_type(parent, node.instance, new_name))
        for file, changes in file_edits.items():
            texts[file] = edits(texts[file], changes)
        details.append({"stage": "specialize", "instance": path, "module": new_name})
    return texts, details


def lift_expression(expression, node, hierarchy, stack=()):
    """Lift module parameters to portable constants/macros, respecting overrides."""
    module = hierarchy.definition(node)
    params = getattr(module, "parameters", {}) if module else {}
    overrides = getattr(node.instance, "parameters", {}) if node.instance else {}
    if getattr(node.instance, "positional_parameters", False):
        raise ValueError("Positional parameter overrides require named overrides before width inference")
    # Mask macros (including function-like macros) and sized number bases.
    pattern = re.compile(r"`[A-Za-z_]\w*|(?:\d[\d_]*)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+|\$[A-Za-z_]\w*|[A-Za-z_][A-Za-z0-9_$]*")
    def replace(match):
        word = match.group()
        if word.startswith(("`", "$")) or "'" in word:
            return word
        if word in ("signed", "unsigned"):
            return word
        marker = (node.path, word)
        if marker in stack:
            raise ValueError("Recursive parameter expression: " + word)
        if word in overrides:
            if not node.parent:
                raise ValueError("Parameter override has no parent scope")
            return "(" + lift_expression(overrides[word], node.parent, hierarchy, stack + (marker,)) + ")"
        if word in params:
            return "(" + lift_expression(params[word], node, hierarchy, stack + (marker,)) + ")"
        raise ValueError("Cannot lift scoped width identifier {!r} from {}; use a macro/constant "
                         "or a resolvable parameter".format(word, node.path))
    return pattern.sub(replace, expression or "")


def signal_info(node, name, hierarchy):
    module = hierarchy.definition(node)
    if module:
        return module.signals.get(name) or module.ports.get(name)
    metadata = hierarchy.cbb.get(node.module, {})
    entry = metadata.get("ports", {}).get(name)
    if not entry:
        raise ValueError("CBB {}.{} requires --cbb port metadata (direction, width, unpacked)".format(node.module, name))
    if not isinstance(entry, dict) or entry.get("direction") not in ("input", "output", "inout"):
        raise ValueError("Invalid CBB port metadata for {}.{}".format(node.module, name))
    return type("CBBPort", (), dict(name=name, width=entry.get("width", ""),
                                    unpacked=entry.get("unpacked", ""),
                                    signed=entry.get("signed", False), kind="wire",
                                    direction=entry["direction"]))()


def shape_of(node, info, selectors, hierarchy):
    if info is None:
        return None
    if getattr(info, "unsupported", None):
        raise ValueError("Cannot route {}.{}: {}".format(node.path, info.name, info.unsupported))
    if getattr(info, "kind", "wire") not in ("wire", "reg", "logic", "bit", "tri", "", None):
        raise ValueError("Unsupported signal type {} for {}.{}".format(info.kind, node.path, info.name))
    packed = dimensions(lift_expression(info.width, node, hierarchy))
    unpacked = dimensions(lift_expression(getattr(info, "unpacked", ""), node, hierarchy))
    signed = bool(info.signed)
    for select in dimensions(selectors):
        if not unpacked:
            signed = False  # Packed bit/part selections are unsigned in SV.
        collection = unpacked if unpacked else packed
        if not collection:
            raise ValueError("Too many indices on {}.{}".format(node.path, info.name))
        collection.pop(0)
        if ":" in select:
            if "+:" in select or "-:" in select:
                width = select[1:-1].split(":", 1)[1]
                collection.insert(0, "[(" + width + ")-1:0]")
            else:
                collection.insert(0, select)
    return Shape("".join(packed), "".join(unpacked), signed)


def loop_shape(node, hierarchy, kind="unpacked"):
    loops = getattr(node.instance, "loops", ())
    if len({loop.var for loop in loops}) != len(loops):
        raise ValueError("Nested generate indices must have different names for indexed routing")
    result = ""
    for loop in loops:
        if loop.step != 1:
            raise ValueError("Indexed generate currently requires an ascending unit-step loop")
        lower = lift_expression(loop.lower, node.parent, hierarchy)
        upper = lift_expression(loop.upper, node.parent, hierarchy)
        if isinstance(expression_key(lower), int) and isinstance(expression_key(upper), int):
            if expression_key(upper) <= expression_key(lower):
                raise ValueError("Cannot route a zero-iteration generate loop")
        if kind == "packed":
            result += "[({})-1:{}]".format(upper, lower)
        else:
            result += "[{}:({})-1]".format(lower, upper)
    return result


def transport(shape, path, mode, hierarchy, source_side=False, kind="unpacked"):
    for node in path:
        if getattr(node.instance, "arrays", ""):
            raise ValueError("Instance arrays require an explicit generate loop for safe routing")
        loops = getattr(node.instance, "loops", ())
        if loops and mode == "shared" and source_side:
            raise ValueError("A generated source cannot drive a shared wire (multiple drivers); use --mode indexed")
        if loops and mode == "indexed":
            shape = shape.prepend(loop_shape(node, hierarchy, kind), kind)
    return shape


def check_external_drivers(module, name, hierarchy):
    """Unknown external ports must not silently become a second net driver."""
    for inst in module.instances:
        if inst.module in hierarchy.design.modules:
            continue
        if inst.positional:
            expressions = module.text[inst.open + 1:inst.close]
            if name in _connection_lhs_names(expressions):
                raise ValueError("Cannot establish CBB driver direction for positional instance " + inst.name)
        else:
            for port, expression in inst.connections.items():
                if name not in _connection_lhs_names(expression):
                    continue
                info = hierarchy.cbb.get(inst.module, {}).get("ports", {}).get(port)
                if info is None:
                    raise ValueError("Destination is connected to unknown CBB port {}.{}; "
                                     "supply --cbb direction metadata".format(inst.name, port))
                if info["direction"] != "input":
                    raise ValueError("Destination already has a driver from CBB {}.{}".format(inst.name, port))
            if inst.wildcard:
                raise ValueError("Cannot establish CBB driver direction for wildcard instance " + inst.name)


class Patch:
    def __init__(self, module):
        assert_safe(module)
        self.module = module
        self.ports = []
        self.body = []
        self.bindings = {}
        self.used = set(module.signals) | set(module.ports) | set(module.parameters)
        self.used.update(inst.name for inst in module.instances if not inst.scopes)
        self.used.update(inst.scopes[0].split("[", 1)[0] for inst in module.instances if inst.scopes)

    def fresh(self, name):
        candidate = name
        i = 2
        while candidate in self.used:
            candidate = name + "_" + str(i)
            i += 1
        self.used.add(candidate)
        return candidate

    def port(self, name, direction, shape, exact=False):
        if exact:
            if name in self.used:
                raise ValueError("Port name collision: " + name)
            self.used.add(name)
        else:
            name = self.fresh(name)
        self.ports.append((name, direction, shape))
        return name

    def wire(self, name, shape, exact=False):
        if exact:
            if name in self.used:
                raise ValueError("Signal name collision: " + name)
            self.used.add(name)
        else:
            name = self.fresh(name)
        self.body.append(shape.declaration(name) + ";")
        return name

    def bind(self, inst, port, expression, replace=False):
        if inst.positional:
            raise ValueError("Positional port connections require named connections: " + inst.name)
        if inst.wildcard:
            raise ValueError("Wildcard .* connections require explicit connections: " + inst.name)
        old = inst.connections.get(port)
        if old and compact(old) != compact(expression) and not replace:
            raise ValueError("{}.{} is already connected to {!r}; use --replace to retarget it".format(inst.name, port, old))
        self.bindings[(inst.open, port)] = (inst, expression)

    def render(self):
        module = self.module
        nl = "\r\n" if "\r\n" in module.text else "\n"
        changes = []
        body = list(self.body)
        if self.ports:
            if module.ansi:
                additions = [shape.declaration(name, direction + " wire") for name, direction, shape in self.ports]
            else:
                additions = [name for name, _, _ in self.ports]
                body = [shape.declaration(name, direction + " wire") + ";" for name, direction, shape in self.ports] + body
            if module.ports_open is None:
                # There is no port list, so a new ANSI list is legal and unambiguous.
                additions = [shape.declaration(name, direction + " wire") for name, direction, shape in self.ports]
                body = list(self.body)
                changes.append((module.header_end - 1, module.header_end - 1,
                                " (" + ("," + nl + "    ").join(additions) + ")"))
            else:
                inside = module.text[module.ports_open + 1:module.ports_close]
                # A comment-only list is empty; consult parser's ports, not raw text.
                separator = "," if module.ports else ""
                changes.append((module.ports_close, module.ports_close,
                                nl + "    " + separator + ("," + nl + "    ").join(additions) + nl))
        declarations = [line for line in body if not line.startswith("assign ")]
        assignments = [line for line in body if line.startswith("assign ")]
        if declarations:
            changes.append((module.body_start, module.body_start,
                            nl + "    // EasyConnect managed wiring" + nl +
                            "".join("    " + line + nl for line in declarations)))
        if assignments:
            changes.append((module.body_end, module.body_end,
                            nl + "    // EasyConnect managed assignments" + nl +
                            "".join("    " + line + nl for line in assignments)))
        additions_by_instance = defaultdict(list)
        for (_, port), (inst, expression) in self.bindings.items():
            if port in inst.connections:
                span = inst.connection_spans.get(port)
                if span is None:
                    raise ValueError("Cannot replace implicit .port shorthand; expand it first")
                changes.append((span[0], span[1], expression))
            else:
                additions_by_instance[inst.open].append((inst, port, expression))
        for group in additions_by_instance.values():
            inst = group[0][0]
            separator = "," if inst.connections else ""
            value = ("," + nl + "        ").join(".{}({})".format(p, expr) for _, p, expr in group)
            changes.append((inst.close, inst.close, nl + "        " + separator + value + nl + "    "))
        return changes


def route(root, texts, spec):
    """Return planned source texts and route explanation; never touch the filesystem."""
    texts = dict(texts)
    name = spec.get("name") or spec.get("id") or "connection"
    if not IDENT.fullmatch(name):
        raise ValueError("Connection name must be a Verilog identifier")
    prefix = "__ec_" + name
    mode = spec.get("mode", "shared")
    if mode not in ("shared", "indexed"):
        raise ValueError("Unknown generate routing mode: " + mode)
    cbb = spec.get("cbb") or {}
    initial = Hierarchy(Design(root, texts=texts), spec.get("top"), cbb)
    if any(inst.module == initial.top for mod in initial.design.modules.values() for inst in mod.instances):
        raise ValueError("Selected --top is itself instantiated elsewhere; select the actual root "
                         "to avoid modifying other instances")
    sn, source, ss = initial.endpoint(spec["source"])
    tn, target, ts = initial.endpoint(spec["target"])
    if sn.path == tn.path and source == target:
        raise ValueError("Source and destination must be different signals")
    canonical_source = sn.path + "." + source + ss
    canonical_target = tn.path + "." + target + ts
    texts, stages = specialize(root, texts, canonical_source, canonical_target, initial.top, cbb, name)
    hierarchy = Hierarchy(Design(root, texts=texts), initial.top, cbb)
    sn, source, ss = hierarchy.endpoint(canonical_source)
    tn, target, ts = hierarchy.endpoint(canonical_target)
    ancestor = common_ancestor(sn, tn)
    up, down = boundary_path(sn, ancestor), boundary_path(tn, ancestor)
    sinfo, tinfo = signal_info(sn, source, hierarchy), signal_info(tn, target, hierarchy)
    if sinfo is None:
        raise ValueError("Source signal does not exist: " + canonical_source)
    ss = lift_expression(ss, sn, hierarchy)
    ts = lift_expression(ts, tn, hierarchy)
    sshape = shape_of(sn, sinfo, ss, hierarchy)
    tshape = shape_of(tn, tinfo, ts, hierarchy)
    if spec.get("width") is not None or spec.get("unpacked") is not None or spec.get("signed"):
        explicit = Shape(spec.get("width") if spec.get("width") is not None else sshape.width,
                         spec.get("unpacked") if spec.get("unpacked") is not None else sshape.unpacked,
                         bool(spec.get("signed")) or sshape.signed)
        if explicit.key() != sshape.key():
            raise ValueError("Explicit shape does not match the source signal (no implicit truncation)")
        sshape = explicit
    lane_kind = spec.get("lane_kind", "auto")
    if lane_kind not in ("auto", "packed", "unpacked"):
        raise ValueError("Unknown lane kind: " + str(lane_kind))
    kinds = ("unpacked", "packed") if lane_kind == "auto" and mode == "indexed" else (
        "unpacked" if lane_kind == "auto" else lane_kind,)
    shape_errors = []
    for kind in kinds:
        try:
            common_shape = transport(sshape, up, mode, hierarchy, source_side=True, kind=kind)
            inferred_target = tshape
            if inferred_target is None:
                if ts:
                    raise ValueError("A new destination port cannot contain an element selector")
                inferred_target = common_shape
                if mode == "indexed":
                    for node in reversed(down):
                        inferred_target = inferred_target.drop(len(getattr(node.instance, "loops", ())), kind)
            target_common = transport(inferred_target, down, mode, hierarchy, kind=kind)
            if common_shape.key() != target_common.key():
                raise ValueError("Source/destination dimensions or signedness differ: {} versus {}".format(
                    common_shape.declaration("signal"), target_common.declaration("signal")))
            tshape, lane_kind = inferred_target, kind
            break
        except ValueError as error:
            shape_errors.append(str(error))
    else:
        raise ValueError("; ".join(dict.fromkeys(shape_errors)))
    tmod = hierarchy.definition(tn)
    smod = hierarchy.definition(sn)
    if tinfo and tinfo.direction == "inout":
        raise ValueError("Bidirectional inout routing is not supported")
    if sinfo.direction == "inout":
        raise ValueError("Bidirectional inout routing is not supported")
    if not smod and sinfo.direction != "output":
        raise ValueError("CBB source must be an output port")
    if not tmod and tinfo.direction != "input":
        raise ValueError("CBB target must be an input port")
    if tinfo and tinfo.direction == "input" and (tn.path == ancestor.path or ts):
        raise ValueError("Cannot internally drive an input port or part of an input port")
    if tmod and (tinfo is None or tinfo.direction != "input") and target in getattr(tmod, "driven", set()):
        raise ValueError("Destination already has a driver: " + canonical_target)
    if tmod and (tinfo is None or tinfo.direction != "input"):
        check_external_drivers(tmod, target, hierarchy)
    patches = {}
    def patch(node):
        mod = hierarchy.definition(node)
        if mod is None:
            raise ValueError("Cannot modify a CBB body: " + node.path)
        if mod.name not in patches:
            patches[mod.name] = Patch(mod)
        return patches[mod.name]
    def edge_suffix(node):
        return "".join("[{}]".format(loop.var) for loop in getattr(node.instance, "loops", ())) if mode == "indexed" else ""
    source_expr = source + ss
    current_shape = sshape
    for index, node in enumerate(up):
        if hierarchy.definition(node):
            p = patch(node)
            port = p.port(prefix + "_out", "output", current_shape)
            p.body.append("assign {} = {};".format(port, source_expr))
        else:
            if index or ss:
                raise ValueError("CBB source selections require an explicit wrapper")
            port = source
        parent_patch = patch(node.parent)
        parent_shape = current_shape
        if mode == "indexed":
            parent_shape = current_shape.prepend(loop_shape(node, hierarchy, lane_kind), lane_kind)
        wire = parent_patch.wire(prefix + "_wire", parent_shape)
        binding = wire + edge_suffix(node)
        existing = node.instance.connections.get(port)
        if hierarchy.definition(node) is None and existing:
            if getattr(node.instance, "loops", ()):
                raise ValueError("Already-connected generated CBB output needs a wrapper to preserve its scope")
            parent_patch.body.append("assign {} = {};".format(binding, existing))
        else:
            parent_patch.bind(node.instance, port, binding)
        stages.append({"stage": "start" if index == 0 else "link", "instance": node.path, "port": port})
        source_expr, current_shape = wire, parent_shape
    stages.append({"stage": "turn", "instance": ancestor.path, "signal": source_expr})
    current_expr = source_expr
    current_shape = common_shape
    for node in reversed(down):
        child_shape = current_shape
        if mode == "indexed":
            child_shape = current_shape.drop(len(getattr(node.instance, "loops", ())), lane_kind)
        is_tip = node.path == tn.path
        if is_tip and tinfo and tinfo.direction == "input":
            port = target
        elif is_tip and tinfo is None:
            port = patch(node).port(target, "input", child_shape, exact=True)
        else:
            port = patch(node).port(prefix + "_in", "input", child_shape)
        patch(node.parent).bind(node.instance, port, current_expr + edge_suffix(node),
                                replace=bool(spec.get("replace")))
        stages.append({"stage": "end" if is_tip else "link", "instance": node.path, "port": port})
        current_expr, current_shape = port, child_shape
    if not down:
        p = patch(tn)
        if tinfo is None:
            p.port(target, "output", tshape, exact=True)
        p.body.append("assign {}{} = {};".format(target, ts, current_expr))
    elif tinfo and tinfo.direction != "input":
        patch(tn).body.append("assign {}{} = {};".format(target, ts, current_expr))
    by_file = defaultdict(list)
    for p in patches.values():
        by_file[p.module.path].extend(p.render())
    for path, changes in by_file.items():
        texts[path] = edits(texts[path], changes)
    # Reparse all generated declarations and connection lists before committing.
    Design(root, texts=texts)
    return texts, {"top": hierarchy.top, "source": canonical_source, "target": canonical_target,
                   "mode": mode, "lane_kind": lane_kind, "stages": stages, "warnings": [],
                   "shape": {"width": common_shape.width, "unpacked": common_shape.unpacked,
                             "signed": common_shape.signed}}


def build_map(root, texts, top=None, cbb=None):
    design = Design(root, texts=texts)
    hierarchy = Hierarchy(design, top, cbb)
    return {"version": "1.0.0", "elaborated": False, "top": hierarchy.top,
            "instances": [{"path": n.path, "module": n.module,
                           "status": "normal" if n.module in design.modules else "cbb",
                           "parent": n.parent.path if n.parent else None,
                           "generated": bool(n.instance and getattr(n.instance, "loops", ())) }
                          for n in hierarchy.nodes.values()],
            "modules": {name: {"file": m.path, "unsafe": getattr(m, "unsafe", []),
                                "ports": {p: {"direction": v.direction, "width": v.width,
                                               "unpacked": getattr(v, "unpacked", ""),
                                               "signed": bool(v.signed)} for p, v in m.ports.items()}}
                        for name, m in design.modules.items()}}
