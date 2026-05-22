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

    output wire [2:0] fm1_ch_sel
);

    localparam IMG_W  = 28;
    localparam IMG_H  = 28;
    localparam OUT_W  = 26;
    localparam OUT_H  = 26;
    localparam OUT_CH = 8;
    localparam K_SIZE = 3;

    localparam MMU_MACS = 36;

    reg [2:0] oc;
    reg [4:0] x;
    reg [4:0] y;
    reg [3:0] k;

    reg signed [7:0] pix [0:8];
    reg signed [7:0] wt  [0:8];

    wire signed [MMU_MACS*8-1:0] data_vec;
    wire signed [MMU_MACS*8-1:0] weight_vec;
    wire signed [31:0]           mmu_acc;

    // conv1 uses only 3x3x1 = 9 valid MAC inputs.
    // The remaining 27 lanes are zero-padded so the same module name MMU can be used.
    assign data_vec = {
        216'd0,
        pix[8], pix[7], pix[6],
        pix[5], pix[4], pix[3],
        pix[2], pix[1], pix[0]
    };

    assign weight_vec = {
        216'd0,
        wt[8], wt[7], wt[6],
        wt[5], wt[4], wt[3],
        wt[2], wt[1], wt[0]
    };

    reg  mmu_valid_in;
    wire mmu_valid_out;

    MMU #(
        .DATA_W   (8),
        .ACC_W    (32),
        .NUM_MACS (MMU_MACS)
    ) u_mmu (
        .clk             (clk),
        .resetn          (resetn),
        .valid_in        (mmu_valid_in),
        .data_vec        (data_vec),
        .weight_vec      (weight_vec),
        .partial_sum_in  (32'sd0),
        .valid_out       (mmu_valid_out),
        .partial_sum_out (mmu_acc)
    );

    wire signed [7:0] q_relu_out;

    quant_relu u_quant_relu (
        .in_data  (mmu_acc),
        .out_data (q_relu_out)
    );

    localparam S_IDLE         = 4'd0;
    localparam S_LOAD_ADDR    = 4'd1;
    localparam S_WAIT_READ    = 4'd2;
    localparam S_STORE        = 4'd3;
    localparam S_COMPUTE      = 4'd4;
    localparam S_COMPUTE_WAIT = 4'd5;
    localparam S_WRITE        = 4'd6;
    localparam S_NEXT         = 4'd7;
    localparam S_DONE         = 4'd8;

    reg [3:0] state;

    reg [1:0] ky;
    reg [1:0] kx;

    always @(*) begin
        case (k)
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
    wire [6:0] w_addr_calc;
    wire [9:0] fm1_addr_calc;

    assign img_addr_calc = (y + ky) * IMG_W + (x + kx);
    assign w_addr_calc   = oc * 7'd9 + k;
    assign fm1_addr_calc = y * OUT_W + x;
    assign fm1_ch_sel    = oc;

    reg signed [7:0] conv_out;

    integer i;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state        <= S_IDLE;
            done         <= 1'b0;
            img_addr     <= 10'd0;
            w_addr       <= 7'd0;
            fm1_addr     <= 10'd0;
            fm1_din      <= 8'sd0;
            fm1_we       <= 1'b0;
            mmu_valid_in <= 1'b0;

            oc <= 3'd0;
            x  <= 5'd0;
            y  <= 5'd0;
            k  <= 4'd0;

            conv_out <= 8'sd0;

            for (i = 0; i < 9; i = i + 1) begin
                pix[i] <= 8'sd0;
                wt[i]  <= 8'sd0;
            end
        end else begin
            case (state)
                S_IDLE: begin
                    done         <= 1'b0;
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    oc <= 3'd0;
                    x  <= 5'd0;
                    y  <= 5'd0;
                    k  <= 4'd0;

                    if (start) begin
                        state <= S_LOAD_ADDR;
                    end
                end

                S_LOAD_ADDR: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;
                    img_addr     <= img_addr_calc;
                    w_addr       <= w_addr_calc;
                    state        <= S_WAIT_READ;
                end

                S_WAIT_READ: begin
                    mmu_valid_in <= 1'b0;
                    state        <= S_STORE;
                end

                S_STORE: begin
                    mmu_valid_in <= 1'b0;
                    pix[k]       <= img_dout;
                    wt[k]        <= w_dout;

                    if (k < 4'd8) begin
                        k     <= k + 4'd1;
                        state <= S_LOAD_ADDR;
                    end else begin
                        k     <= 4'd0;
                        state <= S_COMPUTE;
                    end
                end

                S_COMPUTE: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b1;
                    state        <= S_COMPUTE_WAIT;
                end

                S_COMPUTE_WAIT: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    if (mmu_valid_out) begin
                        conv_out <= q_relu_out;
                        state    <= S_WRITE;
                    end
                end

                S_WRITE: begin
                    mmu_valid_in <= 1'b0;
                    fm1_addr     <= fm1_addr_calc;
                    fm1_din      <= conv_out;
                    fm1_we       <= 1'b1;
                    state        <= S_NEXT;
                end

                S_NEXT: begin
                    fm1_we       <= 1'b0;
                    mmu_valid_in <= 1'b0;

                    if (x < OUT_W - 1) begin
                        x     <= x + 5'd1;
                        k     <= 4'd0;
                        state <= S_LOAD_ADDR;
                    end else if (y < OUT_H - 1) begin
                        x     <= 5'd0;
                        y     <= y + 5'd1;
                        k     <= 4'd0;
                        state <= S_LOAD_ADDR;
                    end else if (oc < OUT_CH - 1) begin
                        x     <= 5'd0;
                        y     <= 5'd0;
                        oc    <= oc + 3'd1;
                        k     <= 4'd0;
                        state <= S_LOAD_ADDR;
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
