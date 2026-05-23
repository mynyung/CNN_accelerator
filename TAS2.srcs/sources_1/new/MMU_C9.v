`timescale 1ns / 1ps

module MMU_C9 #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire signed [9*DATA_W-1:0] data_vec,
    input  wire signed [9*DATA_W-1:0] weight_vec,
    input  wire signed [ACC_W-1:0] partial_sum_in,
    output wire signed [ACC_W-1:0] partial_sum_out
);

    wire signed [DATA_W-1:0] d0 = data_vec[0*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] d1 = data_vec[1*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] d2 = data_vec[2*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] d3 = data_vec[3*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] d4 = data_vec[4*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] d5 = data_vec[5*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] d6 = data_vec[6*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] d7 = data_vec[7*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] d8 = data_vec[8*DATA_W +: DATA_W];

    wire signed [DATA_W-1:0] w0 = weight_vec[0*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] w1 = weight_vec[1*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] w2 = weight_vec[2*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] w3 = weight_vec[3*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] w4 = weight_vec[4*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] w5 = weight_vec[5*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] w6 = weight_vec[6*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] w7 = weight_vec[7*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0] w8 = weight_vec[8*DATA_W +: DATA_W];

    wire signed [ACC_W-1:0] p0 = d0 * w0;
    wire signed [ACC_W-1:0] p1 = d1 * w1;
    wire signed [ACC_W-1:0] p2 = d2 * w2;
    wire signed [ACC_W-1:0] p3 = d3 * w3;
    wire signed [ACC_W-1:0] p4 = d4 * w4;
    wire signed [ACC_W-1:0] p5 = d5 * w5;
    wire signed [ACC_W-1:0] p6 = d6 * w6;
    wire signed [ACC_W-1:0] p7 = d7 * w7;
    wire signed [ACC_W-1:0] p8 = d8 * w8;

    assign partial_sum_out = partial_sum_in
                           + p0 + p1 + p2
                           + p3 + p4 + p5
                           + p6 + p7 + p8;

endmodule