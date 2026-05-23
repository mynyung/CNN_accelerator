`timescale 1ns / 1ps

module MMU_CONV1_8OC #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32,
    parameter OUT_CH = 8,
    parameter K_NUM  = 9
)(
    input  wire clk,
    input  wire resetn,
    input  wire valid_in,

    // 9 pixels: 3x3 input window
    input  wire signed [K_NUM*DATA_W-1:0] data_vec,

    // 8 output channels x 9 weights
    input  wire signed [OUT_CH*K_NUM*DATA_W-1:0] weight_vec,

    output reg  valid_out,
    output reg  signed [OUT_CH*ACC_W-1:0] acc_vec
);

    localparam NUM_MACS = OUT_CH * K_NUM; // 8 * 9 = 72

    wire signed [DATA_W-1:0] data_lane   [0:K_NUM-1];
    wire signed [DATA_W-1:0] weight_lane [0:OUT_CH-1][0:K_NUM-1];
    wire signed [ACC_W-1:0]  product     [0:OUT_CH-1][0:K_NUM-1];

    genvar oc, k;

    generate
        for (k = 0; k < K_NUM; k = k + 1) begin : DATA_UNPACK
            assign data_lane[k] = data_vec[k*DATA_W +: DATA_W];
        end
    endgenerate

    generate
        for (oc = 0; oc < OUT_CH; oc = oc + 1) begin : OC_MACS
            for (k = 0; k < K_NUM; k = k + 1) begin : K_MACS
                assign weight_lane[oc][k] =
                    weight_vec[(oc*K_NUM + k)*DATA_W +: DATA_W];

                MAC #(
                    .DATA_W(DATA_W),
                    .ACC_W (ACC_W)
                ) u_mac (
                    .data_in     (data_lane[k]),
                    .weight_in   (weight_lane[oc][k]),
                    .product_out (product[oc][k])
                );
            end
        end
    endgenerate

    // Per-output-channel adder tree:
    // 9 products -> 5 -> 3 -> 1
    reg signed [ACC_W-1:0] s1 [0:OUT_CH-1][0:4];
    reg signed [ACC_W-1:0] s2 [0:OUT_CH-1][0:2];
    reg signed [ACC_W-1:0] s3 [0:OUT_CH-1];

    reg v1, v2, v3;

    integer i;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            valid_out <= 1'b0;
            acc_vec   <= {(OUT_CH*ACC_W){1'b0}};

            v1 <= 1'b0;
            v2 <= 1'b0;
            v3 <= 1'b0;

            for (i = 0; i < OUT_CH; i = i + 1) begin
                s1[i][0] <= {ACC_W{1'b0}};
                s1[i][1] <= {ACC_W{1'b0}};
                s1[i][2] <= {ACC_W{1'b0}};
                s1[i][3] <= {ACC_W{1'b0}};
                s1[i][4] <= {ACC_W{1'b0}};

                s2[i][0] <= {ACC_W{1'b0}};
                s2[i][1] <= {ACC_W{1'b0}};
                s2[i][2] <= {ACC_W{1'b0}};

                s3[i]    <= {ACC_W{1'b0}};
            end

        end else begin
            v1 <= valid_in;
            v2 <= v1;
            v3 <= v2;

            valid_out <= v3;

            // Stage 1: 9 -> 5
            if (valid_in) begin
                for (i = 0; i < OUT_CH; i = i + 1) begin
                    s1[i][0] <= product[i][0] + product[i][1];
                    s1[i][1] <= product[i][2] + product[i][3];
                    s1[i][2] <= product[i][4] + product[i][5];
                    s1[i][3] <= product[i][6] + product[i][7];
                    s1[i][4] <= product[i][8];
                end
            end

            // Stage 2: 5 -> 3
            if (v1) begin
                for (i = 0; i < OUT_CH; i = i + 1) begin
                    s2[i][0] <= s1[i][0] + s1[i][1];
                    s2[i][1] <= s1[i][2] + s1[i][3];
                    s2[i][2] <= s1[i][4];
                end
            end

            // Stage 3: 3 -> 1
            if (v2) begin
                for (i = 0; i < OUT_CH; i = i + 1) begin
                    s3[i] <= s2[i][0] + s2[i][1] + s2[i][2];
                end
            end

            // Output register
            if (v3) begin
                for (i = 0; i < OUT_CH; i = i + 1) begin
                    acc_vec[i*ACC_W +: ACC_W] <= s3[i];
                end
            end
        end
    end

endmodule