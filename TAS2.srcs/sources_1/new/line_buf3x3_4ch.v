`timescale 1ns / 1ps

module linebuf3x3_4ch #(
    parameter DATA_W = 8,
    parameter IMG_W  = 26,
    parameter OUT_W  = 24
)(
    input  wire clk,
    input  wire resetn,

    input  wire start,
    input  wire [4:0] base_y,

    output reg  busy,
    output reg  done,

    output reg  [9:0] rd_addr,
    input  wire signed [DATA_W-1:0] din0,
    input  wire signed [DATA_W-1:0] din1,
    input  wire signed [DATA_W-1:0] din2,
    input  wire signed [DATA_W-1:0] din3,

    input  wire [4:0] win_x,

    output wire signed [DATA_W-1:0] w0_ch0,
    output wire signed [DATA_W-1:0] w1_ch0,
    output wire signed [DATA_W-1:0] w2_ch0,
    output wire signed [DATA_W-1:0] w3_ch0,
    output wire signed [DATA_W-1:0] w4_ch0,
    output wire signed [DATA_W-1:0] w5_ch0,
    output wire signed [DATA_W-1:0] w6_ch0,
    output wire signed [DATA_W-1:0] w7_ch0,
    output wire signed [DATA_W-1:0] w8_ch0,

    output wire signed [DATA_W-1:0] w0_ch1,
    output wire signed [DATA_W-1:0] w1_ch1,
    output wire signed [DATA_W-1:0] w2_ch1,
    output wire signed [DATA_W-1:0] w3_ch1,
    output wire signed [DATA_W-1:0] w4_ch1,
    output wire signed [DATA_W-1:0] w5_ch1,
    output wire signed [DATA_W-1:0] w6_ch1,
    output wire signed [DATA_W-1:0] w7_ch1,
    output wire signed [DATA_W-1:0] w8_ch1,

    output wire signed [DATA_W-1:0] w0_ch2,
    output wire signed [DATA_W-1:0] w1_ch2,
    output wire signed [DATA_W-1:0] w2_ch2,
    output wire signed [DATA_W-1:0] w3_ch2,
    output wire signed [DATA_W-1:0] w4_ch2,
    output wire signed [DATA_W-1:0] w5_ch2,
    output wire signed [DATA_W-1:0] w6_ch2,
    output wire signed [DATA_W-1:0] w7_ch2,
    output wire signed [DATA_W-1:0] w8_ch2,

    output wire signed [DATA_W-1:0] w0_ch3,
    output wire signed [DATA_W-1:0] w1_ch3,
    output wire signed [DATA_W-1:0] w2_ch3,
    output wire signed [DATA_W-1:0] w3_ch3,
    output wire signed [DATA_W-1:0] w4_ch3,
    output wire signed [DATA_W-1:0] w5_ch3,
    output wire signed [DATA_W-1:0] w6_ch3,
    output wire signed [DATA_W-1:0] w7_ch3,
    output wire signed [DATA_W-1:0] w8_ch3
);

    reg signed [DATA_W-1:0] lb0_ch0 [0:IMG_W-1];
    reg signed [DATA_W-1:0] lb1_ch0 [0:IMG_W-1];
    reg signed [DATA_W-1:0] lb2_ch0 [0:IMG_W-1];

    reg signed [DATA_W-1:0] lb0_ch1 [0:IMG_W-1];
    reg signed [DATA_W-1:0] lb1_ch1 [0:IMG_W-1];
    reg signed [DATA_W-1:0] lb2_ch1 [0:IMG_W-1];

    reg signed [DATA_W-1:0] lb0_ch2 [0:IMG_W-1];
    reg signed [DATA_W-1:0] lb1_ch2 [0:IMG_W-1];
    reg signed [DATA_W-1:0] lb2_ch2 [0:IMG_W-1];

    reg signed [DATA_W-1:0] lb0_ch3 [0:IMG_W-1];
    reg signed [DATA_W-1:0] lb1_ch3 [0:IMG_W-1];
    reg signed [DATA_W-1:0] lb2_ch3 [0:IMG_W-1];

    localparam S_IDLE  = 2'd0;
    localparam S_ADDR  = 2'd1;
    localparam S_WAIT  = 2'd2;
    localparam S_STORE = 2'd3;

    reg [1:0] state;

    reg [1:0] load_row;   // 0,1,2
    reg [4:0] load_col;   // 0~25

    wire [9:0] addr_calc;
    assign addr_calc = (base_y + load_row) * IMG_W + load_col;

    integer i;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state    <= S_IDLE;
            busy     <= 1'b0;
            done     <= 1'b0;
            rd_addr  <= 10'd0;
            load_row <= 2'd0;
            load_col <= 5'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;

                    if (start) begin
                        busy     <= 1'b1;
                        load_row <= 2'd0;
                        load_col <= 5'd0;
                        state    <= S_ADDR;
                    end
                end

                S_ADDR: begin
                    rd_addr <= addr_calc;
                    state   <= S_WAIT;
                end

                S_WAIT: begin
                    state <= S_STORE;
                end

                S_STORE: begin
                    case (load_row)
                        2'd0: begin
                            lb0_ch0[load_col] <= din0;
                            lb0_ch1[load_col] <= din1;
                            lb0_ch2[load_col] <= din2;
                            lb0_ch3[load_col] <= din3;
                        end

                        2'd1: begin
                            lb1_ch0[load_col] <= din0;
                            lb1_ch1[load_col] <= din1;
                            lb1_ch2[load_col] <= din2;
                            lb1_ch3[load_col] <= din3;
                        end

                        2'd2: begin
                            lb2_ch0[load_col] <= din0;
                            lb2_ch1[load_col] <= din1;
                            lb2_ch2[load_col] <= din2;
                            lb2_ch3[load_col] <= din3;
                        end
                    endcase

                    if (load_col < IMG_W - 1) begin
                        load_col <= load_col + 5'd1;
                        state    <= S_ADDR;
                    end else if (load_row < 2) begin
                        load_col <= 5'd0;
                        load_row <= load_row + 2'd1;
                        state    <= S_ADDR;
                    end else begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    // channel 0
    assign w0_ch0 = lb0_ch0[win_x + 0];
    assign w1_ch0 = lb0_ch0[win_x + 1];
    assign w2_ch0 = lb0_ch0[win_x + 2];
    assign w3_ch0 = lb1_ch0[win_x + 0];
    assign w4_ch0 = lb1_ch0[win_x + 1];
    assign w5_ch0 = lb1_ch0[win_x + 2];
    assign w6_ch0 = lb2_ch0[win_x + 0];
    assign w7_ch0 = lb2_ch0[win_x + 1];
    assign w8_ch0 = lb2_ch0[win_x + 2];

    // channel 1
    assign w0_ch1 = lb0_ch1[win_x + 0];
    assign w1_ch1 = lb0_ch1[win_x + 1];
    assign w2_ch1 = lb0_ch1[win_x + 2];
    assign w3_ch1 = lb1_ch1[win_x + 0];
    assign w4_ch1 = lb1_ch1[win_x + 1];
    assign w5_ch1 = lb1_ch1[win_x + 2];
    assign w6_ch1 = lb2_ch1[win_x + 0];
    assign w7_ch1 = lb2_ch1[win_x + 1];
    assign w8_ch1 = lb2_ch1[win_x + 2];

    // channel 2
    assign w0_ch2 = lb0_ch2[win_x + 0];
    assign w1_ch2 = lb0_ch2[win_x + 1];
    assign w2_ch2 = lb0_ch2[win_x + 2];
    assign w3_ch2 = lb1_ch2[win_x + 0];
    assign w4_ch2 = lb1_ch2[win_x + 1];
    assign w5_ch2 = lb1_ch2[win_x + 2];
    assign w6_ch2 = lb2_ch2[win_x + 0];
    assign w7_ch2 = lb2_ch2[win_x + 1];
    assign w8_ch2 = lb2_ch2[win_x + 2];

    // channel 3
    assign w0_ch3 = lb0_ch3[win_x + 0];
    assign w1_ch3 = lb0_ch3[win_x + 1];
    assign w2_ch3 = lb0_ch3[win_x + 2];
    assign w3_ch3 = lb1_ch3[win_x + 0];
    assign w4_ch3 = lb1_ch3[win_x + 1];
    assign w5_ch3 = lb1_ch3[win_x + 2];
    assign w6_ch3 = lb2_ch3[win_x + 0];
    assign w7_ch3 = lb2_ch3[win_x + 1];
    assign w8_ch3 = lb2_ch3[win_x + 2];

endmodule