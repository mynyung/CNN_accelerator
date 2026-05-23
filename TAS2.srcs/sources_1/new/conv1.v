`timescale 1ns / 1ps

module conv1(
    input wire clk,
    input wire resetn,
    input wire start,
    output reg done,

    output reg  [9:0] img_addr,
    input  wire signed [7:0] img_dout,

    output reg  [6:0] w_addr,
    input  wire signed [7:0] w_dout,

    output reg  [9:0] fm1_addr,
    output reg  signed [8*8-1:0] fm1_din_vec,
    output reg  [7:0] fm1_we_vec
);

    localparam IMG_W  = 28;
    localparam IMG_H  = 28;
    localparam OUT_W  = 26;
    localparam OUT_H  = 26;
    localparam OUT_CH = 8;
    localparam K_NUM  = 9;

    localparam DATA_W = 8;
    localparam ACC_W  = 32;

    reg [4:0] rd_x;
    reg [4:0] rd_y;

    reg [4:0] out_x;
    reg [4:0] out_y;

    reg [6:0] w_idx;

    reg signed [DATA_W-1:0] wt [0:OUT_CH-1][0:K_NUM-1];

    reg signed [DATA_W-1:0] lb0 [0:IMG_W-1];
    reg signed [DATA_W-1:0] lb1 [0:IMG_W-1];

    reg signed [DATA_W-1:0] w00, w01, w02;
    reg signed [DATA_W-1:0] w10, w11, w12;
    reg signed [DATA_W-1:0] w20, w21, w22;

    wire signed [DATA_W-1:0] top_pix;
    wire signed [DATA_W-1:0] mid_pix;
    wire signed [DATA_W-1:0] bot_pix;

    assign top_pix = lb0[rd_x];
    assign mid_pix = lb1[rd_x];
    assign bot_pix = img_dout;

    wire current_window_valid;
    assign current_window_valid = (rd_y >= 5'd2) && (rd_x >= 5'd2);

    wire signed [K_NUM*DATA_W-1:0] data_vec;

    assign data_vec[0*DATA_W +: DATA_W] = w00;
    assign data_vec[1*DATA_W +: DATA_W] = w01;
    assign data_vec[2*DATA_W +: DATA_W] = w02;
    assign data_vec[3*DATA_W +: DATA_W] = w10;
    assign data_vec[4*DATA_W +: DATA_W] = w11;
    assign data_vec[5*DATA_W +: DATA_W] = w12;
    assign data_vec[6*DATA_W +: DATA_W] = w20;
    assign data_vec[7*DATA_W +: DATA_W] = w21;
    assign data_vec[8*DATA_W +: DATA_W] = w22;

    wire signed [OUT_CH*K_NUM*DATA_W-1:0] weight_vec;
    wire signed [OUT_CH*ACC_W-1:0] acc_vec;

    wire signed [ACC_W-1:0] mmu_acc [0:OUT_CH-1];

    genvar goc, gk;

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

    reg  mmu_valid_in;
    wire mmu_valid_out;

    MMU_CONV1_8OC #(
        .DATA_W(DATA_W),
        .ACC_W (ACC_W),
        .OUT_CH(OUT_CH),
        .K_NUM (K_NUM)
    ) u_mmu_conv1_8oc (
        .clk        (clk),
        .resetn     (resetn),
        .valid_in   (mmu_valid_in),
        .data_vec   (data_vec),
        .weight_vec (weight_vec),
        .valid_out  (mmu_valid_out),
        .acc_vec    (acc_vec)
    );

    reg signed [ACC_W-1:0] acc_buf [0:OUT_CH-1];

    wire signed [7:0] q_relu_out [0:OUT_CH-1];

    generate
        for (goc = 0; goc < OUT_CH; goc = goc + 1) begin : Q_RELU_ARRAY
            quant_relu u_quant_relu (
                .in_data  (acc_buf[goc]),
                .out_data (q_relu_out[goc])
            );
        end
    endgenerate

    wire [9:0] img_addr_calc;
    wire [9:0] fm1_addr_calc;

    assign img_addr_calc = rd_y * IMG_W + rd_x;
    assign fm1_addr_calc = out_y * OUT_W + out_x;

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

    localparam S_NEXT_PIXEL    = 4'd11;
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
            fm1_din_vec  <= 64'sd0;
            fm1_we_vec   <= 8'b0000_0000;

            rd_x         <= 5'd0;
            rd_y         <= 5'd0;
            out_x        <= 5'd0;
            out_y        <= 5'd0;

            w_idx        <= 7'd0;

            mmu_valid_in <= 1'b0;

            w00 <= 8'sd0;
            w01 <= 8'sd0;
            w02 <= 8'sd0;
            w10 <= 8'sd0;
            w11 <= 8'sd0;
            w12 <= 8'sd0;
            w20 <= 8'sd0;
            w21 <= 8'sd0;
            w22 <= 8'sd0;

            for (i = 0; i < IMG_W; i = i + 1) begin
                lb0[i] <= 8'sd0;
                lb1[i] <= 8'sd0;
            end

            for (i = 0; i < OUT_CH; i = i + 1) begin
                acc_buf[i] <= 32'sd0;
                for (j = 0; j < K_NUM; j = j + 1) begin
                    wt[i][j] <= 8'sd0;
                end
            end

        end else begin
            case (state)

                S_IDLE: begin
                    done         <= 1'b0;
                    fm1_we_vec   <= 8'b0000_0000;
                    mmu_valid_in <= 1'b0;

                    rd_x         <= 5'd0;
                    rd_y         <= 5'd0;
                    out_x        <= 5'd0;
                    out_y        <= 5'd0;

                    w_idx        <= 7'd0;

                    w00 <= 8'sd0;
                    w01 <= 8'sd0;
                    w02 <= 8'sd0;
                    w10 <= 8'sd0;
                    w11 <= 8'sd0;
                    w12 <= 8'sd0;
                    w20 <= 8'sd0;
                    w21 <= 8'sd0;
                    w22 <= 8'sd0;

                    for (i = 0; i < IMG_W; i = i + 1) begin
                        lb0[i] <= 8'sd0;
                        lb1[i] <= 8'sd0;
                    end

                    if (start) begin
                        state <= S_W_ADDR;
                    end
                end

                S_W_ADDR: begin
                    fm1_we_vec   <= 8'b0000_0000;
                    mmu_valid_in <= 1'b0;

                    w_addr       <= w_idx;
                    state        <= S_W_WAIT;
                end

                S_W_WAIT: begin
                    fm1_we_vec   <= 8'b0000_0000;
                    mmu_valid_in <= 1'b0;

                    state        <= S_W_STORE;
                end

                S_W_STORE: begin
                    fm1_we_vec   <= 8'b0000_0000;
                    mmu_valid_in <= 1'b0;

                    wt[w_idx / K_NUM][w_idx % K_NUM] <= w_dout;

                    if (w_idx < OUT_CH*K_NUM - 1) begin
                        w_idx <= w_idx + 7'd1;
                        state <= S_W_ADDR;
                    end else begin
                        w_idx <= 7'd0;
                        rd_x  <= 5'd0;
                        rd_y  <= 5'd0;
                        state <= S_PIX_ADDR;
                    end
                end

                S_PIX_ADDR: begin
                    fm1_we_vec   <= 8'b0000_0000;
                    mmu_valid_in <= 1'b0;

                    img_addr     <= img_addr_calc;
                    state        <= S_PIX_WAIT;
                end

                S_PIX_WAIT: begin
                    fm1_we_vec   <= 8'b0000_0000;
                    mmu_valid_in <= 1'b0;

                    state        <= S_PIX_STORE;
                end

                S_PIX_STORE: begin
                    fm1_we_vec   <= 8'b0000_0000;
                    mmu_valid_in <= 1'b0;

                    w00 <= w01;
                    w01 <= w02;
                    w02 <= top_pix;

                    w10 <= w11;
                    w11 <= w12;
                    w12 <= mid_pix;

                    w20 <= w21;
                    w21 <= w22;
                    w22 <= bot_pix;

                    lb0[rd_x] <= lb1[rd_x];
                    lb1[rd_x] <= img_dout;

                    if (current_window_valid) begin
                        out_x <= rd_x - 5'd2;
                        out_y <= rd_y - 5'd2;
                        state <= S_COMPUTE;
                    end else begin
                        state <= S_NEXT_PIXEL;
                    end
                end

                S_COMPUTE: begin
                    fm1_we_vec   <= 8'b0000_0000;
                    mmu_valid_in <= 1'b1;

                    state        <= S_COMPUTE_WAIT;
                end

                S_COMPUTE_WAIT: begin
                    fm1_we_vec   <= 8'b0000_0000;
                    mmu_valid_in <= 1'b0;

                    if (mmu_valid_out) begin
                        for (i = 0; i < OUT_CH; i = i + 1) begin
                            acc_buf[i] <= mmu_acc[i];
                        end

                        state <= S_WRITE_SETUP;
                    end
                end

                S_WRITE_SETUP: begin
                    mmu_valid_in <= 1'b0;
                    fm1_we_vec   <= 8'b0000_0000;

                    fm1_addr <= fm1_addr_calc;

                    fm1_din_vec[0*DATA_W +: DATA_W] <= q_relu_out[0];
                    fm1_din_vec[1*DATA_W +: DATA_W] <= q_relu_out[1];
                    fm1_din_vec[2*DATA_W +: DATA_W] <= q_relu_out[2];
                    fm1_din_vec[3*DATA_W +: DATA_W] <= q_relu_out[3];
                    fm1_din_vec[4*DATA_W +: DATA_W] <= q_relu_out[4];
                    fm1_din_vec[5*DATA_W +: DATA_W] <= q_relu_out[5];
                    fm1_din_vec[6*DATA_W +: DATA_W] <= q_relu_out[6];
                    fm1_din_vec[7*DATA_W +: DATA_W] <= q_relu_out[7];

                    state <= S_WRITE_PULSE;
                end

                S_WRITE_PULSE: begin
                    mmu_valid_in <= 1'b0;
                    fm1_we_vec   <= 8'b1111_1111;

                    state <= S_NEXT_PIXEL;
                end

                S_NEXT_PIXEL: begin
                    fm1_we_vec   <= 8'b0000_0000;
                    mmu_valid_in <= 1'b0;

                    if (rd_x < IMG_W - 1) begin
                        rd_x  <= rd_x + 5'd1;
                        state <= S_PIX_ADDR;
                    end else if (rd_y < IMG_H - 1) begin
                        rd_x  <= 5'd0;
                        rd_y  <= rd_y + 5'd1;
                        state <= S_PIX_ADDR;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done         <= 1'b1;
                    fm1_we_vec   <= 8'b0000_0000;
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