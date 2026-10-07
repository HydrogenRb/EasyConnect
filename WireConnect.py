"""Plan, preview and transactionally edit connections in an RTL source graph."""
import copy
import difflib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

from RTLGraph import (EasyConnectError, SourceProject, constant,
                      digest, json_bytes, mask_comments, protected, read_source,
                      pairs, split_expressions, tokenize)


def compact(value):
    return re.sub(r"\s+", "", value)


def widths(dimension=None, width=None, previous=None):
    values = split_expressions(width) if width is not None else list(previous or ("1",))
    if not values or any(not value for value in values):
        raise EasyConnectError("-w 必须是非空的各维大小列表")
    if width is not None and (width.strip().endswith(",") or ",," in compact(width)):
        raise EasyConnectError("-w 中存在空维度")
    if dimension is not None and (dimension < 1 or dimension != len(values)):
        raise EasyConnectError("-d 必须为正数，且与 -w 的维度数一致；多维必须提供各维大小")
    for value in values:
        if re.search(r'[;\r\n\[\]{}"]|//|/\*|\*/|(?<![=!<>])=(?!=)', value):
            raise EasyConnectError("位宽表达式不能包含声明、注释或方括号: " + value)
        pairs(tokenize(value))
        number = constant(value)
        if number is not None and number < 1:
            raise EasyConnectError("每一维的大小必须大于零")
    return tuple(values)


def shape_text(shape):
    if len(shape) == 1 and constant(shape[0]) == 1:
        return ""
    return "".join("[%s -1:0]" % value for value in shape) + " "


def zero(shape):
    if len(shape) == 1 and constant(shape[0]) == 1:
        return "1'b0"
    return "{(%s){1'b0}}" % " * ".join("(%s)" % x for x in shape)


def endpoint(value):
    match = re.fullmatch(r"(.+)\.([A-Za-z_$][\w$]*)(\s*(?:\[[^\[\]\r\n]+\]\s*)*)", value)
    if not match:
        raise EasyConnectError("端点格式应为 MODULE.signal 或 MODULE.signal[i]: " + value)
    owner, signal, suffix = match.groups()
    if re.search(r"[;\r\n]|//|/\*", suffix):
        raise EasyConnectError("下标包含不支持的内容")
    if any(not item.strip() for item in re.findall(r"\[([^\]]*)\]", suffix)):
        raise EasyConnectError("下标不能为空")
    return owner, signal, compact(suffix)


def selected_shape(bus, suffix, environment):
    selectors = re.findall(r"\[([^\]]+)\]", suffix)
    if len(selectors) > len(bus):
        raise EasyConnectError("下标数量超过 packed 维数")
    result = []
    for size, selection in zip(bus, selectors):
        part = re.fullmatch(r"(.+?)(\+:|-:)(.+)", selection)
        if part:
            extent = part.group(3).strip()
            number = constant(extent, environment)
            if number is not None and number < 1:
                raise EasyConnectError("part-select 位宽必须为正数")
            result.append(extent)
        elif ":" in selection:
            left, right = selection.split(":", 1)
            a, b = constant(left, environment), constant(right, environment)
            if a is None or b is None:
                raise EasyConnectError("无法确定新建端口的 part-select 形状: [" + selection + "]")
            result.append(str(abs(a - b) + 1))
        # A bit-select consumes one packed dimension. Its index is not evaluated.
    result.extend(bus[len(selectors):])
    return tuple(result) or ("1",)


def check_shape(mod, declaration, required, macros, parameters=None):
    if declaration.unpacked:
        raise EasyConnectError("不支持 unpacked 数组路由: %s.%s" % (mod.name, declaration.name))
    if declaration.kind not in ("wire", "reg", "logic", "bit", "tri", "uwire"):
        raise EasyConnectError("不兼容的信号类型: %s.%s (%s)" % (mod.name, declaration.name, declaration.kind))
    environment = dict(macros, **mod.parameters)
    if parameters: environment.update(parameters)
    actual = []
    for value in declaration.ranges:
        if ":" not in value:
            raise EasyConnectError("无法解析 packed 维度: " + value)
        left, right = value.split(":", 1)
        a, b = constant(left, environment), constant(right, environment)
        actual.append(abs(a - b) + 1 if a is not None and b is not None else None)
    expected = [constant(value, environment) for value in required]
    actual = actual or [1]
    if len(actual) != len(expected) or any(a is not None and b is not None and a != b for a, b in zip(actual, expected)):
        raise EasyConnectError("形状冲突: %s.%s，已有 %s，请求 %s" %
                               (mod.name, declaration.name, declaration.ranges or "标量", required))


