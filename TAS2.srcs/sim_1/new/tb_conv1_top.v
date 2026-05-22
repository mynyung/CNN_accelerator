`timescale 1ns / 1ps

module tb_top;

    reg clk;
    reg resetn;
    reg start;
    wire done;

    // image_mem external port
    reg        image_ena;
    reg        image_wea;
    reg [9:0]  image_addra;
    reg [7:0]  image_dina;
    wire [7:0] image_douta;

    // conv1_w_mem external port
    reg        w1_ena;
    reg        w1_wea;
    reg [6:0]  w1_addra;
    reg [7:0]  w1_dina;
    wire [7:0] w1_douta;

    // conv2_w_mem external port
    reg        w2_ena;
    reg        w2_wea;
    reg [10:0] w2_addra;
    reg [7:0]  w2_dina;
    wire [7:0] w2_douta;

    // fm2_mem external port
    reg        fm2_ena;
    reg        fm2_wea;
    reg [13:0] fm2_addra;
    reg [7:0]  fm2_dina;
    wire [7:0] fm2_douta;

    // pool_mem external port
    reg  [11:0] pool_ext_addr;
    wire [7:0]  pool_ext_dout;

    // fc_w_mem external port
    reg        fc_w_ena;
    reg        fc_w_wea;
    reg [14:0] fc_w_addra;
    reg [7:0]  fc_w_dina;
    wire [7:0] fc_w_douta;

    // fc_out_mem external port
    reg  [3:0]  fc_out_ext_addr;
    wire [31:0] fc_out_ext_dout;

    // Test data arrays
    reg [7:0]  image_data      [0:783];
    reg [7:0]  w1_data         [0:71];
    reg [7:0]  w2_data         [0:1151];
    reg [7:0]  expected_pool   [0:2303];
    reg [7:0]  expected_fm2    [0:9215];
    reg [7:0]  expected_fc_w   [0:23039];
    reg [31:0] expected_fc_out [0:9];

    integer i;
    integer error_count;

    wire [3:0] predicted_digit;
    wire signed [31:0] max_logit;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    cnn_core dut (
        .clk    (clk),
        .resetn (resetn),
        .start  (start),
        .done   (done),

        .image_clka  (clk),
        .image_ena   (image_ena),
        .image_wea   (image_wea),
        .image_addra (image_addra),
        .image_dina  (image_dina),
        .image_douta (image_douta),

        .w1_clka  (clk),
        .w1_ena   (w1_ena),
        .w1_wea   (w1_wea),
        .w1_addra (w1_addra),
        .w1_dina  (w1_dina),
        .w1_douta (w1_douta),

        .w2_clka  (clk),
        .w2_ena   (w2_ena),
        .w2_wea   (w2_wea),
        .w2_addra (w2_addra),
        .w2_dina  (w2_dina),
        .w2_douta (w2_douta),

        .fm2_clka  (clk),
        .fm2_ena   (fm2_ena),
        .fm2_wea   (fm2_wea),
        .fm2_addra (fm2_addra),
        .fm2_dina  (fm2_dina),
        .fm2_douta (fm2_douta),

        .pool_ext_addr (pool_ext_addr),
        .pool_ext_dout (pool_ext_dout),

        .fc_w_clka  (clk),
        .fc_w_ena   (fc_w_ena),
        .fc_w_wea   (fc_w_wea),
        .fc_w_addra (fc_w_addra),
        .fc_w_dina  (fc_w_dina),
        .fc_w_douta (fc_w_douta),

        .fc_out_clka  (clk),
        .fc_out_ena   (1'b1),
        .fc_out_wea   (1'b0),
        .fc_out_addra (fc_out_ext_addr),
        .fc_out_dina  (32'd0),
        .fc_out_douta (fc_out_ext_dout),

        .predicted_digit(predicted_digit),
        .max_logit(max_logit)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Load hex files
        $readmemh("input_784.hex",          image_data);
        $readmemh("conv1_w_72.hex",        w1_data);
        $readmemh("conv2_w_1152.hex",      w2_data);
        $readmemh("expected_pool_2304.hex", expected_pool);
        $readmemh("expected_fm2_9216.hex",  expected_fm2);
        $readmemh("fc1_w_23040.hex",        expected_fc_w);
        $readmemh("output_10.hex",          expected_fc_out);

        // Initialize all signals
        resetn          = 1'b0;
        start           = 1'b0;

        image_ena       = 1'b0;
        image_wea       = 1'b0;
        image_addra     = 10'd0;
        image_dina      = 8'd0;

        w1_ena          = 1'b0;
        w1_wea          = 1'b0;
        w1_addra        = 7'd0;
        w1_dina         = 8'd0;

        w2_ena          = 1'b0;
        w2_wea          = 1'b0;
        w2_addra        = 11'd0;
        w2_dina         = 8'd0;

        fm2_ena         = 1'b0;
        fm2_wea         = 1'b0;
        fm2_addra       = 14'd0;
        fm2_dina        = 8'd0;

        pool_ext_addr   = 12'd0;

        fc_w_ena        = 1'b0;
        fc_w_wea        = 1'b0;
        fc_w_addra      = 15'd0;
        fc_w_dina       = 8'd0;

        fc_out_ext_addr = 4'd0;
        error_count     = 0;

        // Reset pulse
        repeat(10) @(posedge clk);
        resetn = 1'b1;
        repeat(5) @(posedge clk);

        // ------------------------------------------------------------
        // Load image_mem
        // ------------------------------------------------------------
        $display("[%0t] Loading image_mem: 784 values...", $time);
        for (i = 0; i < 784; i = i + 1) begin
            @(posedge clk);
            image_ena   <= 1'b1;
            image_wea   <= 1'b1;
            image_addra <= i[9:0];
            image_dina  <= image_data[i];
        end

        @(posedge clk);
        image_ena   <= 1'b0;
        image_wea   <= 1'b0;
        image_addra <= 10'd0;
        image_dina  <= 8'd0;
        repeat(2) @(posedge clk);

        // ------------------------------------------------------------
        // Load conv1_w_mem
        // ------------------------------------------------------------
        $display("[%0t] Loading conv1_w_mem: 72 values...", $time);
        for (i = 0; i < 72; i = i + 1) begin
            @(posedge clk);
            w1_ena   <= 1'b1;
            w1_wea   <= 1'b1;
            w1_addra <= i[6:0];
            w1_dina  <= w1_data[i];
        end

        @(posedge clk);
        w1_ena   <= 1'b0;
        w1_wea   <= 1'b0;
        w1_addra <= 7'd0;
        w1_dina  <= 8'd0;
        repeat(2) @(posedge clk);

        // ------------------------------------------------------------
        // Load conv2_w_mem
        // ------------------------------------------------------------
        $display("[%0t] Loading conv2_w_mem: 1152 values...", $time);
        for (i = 0; i < 1152; i = i + 1) begin
            @(posedge clk);
            w2_ena   <= 1'b1;
            w2_wea   <= 1'b1;
            w2_addra <= i[10:0];
            w2_dina  <= w2_data[i];
        end

        @(posedge clk);
        w2_ena   <= 1'b0;
        w2_wea   <= 1'b0;
        w2_addra <= 11'd0;
        w2_dina  <= 8'd0;
        repeat(2) @(posedge clk);

        // ------------------------------------------------------------
        // Load fc_w_mem
        // ------------------------------------------------------------
        $display("[%0t] Loading fc_w_mem: 23040 values...", $time);
        for (i = 0; i < 23040; i = i + 1) begin
            @(posedge clk);
            fc_w_ena   <= 1'b1;
            fc_w_wea   <= 1'b1;
            fc_w_addra <= i[14:0];
            fc_w_dina  <= expected_fc_w[i];
        end

        @(posedge clk);
        fc_w_ena   <= 1'b0;
        fc_w_wea   <= 1'b0;
        fc_w_addra <= 15'd0;
        fc_w_dina  <= 8'd0;
        repeat(5) @(posedge clk);

        // ------------------------------------------------------------
        // Start pipeline
        // ------------------------------------------------------------
        $display("[%0t] Starting pipeline: Conv1->Conv2->MaxPool->FC...", $time);
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait(done == 1'b1);
        $display("[%0t] Pipeline done.", $time);

        repeat(20) @(posedge clk);

        // ------------------------------------------------------------
        // Debug FC output
        // ------------------------------------------------------------
        $display("[%0t] DEBUG: raw fc_out_mem probe...", $time);

        fc_out_ext_addr = 4'd0;
        repeat(4) @(posedge clk); #1;
        $display("  DEBUG fc_out_mem[0] = 0x%08h (%0d)",
                 fc_out_ext_dout, $signed(fc_out_ext_dout));

        fc_out_ext_addr = 4'd1;
        repeat(4) @(posedge clk); #1;
        $display("  DEBUG fc_out_mem[1] = 0x%08h (%0d)",
                 fc_out_ext_dout, $signed(fc_out_ext_dout));

        fc_out_ext_addr = 4'd2;
        repeat(4) @(posedge clk); #1;
        $display("  DEBUG fc_out_mem[2] = 0x%08h (%0d)",
                 fc_out_ext_dout, $signed(fc_out_ext_dout));

        fc_out_ext_addr = 4'd3;
        repeat(4) @(posedge clk); #1;
        $display("  DEBUG fc_out_mem[3] = 0x%08h (%0d)",
                 fc_out_ext_dout, $signed(fc_out_ext_dout));

        // ------------------------------------------------------------
        // Check FC output logits
        // ------------------------------------------------------------
        $display("[%0t] Checking final output.npy logits...", $time);
        error_count = 0;

        for (i = 0; i < 10; i = i + 1) begin
            check_fc_out(i[3:0], expected_fc_out[i]);
        end

        $display("========================================");
        $display("Predicted digit = %0d", predicted_digit);
        $display("Max logit       = %0d (0x%08h)", max_logit, max_logit);
        $display("========================================");

        if (error_count == 0) begin
            $display("========================================");
            $display("TEST PASSED: all 10 FC logits correct.");
            $display("========================================");
        end else begin
            $display("========================================");
            $display("TEST FAILED: %0d errors.", error_count);
            $display("========================================");
        end

        repeat(10) @(posedge clk);
        $stop;
    end

    // -------------------------------------------------------------------------
    // FC output check task
    // -------------------------------------------------------------------------
    task check_fc_out;
        input [3:0]  addr;
        input [31:0] expected;
        reg   [31:0] got;
        begin
            @(posedge clk);
            fc_out_ext_addr = addr;

            @(posedge clk);
            @(posedge clk);
            #1;

            got = fc_out_ext_dout;

            if (got !== expected) begin
                $display("FAIL FC_OUT[%0d]: got %0d (0x%08h), expected %0d (0x%08h)",
                         addr, $signed(got), got, $signed(expected), expected);
                error_count = error_count + 1;
            end else begin
                $display("PASS FC_OUT[%0d]: got %0d (0x%08h), expected %0d (0x%08h)",
                         addr, $signed(got), got, $signed(expected), expected);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Latency counter
    // -------------------------------------------------------------------------
    integer latency_cycles;
    reg     counting;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            latency_cycles <= 0;
            counting       <= 1'b0;
        end else begin
            if (start) begin
                latency_cycles <= 0;
                counting       <= 1'b1;
            end else if (counting && !done) begin
                latency_cycles <= latency_cycles + 1;
            end else if (counting && done) begin
                counting <= 1'b0;
                $display("Latency = %0d cycles", latency_cycles);
                $display("At 100 MHz = %.2f us / %.5f ms",
                         latency_cycles * 0.01,
                         latency_cycles * 0.00001);
            end
        end
    end

endmodule