`timescale 1ns / 1ps

module conv2 #(
    parameter NUM_OC_PAR = 4,
    parameter NUM_IC_PAR = 4
)(
    input wire clk,
    input wire resetn,
    input wire start,
    output reg done,

    output wire [9:0]        fm1_addr0,
    output wire [9:0]        fm1_addr1,
    output wire [9:0]        fm1_addr2,
    output wire [9:0]        fm1_addr3,

    input wire signed [7:0]  fm1_dout0,
    input wire signed [7:0]  fm1_dout1,
    input wire signed [7:0]  fm1_dout2,
    input wire signed [7:0]  fm1_dout3,

    output wire              fm1_pass_sel,

    output reg  [10:0]       w_addr,
    input  wire signed [7:0] w_dout,

    output reg  [13:0]       fm2_addr,
    output reg  signed [7:0] fm2_din,
    output reg               fm2_we
);

    // -----------------------------------------------------------------------
    // Layer parameters
    // -----------------------------------------------------------------------
    localparam FM1_W  = 26;
    localparam FM1_H  = 26;

    localparam OUT_W  = 24;
    localparam OUT_H  = 24;

    localparam OUT_CH = 16;
    localparam IN_CH  = 8;

    localparam K_SIZE = 3;

    localparam FM1_CH_SIZE = FM1_W * FM1_H;
    localparam FM2_CH_SIZE = OUT_W * OUT_H;

    localparam NUM_MMU_MACS = NUM_IC_PAR * K_SIZE * K_SIZE; // 4*3*3 = 36
    localparam NUM_PASSES   = IN_CH / NUM_IC_PAR;           // 8/4 = 2
    localparam OC_GROUPS    = OUT_CH / NUM_OC_PAR;          // 16/4 = 4

    // pass = 0: fm1_ch0~3
    // pass = 1: fm1_ch4~7
    assign fm1_pass_sel = pass[0];

    // -----------------------------------------------------------------------
    // Weight buffer
    // w_all[output_channel][input_channel*9 + kernel_index]
    // -----------------------------------------------------------------------
    reg signed [7:0] w_all [0:OUT_CH-1][0:71];

    reg [6:0] w_load_idx;
    reg [3:0] w_load_oc;

    // -----------------------------------------------------------------------
    // Loop variables
    // -----------------------------------------------------------------------
    reg [3:0] oc_base;      // 0, 4, 8, 12
    reg [4:0] x;            // 0 ~ 23
    reg [4:0] y;            // 0 ~ 23
    reg [1:0] pass;         // 0 ~ 1

    // -----------------------------------------------------------------------
    // Pixel and weight staging
    // -----------------------------------------------------------------------
    reg signed [7:0] pix [0:NUM_MMU_MACS-1];
    reg signed [7:0] wt  [0:NUM_OC_PAR-1][0:NUM_MMU_MACS-1];

    reg signed [31:0] partial_sum [0:NUM_OC_PAR-1];
    reg signed [7:0]  conv_out    [0:NUM_OC_PAR-1];

    // -----------------------------------------------------------------------
    // Pack data_vec
    // -----------------------------------------------------------------------
    wire signed [8*NUM_MMU_MACS-1:0] data_vec;

    genvar pi;
    generate
        for (pi = 0; pi < NUM_MMU_MACS; pi = pi + 1) begin : PACK_DATA
            assign data_vec[pi*8 +: 8] = pix[pi];
        end
    endgenerate

    // -----------------------------------------------------------------------
    // MMU instances
    // -----------------------------------------------------------------------
    wire signed [8*NUM_MMU_MACS-1:0] weight_vec [0:NUM_OC_PAR-1];
    wire signed [31:0]               mmu_acc    [0:NUM_OC_PAR-1];

    reg mmu_valid_in;
    wire [NUM_OC_PAR-1:0] mmu_valid_out;

    genvar oi, wi;
    generate
        for (oi = 0; oi < NUM_OC_PAR; oi = oi + 1) begin : OC_MMU

            for (wi = 0; wi < NUM_MMU_MACS; wi = wi + 1) begin : PACK_WEIGHT
                assign weight_vec[oi][wi*8 +: 8] = wt[oi][wi];
            end

            MMU #(
                .DATA_W(8),
                .ACC_W(32),
                .NUM_MACS(NUM_MMU_MACS)
            ) u_mmu (
                .clk             (clk),
                .resetn          (resetn),
                .valid_in        (mmu_valid_in),

                .data_vec        (data_vec),
                .weight_vec      (weight_vec[oi]),
                .partial_sum_in  (partial_sum[oi]),

                .valid_out       (mmu_valid_out[oi]),
                .partial_sum_out (mmu_acc[oi])
            );

        end
    endgenerate

    // -----------------------------------------------------------------------
    // quant_relu per output channel lane
    // -----------------------------------------------------------------------
    wire signed [7:0] q_relu_out [0:NUM_OC_PAR-1];

    genvar ri;
    generate
        for (ri = 0; ri < NUM_OC_PAR; ri = ri + 1) begin : RELU
            quant_relu u_qr (
                .in_data  (mmu_acc[ri]),
                .out_data (q_relu_out[ri])
            );
        end
    endgenerate

    // -----------------------------------------------------------------------
    // fm2 output address calculation
    // -----------------------------------------------------------------------
    wire [13:0] fm2_addr_calc [0:NUM_OC_PAR-1];

    genvar fi;
    generate
        for (fi = 0; fi < NUM_OC_PAR; fi = fi + 1) begin : FM2_ADDR
            assign fm2_addr_calc[fi] =
                (oc_base + fi) * FM2_CH_SIZE + y * OUT_W + x;
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Input channel index per pass
    // -----------------------------------------------------------------------
    wire [2:0] ic0_calc = pass * NUM_IC_PAR + 0;
    wire [2:0] ic1_calc = pass * NUM_IC_PAR + 1;
    wire [2:0] ic2_calc = pass * NUM_IC_PAR + 2;
    wire [2:0] ic3_calc = pass * NUM_IC_PAR + 3;

    // -----------------------------------------------------------------------
    // Line buffer / 3x3 window generator
    // -----------------------------------------------------------------------
    reg lb_start_reg;
    wire lb_busy;
    wire lb_done;
    wire [9:0] lb_rd_addr;

    assign fm1_addr0 = lb_rd_addr;
    assign fm1_addr1 = lb_rd_addr;
    assign fm1_addr2 = lb_rd_addr;
    assign fm1_addr3 = lb_rd_addr;

    wire signed [7:0] lb_w0_ch0, lb_w1_ch0, lb_w2_ch0;
    wire signed [7:0] lb_w3_ch0, lb_w4_ch0, lb_w5_ch0;
    wire signed [7:0] lb_w6_ch0, lb_w7_ch0, lb_w8_ch0;

    wire signed [7:0] lb_w0_ch1, lb_w1_ch1, lb_w2_ch1;
    wire signed [7:0] lb_w3_ch1, lb_w4_ch1, lb_w5_ch1;
    wire signed [7:0] lb_w6_ch1, lb_w7_ch1, lb_w8_ch1;

    wire signed [7:0] lb_w0_ch2, lb_w1_ch2, lb_w2_ch2;
    wire signed [7:0] lb_w3_ch2, lb_w4_ch2, lb_w5_ch2;
    wire signed [7:0] lb_w6_ch2, lb_w7_ch2, lb_w8_ch2;

    wire signed [7:0] lb_w0_ch3, lb_w1_ch3, lb_w2_ch3;
    wire signed [7:0] lb_w3_ch3, lb_w4_ch3, lb_w5_ch3;
    wire signed [7:0] lb_w6_ch3, lb_w7_ch3, lb_w8_ch3;

    linebuf3x3_4ch #(
        .DATA_W(8),
        .IMG_W(FM1_W),
        .OUT_W(OUT_W)
    ) u_linebuf3x3_4ch (
        .clk(clk),
        .resetn(resetn),

        .start(lb_start_reg),
        .base_y(y),

        .busy(lb_busy),
        .done(lb_done),

        .rd_addr(lb_rd_addr),

        .din0(fm1_dout0),
        .din1(fm1_dout1),
        .din2(fm1_dout2),
        .din3(fm1_dout3),

        .win_x(x),

        .w0_ch0(lb_w0_ch0), .w1_ch0(lb_w1_ch0), .w2_ch0(lb_w2_ch0),
        .w3_ch0(lb_w3_ch0), .w4_ch0(lb_w4_ch0), .w5_ch0(lb_w5_ch0),
        .w6_ch0(lb_w6_ch0), .w7_ch0(lb_w7_ch0), .w8_ch0(lb_w8_ch0),

        .w0_ch1(lb_w0_ch1), .w1_ch1(lb_w1_ch1), .w2_ch1(lb_w2_ch1),
        .w3_ch1(lb_w3_ch1), .w4_ch1(lb_w4_ch1), .w5_ch1(lb_w5_ch1),
        .w6_ch1(lb_w6_ch1), .w7_ch1(lb_w7_ch1), .w8_ch1(lb_w8_ch1),

        .w0_ch2(lb_w0_ch2), .w1_ch2(lb_w1_ch2), .w2_ch2(lb_w2_ch2),
        .w3_ch2(lb_w3_ch2), .w4_ch2(lb_w4_ch2), .w5_ch2(lb_w5_ch2),
        .w6_ch2(lb_w6_ch2), .w7_ch2(lb_w7_ch2), .w8_ch2(lb_w8_ch2),

        .w0_ch3(lb_w0_ch3), .w1_ch3(lb_w1_ch3), .w2_ch3(lb_w2_ch3),
        .w3_ch3(lb_w3_ch3), .w4_ch3(lb_w4_ch3), .w5_ch3(lb_w5_ch3),
        .w6_ch3(lb_w6_ch3), .w7_ch3(lb_w7_ch3), .w8_ch3(lb_w8_ch3)
    );

    // -----------------------------------------------------------------------
    // Convert line buffer outputs to lb_win[0:35]
    // -----------------------------------------------------------------------
    wire signed [7:0] lb_win [0:NUM_MMU_MACS-1];

    assign lb_win[0]  = lb_w0_ch0;
    assign lb_win[1]  = lb_w1_ch0;
    assign lb_win[2]  = lb_w2_ch0;
    assign lb_win[3]  = lb_w3_ch0;
    assign lb_win[4]  = lb_w4_ch0;
    assign lb_win[5]  = lb_w5_ch0;
    assign lb_win[6]  = lb_w6_ch0;
    assign lb_win[7]  = lb_w7_ch0;
    assign lb_win[8]  = lb_w8_ch0;

    assign lb_win[9]  = lb_w0_ch1;
    assign lb_win[10] = lb_w1_ch1;
    assign lb_win[11] = lb_w2_ch1;
    assign lb_win[12] = lb_w3_ch1;
    assign lb_win[13] = lb_w4_ch1;
    assign lb_win[14] = lb_w5_ch1;
    assign lb_win[15] = lb_w6_ch1;
    assign lb_win[16] = lb_w7_ch1;
    assign lb_win[17] = lb_w8_ch1;

    assign lb_win[18] = lb_w0_ch2;
    assign lb_win[19] = lb_w1_ch2;
    assign lb_win[20] = lb_w2_ch2;
    assign lb_win[21] = lb_w3_ch2;
    assign lb_win[22] = lb_w4_ch2;
    assign lb_win[23] = lb_w5_ch2;
    assign lb_win[24] = lb_w6_ch2;
    assign lb_win[25] = lb_w7_ch2;
    assign lb_win[26] = lb_w8_ch2;

    assign lb_win[27] = lb_w0_ch3;
    assign lb_win[28] = lb_w1_ch3;
    assign lb_win[29] = lb_w2_ch3;
    assign lb_win[30] = lb_w3_ch3;
    assign lb_win[31] = lb_w4_ch3;
    assign lb_win[32] = lb_w5_ch3;
    assign lb_win[33] = lb_w6_ch3;
    assign lb_win[34] = lb_w7_ch3;
    assign lb_win[35] = lb_w8_ch3;

    // -----------------------------------------------------------------------
    // Partial-sum buffer
    // -----------------------------------------------------------------------
    reg signed [31:0] psum_arr [0:OUT_W-1][0:NUM_OC_PAR-1];

    // -----------------------------------------------------------------------
    // FSM states
    // -----------------------------------------------------------------------
    localparam S_IDLE         = 4'd0;
    localparam S_LOAD_W_ADDR  = 4'd1;
    localparam S_WAIT_W       = 4'd2;
    localparam S_STORE_W      = 4'd3;
    localparam S_LB_START     = 4'd4;
    localparam S_LB_WAIT      = 4'd5;
    localparam S_LOAD_PIX     = 4'd6;
    localparam S_COMPUTE      = 4'd7;
    localparam S_COMPUTE_WAIT = 4'd8;
    localparam S_WRITE        = 4'd9;
    localparam S_DONE         = 4'd10;
    localparam S_PRELOAD_WT   = 4'd11;

    reg [3:0] state;
    reg [1:0] write_idx;

    integer i, j;

    // -----------------------------------------------------------------------
    // Main FSM
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state         <= S_IDLE;
            done          <= 1'b0;

            w_addr        <= 11'd0;

            fm2_addr      <= 14'd0;
            fm2_din       <= 8'sd0;
            fm2_we        <= 1'b0;

            oc_base       <= 4'd0;
            x             <= 5'd0;
            y             <= 5'd0;
            pass          <= 2'd0;

            write_idx     <= 2'd0;

            w_load_idx    <= 7'd0;
            w_load_oc     <= 4'd0;

            lb_start_reg  <= 1'b0;
            mmu_valid_in  <= 1'b0;

            for (i = 0; i < NUM_MMU_MACS; i = i + 1) begin
                pix[i] <= 8'sd0;
            end

            for (i = 0; i < NUM_OC_PAR; i = i + 1) begin
                partial_sum[i] <= 32'sd0;
                conv_out[i]    <= 8'sd0;

                for (j = 0; j < NUM_MMU_MACS; j = j + 1) begin
                    wt[i][j] <= 8'sd0;
                end
            end

            for (i = 0; i < OUT_W; i = i + 1) begin
                for (j = 0; j < NUM_OC_PAR; j = j + 1) begin
                    psum_arr[i][j] <= 32'sd0;
                end
            end

            for (i = 0; i < OUT_CH; i = i + 1) begin
                for (j = 0; j < 72; j = j + 1) begin
                    w_all[i][j] <= 8'sd0;
                end
            end

        end else begin
            case (state)

                // ----------------------------------------------------------
                // Wait for start
                // ----------------------------------------------------------
                S_IDLE: begin
                    done         <= 1'b0;
                    fm2_we       <= 1'b0;
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    oc_base      <= 4'd0;
                    x            <= 5'd0;
                    y            <= 5'd0;
                    pass         <= 2'd0;

                    for (i = 0; i < NUM_OC_PAR; i = i + 1) begin
                        partial_sum[i] <= 32'sd0;
                    end

                    if (start) begin
                        w_load_oc  <= 4'd0;
                        w_load_idx <= 7'd0;
                        w_addr     <= 11'd0;
                        state      <= S_WAIT_W;
                    end
                end

                // ----------------------------------------------------------
                // Weight load address
                // ----------------------------------------------------------
                S_LOAD_W_ADDR: begin
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;
                    fm2_we       <= 1'b0;

                    w_addr <= w_load_oc * 11'd72 + w_load_idx;
                    state  <= S_WAIT_W;
                end

                // ----------------------------------------------------------
                // Wait weight BRAM read latency
                // ----------------------------------------------------------
                S_WAIT_W: begin
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;
                    fm2_we       <= 1'b0;

                    state <= S_STORE_W;
                end

                // ----------------------------------------------------------
                // Store weight into full weight buffer
                // ----------------------------------------------------------
                S_STORE_W: begin
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;
                    fm2_we       <= 1'b0;

                    w_all[w_load_oc][w_load_idx] <= w_dout;

                    if (w_load_idx < 7'd71) begin
                        w_load_idx <= w_load_idx + 7'd1;
                        state      <= S_LOAD_W_ADDR;

                    end else if (w_load_oc < OUT_CH - 1) begin
                        w_load_oc  <= w_load_oc + 4'd1;
                        w_load_idx <= 7'd0;
                        state      <= S_LOAD_W_ADDR;

                    end else begin
                        w_load_oc  <= 4'd0;
                        w_load_idx <= 7'd0;

                        oc_base    <= 4'd0;
                        x          <= 5'd0;
                        y          <= 5'd0;
                        pass       <= 2'd0;

                        // Load the first OC/pass weight group only once.
                        state      <= S_PRELOAD_WT;
                    end
                end

                // ----------------------------------------------------------
                // Preload weights for current oc_base and pass.
                //
                // This state replaces repeated weight reload in S_LOAD_PIX.
                // wt is updated only when pass/oc_base changes,
                // not for every output x.
                // ----------------------------------------------------------
                S_PRELOAD_WT: begin
                    fm2_we       <= 1'b0;
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    for (i = 0; i < NUM_OC_PAR; i = i + 1) begin
                        for (j = 0; j < 9; j = j + 1) begin
                            wt[i][j]      <= w_all[oc_base + i][ic0_calc * 9 + j];
                            wt[i][j + 9]  <= w_all[oc_base + i][ic1_calc * 9 + j];
                            wt[i][j + 18] <= w_all[oc_base + i][ic2_calc * 9 + j];
                            wt[i][j + 27] <= w_all[oc_base + i][ic3_calc * 9 + j];
                        end
                    end

                    state <= S_LB_START;
                end

                // ----------------------------------------------------------
                // Load line buffer once per current y/pass.
                // ----------------------------------------------------------
                S_LB_START: begin
                    fm2_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;
                    lb_start_reg <= 1'b1;
                    state        <= S_LB_WAIT;
                end

                S_LB_WAIT: begin
                    fm2_we       <= 1'b0;
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    if (lb_done) begin
                        x     <= 5'd0;
                        state <= S_LOAD_PIX;
                    end
                end

                // ----------------------------------------------------------
                // Load only pixels and partial sum.
                // Weights are no longer reloaded here.
                // ----------------------------------------------------------
                S_LOAD_PIX: begin
                    fm2_we       <= 1'b0;
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    for (j = 0; j < NUM_MMU_MACS; j = j + 1) begin
                        pix[j] <= lb_win[j];
                    end

                    for (i = 0; i < NUM_OC_PAR; i = i + 1) begin
                        partial_sum[i] <= (pass == 2'd0) ? 32'sd0 : psum_arr[x][i];
                    end

                    state <= S_COMPUTE;
                end

                S_COMPUTE: begin
                    fm2_we       <= 1'b0;
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b1;
                    state        <= S_COMPUTE_WAIT;
                end

                S_COMPUTE_WAIT: begin
                    fm2_we       <= 1'b0;
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    if (mmu_valid_out[0]) begin
                        if (pass == 2'd0) begin
                            // Store pass-0 partial sums for this x.
                            for (i = 0; i < NUM_OC_PAR; i = i + 1) begin
                                psum_arr[x][i] <= mmu_acc[i];
                            end

                            if (x < OUT_W - 1) begin
                                x     <= x + 5'd1;
                                state <= S_LOAD_PIX;
                            end else begin
                                // Now load ch4~ch7 weights once and scan all x again.
                                x     <= 5'd0;
                                pass  <= 2'd1;
                                state <= S_PRELOAD_WT;
                            end

                        end else begin
                            // Final result for this x after pass 1.
                            for (i = 0; i < NUM_OC_PAR; i = i + 1) begin
                                conv_out[i] <= q_relu_out[i];
                            end

                            write_idx <= 2'd0;
                            state     <= S_WRITE;
                        end
                    end
                end

                // ----------------------------------------------------------
                // Write 4 output-channel lanes sequentially.
                // ----------------------------------------------------------
                S_WRITE: begin
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    fm2_addr <= fm2_addr_calc[write_idx];
                    fm2_din  <= conv_out[write_idx];
                    fm2_we   <= 1'b1;

                    if (write_idx < NUM_OC_PAR - 1) begin
                        write_idx <= write_idx + 2'd1;
                    end else begin
                        write_idx <= 2'd0;
                        fm2_we    <= 1'b1;

                        if (x < OUT_W - 1) begin
                            x     <= x + 5'd1;
                            state <= S_LOAD_PIX;

                        end else begin
                            // Finished pass 1 for this y and oc_group.
                            x    <= 5'd0;
                            pass <= 2'd0;

                            if (y < OUT_H - 1) begin
                                y     <= y + 5'd1;
                                state <= S_PRELOAD_WT;

                            end else if (oc_base < OUT_CH - NUM_OC_PAR) begin
                                y       <= 5'd0;
                                oc_base <= oc_base + NUM_OC_PAR;
                                state   <= S_PRELOAD_WT;

                            end else begin
                                state <= S_DONE;
                            end
                        end
                    end
                end

                S_DONE: begin
                    done         <= 1'b1;
                    fm2_we       <= 1'b0;
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;
                    state        <= S_DONE;
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule