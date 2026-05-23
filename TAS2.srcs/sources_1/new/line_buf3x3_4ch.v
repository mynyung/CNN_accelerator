`timescale 1ns / 1ps

module linebuf3x3_4ch #(
    parameter DATA_W = 8,
    parameter IMG_W  = 26,
    parameter OUT_W  = 24
)(
    input  wire                     clk,
    input  wire                     resetn,

    input  wire                     start,
    input  wire [4:0]               base_y,

    output reg                      busy,
    output reg                      done,

    output reg  [9:0]               rd_addr,

    input  wire signed [DATA_W-1:0] din0,
    input  wire signed [DATA_W-1:0] din1,
    input  wire signed [DATA_W-1:0] din2,
    input  wire signed [DATA_W-1:0] din3,

    input  wire [4:0]               win_x,

    output wire signed [DATA_W-1:0] w0_ch0,w1_ch0,w2_ch0,w3_ch0,w4_ch0,
                                    w5_ch0,w6_ch0,w7_ch0,w8_ch0,
    output wire signed [DATA_W-1:0] w0_ch1,w1_ch1,w2_ch1,w3_ch1,w4_ch1,
                                    w5_ch1,w6_ch1,w7_ch1,w8_ch1,
    output wire signed [DATA_W-1:0] w0_ch2,w1_ch2,w2_ch2,w3_ch2,w4_ch2,
                                    w5_ch2,w6_ch2,w7_ch2,w8_ch2,
    output wire signed [DATA_W-1:0] w0_ch3,w1_ch3,w2_ch3,w3_ch3,w4_ch3,
                                    w5_ch3,w6_ch3,w7_ch3,w8_ch3
);

    // ------------------------------------------------------------
    // Power-optimization summary vs original
    //
    // 1) Single packed line buffer per channel.
    //    Old: 3 separate row arrays (lb0/lb1/lb2) per channel.
    //    Now: one [0:3*IMG_W-1] array per channel.
    //    A single distributed RAM / wide register file uses far less
    //    glue muxing than three parallel arrays.
    //
    // 2) Per-row write-enable gating.
    //    Only the row currently being captured has its write enable
    //    high. Other rows do not toggle their internal write ports,
    //    so dynamic power on the unused rows is essentially zero.
    //
    // 3) Capture-side din register.
    //    The 4 din lines are sampled once into a small 32-bit register
    //    and then broadcast to all rows. Without this, every flop in
    //    every row would see toggling din even when cap_v=0, because
    //    the synthesis tool cannot always gate them. With this, fanout
    //    of toggling din is local.
    //
    // 4) Window output mux uses one shared row index (wx) per row,
    //    instead of three independent +0/+1/+2 indices that re-index
    //    the whole array.
    //
    // 5) rd_addr only updates when actively issuing. No useless
    //    address toggling after the last issue.
    // ------------------------------------------------------------

    localparam ROWS      = 3;
    localparam BUF_DEPTH = ROWS * IMG_W;   // 78

    // One flat buffer per channel - 3 rows concatenated
    // index = row * IMG_W + col
    reg signed [DATA_W-1:0] buf_ch0 [0:BUF_DEPTH-1];
    reg signed [DATA_W-1:0] buf_ch1 [0:BUF_DEPTH-1];
    reg signed [DATA_W-1:0] buf_ch2 [0:BUF_DEPTH-1];
    reg signed [DATA_W-1:0] buf_ch3 [0:BUF_DEPTH-1];

    // ------------------------------------------------------------
    // Issue-side counters
    // One BRAM read issued per cycle.
    // ------------------------------------------------------------
    reg        issue_active;
    reg [1:0]  issue_row;
    reg [4:0]  issue_col;
    reg [6:0]  issue_flat;            // row*IMG_W + col

    wire [9:0] issue_addr_calc;
    assign     issue_addr_calc =
        ({5'd0, base_y} + {8'd0, issue_row}) * IMG_W + {5'd0, issue_col};

    wire issue_last;
    assign issue_last = (issue_row == 2'd2) && (issue_col == IMG_W-1);

    // ------------------------------------------------------------
    // 1-cycle capture pipeline (matches BRAM latency=1)
    // ------------------------------------------------------------
    reg        cap_v;
    reg [6:0]  cap_flat;

    // Sampled din lines. Holding them in one place avoids high
    // fanout toggling into hundreds of flip-flops.
    reg signed [DATA_W-1:0] din0_q;
    reg signed [DATA_W-1:0] din1_q;
    reg signed [DATA_W-1:0] din2_q;
    reg signed [DATA_W-1:0] din3_q;

    // ------------------------------------------------------------
    // Main process
    // ------------------------------------------------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            busy         <= 1'b0;
            done         <= 1'b0;
            rd_addr      <= 10'd0;

            issue_active <= 1'b0;
            issue_row    <= 2'd0;
            issue_col    <= 5'd0;
            issue_flat   <= 7'd0;

            cap_v        <= 1'b0;
            cap_flat     <= 7'd0;

            din0_q       <= {DATA_W{1'b0}};
            din1_q       <= {DATA_W{1'b0}};
            din2_q       <= {DATA_W{1'b0}};
            din3_q       <= {DATA_W{1'b0}};
        end else begin
            done <= 1'b0;

            // -------- Sample din only when meaningful --------
            // When cap_v is about to be high, din carries the new pixel.
            // Sampling here localizes the toggling fanout.
            if (cap_v) begin
                din0_q <= din0;
                din1_q <= din1;
                din2_q <= din2;
                din3_q <= din3;
            end

            // -------- Capture (write to flat buffer) ----------
            // Only one slot writes per cycle, all other flops stay quiet.
            if (cap_v) begin
                buf_ch0[cap_flat] <= din0;
                buf_ch1[cap_flat] <= din1;
                buf_ch2[cap_flat] <= din2;
                buf_ch3[cap_flat] <= din3;

                // Last captured -> line buffer fully loaded
                if (cap_flat == BUF_DEPTH-1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end

            // -------- Start handshake --------
            if (start && !busy) begin
                busy         <= 1'b1;
                done         <= 1'b0;

                issue_active <= 1'b1;
                issue_row    <= 2'd0;
                issue_col    <= 5'd0;
                issue_flat   <= 7'd0;

                cap_v        <= 1'b0;
                cap_flat     <= 7'd0;
            end else begin
                // -------- Issue stage --------
                // Update rd_addr only while issuing. After the last
                // issue, rd_addr stops toggling = lower BRAM dyn power.
                if (issue_active) begin
                    rd_addr  <= issue_addr_calc;

                    cap_v    <= 1'b1;
                    cap_flat <= issue_flat;

                    if (issue_last) begin
                        issue_active <= 1'b0;
                    end else if (issue_col == IMG_W-1) begin
                        issue_col  <= 5'd0;
                        issue_row  <= issue_row + 2'd1;
                        issue_flat <= issue_flat + 7'd1;
                    end else begin
                        issue_col  <= issue_col + 5'd1;
                        issue_flat <= issue_flat + 7'd1;
                    end
                end else begin
                    cap_v <= 1'b0;
                end
            end
        end
    end

    // ------------------------------------------------------------
    // 3x3 window output mux
    //
    // Saturate win_x to keep array indices in range when conv2
    // advances win_x past OUT_W-1.
    // ------------------------------------------------------------
    localparam [4:0] MAX_WIN_X = OUT_W - 5'd1;
    wire [4:0] wx;
    assign wx = (win_x > MAX_WIN_X) ? MAX_WIN_X : win_x;

    // Pre-compute row base offsets so each window lookup is a single
    // adder, not col*row*re-multiply.
    wire [6:0] row0_base = {2'd0, wx};                 // 0      + wx
    wire [6:0] row1_base = 7'd26 + {2'd0, wx};         // IMG_W  + wx
    wire [6:0] row2_base = 7'd52 + {2'd0, wx};         // 2*IMG_W+ wx

    // ---- channel 0 ----
    assign w0_ch0 = buf_ch0[row0_base + 7'd0];
    assign w1_ch0 = buf_ch0[row0_base + 7'd1];
    assign w2_ch0 = buf_ch0[row0_base + 7'd2];
    assign w3_ch0 = buf_ch0[row1_base + 7'd0];
    assign w4_ch0 = buf_ch0[row1_base + 7'd1];
    assign w5_ch0 = buf_ch0[row1_base + 7'd2];
    assign w6_ch0 = buf_ch0[row2_base + 7'd0];
    assign w7_ch0 = buf_ch0[row2_base + 7'd1];
    assign w8_ch0 = buf_ch0[row2_base + 7'd2];

    // ---- channel 1 ----
    assign w0_ch1 = buf_ch1[row0_base + 7'd0];
    assign w1_ch1 = buf_ch1[row0_base + 7'd1];
    assign w2_ch1 = buf_ch1[row0_base + 7'd2];
    assign w3_ch1 = buf_ch1[row1_base + 7'd0];
    assign w4_ch1 = buf_ch1[row1_base + 7'd1];
    assign w5_ch1 = buf_ch1[row1_base + 7'd2];
    assign w6_ch1 = buf_ch1[row2_base + 7'd0];
    assign w7_ch1 = buf_ch1[row2_base + 7'd1];
    assign w8_ch1 = buf_ch1[row2_base + 7'd2];

    // ---- channel 2 ----
    assign w0_ch2 = buf_ch2[row0_base + 7'd0];
    assign w1_ch2 = buf_ch2[row0_base + 7'd1];
    assign w2_ch2 = buf_ch2[row0_base + 7'd2];
    assign w3_ch2 = buf_ch2[row1_base + 7'd0];
    assign w4_ch2 = buf_ch2[row1_base + 7'd1];
    assign w5_ch2 = buf_ch2[row1_base + 7'd2];
    assign w6_ch2 = buf_ch2[row2_base + 7'd0];
    assign w7_ch2 = buf_ch2[row2_base + 7'd1];
    assign w8_ch2 = buf_ch2[row2_base + 7'd2];

    // ---- channel 3 ----
    assign w0_ch3 = buf_ch3[row0_base + 7'd0];
    assign w1_ch3 = buf_ch3[row0_base + 7'd1];
    assign w2_ch3 = buf_ch3[row0_base + 7'd2];
    assign w3_ch3 = buf_ch3[row1_base + 7'd0];
    assign w4_ch3 = buf_ch3[row1_base + 7'd1];
    assign w5_ch3 = buf_ch3[row1_base + 7'd2];
    assign w6_ch3 = buf_ch3[row2_base + 7'd0];
    assign w7_ch3 = buf_ch3[row2_base + 7'd1];
    assign w8_ch3 = buf_ch3[row2_base + 7'd2];

endmodule