"""Routing regressions that exercise scope, aliasing, and generated RTL syntax."""

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from easyconnect.engine import route
from svcheck import check_text


class EngineTests(unittest.TestCase):
    def plan(self, code, source, target, **options):
        with tempfile.TemporaryDirectory() as directory:
            spec = dict(name="route", source=source, target=target, top="top")
            spec.update(options)
            texts, details = route(Path(directory), {"design.v": code}, spec)
            check_text(self, texts["design.v"])
            return texts["design.v"], details

    def test_wiring_preserves_always_block_verbatim(self):
        block = """    always@(*) begin
        // Existing business logic is opaque to EasyConnect.
        if (enable) result = data;
        else result = 8'h00;
    end"""
        code = """module top(input wire enable, input wire [7:0] data);
    reg [7:0] result;
%s
endmodule
""" % block
        output, _ = self.plan(code, "top.result", "top.observed")
        self.assertIn(block, output)
        self.assertEqual(output.count("always@(*)"), 1)

    def test_route_outside_conditional_generate_preserves_block(self):
        block = """generate
  if (USE) begin : logic_on
    always @(*) begin
      if (enable) begin result = data; end
      else begin result = 8'h00; end
    end
  end else begin : logic_off
    always @(*) begin result = 8'h01; end
  end
endgenerate"""
        output, _ = self.plan("""module top #(parameter USE=1)(input enable, input [7:0] data);
reg [7:0] result;
%s
Dst d();
endmodule
module Dst(); wire [7:0] received; endmodule
""" % block, "top.result", "top.d.received")
        self.assertIn(block, output)

    def test_skipped_branch_instances_keep_original_module_definition(self):
        leaf = "module Leaf(); wire value; endmodule"
        output, _ = self.plan("""module top(input wire source);
generate if (1) begin : hidden Leaf h(); end endgenerate
Leaf selected();
endmodule
""" + leaf, "top.source", "top.selected.value")
        self.assertIn(leaf, output)
        self.assertIn("begin : hidden Leaf h(); end", output)
        self.assertRegex(output, r"Leaf__ec_\w+\s+selected")

    def test_request_into_skipped_branch_explains_why_path_is_missing(self):
        with self.assertRaisesRegex(ValueError, "conditional generate branches were skipped at design.v:2"):
            self.plan("""module top(input wire source);
if(1) begin : hidden Dst d(); end
endmodule
module Dst(); wire value; endmodule
""", "top.source", "top.hidden.d.value")

    def test_parameter_defaults_overrides_and_localparam_chain(self):
        output, _ = self.plan("""
module top(); Src #(.W(12)) s(); Dst d(); endmodule
module Src #(parameter W=8)();
  localparam BITS=W; wire [BITS-1:0] data; assign data='0;
endmodule
module Dst(); wire [11:0] data; endmodule
""", "top.s.data", "top.d.data")
        self.assertIn("output wire", output)
        self.assertNotIn("[BITS-1:0] __ec_", output)

    def test_missing_source_names_module_and_declared_signal_hint(self):
        with self.assertRaisesRegex(ValueError, r"'missing'.*module 'Src'.*Declared names: \[data\]"):
            self.plan("""
module top(); Src s(); Dst d(); endmodule
module Src(); wire [7:0] data; endmodule
module Dst(); wire received; endmodule
""", "top.s.missing", "top.d.received")

    def test_route_with_multiple_interface_ports_preserves_existing_interfaces(self):
        source = """
interface bus_if;
  logic req;
  modport host(output req);
  modport device(input req);
endinterface
module top();
  bus_if a(), b(), c();
  Src s(.m0(a), .m1(b), .s0(c));
  Dst d(.m0(a), .m1(b), .s0(c));
endmodule
module Src(bus_if.host m0, m1, bus_if.device s0);
  wire [7:0] data; assign data=8'h42;
endmodule
module Dst(bus_if.host m0, m1, bus_if.device s0);
  wire [7:0] received;
endmodule
"""
        output, _ = self.plan(source, "top.s.data", "top.d.received")
        self.assertEqual(output.count("bus_if.host m0, m1, bus_if.device s0"), 2)
        self.assertEqual(output.count(".m0(a), .m1(b), .s0(c)"), 2)
        self.assertIn("output wire [7:0] __ec_route_out", output)
        self.assertIn("input wire [7:0] __ec_route_in", output)

    def test_routing_alongside_interface_arrays_preserves_dimensions(self):
        self.plan("""
interface bus_if;
  logic req;
  modport host(output req);
  modport device(input req);
endinterface
module top();
  bus_if a[0:1](), b[0:2]();
  Src s(.a(a), .b(b)); Dst d(.a(a), .b(b));
endmodule
module Src(bus_if.host a[0:1], bus_if.device b[0:2]); wire data; endmodule
module Dst(bus_if.host a[0:1], bus_if.device b[0:2]); wire received; endmodule
""", "top.s.data", "top.d.received")

    def test_overrides_refer_to_parent_parameters(self):
        self.plan("""
module top #(parameter GLOBAL_W=4)();
  Mid #(.W(GLOBAL_W*2)) m(); Dst d();
endmodule
module Mid #(parameter W=2)(); Src #(.W(W)) s(); endmodule
module Src #(parameter W=1)(); wire [W-1:0] data; endmodule
module Dst(); wire [7:0] data; endmodule
""", "top.m.s.data", "top.d.data")

    def test_comma_separated_instances_can_be_specialized(self):
        output, _ = self.plan("""
module top(); Src #(.W(8)) s0(), s1(); Dst d0(), d1(); endmodule
module Src #(parameter W=8)(); wire [W-1:0] data; endmodule
module Dst(); wire [7:0] data; endmodule
""", "top.s0.data", "top.d0.data")
        self.assertIn("Src #(.W(8)) s1();", output)
        self.assertIn("Dst d1();", output)

    def test_repeated_ancestor_path_is_isolated(self):
        output, _ = self.plan("""
module top(); Bridge b0(), b1(); Dst d(); endmodule
module Bridge(); Src s(); endmodule
module Src(); wire [7:0] data; endmodule
module Dst(); wire [7:0] data; endmodule
""", "top.b0.s.data", "top.d.data")
        self.assertIn("Bridge b1();", output)

    def test_no_parentheses_and_labeled_endmodule(self):
        self.plan("""
module top; Src s0(), s1(); Dst d(); endmodule : top
module Src; wire data; endmodule : Src
module Dst; wire data; endmodule : Dst
""", "top.s0.data", "top.d.data")

    def test_comment_at_end_of_port_and_connection_lists(self):
        self.plan("""
module top(input wire clk // keep this comment
); Src s(.clk(clk) // keep binding comment
); Dst d(); endmodule
module Src(input wire clk // keep child comment
); wire data; endmodule
module Dst(); wire data; endmodule
""", "top.s.data", "top.d.data")

    def test_packed_bit_select_is_unsigned(self):
        self.plan("""
module top(); Src s(); Dst d(); endmodule
module Src(); wire signed [7:0] data; endmodule
module Dst(); wire bit_in; endmodule
""", "top.s.data[0]", "top.d.bit_in")

    def test_unpacked_select_retains_signed_element(self):
        self.plan("""
module top(); Src s(); Dst d(); endmodule
module Src(); wire signed [7:0] data [0:3]; endmodule
module Dst(); wire signed [7:0] received; endmodule
""", "top.s.data[2]", "top.d.received")

    def test_parameter_selector_is_lifted(self):
        output, _ = self.plan("""
module top(); Src s(); Dst d(); endmodule
module Src(); localparam IDX=2; wire [3:0] data; endmodule
module Dst(); wire received; endmodule
""", "top.s.data[IDX]", "top.d.received")
        self.assertIn("data[(2)]", output)

    def test_dynamic_selector_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "scoped width identifier"):
            self.plan("""
module top(); Src s(); Dst d(); endmodule
module Src(); wire [3:0] data; wire [1:0] idx; endmodule
module Dst(); wire received; endmodule
""", "top.s.data[idx]", "top.d.received")

    def test_multilevel_generated_sources_keep_each_lane(self):
        self.plan("""
module top();
  for(genvar i=0;i<2;i++) begin:g
    Bridge b();
  end
  Dst d();
endmodule
module Bridge();
  for(genvar j=0;j<3;j++) begin:h
    Src s();
  end
endmodule
module Src(); wire [7:0] data; endmodule
module Dst(); wire [7:0] received [0:1][0:2]; endmodule
""", "top.g[i].b.h[j].s.data", "top.d.received", mode="indexed")

    def test_generated_cbb_output_and_input(self):
        metadata = {"modules": {"IP": {"ports": {
            "data": {"direction": "output", "width": "[7:0]"}}}}}
        # Check the transformation with external metadata, then elaborate with a stub.
        with tempfile.TemporaryDirectory() as directory:
            code = """
module top();
  for(genvar i=0;i<2;i++) begin:g
    IP s(.data()); Dst d();
  end
endmodule
module Dst(); wire [7:0] received; endmodule
"""
            texts, _ = route(Path(directory), {"design.v": code}, dict(
                top="top", name="ip", source="top.g[i].s.data", target="top.g[i].d.received",
                mode="indexed", cbb=metadata))
            check_text(self, texts["design.v"] + "\nmodule IP(output wire [7:0] data); endmodule\n")

    def test_child_output_driven_destination_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "already has a driver"):
            self.plan("""
module top(input wire source); Dst d(); endmodule
module Dst(); wire received; Driver x(.out(received)); endmodule
module Driver(output wire out); assign out=1'b0; endmodule
""", "top.source", "top.d.received")

    def test_generated_path_must_not_be_zero_iteration(self):
        with self.assertRaisesRegex(ValueError, "zero-iteration"):
            self.plan("""
module top(); for(genvar i=0;i<0;i++) begin:g Src s(); end Dst d(); endmodule
module Src(); wire data; endmodule
module Dst(); wire received [0:0]; endmodule
""", "top.g[i].s.data", "top.d.received", mode="indexed")

    def test_wildcard_and_positional_are_refused(self):
        for binding in (".*", "source"):
            with self.subTest(binding=binding), self.assertRaisesRegex(ValueError, "connections"):
                self.plan("""
module top(input wire source); Dst d(%s); endmodule
module Dst(input wire clk); wire received; endmodule
""" % binding, "top.source", "top.d.received")

    def test_packed_enable_bus_drives_each_generated_bit(self):
        output, details = self.plan("""
`define LANES 4
module top(input wire [`LANES-1:0] enable);
  for(genvar i=0;i<`LANES;i++) begin:g Dst d(); end
endmodule
module Dst(); wire en; endmodule
""", "top.enable", "top.g[i].d.en", mode="indexed")
        self.assertEqual(details["lane_kind"], "packed")
        self.assertIn("(enable[i])", output)

    def test_generated_sources_drive_packed_matrix(self):
        output, details = self.plan("""
module top();
  for(genvar i=0;i<4;i++) begin:g Src s(); end
  Dst d();
endmodule
module Src(); wire [7:0] data; endmodule
module Dst(); wire [3:0][7:0] received; endmodule
""", "top.g[i].s.data", "top.d.received", mode="indexed")
        self.assertEqual(details["lane_kind"], "packed")

    def test_explicit_packed_lanes_between_generated_families(self):
        self.plan("""
module top();
  for(genvar i=0;i<3;i++) begin:g Src s(); Dst d(); end
endmodule
module Src(); wire [7:0] data; endmodule
module Dst(); wire [7:0] received; endmodule
""", "top.g[i].s.data", "top.g[i].d.received", mode="indexed", lane_kind="packed")

    def test_nested_packed_lanes(self):
        self.plan("""
module top(input wire [1:0][2:0][7:0] data);
  for(genvar i=0;i<2;i++) begin:g
    for(genvar j=0;j<3;j++) begin:h Dst d(); end
  end
endmodule
module Dst(); wire [7:0] received; endmodule
""", "top.data", "top.g[i].h[j].d.received", mode="indexed")

    def test_unknown_cbb_driver_must_be_described(self):
        with self.assertRaisesRegex(ValueError, "unknown CBB port"):
            self.plan("""
module top(input wire source); Dst d(); endmodule
module Dst(); wire received; External x(.out(received)); endmodule
""", "top.source", "top.d.received")

    def test_cbb_output_driver_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "already has a driver"):
            self.plan("""
module top(input wire source); Dst d(); endmodule
module Dst(); wire received; External x(.out(received)); endmodule
""", "top.source", "top.d.received", cbb={"modules": {
    "External": {"ports": {"out": {"direction": "output"}}}}})

    def test_invalid_cbb_metadata_is_a_clean_diagnostic(self):
        for cbb in ({"modules": []}, {"modules": {"IP": {"ports": []}}},
                    {"IP": {"ports": {"out": {"direction": "output", "width": 8}}}}):
            with self.subTest(cbb=cbb), self.assertRaisesRegex(ValueError, "CBB"):
                self.plan("module top(input wire a); wire b; endmodule", "top.a", "top.b", cbb=cbb)

    def test_new_port_cannot_collide_with_parameter(self):
        with self.assertRaisesRegex(ValueError, "collision"):
            self.plan("""
module top(input wire source); Dst d(); endmodule
module Dst(); localparam received=0; endmodule
""", "top.source", "top.d.received")

    def test_implicit_destination_net_already_driven_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "already has a driver"):
            self.plan("""
module top(input wire source); Dst d(); endmodule
module Dst(); assign received=1'b0; endmodule
""", "top.source", "top.d.received")

    def test_implicit_child_output_destination_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "already has a driver"):
            self.plan("""
module top(input wire source); Dst d(); endmodule
module Dst(); Driver x(.out(received)); endmodule
module Driver(output wire out); assign out=1'b0; endmodule
""", "top.source", "top.d.received")


if __name__ == "__main__":
    unittest.main()
