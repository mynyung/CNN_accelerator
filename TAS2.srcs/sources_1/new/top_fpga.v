`timescale 1ns / 1ps

module cnn_core_wrapper (
    input  wire clk,
    input  wire resetn,
    input  wire start,
    output wire done,
    output wire [3:0]  predicted_digit,
    output wire signed [31:0] max_logit
);

    // -----------------------------------------------------------------------
    // Stub signals for BRAM Port A connections
    // (will be driven by AXI BRAM Controllers in final block design)
    // -----------------------------------------------------------------------

    // image_mem Port A stubs
    wire        image_ena   = 1'b0;
    wire        image_wea   = 1'b0;
    wire [9:0]  image_addra = 10'd0;
    wire [7:0]  image_dina  = 8'd0;
    wire [7:0]  image_douta;

    // conv1_w_mem Port A stubs
    wire        w1_ena   = 1'b0;
    wire        w1_wea   = 1'b0;
    wire [6:0]  w1_addra = 7'd0;
    wire [7:0]  w1_dina  = 8'd0;
    wire [7:0]  w1_douta;

    // conv2_w_mem Port A stubs
    wire        w2_ena   = 1'b0;
    wire        w2_wea   = 1'b0;
    wire [10:0] w2_addra = 11'd0;
    wire [7:0]  w2_dina  = 8'd0;
    wire [7:0]  w2_douta;

    // fm2_mem Port A stubs
    wire        fm2_ena   = 1'b0;
    wire        fm2_wea   = 1'b0;
    wire [13:0] fm2_addra = 14'd0;
    wire [7:0]  fm2_dina  = 8'd0;
    wire [7:0]  fm2_douta;

    // pool_mem external readback stubs
    wire [11:0] pool_ext_addr = 12'd0;
    wire [7:0]  pool_ext_dout;

    // fc_w_mem Port A stubs
    wire        fc_w_ena   = 1'b0;
    wire        fc_w_wea   = 1'b0;
    wire [14:0] fc_w_addra = 15'd0;
    wire [7:0]  fc_w_dina  = 8'd0;
    wire [7:0]  fc_w_douta;

    // fc_out_mem Port A stubs
    wire        fc_out_ena   = 1'b1;
    wire        fc_out_wea   = 1'b0;
    wire [3:0]  fc_out_addra = 4'd0;
    wire [31:0] fc_out_dina  = 32'd0;
    wire [31:0] fc_out_douta;

    // -----------------------------------------------------------------------
    // Instantiate cnn_core
    // -----------------------------------------------------------------------
    cnn_core u_cnn_core (
        .clk      (clk),
        .resetn   (resetn),
        .start    (start),
        .done     (done),

        // image_mem external port
        .image_clka  (clk),
        .image_ena   (image_ena),
        .image_wea   (image_wea),
        .image_addra (image_addra),
        .image_dina  (image_dina),
        .image_douta (image_douta),

        // conv1_w_mem external port
        .w1_clka  (clk),
        .w1_ena   (w1_ena),
        .w1_wea   (w1_wea),
        .w1_addra (w1_addra),
        .w1_dina  (w1_dina),
        .w1_douta (w1_douta),

        // conv2_w_mem external port
        .w2_clka  (clk),
        .w2_ena   (w2_ena),
        .w2_wea   (w2_wea),
        .w2_addra (w2_addra),
        .w2_dina  (w2_dina),
        .w2_douta (w2_douta),

        // fm2_mem external port
        .fm2_clka  (clk),
        .fm2_ena   (fm2_ena),
        .fm2_wea   (fm2_wea),
        .fm2_addra (fm2_addra),
        .fm2_dina  (fm2_dina),
        .fm2_douta (fm2_douta),

        // pool_mem external readback port
        .pool_ext_addr (pool_ext_addr),
        .pool_ext_dout (pool_ext_dout),

        // fc_w_mem external port
        .fc_w_clka  (clk),
        .fc_w_ena   (fc_w_ena),
        .fc_w_wea   (fc_w_wea),
        .fc_w_addra (fc_w_addra),
        .fc_w_dina  (fc_w_dina),
        .fc_w_douta (fc_w_douta),

        // fc_out_mem external port
        .fc_out_clka  (clk),
        .fc_out_ena   (fc_out_ena),
        .fc_out_wea   (fc_out_wea),
        .fc_out_addra (fc_out_addra),
        .fc_out_dina  (fc_out_dina),
        .fc_out_douta (fc_out_douta),

        .predicted_digit (predicted_digit),
        .max_logit       (max_logit)
    );

endmodule