// module FAKE; S fake(); endmodule
module TOP(input clk);
  /* S fake2(); */
  unknown U_BLACKBOX(.clk(clk));
  S #(.W(4)) U_ONE(.a({4{clk}})), U_TWO(.a(4'b0));
  for(genvar i=0; i<3; i=i+1) begin : g
    S U_LOOP[i](.a(8'b0));
  end
endmodule
