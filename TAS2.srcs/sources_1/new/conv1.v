`timescale 1ns / 1ps

module conv1(
    input wire clk,
    input wire resetn,
    input wire start,
    output reg done,

    // image_mem read port
    output reg  [9:0] img_addr,
    input  wire signed [7:0] img_dout,

    // conv1 weight memory read port
    output reg  [6:0] w_addr,
    input  wire signed [7:0] w_dout,

    // fm1 output memory write port
    output reg  [9:0] fm1_addr,
    output reg  signed [7:0] fm1_din,
    output reg  fm1_we,

    output reg  [2:0] fm1_ch_sel
);

    localparam IMG_W  = 28;
    localparam IMG_H  = 28;
    localparam OUT_W  = 26;
    localparam OUT_H  = 26;
    localparam OUT_CH = 8;
    localparam K_NUM  = 9;

    localparam DATA_W = 8;
    localparam ACC_W  = 32;

    // ------------------------------------------------------------
    // Position counters
    // ------------------------------------------------------------
    reg [4:0] x;
    reg [4:0] y;

    reg [3:0] pix_k;
    reg [6:0] w_idx;
    reg [2:0] write_ch;

    // ------------------------------------------------------------
    // Local buffers
    // ------------------------------------------------------------
    reg signed [DATA_W-1:0] pix [0:K_NUM-1];
    reg signed [DATA_W-1:0] wt  [0:OUT_CH-1][0:K_NUM-1];

    reg signed [ACC_W-1:0] acc_buf [0:OUT_CH-1];

    wire signed [ACC_W-1:0] mmu_acc [0:OUT_CH-1];

    // ------------------------------------------------------------
    // Pack data_vec and weight_vec
    // ------------------------------------------------------------
    wire signed [K_NUM*DATA_W-1:0] data_vec;
    wire signed [OUT_CH*K_NUM*DATA_W-1:0] weight_vec;
    wire signed [OUT_CH*ACC_W-1:0] acc_vec;

    genvar gk, goc;

    generate
        for (gk = 0; gk < K_NUM; gk = gk + 1) begin : PACK_DATA
            assign data_vec[gk*DATA_W +: DATA_W] = pix[gk];
        end
    endgenerate

    generate
        for (goc = 0; goc < OUT_CH; goc = goc + 1) begin : PACK_WEIGHT_OC
            for (gk = 0; gk < K_NUM; gk = gk + 1) begin : PACK_WEIGHT_K
                assign weight_vec[(goc*K_NUM + gk)*DATA_W +: DATA_W] = wt[goc][gk];
            end
        end
    endgenerate

    generate
        for (goc = 0; goc < OUT_CH; goc = goc + 1) begin : UNPACK_ACC
            assign mmu_acc[goc] = acc_vec[goc*ACC_W +: ACC_W];
        end
    endgenerate

    // ------------------------------------------------------------
    // 72 MAC parallel MMU for conv1
    // ------------------------------------------------------------
    reg  mmu_valid_in;
    wire mmu_valid_out;

    MMU_CONV1_8OC #(
        .DATA_W(DATA_W),
        .ACC_W (ACC_W),
        .OUT_CH(OUT_CH),
        .K_NUM (K_NUM)
    ) u_mmu_conv1_8oc (
        .clk       (clk),
        .resetn    (resetn),
        .valid_in  (mmu_valid_in),
        .data_vec  (data_vec),
        .weight_vec(weight_vec),
        .valid_out (mmu_valid_out),
        .acc_vec   (acc_vec)
    );

    // ------------------------------------------------------------
    // Quant + ReLU
    // IMPORTANT:
    // quant_relu must use latched acc_buf, not raw mmu_acc.
    // ------------------------------------------------------------
    wire signed [7:0] q_relu_out [0:OUT_CH-1];

    generate
        for (goc = 0; goc < OUT_CH; goc = goc + 1) begin : Q_RELU_ARRAY
            quant_relu u_quant_relu (
                .in_data  (acc_buf[goc]),
                .out_data (q_relu_out[goc])
            );
        end
    endgenerate

    // ------------------------------------------------------------
    // Address calculation for input pixel
    // ------------------------------------------------------------
    reg [1:0] ky;
    reg [1:0] kx;

    always @(*) begin
        case (pix_k)
            4'd0: begin ky = 2'd0; kx = 2'd0; end
            4'd1: begin ky = 2'd0; kx = 2'd1; end
            4'd2: begin ky = 2'd0; kx = 2'd2; end
            4'd3: begin ky = 2'd1; kx = 2'd0; end
            4'd4: begin ky = 2'd1; kx = 2'd1; end
            4'd5: begin ky = 2'd1; kx = 2'd2; end
            4'd6: begin ky = 2'd2; kx = 2'd0; end
            4'd7: begin ky = 2'd2; kx = 2'd1; end
            4'd8: begin ky = 2'd2; kx = 2'd2; end
            default: begin ky = 2'd0; kx = 2'd0; end
        endcase
    end

    wire [9:0] img_addr_calc;
    wire [9:0] fm1_addr_calc;

    assign img_addr_calc = (y + ky) * IMG_W + (x + kx);
    assign fm1_addr_calc = y * OUT_W + x;

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    localparam S_IDLE          = 4'd0;

    localparam S_W_ADDR        = 4'd1;
    localparam S_W_WAIT        = 4'd2;
    localparam S_W_STORE       = 4'd3;

    localparam S_PIX_ADDR      = 4'd4;
    localparam S_PIX_WAIT      = 4'd5;
    localparam S_PIX_STORE     = 4'd6;

    localparam S_COMPUTE       = 4'd7;
    localparam S_COMPUTE_WAIT  = 4'd8;

    localparam S_WRITE_SETUP   = 4'd9;
    localparam S_WRITE_PULSE   = 4'd10;

    localparam S_NEXT          = 4'd11;
    localparam S_DONE          = 4'd12;

    reg [3:0] state;

    integer i;
    integer j;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state        <= S_IDLE;
            done         <= 1'b0;

            img_addr     <= 10'd0;
            w_addr       <= 7'd0;

            fm1_addr     <= 10'd0;
            fm1_din      <= 8'sd0;
            fm1_we       <= 1'b0;
            fm1_ch_sel   <= 3'd0;

            x            <= 5'd0;
            y            <= 5'd0;
            pix_k        <= 4'd0;
            w_idx        <= 7'd0;
            write_ch     <= 3'd0;

            mmu_valid_in <= 1'b0;

            for (i = 0; i < K_NUM; i = i + 1) begin
                pix[i] <= 8'sd0;
            end

            for (i = 0; i < OUT_CH; i = i + 1) begin
                acc_buf[i] <= 32'sd0;
                for (j = 0; j < K_NUM; j = j + 1) begin
                    wt[i][j] <= 8'sd0;
                end
            end

        end else begin
            case (state)

                // ------------------------------------------------
                // IDLE
                // ------------------------------------------------
                S_IDLE: begin
                    done         <= 1'b0;
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    x            <= 5'd0;
                    y            <= 5'd0;
                    pix_k        <= 4'd0;
                    w_idx        <= 7'd0;
                    write_ch     <= 3'd0;
                    fm1_ch_sel   <= 3'd0;

                    if (start) begin
                        state <= S_W_ADDR;
                    end
                end

                // ------------------------------------------------
                // Weight preload: 72 weights
                // Address order:
                // w_addr = oc * 9 + k
                // ------------------------------------------------
                S_W_ADDR: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    w_addr       <= w_idx;
                    state        <= S_W_WAIT;
                end

                S_W_WAIT: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    state        <= S_W_STORE;
                end

                S_W_STORE: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    wt[w_idx / K_NUM][w_idx % K_NUM] <= w_dout;

                    if (w_idx < OUT_CH*K_NUM - 1) begin
                        w_idx <= w_idx + 7'd1;
                        state <= S_W_ADDR;
                    end else begin
                        w_idx <= 7'd0;
                        pix_k <= 4'd0;
                        state <= S_PIX_ADDR;
                    end
                end

                // ------------------------------------------------
                // Load 3x3 input pixels for current x,y
                // ------------------------------------------------
                S_PIX_ADDR: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    img_addr     <= img_addr_calc;
                    state        <= S_PIX_WAIT;
                end

                S_PIX_WAIT: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    state        <= S_PIX_STORE;
                end

                S_PIX_STORE: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    pix[pix_k] <= img_dout;

                    if (pix_k < K_NUM - 1) begin
                        pix_k <= pix_k + 4'd1;
                        state <= S_PIX_ADDR;
                    end else begin
                        pix_k <= 4'd0;
                        state <= S_COMPUTE;
                    end
                end

                // ------------------------------------------------
                // Compute 8 output channels in parallel
                // ------------------------------------------------
                S_COMPUTE: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b1;

                    state        <= S_COMPUTE_WAIT;
                end

                S_COMPUTE_WAIT: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    if (mmu_valid_out) begin
                        for (i = 0; i < OUT_CH; i = i + 1) begin
                            acc_buf[i] <= mmu_acc[i];
                        end

                        write_ch   <= 3'd0;
                        fm1_ch_sel <= 3'd0;
                        state      <= S_WRITE_SETUP;
                    end
                end

                // ------------------------------------------------
                // Setup write signals first.
                // fm1_we is still 0 here.
                // This gives fm1_addr, fm1_din, fm1_ch_sel one full cycle
                // to become stable before the actual write pulse.
                // ------------------------------------------------
                S_WRITE_SETUP: begin
                    mmu_valid_in <= 1'b0;
                    fm1_we       <= 1'b0;

                    fm1_addr     <= fm1_addr_calc;
                    fm1_din      <= q_relu_out[write_ch];
                    fm1_ch_sel   <= write_ch;

                    state        <= S_WRITE_PULSE;
                end

                // ------------------------------------------------
                // Actual write pulse.
                // Keep addr/din/ch stable while fm1_we is high.
                // ------------------------------------------------
                S_WRITE_PULSE: begin
                    mmu_valid_in <= 1'b0;
                    fm1_we       <= 1'b1;

                    if (write_ch < OUT_CH - 1) begin
                        write_ch <= write_ch + 3'd1;
                        state    <= S_WRITE_SETUP;
                    end else begin
                        write_ch <= 3'd0;
                        state    <= S_NEXT;
                    end
                end

                // ------------------------------------------------
                // Next spatial position
                // ------------------------------------------------
                S_NEXT: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    if (x < OUT_W - 1) begin
                        x     <= x + 5'd1;
                        pix_k <= 4'd0;
                        state <= S_PIX_ADDR;
                    end else if (y < OUT_H - 1) begin
                        x     <= 5'd0;
                        y     <= y + 5'd1;
                        pix_k <= 4'd0;
                        state <= S_PIX_ADDR;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done         <= 1'b1;
                    fm1_we       <= 1'b0;
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