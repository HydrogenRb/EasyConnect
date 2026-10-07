"""Independent RTL syntax, semantic compilation and hierarchy checks (optional)."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "test_result" / "_tools"))
import test_easyconnect as functional
from validate_rtl import compile_graph


@unittest.skipUnless(importlib.util.find_spec("pyslang"), "optional pyslang compiler is unavailable")
class CompilerTests(functional.RoutingTests):
    # Only the explicitly listed compile scenarios run here; base fixture helpers
    # are reused without inheriting all the functional test cases.
    pass

for inherited in [name for name in dir(functional.RoutingTests) if name.startswith("test_")]:
    setattr(CompilerTests, inherited, None)


def compilation_test(operation):
    def test(self):
        operation(self)
        report = compile_graph(self.graph)
        (self.folder / "compile.json").write_text(__import__("json").dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        self.assertEqual(report["errors"], 0, report["diagnostics"])
    return test


SCENARIOS = {
    "cross_layer": lambda t: t.op(),
    "ancestor_source": lambda t: t.op(endpoints=("TOP.sig", "SRC.recv"), dst_instance="U_SRC"),
    "ancestor_target": lambda t: t.op(endpoints=("SRC.sig", "TOP.recv"), dst_instance="TOP"),
    "local": lambda t: t.op(endpoints=("TOP.sig", "TOP.recv"), dst_instance="TOP"),
    "same_type_instances": lambda t: t.op(endpoints=("DST.sig", "DST.recv"), src_instance="U_DST", dst_instance="U_UNUSED"),
    "fanout": lambda t: (t.op(), t.op(endpoints=("SRC.sig", "DST.other"), dst_instance="U_UNUSED")),
    "multi_packed": lambda t: t.op(dimension=2, width="8,4"),
    "selected_source": lambda t: t.op(endpoints=("SRC.sig[0]", "DST.recv"), width="8"),
    "selected_target": lambda t: t.op(endpoints=("SRC.sig", "DST.recv[3]"), width="8"),
    "part_select": lambda t: t.op(endpoints=("SRC.sig[3:0]", "DST.recv"), width="8"),
    "existing_reg_source": lambda t: (t.write("SRC.v", "module SRC(input clk); reg [7:0] sig; always @(posedge clk) sig<=8'h55; endmodule\n"), t.rebuild(), t.op(width="8")),
    "existing_internal_target": lambda t: (t.write("DST.v", "module DST(input clk); wire [7:0] recv; endmodule\n"), t.rebuild(), t.op(width="8")),
    "non_ansi": lambda t: (t.write("SRC.v", "module SRC(clk); input clk; endmodule\n"), t.write("DST.v", "module DST(clk); input clk; endmodule\n"), t.rebuild(), t.op()),
    "no_ports": lambda t: (t.write("SRC.v", "module SRC; endmodule\n"), t.write("MID.v", "module MID(input clk); SRC U_SRC(); endmodule\n"), t.rebuild(), t.op()),
    "mv": lambda t: (t.op(), t.op("mv", ("c0001",), width="16", src="SRC.renamed")),
    "rm": lambda t: (t.op(), t.op("rm", ("c0001",))),
    "user_driven_source_rm": lambda t: (t.op(), t.write("SRC.v", t.read("SRC.v").replace("endmodule", "assign sig = clk; endmodule")), t.op("rm", ("c0001",))),
    "parameter_override": lambda t: (t.write("SRC.v", "module SRC #(parameter W=8)(input clk); wire [W-1:0] sig; endmodule\n"),
                                     t.write("MID.v", "module MID(input clk); SRC #(.W(4)) U_SRC(.clk(clk)); endmodule\n"), t.rebuild(), t.op(width="4")),
}
for name, operation in SCENARIOS.items():
    setattr(CompilerTests, "test_compile_" + name, compilation_test(operation))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    # Explicit suite excludes imported RoutingTests.
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(CompilerTests))
    sys.exit(not result.wasSuccessful())
