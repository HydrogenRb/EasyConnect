`include "defs.vh"

module top (
    input wire clk,
    input wire [`LANES-1:0] lane_enable,
    input wire [`DATA_W-1:0][1:0] lane_data [0:`LANES-1][0:`ROWS-1][0:`COLS-1]
);
    for (genvar i = 0; i < `LANES; i++) begin : g_lane
        lane U_LANE (.clk(clk));
    end
endmodule

module lane (input wire clk);
    wire enable;
    wire [`DATA_W-1:0][1:0] payload [0:`ROWS-1][0:`COLS-1];
    // EasyConnect routes to these existing, currently undriven internal signals.
endmodule
