#!/usr/bin/env python3
"""Render SV instance hierarchies, using Python 3.8+ standard library only.

Input structure: {"modules": {"module_name": {"instantiations": [...]}}}.
Only module/instance/style/status are read from each instantiation. All other
metadata, including roots, top, times, generate_block and loop_depth, is ignored.
Usage: python hierarchy_to_html.py expected_hierarchy.json -o architecture.html
"""
import argparse
import html
import json
from pathlib import Path
import sys

FIELDS = ('module', 'instance', 'style', 'status')


def normalize(data):
    """Validate structural containers and project records onto the four fields."""
    if not isinstance(data, dict) or not isinstance(data.get('modules'), dict):
        raise ValueError('输入必须包含 modules 对象')
    modules = {}
    for name, body in data['modules'].items():
        if not isinstance(name, str) or not name.strip():
            raise ValueError('模块名必须为非空字符串')
        if not isinstance(body, dict) or not isinstance(body.get('instantiations'), list):
            raise ValueError('%s: instantiations 必须为数组' % name)
        records = []
        for index, record in enumerate(body['instantiations']):
            if not isinstance(record, dict):
                raise ValueError('%s[%d]: 例化必须为对象' % (name, index))
            for key in FIELDS:
                if not isinstance(record.get(key), str) or not record[key].strip():
                    raise ValueError('%s[%d].%s 必须为非空字符串' % (name, index, key))
            records.append({key: record[key] for key in FIELDS})
        modules[name] = records
    if not modules:
        raise ValueError('modules 不能为空')
    return modules


def infer_roots(modules):
    """Find unreferenced definitions, preferring non-leaf roots, not a name rule."""
    targets = {r['module'] for records in modules.values() for r in records}
    roots = [name for name in modules if name not in targets]
    return sorted(roots, key=lambda name: (not bool(modules[name]), name))


CSS = r'''
*{box-sizing:border-box}body{margin:0;background:#f3f6fa;color:#243449;font:14px/1.5 system-ui,-apple-system,"Microsoft YaHei",sans-serif}header{padding:24px 28px 18px;background:#fff;border-bottom:1px solid #dce4ec}h1{font-size:25px;margin:4px 0 8px}.eyebrow{font-size:11px;letter-spacing:2px;color:#657b95}p{margin:5px 0;color:#60728a}.toolbar{display:flex;gap:8px;flex-wrap:wrap;align-items:center;padding:14px 28px;background:#fff;border-bottom:1px solid #dce4ec}button,select,input{font:inherit;border:1px solid #c5d1e0;border-radius:6px;padding:7px 10px;background:#fff;color:#32465f;max-width:100%}button,summary,select{cursor:pointer}button:hover{background:#eef5ff}button:focus-visible,summary:focus-visible{outline:3px solid #e3ad42}input{width:200px}.legend{padding:14px 28px;color:#60728a;font-size:12px;display:flex;gap:20px;flex-wrap:wrap}.dot{display:inline-block;width:10px;height:10px;background:#5285d5;margin-right:5px;border-radius:2px}.dot.gen{background:#129985}main{overflow:auto;padding:8px 28px 50px}#diagram{min-width:300px}.root-view{margin-bottom:32px}.root-title{font:12px/1.7 ui-monospace,Consolas,monospace;overflow-wrap:anywhere;margin:0 0 12px;color:#627590}.node{position:relative;min-width:0;margin:0}.front{position:relative;z-index:2;border:1px solid #bbcee4;border-top:3px solid #5285d5;background:#fff;border-radius:7px;overflow:hidden}.generated{padding-top:24px;margin-right:24px;margin-bottom:10px}.generated:before,.generated:after{content:"";position:absolute;top:24px;bottom:0;left:0;right:0;border:1px solid #83c1b6;border-radius:7px;background:#e2f2ed;z-index:0}.generated:before{transform:translate(20px,-20px)}.generated:after{transform:translate(10px,-10px)}.generated>.front{border-color:#83c1b6;border-top-color:#129985}summary,.leaf-head{padding:12px 14px;background:#f8fbff}.generated>.front>summary,.generated>.front>.leaf-head{background:#eff9f5}summary::marker{color:#667e99}.instance{font:600 14px/1.6 ui-monospace,Consolas,monospace;overflow-wrap:anywhere}.module{font:12px/1.7 ui-monospace,Consolas,monospace;color:#63758c;overflow-wrap:anywhere}.badge{display:inline-block;font-size:11px;padding:2px 6px;background:#d9f0e9;color:#136c59;border-radius:4px;margin-left:8px}.metadata{font-size:11px;color:#61778d;margin-top:5px;overflow-wrap:anywhere}.body{padding:14px;border-top:1px solid #e2e9f1}.hint{font-size:11px;color:#237d68;margin-bottom:12px}.children{display:grid;grid-template-columns:1fr;gap:16px;align-items:start}.root-view>.node>.front>.body>.children{grid-template-columns:repeat(auto-fit,minmax(min(100%,320px),1fr))}.message{font-size:12px;color:#796338;background:#fff7e4;padding:9px;border-radius:4px}.node.match>.front{outline:3px solid #d49b25}.path{font:11px/1.5 ui-monospace,Consolas,monospace;overflow-wrap:anywhere;color:#7a8797;padding:8px 14px;border-top:1px solid #eef1f5}.footer{padding:14px 28px;background:#fff;color:#6b7b8c;font-size:12px;border-top:1px solid #dce4ec}[hidden]{display:none!important}#feedback{font-size:12px;color:#61778d}noscript{display:block;padding:12px 28px}@media(max-width:650px){header,.toolbar,.legend{padding-left:14px;padding-right:14px}main{padding:8px 14px 35px}.body{padding:10px}h1{font-size:21px}}@media print{.toolbar{display:none}main{overflow:visible}#diagram{zoom:1!important}summary,.leaf-head{break-inside:avoid}}
'''

JS = r'''
const diagram=document.getElementById('diagram');
const views=[...document.querySelectorAll('.root-view')];
const picker=document.getElementById('root');
function choose(){views.forEach(v=>v.hidden=picker.value!=='all'&&v.id!==picker.value)}
picker.addEventListener('change',choose);choose();
document.getElementById('expand').onclick=()=>views.filter(v=>!v.hidden).forEach(v=>v.querySelectorAll('details').forEach(d=>d.open=true));
document.getElementById('collapse').onclick=()=>views.filter(v=>!v.hidden).forEach(v=>v.querySelectorAll('details').forEach(d=>d.open=d.parentElement.parentElement===v));
document.getElementById('zoom').onchange=e=>diagram.style.zoom=e.target.value;
const query=document.getElementById('query');
function search(){
 const q=query.value.trim().toLowerCase();let first=null,count=0;
 document.querySelectorAll('.node').forEach(n=>{
  const hit=q!==''&&n.dataset.search.toLowerCase().includes(q);
  n.classList.toggle('match',hit);
  if(hit){count++;if(!first)first=n;for(let a=n.parentElement;a;a=a.parentElement){if(a.tagName==='DETAILS')a.open=true}}
 });
 if(q){picker.value='all';choose()}
 document.getElementById('feedback').textContent=q?count+' 个匹配（按路径分别显示）':'';
 if(first)first.scrollIntoView({block:'center',behavior:'smooth'});
}
document.getElementById('find').onclick=search;query.addEventListener('keydown',e=>{if(e.key==='Enter')search()});
'''


def generate_html(data, top=None, open_depth=2, max_nodes=20000):
    modules = normalize(data)
    roots = infer_roots(modules)
    if top is not None:
        if top not in modules:
            raise ValueError('--top 指定的模块不存在: ' + top)
        roots = [top]
    else:
        # Also cover disconnected recursive components, without hiding definitions.
        seen = set()
        def visit(start):
            pending = [start]
            while pending:
                name = pending.pop()
                if name in seen or name not in modules:
                    continue
                seen.add(name)
                pending.extend(r['module'] for r in modules[name])
        for name in roots:
            visit(name)
        for name in modules:
            if name not in seen:
                roots.append(name)
                visit(name)
    if open_depth < 0 or max_nodes < 1:
        raise ValueError('open_depth 必须 >= 0，max_nodes 必须 >= 1')
    esc = html.escape
    rendered = 0
    def render(record, ancestry, path, depth, is_root=False):
        nonlocal rendered
        rendered += 1
        if rendered > max_nodes:
            raise ValueError('显示节点数超过 %d；请用 --top 选择子模块或增大 --max-nodes' % max_nodes)
        if depth > 200:
            raise ValueError('层级深度超过 200；请用 --top 选择子模块')
        module, instance = record['module'], record['instance']
        generated = record['status'] == 'for_generated' and not is_root
        current_path = path + [instance]
        cycle = module in ancestry
        missing = module not in modules
        records = modules.get(module, [])
        container = bool(records) and not cycle
        heading = '<span class="instance">%s</span>' % esc(instance)
        if generated:
            heading += '<span class="badge">for generate · 重复数未知</span>'
        heading += '<div class="module">%s</div>' % esc(module)
        if not is_root:
            heading += '<div class="metadata">style: %s · status: %s</div>' % (esc(record['style']), esc(record['status']))
        else:
            heading += '<div class="metadata">层级入口 · 从 module 引用关系推导，或由 --top 指定</div>'
        attrs = ' data-module="%s" data-instance="%s" data-search="%s"' % (
            esc(module, quote=True), esc(instance, quote=True),
            esc(' '.join(record.values()), quote=True))
        result = ['<section class="node%s"%s>' % (' generated' if generated else '', attrs)]
        if container:
            result.append('<details class="front"%s><summary>%s</summary>' % (' open' if depth < open_depth else '', heading))
        else:
            result.append('<div class="front"><div class="leaf-head">%s</div>' % heading)
        result.append('<div class="body">')
        if generated:
            result.append('<div class="hint">叠层仅示意重复结构；前层展示代表实例。索引按原文保留。</div>')
        if cycle:
            result.append('<div class="message">循环引用：%s；停止继续展开。</div>' % esc(module))
        elif missing:
            result.append('<div class="message">未提供模块定义；保留该实例。</div>')
        elif records:
            result.append('<div class="children">')
            for child in records:
                result.append(render(child, ancestry + (module,), current_path, depth + 1))
            result.append('</div>')
        else:
            result.append('<div class="module">叶模块 · 无下级例化</div>')
        result.append('</div><div class="path">%s</div>' % esc(' → '.join(current_path)))
        result.append('</details>' if container else '</div>')
        result.append('</section>')
        return ''.join(result)
    views, options = [], []
    for index, name in enumerate(roots):
        identity = 'view-%d' % index
        options.append('<option value="%s">%s</option>' % (identity, esc(name)))
        views.append('<section class="root-view" id="%s"><h2 class="root-title">%s</h2>%s</section>' % (
            identity, esc(name), render(dict(module=name, instance=name, style='', status=''), (), [], 0, True)))
    return '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>SV 模块例化架构</title><style>''' + CSS + '''</style></head><body>
<header><div class="eyebrow">SYSTEMVERILOG / INSTANCE HIERARCHY</div><h1>模块例化架构</h1><p>普通实例独立展示 · generate 多层堆叠 · 前层展示内部细节</p></header>
<div class="toolbar"><label>层级入口 <select id="root">''' + ''.join(options) + '''<option value="all">全部入口</option></select></label>
<button id="expand">展开全部</button><button id="collapse">折叠子层</button><label>查找 <input id="query" placeholder="模块 / 实例 / style / status"></label><button id="find">定位</button><label>缩放 <select id="zoom"><option value="0.65">65%</option><option value="0.8">80%</option><option value="1" selected>100%</option><option value="1.2">120%</option></select></label><span id="feedback" aria-live="polite"></span></div>
<div class="legend"><span><i class="dot"></i>普通例化</span><span><i class="dot gen"></i>for_generated</span><span>嵌套容器表示父子例化；点击标题展开</span></div>
<noscript>JavaScript 未启用：全部入口仍可阅读，点击模块标题可展开或折叠。</noscript>
<main id="diagram">''' + ''.join(views) + '''</main><div class="footer">仅使用 module、instance、style、status；modules / instantiations 仅用于组织层级。未读取重复次数、循环维度或 generate 块名；叠层数量不代表实例数量。图中路径为实例层级示意，不是补全 generate 块后的 HDL 完整路径。</div>
<script>''' + JS + '''</script></body></html>'''


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('input', type=Path, help='输入 JSON 文件')
    parser.add_argument('-o', '--output', type=Path, help='输出 HTML，默认与输入同名')
    parser.add_argument('--top', help='显式指定层级入口（不读取 JSON roots/top）')
    parser.add_argument('--open-depth', type=int, default=2, help='初始展开深度，默认 2')
    parser.add_argument('--max-nodes', type=int, default=20000, help='最大渲染节点数，超出时报错而非截断')
    args = parser.parse_args(argv)
    destination = args.output or args.input.with_suffix('.html')
    if destination.resolve() == args.input.resolve():
        parser.error('输出路径不能与输入路径相同')
    try:
        data = json.loads(args.input.read_text(encoding='utf-8-sig'))
        output = generate_html(data, args.top, args.open_depth, args.max_nodes)
        destination.write_text(output, encoding='utf-8')
    except (OSError, ValueError, RecursionError) as exc:
        parser.exit(2, '错误: %s\n' % exc)
    print('已生成: %s' % destination)
    return 0


if __name__ == '__main__':
    sys.exit(main())