def hierarchy_paths(project, limit=20000):
    result, count = {}, [0]
    def visit(module, nodes, ancestry):
        if module in ancestry:
            raise EasyConnectError("层级含递归模块引用，无法生成连接路径: " + module)
        count[0] += 1
        if count[0] > limit or len(nodes) > 200:
            raise EasyConnectError("源码引用路径过多或过深，不能安全选择路径")
        result.setdefault(module, []).append(nodes)
        instances = project.modules[module].instances
        counts = {}
        for inst in instances: counts[inst.name] = counts.get(inst.name, 0) + 1
        for inst in instances:
            display = inst.name + ("@%d" % (inst.ordinal + 1) if counts[inst.name] > 1 else "")
            visit(inst.module, nodes + [(inst.module, inst.ordinal, inst.name, display)], ancestry + [module])
    visit(project.top, [(project.top, None, project.top, project.top)], [])
    return result


def path_name(nodes):
    return "/".join(node[3] if len(node) > 3 else node[2] for node in nodes)


def parameter_environments(project, nodes):
    """Resolve explicit instance parameter values in their parent's scope."""
    result = []
    for depth, node in enumerate(nodes):
        mod = project.modules[node[0]]
        environment = dict(project.module_macros.get(mod.name, project.macros), **mod.parameters)
        if depth:
            parent = project.modules[nodes[depth - 1][0]]
            inst = parent.instances[node[1]]
            overrides = split_expressions(inst.parameters)
            for index, entry in enumerate(overrides):
                named = re.fullmatch(r"\s*\.([A-Za-z_$][\w$]*)\s*\(([\s\S]*)\)\s*", entry)
                if named:
                    key, value = named.groups()
                elif index < len(mod.parameters):
                    key, value = list(mod.parameters)[index], entry
                else:
                    continue
                known = constant(value, result[depth - 1])
                environment[key] = str(known) if known is not None else "__EASYCONNECT_UNKNOWN__"
            # defparam changes are not elaborated; suppress misleading default
            # constant checks for any explicitly overridden parameter.
            for match in re.finditer(r"\bdefparam\s+" + re.escape(inst.name) + r"\.([A-Za-z_$][\w$]*)\s*=", parent.masked):
                environment[match.group(1)] = "__EASYCONNECT_UNKNOWN__"
        result.append(environment)
    return result


def choose_path(project, paths, owner, selector, label):
    candidates = paths.get(owner, [])
    if not candidates:
        candidates = [nodes for group in paths.values() for nodes in group
                      if nodes[-1][2] == owner or path_name(nodes) == owner.replace("\\", "/")]
    if not candidates:
        raise EasyConnectError("%s端点不在顶层的源码层级中: %s" % (label, owner))
    if selector:
        if selector.isdigit() and 1 <= int(selector) <= len(candidates):
            candidates = [candidates[int(selector) - 1]]
        else:
            candidates = [nodes for nodes in candidates if path_name(nodes) == selector.replace("\\", "/") or nodes[-1][2] == selector]
        if not candidates:
            raise EasyConnectError("%s实例选择无匹配: %s" % (label, selector))
    if len(candidates) == 1:
        return candidates[0]
    lines = []
    for index, nodes in enumerate(candidates, 1):
        parent = project.modules[nodes[-2][0]]
        inst = parent.instances[nodes[-1][1]]
        lines.append("  %d. %s | 父模块 %s | %s:%d" %
                     (index, path_name(nodes), parent.name, parent.file, parent.line(inst.start)))
    description = "%s模块有多个例化位置：\n%s" % (label, "\n".join(lines))
    if not sys.stdin.isatty():
        raise EasyConnectError(description + "\n请用 --%s-instance 指定编号或完整路径" % ("src" if label == "源" else "dst"))
    print(description)
    try:
        answer = input("选择%s实例编号: " % label).strip()
    except (EOFError, KeyboardInterrupt) as exc:
        raise EasyConnectError("实例选择已取消") from exc
    if not answer.isdigit() or not 1 <= int(answer) <= len(candidates):
        raise EasyConnectError("无效的实例编号")
    return candidates[int(answer) - 1]


