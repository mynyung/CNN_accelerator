`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/17/2026 10:13:45 PM
// Design Name: 
// Module Name: quant_relu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module quant_relu #(
    parameter IN_W  = 32,
    parameter OUT_W = 8,
    parameter SHIFT = 10
)(
    input  wire signed [IN_W-1:0]  in_data,
    output reg  signed [OUT_W-1:0] out_data
);

    reg signed [IN_W-1:0] shifted;
    reg signed [OUT_W-1:0] saturated;

    always @(*) begin
        shifted = in_data >>> SHIFT;

        if (shifted > 32'sd127)
            saturated = 8'sd127;
        else if (shifted < -32'sd128)
            saturated = -8'sd128;
        else
            saturated = shifted[7:0];

        // ReLU
        if (saturated < 0)
            out_data = 8'sd0;
        else
            out_data = saturated;
    end

endmodule