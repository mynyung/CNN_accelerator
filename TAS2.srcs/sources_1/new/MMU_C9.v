module MAC #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire signed [DATA_W-1:0] data_in,
    input  wire signed [DATA_W-1:0] weight_in,
    output wire signed [ACC_W-1:0] product_out
);

    (* use_dsp = "yes" *) wire signed [(2*DATA_W)-1:0] mult_result;

    assign mult_result = data_in * weight_in;

    assign product_out =
        {{(ACC_W-(2*DATA_W)){mult_result[(2*DATA_W)-1]}}, mult_result};

endmodule