def text_opcodes(before, after):
    """Match whole lines first; refine only the small edited line groups.

    Character matching on an entire aligned RTL file is quadratic in repeated
    whitespace. The line pass keeps reversibility without that performance trap.
    """
    a, b = before.splitlines(True), after.splitlines(True)
    ao, bo = [0], [0]
    for line in a: ao.append(ao[-1] + len(line))
    for line in b: bo.append(bo[-1] + len(line))
    result = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag == "equal":
            refined = [(tag, ao[i1], ao[i2], bo[j1], bo[j2])]
        else:
            left, right = before[ao[i1]:ao[i2]], after[bo[j1]:bo[j2]]
            refined = [(t, ao[i1] + x1, ao[i1] + x2, bo[j1] + y1, bo[j1] + y2)
                       for t, x1, x2, y1, y2 in difflib.SequenceMatcher(None, left, right,
                               autojunk=len(left) * len(right) > 4000000).get_opcodes()]
        for item in refined:
            if result and item[0] == "equal" and result[-1][0] == "equal" and result[-1][2] == item[1] and result[-1][4] == item[3]:
                previous = result.pop()
                result.append(("equal", previous[1], item[2], previous[3], item[4]))
            else:
                result.append(item)
    return result


def edits_between(before, after):
    return [(i1, i2, j1, j2) for tag, i1, i2, j1, j2 in text_opcodes(before, after) if tag != "equal"]


def unrender(file, record, current):
    """Reverse generated changes while carrying unrelated manual edits forward."""
    before, after = record["before"], record["after"]
    changes = edits_between(before, after)
    human = edits_between(after, current)
    for i1, i2, j1, j2 in changes:
        for a1, a2, b1, b2 in human:
            overlapping = (a1 < j2 and a2 > j1) if a1 != a2 else j1 < a1 < j2
            if j1 == j2:
                overlapping = a1 < j1 < a2
            if overlapping:
                difference = "".join(difflib.unified_diff(after.splitlines(True), current.splitlines(True),
                                                         fromfile="工具记录", tofile="当前源码", n=2))
                raise EasyConnectError("受管片段被人工修改，拒绝覆盖: %s\n%s" % (file, difference))
    blocks = [(i1, j1, i2 - i1) for tag, i1, i2, j1, j2 in text_opcodes(after, current) if tag == "equal"]
    def locate(start, end):
        for a, b, size in blocks:
            if a <= start and end <= a + size:
                return b + start - a, b + end - a
        raise EasyConnectError("无法可靠定位受管片段，拒绝覆盖: " + file)
    replacements = []
    for i1, i2, j1, j2 in changes:
        left, right = locate(j1, j2)
        if current[left:right] != after[j1:j2]:
            raise EasyConnectError("受管片段校验失败: " + file)
        replacements.append((left, right, before[i1:i2]))
    for left, right, value in sorted(replacements, reverse=True):
        current = current[:left] + value + current[right:]
    return current


