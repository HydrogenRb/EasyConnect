`ifdef FLAG
module TOP(input clk); endmodule
`elsif OTHER
module TOP(input other); endmodule
`else
module TOP; endmodule
`endif
