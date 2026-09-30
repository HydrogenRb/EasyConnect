"""Offset preservation, grouped types, macro arrays and hierarchy regression tests."""
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from easyconnect.rtl import Design, RTLException, mask


class FrontendTests(unittest.TestCase):
    def design(self, text):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        return Design(temp.name, {"design.v": text})

    def test_multiple_interface_modports_use_port_names_not_type_names(self):
        raw = """module A (
  bus_if.master m0, m1,
  bus_if.slave s0,
  bus_if.master m2 [0:1],
  input logic clk
);
wire [7:0] payload;
endmodule
"""
        module = self.design(raw).modules["A"]
        self.assertEqual(list(module.ports), ["m0", "m1", "s0", "m2", "clk"])
        self.assertEqual(module.ports["m0"].kind, "bus_if.master")
        self.assertEqual(module.ports["m1"].kind, "bus_if.master")
        self.assertEqual(module.ports["m2"].unpacked, "[0:1]")
        self.assertTrue(module.ansi)
        self.assertFalse(module.unsafe)
        self.assertEqual(module.text, raw)

    def test_interface_only_and_generic_interface_headers_are_ansi(self):
        for ports in ("bus_if.master a, b, bus_if.slave c", "bus_if a, b, bus_if c", "interface a, b, interface c"):
            with self.subTest(ports=ports):
                module = self.design("module A(" + ports + "); endmodule").modules["A"]
                self.assertTrue(module.ansi)
                self.assertEqual(list(module.ports), ["a", "b", "c"])
                self.assertFalse(module.unsafe)

    def test_existing_duplicate_port_and_binding_lists_are_not_validated(self):
        for ports in ("input a, input a", "a, a"):
            with self.subTest(ports=ports):
                raw = "module A(" + ports + "); B b(.x(a), .x(a)); endmodule"
                module = self.design(raw).modules["A"]
                self.assertEqual(module.text, raw)
                self.assertEqual(module.instances[0].name, "b")

    def test_map_mode_skips_declarations_connections_and_driver_analysis(self):
        raw = """module A #(parameter N=2) (bus_if.master a, bus_if.slave b, input a);
wire [`WIDTH-1:0] signal;
assign signal='0;
for(genvar i=0;i<N;i++) begin:g
  Leaf #(.W(8), .W(16)) u(.p(signal), .p(signal));
end
endmodule
"""
        with tempfile.TemporaryDirectory() as directory:
            with patch("easyconnect.rtl._declarations", side_effect=AssertionError("declaration parsing")), \
                 patch("easyconnect.rtl._connections", side_effect=AssertionError("connection parsing")), \
                 patch("easyconnect.rtl._parameters", side_effect=AssertionError("parameter parsing")), \
                 patch("easyconnect.rtl._mark_child_drivers", side_effect=AssertionError("driver checking")):
                module = Design(directory, {"design.v": raw}, structure_only=True).modules["A"]
            self.assertEqual([inst.full_name for inst in module.instances], ["g[i].u"])
            self.assertEqual(module.ports, {})
            self.assertEqual(module.signals, {})
            self.assertEqual(module.driven, set())

    def test_qualified_type_widths_keep_declarator_names(self):
        module = self.design("module A(input pkg::word_t a, b, input logic [3:0] c); endmodule").modules["A"]
        self.assertEqual(list(module.ports), ["a", "b", "c"])
        self.assertEqual(module.ports["a"].kind, "pkg::word_t")
        self.assertEqual(module.ports["b"].kind, "pkg::word_t")
        self.assertEqual(module.ports["c"].width, "[3:0]")

    def test_ansi_grouped_macro_multidimensional(self):
        raw = """`include "widths.vh"
module A # (parameter W=8) (
 input logic signed [`W-1:0][1:0] a [0:`N-1][2:0], b [4:0],
 output logic [W-1:0] c, d,
 input clk
);
 wire [`LANES-1:0][7:0] internal_a [0:2], internal_b [0:3];
 always_ff @(posedge clk) begin
   c <= a[0];
   d <= b;
 end
endmodule : A
"""
        module = self.design(raw).modules["A"]
        self.assertEqual(module.ports["a"].width, "[`W-1:0][1:0]")
        self.assertEqual(module.ports["a"].unpacked, "[0:`N-1][2:0]")
        self.assertEqual(module.ports["b"].width, "[`W-1:0][1:0]")
        self.assertEqual(module.ports["b"].unpacked, "[4:0]")
        self.assertTrue(module.ports["b"].signed)
        self.assertEqual(module.ports["d"].width, "[W-1:0]")
        self.assertEqual(module.ports["clk"].width, "")
        self.assertEqual(module.signals["internal_b"].unpacked, "[0:3]")
        self.assertEqual(module.parameters, {"W": "8"})
        self.assertFalse({"c", "d"} & module.driven)
        self.assertEqual(raw[module.name_start:module.name_end], "A")
        self.assertEqual(raw[module.ports_open], "(")
        self.assertEqual(raw[module.ports_close], ")")
        self.assertEqual(raw[module.end - len("endmodule : A"):module.end], "endmodule : A")
        self.assertFalse(module.unsafe)

    def test_nonansi_and_no_parentheses(self):
        modules = self.design("""module A(a,b);
 input signed [7:0] a;
 output [7:0] b;
 reg [7:0] b;
 always @* b = a;
endmodule
module Empty; endmodule
""").modules
        module = modules["A"]
        self.assertFalse(module.ansi)
        self.assertTrue(module.ports["a"].signed)
        self.assertEqual(module.ports["b"].kind, "reg")
        self.assertEqual(module.ports["b"].direction, "output")
        self.assertNotIn("b", module.driven)
        self.assertIsNone(modules["Empty"].ports_open)

    def test_scopes_instances_parameters_and_connections(self):
        raw = """module A #(parameter N=4) (input logic [3:0] bus);
 genvar i;
 generate
 for (i=0; i<N; i=i+1) begin : lane
   CBB #(.W(`W), .N(N)) first (.a(bus[i]), .b(), .clk), second (.a(bus[i]), .*);
 end
 endgenerate
 begin : outer
   B inst (.bus(bus));
 end
endmodule
module B(input [3:0] bus); endmodule
"""
        module = self.design(raw).modules["A"]
        first, second, third = module.instances
        self.assertEqual(first.full_name, "lane[i].first")
        self.assertEqual(first.parameters, {"W": "`W", "N": "N"})
        self.assertEqual(first.connections, {"a": "bus[i]", "b": "", "clk": "clk"})
        self.assertEqual(first.shorthand, {"clk"})
        self.assertEqual(first.loops[0].lower, "0")
        self.assertEqual(first.loops[0].upper, "N")
        self.assertEqual(first.loops[0].step, 1)
        self.assertEqual(first.scopes, ("lane[i]",))
        self.assertTrue(second.wildcard)
        self.assertEqual(first.type_start, second.type_start)
        self.assertEqual(first.declaration_count, 2)
        self.assertEqual(raw[first.name_start:first.name_end], "first")
        self.assertTrue(raw[first.member_start:first.member_end].startswith("first ("))
        self.assertEqual(raw[first.connection_spans["a"][0]:first.connection_spans["a"][1]], "bus[i]")
        self.assertEqual(third.full_name, "outer.inst")

    def test_loop_inclusive_descending_nested(self):
        module = self.design("""module A;
for (genvar i=3; i>=0; --i) begin : g
 for (genvar j=1; j<=2; j+=1) begin : h
  Unknown u();
 end
end
endmodule""").modules["A"]
        instance = module.instances[0]
        self.assertEqual(instance.full_name, "g[i].h[j].u")
        self.assertEqual(instance.loops[0].upper, "(0)-1")
        self.assertEqual(instance.loops[0].step, -1)
        self.assertEqual(instance.loops[1].upper, "(2)+1")

    def test_ignores_procedural_calls_and_functions(self):
        module = self.design("""module A(input clk);
 function automatic logic f(input logic a);
   f = a;
 endfunction
 always @(posedge clk) begin
   if (clk) $display("looks // like comments");
   else begin task_call(1); end
 end
 initial begin
   for (int i=0;i<2;i++) task_call(i);
 end
 B real_instance();
endmodule
""").modules["A"]
        self.assertEqual([i.name for i in module.instances], ["real_instance"])

    def test_positional_and_instance_arrays(self):
        instance = self.design("module A; B #(4, `N) u[0:3](a,b); endmodule").modules["A"].instances[0]
        self.assertTrue(instance.positional)
        self.assertTrue(instance.positional_parameters)
        self.assertEqual(instance.arrays, "[0:3]")
        self.assertEqual(instance.parameters, {"0": "4", "1": "`N"})

    def test_conditionals_are_unsafe(self):
        module = self.design("""`ifdef ENABLE
module A;
 if (1) begin : yes
   B u();
 end else begin : no
   C v();
 end
endmodule
`endif
""").modules["A"]
        self.assertTrue(any("preprocessing" in x for x in module.unsafe))
        self.assertFalse(any("conditional generate" in x for x in module.unsafe))
        self.assertEqual(module.instances, [])
        self.assertEqual(len(module.ignored_regions), 1)

    def test_generate_if_with_nested_always_is_skipped(self):
        raw = """module A #(parameter USE=1)(input a, input b, output reg q);
generate
  if (USE) begin : selected
    always @(*) begin
      if (a) begin q = b; end
      else begin q = 0; end
    end
  end else begin : other
    always @(*) begin q = a; end
  end
endgenerate
B actual();
endmodule
"""
        module = self.design(raw).modules["A"]
        self.assertEqual([i.name for i in module.instances], ["actual"])
        self.assertFalse(module.unsafe)
        self.assertFalse(module.driven)
        self.assertEqual(module.text, raw)
        self.assertEqual(module.ignored_regions[0]["line"], 3)

    def test_single_statement_generate_branches_and_else_if(self):
        module = self.design("""module A #(parameter P=1)(input a,b, output reg q);
if(P) always @(*) if(a) q=b; else q=0;
else if(P==2) always_comb begin q=a; end
else always @* q=b;
B actual();
endmodule
""").modules["A"]
        self.assertEqual([i.name for i in module.instances], ["actual"])
        self.assertFalse(module.unsafe)
        self.assertEqual(len(module.ignored_regions), 1)

    def test_generate_case_skips_nested_procedures_and_instances(self):
        module = self.design("""module A #(parameter P=1)(input a, output reg q);
generate case(P)
  1: begin : c
    always @(*) begin
      case(a) 0: q=0; default: q=1; endcase
    end
    B hidden();
  end
  default: begin always_comb q=a; end
endcase endgenerate
B actual();
endmodule
""").modules["A"]
        self.assertEqual([i.name for i in module.instances], ["actual"])
        self.assertFalse(module.unsafe)

    def test_conditional_generate_within_for_does_not_hide_siblings(self):
        module = self.design("""module A(input a, output logic [1:0] q);
for(genvar i=0;i<2;i++) begin : g
  if(i==0) begin : special
    always @(*) begin q[i]=a; end
  end else begin
    always_comb q[i]=0;
  end
  B actual();
end
endmodule
""").modules["A"]
        self.assertEqual([i.full_name for i in module.instances], ["g[i].actual"])
        self.assertFalse(module.unsafe)

    def test_actual_unclosed_begin_reports_location_and_stage(self):
        with self.assertRaises(RTLException) as caught:
            self.design("module A(input a, output logic q);\nalways @(*) begin\nq=a;\nendmodule\n")
        self.assertIn("design.v:2:13", str(caught.exception))
        self.assertIn("[module A]", str(caught.exception))
        self.assertIn("always @(*) begin", str(caught.exception))
        self.assertIn("^", str(caught.exception))
        self.assertEqual(caught.exception.easyconnect_stages,
                         ["parse RTL file design.v", "scan module A structure"])

    def test_typedef_ports_are_flagged(self):
        module = self.design("module A(input custom_t p, output integer q); endmodule").modules["A"]
        self.assertTrue(module.ports["p"].unsupported)
        self.assertTrue(module.ports["q"].unsupported)

    def test_duplicate_modules_and_unbalanced_rejected(self):
        with self.assertRaisesRegex(RTLException, "duplicate module"):
            self.design("module A; endmodule module A; endmodule")
        with self.assertRaisesRegex(RTLException, "unmatched"):
            self.design("module A(input a; endmodule")

    def test_mask_preserves_crlf_and_macro_dimensions(self):
        raw = '`define W 8\r\nmodule A(input [`W-1:0] a); // c\r\nendmodule\r\n'
        masked = mask(raw)
        self.assertEqual(len(masked), len(raw))
        self.assertEqual([i for i, ch in enumerate(raw) if ch in "\r\n"],
                         [i for i, ch in enumerate(masked) if ch in "\r\n"])
        self.assertIn("[`W-1:0]", masked)
        self.assertEqual(self.design(raw).modules["A"].ports["a"].width, "[`W-1:0]")

    def test_child_output_connections_are_drivers(self):
        module = self.design("""module A(input clk);
 wire [3:0] a,b,c,d,e;
 wire index;
 B one(.source(a[index]), .unused(clk));
 B two({b,c}, clk);
 B three(.source, .unused(clk));
 wire source;
 C four(.*);
endmodule
module B(output source, input unused); endmodule
module C(output d, inout e, input index); endmodule
""").modules["A"]
        self.assertTrue({"a", "b", "c", "d", "e", "source"}.issubset(module.driven))
        self.assertNotIn("index", module.driven)
        self.assertNotIn("clk", module.driven)

    def test_always_comb_body_is_ignored(self):
        module = self.design("""module A(input a,b, output logic c);
 always_comb begin
   if (a <= b) c = 1;
   else c = 0;
 end
endmodule
""").modules["A"]
        self.assertEqual(module.driven, set())

    def test_procedural_blocks_skip_assignment_analysis(self):
        for header in ("always@(*)", "always @*", "always_comb", "always_latch",
                       "always_ff @(posedge clk)", "initial", "final"):
            with self.subTest(header=header), patch("easyconnect.rtl._driven") as scan:
                raw = """module A(input clk, input a, output logic q);
%s begin
  if (a) begin q = a; end
  else begin
    case(a)
      1'b0: q = 0;
      default: q = 1;
    endcase
  end
end
B actual_instance();
endmodule
""" % header
                module = self.design(raw).modules["A"]
                scan.assert_not_called()
                self.assertEqual(module.driven, set())
                self.assertEqual([i.name for i in module.instances], ["actual_instance"])
                self.assertEqual(module.text, raw)

    def test_multiline_comments_and_functionlike_macro_width(self):
        raw = ("module A(\r\n"
               " input /* input declarations */ logic signed\r\n"
               " [`WIDTH(2)-1:0][1:0] // retained dimensions\r\n"
               " a /* memory */ [0:`N-1],\r\n"
               " b [0:`N-1] /* grouped port */\r\n"
               ");\r\nendmodule\r\n")
        module = self.design(raw).modules["A"]
        self.assertEqual(module.ports["b"].width, "[`WIDTH(2)-1:0][1:0]")
        self.assertEqual(module.ports["b"].unpacked, "[0:`N-1]")
        self.assertTrue(module.ports["b"].signed)
        self.assertEqual(module.text, raw)

    def test_unbracketed_macro_type_alias_is_flagged(self):
        module = self.design("module A(input `WIDTH_RANGE value); endmodule").modules["A"]
        self.assertTrue(module.ports["value"].unsupported)


if __name__ == "__main__":
    unittest.main()
