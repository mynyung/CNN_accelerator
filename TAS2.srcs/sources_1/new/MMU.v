`timescale 1ns / 1ps

module MMU #(
    parameter DATA_W   = 8,
    parameter ACC_W    = 32,
    parameter NUM_MACS = 36
)(
    input  wire clk,
    input  wire resetn,
    input  wire valid_in,

    input  wire signed [NUM_MACS*DATA_W-1:0] data_vec,
    input  wire signed [NUM_MACS*DATA_W-1:0] weight_vec,
    input  wire signed [ACC_W-1:0] partial_sum_in,

    output reg  valid_out,
    output reg  signed [ACC_W-1:0] partial_sum_out
);

    wire signed [ACC_W-1:0] product [0:NUM_MACS-1];

    genvar i;
    generate
        for (i = 0; i < NUM_MACS; i = i + 1) begin : MAC_ARRAY
            MAC #(
                .DATA_W(DATA_W),
                .ACC_W(ACC_W)
            ) u_mac (
                .data_in     (data_vec[i*DATA_W +: DATA_W]),
                .weight_in   (weight_vec[i*DATA_W +: DATA_W]),
                .product_out (product[i])
            );
        end
    endgenerate

    reg signed [ACC_W-1:0] s1 [0:17];
    reg signed [ACC_W-1:0] s2 [0:8];
    reg signed [ACC_W-1:0] s3 [0:4];
    reg signed [ACC_W-1:0] s4 [0:2];
    reg signed [ACC_W-1:0] s5;

    reg signed [ACC_W-1:0] ps_d1;
    reg signed [ACC_W-1:0] ps_d2;
    reg signed [ACC_W-1:0] ps_d3;
    reg signed [ACC_W-1:0] ps_d4;
    reg signed [ACC_W-1:0] ps_d5;

    reg v1, v2, v3, v4, v5;

    integer j;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            valid_out       <= 1'b0;
            partial_sum_out <= {ACC_W{1'b0}};

            v1 <= 1'b0;
            v2 <= 1'b0;
            v3 <= 1'b0;
            v4 <= 1'b0;
            v5 <= 1'b0;

            ps_d1 <= {ACC_W{1'b0}};
            ps_d2 <= {ACC_W{1'b0}};
            ps_d3 <= {ACC_W{1'b0}};
            ps_d4 <= {ACC_W{1'b0}};
            ps_d5 <= {ACC_W{1'b0}};

            for (j = 0; j < 18; j = j + 1)
                s1[j] <= {ACC_W{1'b0}};

            for (j = 0; j < 9; j = j + 1)
                s2[j] <= {ACC_W{1'b0}};

            for (j = 0; j < 5; j = j + 1)
                s3[j] <= {ACC_W{1'b0}};

            for (j = 0; j < 3; j = j + 1)
                s4[j] <= {ACC_W{1'b0}};

            s5 <= {ACC_W{1'b0}};

        end else begin
            // valid pipeline always moves
            v1 <= valid_in;
            v2 <= v1;
            v3 <= v2;
            v4 <= v3;
            v5 <= v4;

            valid_out <= v5;

            // stage 1: 36 -> 18
            if (valid_in) begin
                for (j = 0; j < 18; j = j + 1) begin
                    s1[j] <= product[2*j] + product[2*j + 1];
                end
                ps_d1 <= partial_sum_in;
            end

            // stage 2: 18 -> 9
            if (v1) begin
                for (j = 0; j < 9; j = j + 1) begin
                    s2[j] <= s1[2*j] + s1[2*j + 1];
                end
                ps_d2 <= ps_d1;
            end

            // stage 3: 9 -> 5
            if (v2) begin
                s3[0] <= s2[0] + s2[1];
                s3[1] <= s2[2] + s2[3];
                s3[2] <= s2[4] + s2[5];
                s3[3] <= s2[6] + s2[7];
                s3[4] <= s2[8];
                ps_d3 <= ps_d2;
            end

            // stage 4: 5 -> 3
            if (v3) begin
                s4[0] <= s3[0] + s3[1];
                s4[1] <= s3[2] + s3[3];
                s4[2] <= s3[4];
                ps_d4 <= ps_d3;
            end

            // stage 5: 3 -> 1
            if (v4) begin
                s5    <= s4[0] + s4[1] + s4[2];
                ps_d5 <= ps_d4;
            end

            // final
            if (v5) begin
                partial_sum_out <= ps_d5 + s5;
            end
        end
    end

endmodule