class Planner:
    def __init__(self, project):
        self.project = project
        self.ports, self.bindings, self.resources = {}, {}, {}
        self.exports, self.net_owners, self.targets = {}, {}, {}
        self.new_sources, self.notes, self.routes = [], [], []
        self.generated_signals = []
        self.connection = None
        self.environments = {}
        self.parents = {}
        for mod in project.modules.values():
            for inst in mod.instances:
                self.parents.setdefault(inst.module, set()).add(mod.name)

    def resource(self, kind, module, name, generated=False):
        key = "%s|%s|%s" % (kind, module, name)
        entry = self.resources.setdefault(key, {"kind": kind, "module": module, "name": name,
                                                "generated": generated, "owners": []})
        if self.connection["id"] not in entry["owners"]:
            entry["owners"].append(self.connection["id"])

    def modify(self, module, edits):
        mod = self.project.modules[module]
        content = self.project.texts[mod.file]
        for start, end, value in sorted(edits, reverse=True):
            content = content[:start] + value + content[end:]
        self.project.texts[mod.file] = content
        self.project.refresh(mod.file)

    def comment(self):
        comment = self.connection.get("comment", "")
        return " // " + comment if comment else ""

    def append_list(self, module, opening, closing, entry, indentation):
        mod = self.project.modules[module]
        tokens = tokenize(mask_comments(mod.text[opening + 1:closing]))
        insertion = mod.newline + indentation + entry + self.comment() + mod.newline
        edits = [(closing, closing, insertion)]
        if tokens:
            if tokens[-1].value == ",":
                raise EasyConnectError("端口列表含尾随逗号，无法安全修改: " + module)
            position = opening + 1 + tokens[-1].end
            if position == closing:
                edits = [(closing, closing, "," + insertion)]
            else:
                edits.append((position, position, ","))
        self.modify(module, edits)

    def shape_check(self, mod, declaration, shape):
        return check_shape(mod, declaration, shape, self.project.module_macros.get(mod.name, self.project.macros),
                           self.environments.get(mod.name))

    def check_symbol(self, mod, signal):
        if signal in mod.parameters or any(inst.name == signal for inst in mod.instances) or re.search(
                r"\bgenvar\s+" + re.escape(signal) + r"\b", mod.masked):
            raise EasyConnectError("信号名与已有参数、genvar 或例化名冲突: %s.%s" % (mod.name, signal))

    def declare(self, module, name, shape, direction="", kind="wire", ranges=None):
        mod = self.project.modules[module]
        packed = ("".join("[" + value + "]" for value in ranges) + " ") if ranges else shape_text(shape)
        content = (direction + " " if direction else "") + kind + " " + packed + name
        self.generated_signals.append({"module": module, "signal": name, "shape": list(shape), "ranges": list(ranges or [])})
        if direction:
            if mod.opening is None:
                # module M; -> module M (output wire sig);
                insertion = " (" + mod.newline + "    " + content + self.comment() + mod.newline + ")"
                self.modify(module, [(mod.header_end - 1, mod.header_end - 1, insertion)])
            elif mod.ansi:
                self.append_list(module, mod.opening, mod.closing, content, "    ")
            else:
                self.append_list(module, mod.opening, mod.closing, name, "    ")
                mod = self.project.modules[module]
                self.modify(module, [(mod.header_end, mod.header_end,
                                      mod.newline + "    " + content + ";" + self.comment() + mod.newline)])
            self.ports[(module, name)] = (direction, shape)
            self.resource("port", module, name, True)
        else:
            self.modify(module, [(mod.header_end, mod.header_end,
                                  mod.newline + "    " + content + ";" + self.comment() + mod.newline)])
            self.resource("wire", module, name, True)
        return name

    def driven(self, module, signal):
        mod = self.project.modules[module]
        body = mod.masked[mod.header_end:mod.end]
        if re.search(r"\b" + re.escape(signal) + r"\b\s*(?:\[[^\]]*\]\s*)*(?:<=|=(?!=))", body):
            return True
        for inst in mod.instances:
            child = self.project.modules[inst.module]
            for port, binding in inst.bindings.items():
                declaration = child.declarations.get(port)
                if declaration and declaration.direction in ("output", "inout"):
                    if re.search(r"\b" + re.escape(signal) + r"\b", mask_comments(binding[0], True)):
                        return True
        return False

    def port(self, module, signal, shape, direction, role="relay", permit_driver=False):
        mod = self.project.modules[module]
        self.check_symbol(mod, signal)
        declaration = mod.declarations.get(signal)
        if declaration:
            self.shape_check(mod, declaration, shape)
            if declaration.direction == direction:
                if direction == "input" and self.driven(module, signal):
                    raise EasyConnectError("输入信号已有驱动: %s.%s" % (module, signal))
                if direction == "output" and role == "relay" and not permit_driver and self.driven(module, signal):
                    raise EasyConnectError("中间信号已有驱动: %s.%s" % (module, signal))
                self.resource("port", module, signal, (module, signal) in self.ports)
                return signal
            # Keep existing internal declarations and business logic verbatim.
            if direction == "input" and self.driven(module, signal):
                raise EasyConnectError("目标已有可识别的驱动: %s.%s" % (module, signal))
            key = (module, signal, direction, tuple(shape))
            if key in self.exports:
                auxiliary = self.exports[key]
                self.resource("port", module, auxiliary, True)
                self.resource("assign", module, auxiliary, True)
                return auxiliary
            auxiliary = "ec_%s_%s_%s" % (self.connection["id"], signal, "out" if direction == "output" else "in")
            if auxiliary in mod.declarations:
                raise EasyConnectError("辅助端口名已存在: %s.%s" % (module, auxiliary))
            self.declare(module, auxiliary, shape, direction, ranges=declaration.ranges)
            left, right = (auxiliary, signal) if direction == "output" else (signal, auxiliary)
            self.assignment(module, left, right)
            self.exports[key] = auxiliary
            self.notes.append("%s.%s 保留原声明，通过辅助端口 %s 接入" % (module, signal, auxiliary))
            return auxiliary
        self.declare(module, signal, shape, direction)
        if role == "source":
            self.new_sources.append({"module": module, "signal": signal, "shape": list(shape)})
            self.notes.append("%s.%s 本次新建、待用户驱动" % (module, signal))
        return signal

    def local(self, module, signal, shape, source=False, target=False):
        mod = self.project.modules[module]
        self.check_symbol(mod, signal)
        declaration = mod.declarations.get(signal)
        if declaration:
            self.shape_check(mod, declaration, shape)
            if target and (declaration.direction in ("input", "inout") or self.driven(module, signal)):
                raise EasyConnectError("局部目标不能覆盖已有输入或驱动: %s.%s" % (module, signal))
            self.resource("wire", module, signal, False)
            return signal
        self.declare(module, signal, shape)
        if source:
            self.new_sources.append({"module": module, "signal": signal, "shape": list(shape)})
            self.notes.append("%s.%s 本次新建、待用户驱动" % (module, signal))
        return signal

    def assignment(self, module, left, right):
        mod = self.project.modules[module]
        wanted = "assign %s = %s;" % (left, right)
        if compact(wanted) in compact(mask_comments(mod.text)):
            self.resource("assign", module, left, False)
            return
        if self.driven(module, left):
            raise EasyConnectError("信号已有驱动，不能添加赋值: %s.%s" % (module, left))
        position = mod.end - len("endmodule")
        self.modify(module, [(position, position,
                              mod.newline + "    " + wanted + self.comment() + mod.newline)])
        self.resource("assign", module, left, True)

    def get_instance(self, parent, node):
        mod = self.project.modules[parent]
        if node[1] is None or node[1] >= len(mod.instances):
            raise EasyConnectError("例化位置已失效: " + str(node))
        inst = mod.instances[node[1]]
        if inst.module != node[0] or inst.name != node[2]:
            raise EasyConnectError("例化位置发生变化，请重新建图: " + str(node))
        return inst

    def bind(self, parent, node, port, expression):
        inst = self.get_instance(parent, node)
        if not inst.named:
            raise EasyConnectError("仅支持编辑显式命名端口连接: %s.%s" % (parent, inst.name))
        key = (parent, inst.ordinal, port)
        if key in self.bindings and compact(self.bindings[key]) != compact(expression):
            raise EasyConnectError("共用例化端口连接冲突: %s.%s.%s" % (parent, inst.name, port))
        existing = inst.bindings.get(port)
        if existing:
            if compact(existing[0]) != compact(expression):
                if existing[0]:
                    raise EasyConnectError("已有端口绑定不能覆盖: %s.%s.%s (%s -> %s)" %
                                           (parent, inst.name, port, existing[0], expression))
                self.modify(parent, [(existing[1], existing[2], expression)])
        else:
            self.append_list(parent, inst.opening, inst.closing, ".%s(%s)" % (port, expression), "        ")
        self.bindings[key] = expression
        self.resource("binding", parent, "%d.%s" % (inst.ordinal, port), existing is None)

    def turn_wire(self, module, signal, shape, source_key):
        name = "w_" + signal
        mod = self.project.modules[module]
        if name in mod.declarations and self.net_owners.get((module, name)) != source_key:
            name += "_" + self.connection["id"]
        if name in mod.declarations:
            self.shape_check(mod, mod.declarations[name], shape)
        else:
            self.declare(module, name, shape)
        self.net_owners[(module, name)] = source_key
        self.resource("wire", module, name, True)
        return name

    def existing_up_net(self, parent, node, port, shape, suffix):
        inst = self.get_instance(parent, node)
        binding = inst.bindings.get(port)
        if not binding or not binding[0]:
            return None
        match = re.fullmatch(r"([A-Za-z_$][\w$]*)(\s*(?:\[[^\]]+\]\s*)*)", binding[0])
        if not match or compact(match.group(2)) != suffix:
            raise EasyConnectError("源端已有绑定无法安全复用: %s.%s.%s(%s)" % (parent, inst.name, port, binding[0]))
        name = match.group(1)
        declaration = self.project.modules[parent].declarations.get(name)
        if declaration is None:
            raise EasyConnectError("源端绑定未声明，无法核验形状: %s.%s" % (parent, name))
        self.shape_check(self.project.modules[parent], declaration, shape)
        return name

    def plan(self, connection):
        self.connection = connection
        paths = hierarchy_paths(self.project)
        source = choose_path(self.project, paths, endpoint(connection["src"])[0], connection.get("src_instance"), "源")
        target = choose_path(self.project, paths, endpoint(connection["dst"])[0], connection.get("dst_instance"), "目标")
        connection["src_instance"], connection["dst_instance"] = path_name(source), path_name(target)
        _, src_signal, src_suffix = endpoint(connection["src"])
        _, dst_signal, dst_suffix = endpoint(connection["dst"])
        if source == target and src_signal == dst_signal and src_suffix == dst_suffix:
            return False
        common = 0
        while common + 1 < min(len(source), len(target)) and source[common + 1] == target[common + 1]:
            common += 1
        for node in source[common:] + target[common:]:
            if len(self.parents.get(node[0], set())) > 1:
                raise EasyConnectError("1.0 不支持同一 module 被不同父模块类型例化的路径: %s (%s)" %
                                       (node[0], ", ".join(sorted(self.parents[node[0]]))))
        shape = tuple(connection["widths"])
        source_env = parameter_environments(self.project, source)
        target_env = parameter_environments(self.project, target)
        self.environments = {node[0]: env for node, env in zip(source, source_env)}
        src_shape = selected_shape(shape, src_suffix, source_env[-2] if len(source) > 1 else source_env[-1])
        dst_shape = selected_shape(shape, dst_suffix, target_env[-2] if len(target) > 1 else target_env[-1])
        source_key = (path_name(source), src_signal, src_suffix)
        target_key = (path_name(target), dst_signal, dst_suffix)
        if target_key in self.targets and self.targets[target_key] != source_key:
            raise EasyConnectError("同一目标不能被不同源重复占用: " + connection["dst"])
        self.targets[target_key] = source_key
        lca = source[common][0]
        self.routes.append("%s: %s.%s → %s.%s；转向/公共作用域 %s" %
                           (connection["id"], path_name(source), src_signal + src_suffix,
                            path_name(target), dst_signal + dst_suffix, lca))
        self.notes.append("定义级影响: 修改路径上的共用 module 会作用于该 module 的所有实例；不统计循环展开数量")
        if source == target:
            if src_suffix or dst_suffix:
                raise EasyConnectError("同作用域局部连接没有父层端口绑定，不能使用父层下标")
            src_net = self.local(lca, src_signal, shape, source=True)
            dst_net = self.local(lca, dst_signal, shape, target=True)
            self.assignment(lca, dst_net, src_net)
            return True
        if len(source) - 1 == common:
            if src_suffix:
                raise EasyConnectError("源为祖先时没有源端的父层绑定，无法确定下标的作用位置")
            net = self.local(lca, src_signal, shape, source=True)
        else:
            current_port = self.port(source[-1][0], src_signal, src_shape, "output", "source")
            net = None
            for depth in range(len(source) - 1, common, -1):
                parent = source[depth - 1][0]
                suffix = src_suffix if depth == len(source) - 1 else ""
                existing = self.existing_up_net(parent, source[depth], current_port, shape, suffix)
                if depth - 1 == common:
                    if existing:
                        net = existing
                    elif len(target) - 1 == common:
                        if dst_suffix:
                            raise EasyConnectError("目标为祖先时没有目标端的父层绑定，无法应用目标下标")
                        declaration = self.project.modules[parent].declarations.get(dst_signal)
                        if declaration is None:
                            net = self.port(parent, dst_signal, shape, "output", "target")
                        else:
                            net = self.local(parent, dst_signal, shape, target=True)
                    else:
                        net = self.turn_wire(parent, src_signal, shape, source_key)
                    self.bind(parent, source[depth], current_port, net + suffix)
                else:
                    intermediate_net = existing or src_signal
                    intermediate_port = self.port(parent, intermediate_net, shape, "output", "relay", bool(existing))
                    if intermediate_port != intermediate_net and not existing:
                        self.local(parent, intermediate_net, shape, target=True)
                    self.bind(parent, source[depth], current_port, intermediate_net + suffix)
                    current_port = intermediate_port
        if len(target) - 1 == common:
            if dst_suffix:
                raise EasyConnectError("目标为祖先时不能使用父层绑定下标")
            mod = self.project.modules[lca]
            if dst_signal not in mod.declarations:
                self.port(lca, dst_signal, shape, "output", "target")
            elif net != dst_signal:
                self.local(lca, dst_signal, shape, target=True)
            if net != dst_signal:
                self.assignment(lca, dst_signal, net)
            return True
        for depth in range(common + 1, len(target)):
            last = depth == len(target) - 1
            child = target[depth][0]
            self.environments[child] = target_env[depth]
            port = self.port(child, dst_signal, dst_shape if last else shape, "input", "target" if last else "relay")
            self.bind(target[depth - 1][0], target[depth], port, net + (dst_suffix if last else ""))
            net = port
        return True

    def defaults(self):
        """Make every newly added interface explicit in unselected references."""
        saved = self.connection
        for (module, port), (direction, shape) in list(self.ports.items()):
            references = [(mod.name, inst.ordinal, inst.name) for mod in self.project.modules.values()
                          for inst in mod.instances if inst.module == module]
            owners = self.resources["port|%s|%s" % (module, port)]["owners"]
            self.connection = {"id": owners[0], "comment": next((c.get("comment", "") for c in self.connections if c["id"] == owners[0]), "")}
            for parent, ordinal, name in references:
                inst = self.project.modules[parent].instances[ordinal]
                if (parent, ordinal, port) not in self.bindings:
                    self.bind(parent, (module, ordinal, name), port, zero(shape) if direction == "input" else "")
                    self.resource("default", parent, "%d.%s" % (ordinal, port), True)
                    self.notes.append("未选位置 %s.%s.%s：%s" % (parent, name, port, "接全零" if direction == "input" else "显式悬空"))
        self.connection = saved

    def render(self, connections):
        self.connections = connections
        retained = []
        for connection in connections:
            if self.plan(connection):
                retained.append(connection)
        self.connections = retained
        if retained:
            self.defaults()
        return retained


def preserve_used_sources(project, previous_sources, notes):
    """After undo, any user use of a formerly new signal needs a declaration."""
    seen = set()
    for item in previous_sources:
        key = (item["module"], item["signal"])
        if key in seen or item["module"] not in project.modules:
            continue
        seen.add(key)
        mod = project.modules[item["module"]]
        signal = item["signal"]
        if signal in mod.declarations:
            continue
        if re.search(r"\b" + re.escape(signal) + r"\b", mask_comments(mod.text[mod.header_end:mod.end], True)):
            packed = ("".join("[" + value + "]" for value in item.get("ranges", [])) + " ") if item.get("ranges") else shape_text(item["shape"])
            insertion = mod.newline + "    wire " + packed + signal + ";" + mod.newline
            project.texts[mod.file] = mod.text[:mod.header_end] + insertion + mod.text[mod.header_end:]
            project.refresh(mod.file)
            notes.append("保留 %s.%s 的局部 wire：用户代码已使用该信号" % key)


def identify_connection(connections, identifiers):
    if len(identifiers) == 1:
        matches = [c for c in connections if c["id"] == identifiers[0]]
    elif len(identifiers) == 2:
        matches = [c for c in connections if c["src"] == identifiers[0] and c["dst"] == identifiers[1]]
    else:
        matches = []
    if len(matches) != 1:
        raise EasyConnectError("连接不存在或不唯一；请使用连接 ID")
    return matches[0]


def transaction(changes, originals):
    for file in changes:
        if protected(file):
            raise EasyConnectError("test_cases 是只读 golden；请先复制到 test_result 再建图连线: " + file)
        current = Path(file).read_bytes() if Path(file).exists() else None
        if current != originals[file]:
            raise EasyConnectError("预览期间文件发生变化，未写入: " + file)
    written, staged, backups = [], {}, {}
    def stage(file, data):
        descriptor, name = tempfile.mkstemp(prefix=".easyconnect-", dir=str(Path(file).parent))
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
        except BaseException:
            Path(name).unlink(missing_ok=True)
            raise
        return name
    try:
        # Allocate all new content and rollback copies before replacing a source.
        # A later rollback only renames files and needs no additional disk space.
        for file, data in changes.items():
            staged[file] = stage(file, data)
            if originals[file] is not None: backups[file] = stage(file, originals[file])
        for file in changes:
            if (Path(file).read_bytes() if Path(file).exists() else None) != originals[file]:
                raise EasyConnectError("提交前文件发生变化，未写入: " + file)
        for file in changes:
            os.replace(staged[file], file)
            written.append(file)
    except BaseException:
        for file in reversed(written):
            if originals[file] is None:
                Path(file).unlink(missing_ok=True)
            else:
                os.replace(backups[file], file)
        raise
    finally:
        for name in list(staged.values()) + list(backups.values()):
            Path(name).unlink(missing_ok=True)


def execute(json_file, action, identifiers=(), src=None, dst=None, dimension=None,
            width=None, comment=None, src_instance=None, dst_instance=None,
            dry_run=False, printer=print):
    json_file = str(Path(json_file).resolve())
    if protected(json_file):
        raise EasyConnectError("连接管理 JSON 不可写入 test_cases")
    lock = json_file + ".lock"
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError as exc:
        raise EasyConnectError("连接管理文件正在使用，或上次异常退出留下锁: " + lock) from exc
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(str(os.getpid()))
        raw_graph = Path(json_file).read_bytes()
        graph = json.loads(raw_graph.decode("utf-8-sig"))
        config = graph.get("input_config", {})
        if "sources" not in graph or not config.get("files") or not config.get("top"):
            raise EasyConnectError("JSON 缺少源码位置/校验信息，请先执行 EasyConnect.py 1 建图")
        state = copy.deepcopy(graph.get("_easyconnect", {"connections": [], "files": {}, "next_id": 1, "new_sources": []}))
        current, baseline, original_bytes = {}, {}, {json_file: raw_graph}
        for file in config["files"]:
            path = Path(file)
            if not path.is_file(): raise EasyConnectError("JSON 记录的源码不存在，请重新建图: " + file)
            raw = path.read_bytes()
            original_bytes[file] = raw
            text, _ = read_source(file)
            current[file] = text
            if file in state["files"]:
                baseline[file] = unrender(file, state["files"][file], text)
            else:
                if digest(raw) != graph["sources"][file]["sha256"]:
                    raise EasyConnectError("JSON 与源码校验不一致，请重新建图: " + file)
                baseline[file] = text
        folder = Path(config["rtl_folder"])
        new_files = {str(p.resolve()) for p in folder.rglob("*") if p.is_file() and p.suffix.lower() in (".v", ".sv")} - set(config["files"])
        if new_files:
            raise EasyConnectError("发现 JSON 未记录的 RTL 文件，请重新建图: " + ", ".join(sorted(new_files)))
        connections = state["connections"]
        changed_id = None
        if action == "add":
            if src is None or dst is None:
                if len(identifiers) != 2: raise EasyConnectError("add 需要源、目标两个端点")
                src, dst = identifiers
            endpoint(src); endpoint(dst)
            changed_id = "c%04d" % state["next_id"]
            connection = {"id": changed_id, "src": src, "dst": dst,
                          "widths": list(widths(dimension, width)), "comment": comment or "",
                          "src_instance": src_instance, "dst_instance": dst_instance}
            connections.append(connection)
        elif action in ("rm", "mv"):
            old = identify_connection(connections, identifiers)
            changed_id = old["id"]
            if action == "rm":
                connections.remove(old)
            else:
                if src is not None:
                    if endpoint(src)[0] != endpoint(old["src"])[0]: old["src_instance"] = None
                    old["src"] = src
                if dst is not None:
                    if endpoint(dst)[0] != endpoint(old["dst"])[0]: old["dst_instance"] = None
                    old["dst"] = dst
                old["widths"] = list(widths(dimension, width, old["widths"]))
                if comment is not None: old["comment"] = comment
                if src_instance is not None: old["src_instance"] = src_instance
                if dst_instance is not None: old["dst_instance"] = dst_instance
        else:
            raise EasyConnectError("未知连接操作: " + action)
        if comment is not None and ("\n" in comment or "\r" in comment):
            raise EasyConnectError("-c 注释必须在一行内")
        project = SourceProject(config["files"], config["top"], config.get("defines"), config.get("include_dirs"), baseline)
        notes = []
        preserve_used_sources(project, state.get("generated_signals", state.get("new_sources", [])), notes)
        # Retained user-used source wires now belong to the baseline, not the tool.
        baseline = dict(project.texts)
        planner = Planner(project)
        connections = planner.render(connections)
        if action == "add" and not any(c["id"] == changed_id for c in connections):
            printer("两端完全相同，无需连线；未新增记录。")
            return {"id": None, "changed_files": [], "dry_run": dry_run}
        if action == "add": state["next_id"] += 1
        state["connections"] = connections
        state["resources"] = list(planner.resources.values())
        state["new_sources"] = planner.new_sources
        state["generated_signals"] = planner.generated_signals
        state["files"] = {file: {"before": baseline[file], "after": text}
                          for file, text in project.texts.items() if text != baseline[file]}
        refreshed = project.graph(config["rtl_folder"], state)
        changes = {file: text.encode(project.encodings[file]) for file, text in project.texts.items() if text != current[file]}
        printer("%s %s%s" % (action, changed_id, " [dry-run]" if dry_run else ""))
        for route in planner.routes: printer(route)
        for note in dict.fromkeys(notes + planner.notes): printer(note)
        for module in sorted({resource["module"] for resource in planner.resources.values()}):
            references = ["%s.%s" % (mod.name, inst.name) for mod in project.modules.values() for inst in mod.instances if inst.module == module]
            if references: printer("源码引用影响 %s: %s" % (module, ", ".join(references)))
        for file in changes:
            difference = "".join(difflib.unified_diff(current[file].splitlines(True), project.texts[file].splitlines(True),
                                                     fromfile=file, tofile=file, n=3))
            printer(difference)
        changes[json_file] = json_bytes(refreshed)
        if not dry_run:
            transaction(changes, original_bytes)
        printer("%s：%d 个 RTL 文件；连接 ID %s。RTL 编译需要单独验证。" %
                ("预览完成，未写入" if dry_run else "提交完成", len(changes) - 1, changed_id))
        return {"id": changed_id, "changed_files": [p for p in changes if p != json_file], "dry_run": dry_run,
                "connections": connections, "notes": notes + planner.notes}
    finally:
        Path(lock).unlink(missing_ok=True)
