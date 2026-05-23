`timescale 1ns / 1ps

module conv2 #(
    parameter NUM_OC_PAR = 4,
    parameter NUM_IC_PAR = 4
)(
    input  wire             clk,
    input  wire             resetn,
    input  wire             start,
    output reg              done,

    output wire [9:0]       fm1_addr0,
    output wire [9:0]       fm1_addr1,
    output wire [9:0]       fm1_addr2,
    output wire [9:0]       fm1_addr3,

    input  wire signed [7:0] fm1_dout0,
    input  wire signed [7:0] fm1_dout1,
    input  wire signed [7:0] fm1_dout2,
    input  wire signed [7:0] fm1_dout3,

    output wire             fm1_pass_sel,

    output reg  [10:0]      w_addr,
    input  wire signed [7:0] w_dout,

    output reg  [13:0]      fm2_addr,
    output reg  signed [7:0] fm2_din,
    output reg              fm2_we
);

    // ---------------- parameters ----------------
    localparam FM1_W        = 26;
    localparam OUT_W        = 24;
    localparam OUT_H        = 24;
    localparam OUT_CH       = 16;
    localparam IN_CH        = 8;
    localparam K_SIZE       = 3;
    localparam FM2_CH_SIZE  = OUT_W * OUT_W;
    localparam NUM_MMU_MACS = NUM_IC_PAR * K_SIZE * K_SIZE; // 36
    localparam OC_GROUPS    = OUT_CH / NUM_OC_PAR;          // 4
    localparam MMU_LAT      = 6;                            // valid_in -> valid_out

    // streaming termination cycles
    localparam P0_END = OUT_W + MMU_LAT;                    // 30
    localparam P1_END = 4*(OUT_W-1) + MMU_LAT + NUM_OC_PAR - 1 + 1; // 102

    // ---------------- regs ----------------
    reg [1:0] pass;                 // 0/1
    assign fm1_pass_sel = pass[0];

    reg signed [7:0] w_all [0:OUT_CH-1][0:71];
    reg [6:0]  w_load_idx;
    reg [3:0]  w_load_oc;

    reg [4:0]  y;
    reg [1:0]  oc_group;
    reg [3:0]  oc_base;

    reg [6:0]  stream_cnt;
    reg [4:0]  x_recv;          // next x to capture/write
    reg [4:0]  write_x;         // x currently being written (pass 1)
    reg [1:0]  write_phase;     // OC index 0..3 during write (pass 1)
    reg        write_active;

    reg signed [7:0]  wt [0:NUM_OC_PAR-1][0:NUM_MMU_MACS-1];
    reg signed [31:0] partial_sum [0:NUM_OC_PAR-1];

    // [oc_group][x][oc_par]
    reg signed [31:0] psum_arr [0:OC_GROUPS-1][0:OUT_W-1][0:NUM_OC_PAR-1];

    reg [4:0]  lb_win_x_reg;
    reg        lb_start_reg;
    reg        mmu_valid_in;

    // ---------------- line buffer wiring ----------------
    wire lb_busy, lb_done;
    wire [9:0] lb_rd_addr;
    assign fm1_addr0 = lb_rd_addr;
    assign fm1_addr1 = lb_rd_addr;
    assign fm1_addr2 = lb_rd_addr;
    assign fm1_addr3 = lb_rd_addr;

    wire signed [7:0] lb_w0_ch0,lb_w1_ch0,lb_w2_ch0,lb_w3_ch0,lb_w4_ch0,
                      lb_w5_ch0,lb_w6_ch0,lb_w7_ch0,lb_w8_ch0;
    wire signed [7:0] lb_w0_ch1,lb_w1_ch1,lb_w2_ch1,lb_w3_ch1,lb_w4_ch1,
                      lb_w5_ch1,lb_w6_ch1,lb_w7_ch1,lb_w8_ch1;
    wire signed [7:0] lb_w0_ch2,lb_w1_ch2,lb_w2_ch2,lb_w3_ch2,lb_w4_ch2,
                      lb_w5_ch2,lb_w6_ch2,lb_w7_ch2,lb_w8_ch2;
    wire signed [7:0] lb_w0_ch3,lb_w1_ch3,lb_w2_ch3,lb_w3_ch3,lb_w4_ch3,
                      lb_w5_ch3,lb_w6_ch3,lb_w7_ch3,lb_w8_ch3;

    linebuf3x3_4ch #(.DATA_W(8), .IMG_W(FM1_W), .OUT_W(OUT_W))
    u_linebuf3x3_4ch (
        .clk(clk), .resetn(resetn),
        .start(lb_start_reg), .base_y(y),
        .busy(lb_busy), .done(lb_done),
        .rd_addr(lb_rd_addr),
        .din0(fm1_dout0), .din1(fm1_dout1),
        .din2(fm1_dout2), .din3(fm1_dout3),
        .win_x(lb_win_x_reg),
        .w0_ch0(lb_w0_ch0),.w1_ch0(lb_w1_ch0),.w2_ch0(lb_w2_ch0),
        .w3_ch0(lb_w3_ch0),.w4_ch0(lb_w4_ch0),.w5_ch0(lb_w5_ch0),
        .w6_ch0(lb_w6_ch0),.w7_ch0(lb_w7_ch0),.w8_ch0(lb_w8_ch0),
        .w0_ch1(lb_w0_ch1),.w1_ch1(lb_w1_ch1),.w2_ch1(lb_w2_ch1),
        .w3_ch1(lb_w3_ch1),.w4_ch1(lb_w4_ch1),.w5_ch1(lb_w5_ch1),
        .w6_ch1(lb_w6_ch1),.w7_ch1(lb_w7_ch1),.w8_ch1(lb_w8_ch1),
        .w0_ch2(lb_w0_ch2),.w1_ch2(lb_w1_ch2),.w2_ch2(lb_w2_ch2),
        .w3_ch2(lb_w3_ch2),.w4_ch2(lb_w4_ch2),.w5_ch2(lb_w5_ch2),
        .w6_ch2(lb_w6_ch2),.w7_ch2(lb_w7_ch2),.w8_ch2(lb_w8_ch2),
        .w0_ch3(lb_w0_ch3),.w1_ch3(lb_w1_ch3),.w2_ch3(lb_w2_ch3),
        .w3_ch3(lb_w3_ch3),.w4_ch3(lb_w4_ch3),.w5_ch3(lb_w5_ch3),
        .w6_ch3(lb_w6_ch3),.w7_ch3(lb_w7_ch3),.w8_ch3(lb_w8_ch3)
    );

    // Combinational lb_win[0..35] -- no pix register, save 1 cycle
    wire signed [7:0] lb_win [0:NUM_MMU_MACS-1];
    assign lb_win[ 0]=lb_w0_ch0; assign lb_win[ 1]=lb_w1_ch0; assign lb_win[ 2]=lb_w2_ch0;
    assign lb_win[ 3]=lb_w3_ch0; assign lb_win[ 4]=lb_w4_ch0; assign lb_win[ 5]=lb_w5_ch0;
    assign lb_win[ 6]=lb_w6_ch0; assign lb_win[ 7]=lb_w7_ch0; assign lb_win[ 8]=lb_w8_ch0;
    assign lb_win[ 9]=lb_w0_ch1; assign lb_win[10]=lb_w1_ch1; assign lb_win[11]=lb_w2_ch1;
    assign lb_win[12]=lb_w3_ch1; assign lb_win[13]=lb_w4_ch1; assign lb_win[14]=lb_w5_ch1;
    assign lb_win[15]=lb_w6_ch1; assign lb_win[16]=lb_w7_ch1; assign lb_win[17]=lb_w8_ch1;
    assign lb_win[18]=lb_w0_ch2; assign lb_win[19]=lb_w1_ch2; assign lb_win[20]=lb_w2_ch2;
    assign lb_win[21]=lb_w3_ch2; assign lb_win[22]=lb_w4_ch2; assign lb_win[23]=lb_w5_ch2;
    assign lb_win[24]=lb_w6_ch2; assign lb_win[25]=lb_w7_ch2; assign lb_win[26]=lb_w8_ch2;
    assign lb_win[27]=lb_w0_ch3; assign lb_win[28]=lb_w1_ch3; assign lb_win[29]=lb_w2_ch3;
    assign lb_win[30]=lb_w3_ch3; assign lb_win[31]=lb_w4_ch3; assign lb_win[32]=lb_w5_ch3;
    assign lb_win[33]=lb_w6_ch3; assign lb_win[34]=lb_w7_ch3; assign lb_win[35]=lb_w8_ch3;

    // ---------------- pack data_vec straight from line buffer ----------------
    wire signed [8*NUM_MMU_MACS-1:0] data_vec;
    genvar pi;
    generate
        for (pi = 0; pi < NUM_MMU_MACS; pi = pi + 1) begin : PACK_DATA
            assign data_vec[pi*8 +: 8] = lb_win[pi];
        end
    endgenerate

    // ---------------- 4 MMUs ----------------
    wire signed [8*NUM_MMU_MACS-1:0] weight_vec [0:NUM_OC_PAR-1];
    wire signed [31:0]               mmu_acc    [0:NUM_OC_PAR-1];
    wire [NUM_OC_PAR-1:0]            mmu_valid_out;

    genvar oi, wi;
    generate
        for (oi = 0; oi < NUM_OC_PAR; oi = oi + 1) begin : OC_MMU
            for (wi = 0; wi < NUM_MMU_MACS; wi = wi + 1) begin : PACK_W
                assign weight_vec[oi][wi*8 +: 8] = wt[oi][wi];
            end
            MMU #(.DATA_W(8), .ACC_W(32), .NUM_MACS(NUM_MMU_MACS)) u_mmu (
                .clk(clk), .resetn(resetn),
                .valid_in(mmu_valid_in),
                .data_vec(data_vec),
                .weight_vec(weight_vec[oi]),
                .partial_sum_in(partial_sum[oi]),
                .valid_out(mmu_valid_out[oi]),
                .partial_sum_out(mmu_acc[oi])
            );
        end
    endgenerate

    wire signed [7:0] q_relu_out [0:NUM_OC_PAR-1];
    genvar ri;
    generate
        for (ri = 0; ri < NUM_OC_PAR; ri = ri + 1) begin : RELU
            quant_relu u_qr (.in_data(mmu_acc[ri]), .out_data(q_relu_out[ri]));
        end
    endgenerate

    // ---------------- channel indices per pass ----------------
    wire [2:0] ic0_calc = pass * NUM_IC_PAR + 0;
    wire [2:0] ic1_calc = pass * NUM_IC_PAR + 1;
    wire [2:0] ic2_calc = pass * NUM_IC_PAR + 2;
    wire [2:0] ic3_calc = pass * NUM_IC_PAR + 3;

    // ---------------- FSM ----------------
    localparam S_IDLE         = 4'd0;
    localparam S_LOAD_W_ADDR  = 4'd1;
    localparam S_WAIT_W       = 4'd2;
    localparam S_STORE_W      = 4'd3;
    localparam S_LB_START     = 4'd4;
    localparam S_LB_WAIT      = 4'd5;
    localparam S_PRELOAD_WT   = 4'd6;
    localparam S_STREAM       = 4'd7;
    localparam S_DONE         = 4'd8;

    reg [3:0] state;
    integer i, j, og, xi;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            w_addr        <= 11'd0;
            fm2_addr      <= 14'd0;
            fm2_din       <= 8'sd0;
            fm2_we        <= 1'b0;

            y             <= 5'd0;
            oc_group      <= 2'd0;
            oc_base       <= 4'd0;
            pass          <= 2'd0;

            stream_cnt    <= 7'd0;
            x_recv        <= 5'd0;
            write_x       <= 5'd0;
            write_phase   <= 2'd0;
            write_active  <= 1'b0;

            w_load_idx    <= 7'd0;
            w_load_oc     <= 4'd0;

            lb_start_reg  <= 1'b0;
            lb_win_x_reg  <= 5'd0;
            mmu_valid_in  <= 1'b0;

            for (i = 0; i < NUM_OC_PAR; i = i + 1) begin
                partial_sum[i] <= 32'sd0;
                for (j = 0; j < NUM_MMU_MACS; j = j + 1)
                    wt[i][j] <= 8'sd0;
            end
            for (og = 0; og < OC_GROUPS; og = og + 1)
                for (xi = 0; xi < OUT_W; xi = xi + 1)
                    for (i = 0; i < NUM_OC_PAR; i = i + 1)
                        psum_arr[og][xi][i] <= 32'sd0;
            for (i = 0; i < OUT_CH; i = i + 1)
                for (j = 0; j < 72; j = j + 1)
                    w_all[i][j] <= 8'sd0;
        end else begin
            // defaults
            fm2_we <= 1'b0;

            case (state)
                // --------------------------------------------------------
                S_IDLE: begin
                    done <= 1'b0;
                    lb_start_reg <= 1'b0;
                    mmu_valid_in <= 1'b0;
                    if (start) begin
                        w_load_oc  <= 4'd0;
                        w_load_idx <= 7'd0;
                        w_addr     <= 11'd0;
                        state      <= S_WAIT_W;
                    end
                end

                // --------------------------------------------------------
                // Weight load (same as before, all weights to w_all once)
                // --------------------------------------------------------
                S_LOAD_W_ADDR: begin
                    w_addr <= w_load_oc * 11'd72 + w_load_idx;
                    state  <= S_WAIT_W;
                end
                S_WAIT_W: state <= S_STORE_W;
                S_STORE_W: begin
                    w_all[w_load_oc][w_load_idx] <= w_dout;
                    if (w_load_idx < 7'd71) begin
                        w_load_idx <= w_load_idx + 7'd1;
                        state      <= S_LOAD_W_ADDR;
                    end else if (w_load_oc < OUT_CH - 1) begin
                        w_load_oc  <= w_load_oc + 4'd1;
                        w_load_idx <= 7'd0;
                        state      <= S_LOAD_W_ADDR;
                    end else begin
                        // begin compute: y=0, pass=0, oc_group=0
                        w_load_oc  <= 4'd0;
                        w_load_idx <= 7'd0;
                        y          <= 5'd0;
                        pass       <= 2'd0;
                        oc_group   <= 2'd0;
                        oc_base    <= 4'd0;
                        state      <= S_LB_START;
                    end
                end

                // --------------------------------------------------------
                // Load line buffer (once per (y, pass) -- not per oc_group)
                // --------------------------------------------------------
                S_LB_START: begin
                    lb_start_reg <= 1'b1;
                    state        <= S_LB_WAIT;
                end
                S_LB_WAIT: begin
                    lb_start_reg <= 1'b0;
                    if (lb_done) begin
                        oc_group   <= 2'd0;
                        oc_base    <= 4'd0;
                        state      <= S_PRELOAD_WT;
                    end
                end

                // --------------------------------------------------------
                // Preload wt for (oc_base, pass) -- 36 weights x 4 OCs
                // --------------------------------------------------------
                S_PRELOAD_WT: begin
                    for (i = 0; i < NUM_OC_PAR; i = i + 1) begin
                        for (j = 0; j < 9; j = j + 1) begin
                            wt[i][j]      <= w_all[oc_base + i][ic0_calc * 9 + j];
                            wt[i][j + 9]  <= w_all[oc_base + i][ic1_calc * 9 + j];
                            wt[i][j + 18] <= w_all[oc_base + i][ic2_calc * 9 + j];
                            wt[i][j + 27] <= w_all[oc_base + i][ic3_calc * 9 + j];
                        end
                    end
                    stream_cnt   <= 7'd0;
                    x_recv       <= 5'd0;
                    write_x      <= 5'd0;
                    write_phase  <= 2'd0;
                    write_active <= 1'b0;
                    lb_win_x_reg <= 5'd0;     // first window = x=0
                    state        <= S_STREAM;
                end

                // --------------------------------------------------------
                // STREAMING COMPUTE
                //   pass 0: feed 1/cycle, capture into psum_arr (31 cycles)
                //   pass 1: feed every 4 cycles, write fm2 1/cycle (~103)
                // --------------------------------------------------------
                S_STREAM: begin
                    if (pass == 2'd0) begin
                        // ---- PASS 0: 1 input / cycle ----
                        if (stream_cnt < OUT_W) begin
                            mmu_valid_in <= 1'b1;
                            lb_win_x_reg <= stream_cnt[4:0] + 5'd1; // pre-stage next
                            for (i = 0; i < NUM_OC_PAR; i = i + 1)
                                partial_sum[i] <= 32'sd0;
                        end else begin
                            mmu_valid_in <= 1'b0;
                        end

                        // capture every valid_out
                        if (mmu_valid_out[0]) begin
                            for (i = 0; i < NUM_OC_PAR; i = i + 1)
                                psum_arr[oc_group][x_recv][i] <= mmu_acc[i];
                            x_recv <= x_recv + 5'd1;
                        end

                        // terminate
                        if (stream_cnt == P0_END) begin
                            mmu_valid_in <= 1'b0;
                            stream_cnt   <= 7'd0;
                            x_recv       <= 5'd0;
                            // next oc_group, or done with this pass
                            if (oc_group < OC_GROUPS - 1) begin
                                oc_group <= oc_group + 2'd1;
                                oc_base  <= oc_base  + NUM_OC_PAR;
                                state    <= S_PRELOAD_WT;
                            end else begin
                                // pass 0 done for this y -> reload LB for pass 1
                                pass     <= 2'd1;
                                oc_group <= 2'd0;
                                oc_base  <= 4'd0;
                                state    <= S_LB_START;
                            end
                        end else begin
                            stream_cnt <= stream_cnt + 7'd1;
                        end
                    end else begin
                        // ---- PASS 1: 1 input every 4 cycles ----
                        if ((stream_cnt[1:0] == 2'b00) &&
                            (stream_cnt < 4*OUT_W)) begin
                            mmu_valid_in <= 1'b1;
                            lb_win_x_reg <= stream_cnt[6:2] + 5'd1; // pre-stage next
                            for (i = 0; i < NUM_OC_PAR; i = i + 1)
                                partial_sum[i] <= psum_arr[oc_group][stream_cnt[6:2]][i];
                        end else begin
                            mmu_valid_in <= 1'b0;
                        end

                        // Write logic:
                        //   on valid_out -> write OC0, latch write_x, start write_active
                        //   while write_active -> write OC1..3
                        if (mmu_valid_out[0]) begin
                            fm2_addr     <= (oc_base) * FM2_CH_SIZE +
                                            y * OUT_W + x_recv;
                            fm2_din      <= q_relu_out[0];
                            fm2_we       <= 1'b1;
                            write_x      <= x_recv;
                            x_recv       <= x_recv + 5'd1;
                            write_phase  <= 2'd1;
                            write_active <= 1'b1;
                        end else if (write_active) begin
                            fm2_addr <= (oc_base + write_phase) * FM2_CH_SIZE +
                                        y * OUT_W + write_x;
                            fm2_din  <= q_relu_out[write_phase];
                            fm2_we   <= 1'b1;
                            if (write_phase == NUM_OC_PAR - 1)
                                write_active <= 1'b0;
                            else
                                write_phase <= write_phase + 2'd1;
                        end

                        // terminate
                        if (stream_cnt == P1_END) begin
                            mmu_valid_in <= 1'b0;
                            stream_cnt   <= 7'd0;
                            x_recv       <= 5'd0;
                            write_active <= 1'b0;
                            // next oc_group, next y, or done
                            if (oc_group < OC_GROUPS - 1) begin
                                oc_group <= oc_group + 2'd1;
                                oc_base  <= oc_base  + NUM_OC_PAR;
                                state    <= S_PRELOAD_WT;
                            end else begin
                                pass     <= 2'd0;
                                oc_group <= 2'd0;
                                oc_base  <= 4'd0;
                                if (y < OUT_H - 1) begin
                                    y     <= y + 5'd1;
                                    state <= S_LB_START;
                                end else begin
                                    state <= S_DONE;
                                end
                            end
                        end else begin
                            stream_cnt <= stream_cnt + 7'd1;
                        end
                    end
                end

                // --------------------------------------------------------
                S_DONE: begin
                    done         <= 1'b1;
                    mmu_valid_in <= 1'b0;
                    state        <= S_DONE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule