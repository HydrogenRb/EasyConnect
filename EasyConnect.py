#!/usr/bin/env python3
"""EasyConnect CLI; Python 3.8+, standard library only."""

import argparse
import json
import sys
from pathlib import Path

from easyconnect import __version__
from easyconnect import state


def _common(parser):
    # SUPPRESS lets the same options appear before or after the subcommand.
    parser.add_argument("--src", default=argparse.SUPPRESS, metavar="DIR",
                        help="RTL root directory (default: current directory)")
    parser.add_argument("--top", default=argparse.SUPPRESS, metavar="MODULE",
                        help="top module; inferred only when unambiguous")
    parser.add_argument("--cbb", default=argparse.SUPPRESS, metavar="JSON",
                        help="external module/port metadata JSON file")
    parser.add_argument("--dry-run", action="store_true", default=argparse.SUPPRESS,
                        help="show a diff without writing RTL or state")


def _route_options(parser, allow_name):
    if allow_name:
        parser.add_argument("--name", default=argparse.SUPPRESS,
                            help="connection ID and generated-signal prefix (default: c001, c002, ...)")
    parser.add_argument("--width", default=argparse.SUPPRESS, metavar="PACKED",
                        help="packed dimensions, e.g. '[`DATA_W-1:0]' or '[1:0][`W-1:0]'")
    parser.add_argument("--unpacked", default=argparse.SUPPRESS, metavar="DIMS",
                        help="unpacked dimensions, e.g. '[0:`N-1][0:3]'")
    parser.add_argument("--signed", action="store_true", default=argparse.SUPPRESS,
                        help="use signed signal type")
    parser.add_argument("--replace", action="store_true", default=argparse.SUPPRESS,
                        help="allow replacing an existing destination connection")
    parser.add_argument("--mode", choices=("shared", "indexed"), default=argparse.SUPPRESS,
                        help="generate loop routing mode (default: shared)")
    parser.add_argument("--lane-kind", choices=("auto", "packed", "unpacked"), default=argparse.SUPPRESS,
                        help="indexed lane dimension layout (default: auto from endpoint shapes)")


def make_parser():
    parser = argparse.ArgumentParser(
        description="EasyConnect {} — reversible Verilog/SystemVerilog hierarchy wiring".format(__version__),
        epilog="Examples and supported RTL syntax: README.md")
    parser.add_argument("--version", action="version", version="EasyConnect " + __version__)
    _common(parser)
    commands = parser.add_subparsers(dest="command", required=True)
    graph = commands.add_parser("map", help="inspect modules and instance hierarchy")
    _common(graph)
    graph.add_argument("--json", action="store_true", help="JSON output (also the default)")
    add = commands.add_parser("add", help="add a source-to-destination connection")
    _common(add)
    add.add_argument("source", help="source instance.signal, e.g. U_C.fifo_rd")
    add.add_argument("target", help="destination instance.signal, e.g. U_D.fifo_rd_in")
    _route_options(add, True)
    listing = commands.add_parser("list", help="list managed connections")
    _common(listing)
    listing.add_argument("--json", action="store_true", help="machine-readable connection records")
    remove = commands.add_parser("remove", aliases=["rm", "delete"], help="remove a managed connection by ID")
    _common(remove)
    remove.add_argument("id")
    change = commands.add_parser("change", aliases=["update", "modify"], help="reroute a managed connection by ID")
    _common(change)
    change.add_argument("id")
    change.add_argument("source")
    change.add_argument("target")
    _route_options(change, False)
    recovery = commands.add_parser("recover", help="roll back an interrupted transaction")
    _common(recovery)
    return parser


def _cbb(path):
    if path is None:
        return None
    try:
        value = json.loads(Path(path).read_bytes().decode("utf-8-sig"))
    except (OSError, ValueError, UnicodeError) as error:
        raise ValueError("Cannot read CBB metadata {}: {}".format(path, error))
    if not isinstance(value, dict):
        raise ValueError("CBB metadata must be a JSON object")
    return value


def _spec(args, adding):
    value = ({"top": None, "width": None, "unpacked": None, "signed": False,
              "cbb": None, "replace": False, "mode": "shared"}
             if adding else {})
    for key in ("source", "target", "name", "top", "width", "unpacked", "signed", "replace", "mode", "lane_kind"):
        if hasattr(args, key):
            value[key] = getattr(args, key)
    if hasattr(args, "cbb"):
        value["cbb"] = _cbb(args.cbb)
    return value


def _report(result):
    if result["dry_run"]:
        print("DRY RUN: {} {}".format(result["operation"], result["id"]))
        print(result["diff"] or "(No RTL changes)")
    else:
        print("{} {}: {} RTL file(s) changed".format(
            result["operation"], result["id"], len(result["files"])))
        for filename in result["files"]:
            print("  " + filename)
    for record in result["details"]:
        if record["id"] == result["id"]:
            print(json.dumps(record["detail"], ensure_ascii=False, indent=2))


def main(argv=None):
    parser = make_parser()
    args = parser.parse_args(argv)
    root = Path(getattr(args, "src", ".")).resolve()
    dry_run = getattr(args, "dry_run", False)
    try:
        if args.command == "map":
            from easyconnect.engine import build_map
            state.assert_no_pending(root)
            result = build_map(root, state.scan_rtl(root), getattr(args, "top", None),
                               _cbb(getattr(args, "cbb", None)))
            print(json.dumps(result, ensure_ascii=False, indent=2))
        elif args.command == "list":
            connections = state.list_connections(root)
            if args.json:
                print(json.dumps(connections, ensure_ascii=False, indent=2))
            elif not connections:
                print("No managed connections.")
            else:
                for item in connections:
                    print("{}: {} -> {}".format(item["id"], item["source"], item["target"]))
        elif args.command == "recover":
            if dry_run:
                raise ValueError("recover does not support --dry-run; it restores the pending transaction")
            result = state.recover(root)
            print("Interrupted transaction rolled back." if result["recovered"] else "No pending transaction.")
        else:
            operation = {"rm": "remove", "delete": "remove", "update": "change", "modify": "change"}.get(
                args.command, args.command)
            spec = _spec(args, operation == "add") if operation in ("add", "change") else None
            result = state.apply_operation(root, operation, spec, getattr(args, "id", None), dry_run)
            _report(result)
        return 0
    except (ValueError, OSError) as error:
        print("EasyConnect error: {}".format(error), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("EasyConnect interrupted. If a transaction is pending, run recover.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
