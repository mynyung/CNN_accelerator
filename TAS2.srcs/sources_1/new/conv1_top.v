`timescale 1ns / 1ps
 
module cnn_core(
    input wire clk,
    input wire resetn,
 
    input  wire start,
    output wire done,
 
    // image_mem external port
    input  wire        image_clka,
    input  wire        image_ena,
    input  wire        image_wea,
    input  wire [9:0]  image_addra,
    input  wire [7:0]  image_dina,
    output wire [7:0]  image_douta,
 
    // conv1_w_mem external port
    input  wire        w1_clka,
    input  wire        w1_ena,
    input  wire        w1_wea,
    input  wire [6:0]  w1_addra,
    input  wire [7:0]  w1_dina,
    output wire [7:0]  w1_douta,
 
    // conv2_w_mem external port
    input  wire        w2_clka,
    input  wire        w2_ena,
    input  wire        w2_wea,
    input  wire [10:0] w2_addra,
    input  wire [7:0]  w2_dina,
    output wire [7:0]  w2_douta,
 
    // fm2_mem external port
    input  wire        fm2_clka,
    input  wire        fm2_ena,
    input  wire        fm2_wea,
    input  wire [13:0] fm2_addra,
    input  wire [7:0]  fm2_dina,
    output wire [7:0]  fm2_douta,

    // pool_mem external readback port
    input  wire [11:0] pool_ext_addr,
    output wire [7:0]  pool_ext_dout,

    // fc_w_mem external port
    input  wire        fc_w_clka,
    input  wire        fc_w_ena,
    input  wire        fc_w_wea,
    input  wire [14:0] fc_w_addra,
    input  wire [7:0]  fc_w_dina,
    output wire [7:0]  fc_w_douta,

    // fc_out_mem external port
    input  wire        fc_out_clka,
    input  wire        fc_out_ena,
    input  wire        fc_out_wea,
    input  wire [3:0]  fc_out_addra,
    input  wire [31:0] fc_out_dina,
    output wire [31:0] fc_out_douta,

    output wire [3:0] predicted_digit,
    output wire signed [31:0] max_logit
);
 
    // -------------------------------------------------------------------------
    // Top FSM state encoding
    // -------------------------------------------------------------------------
    localparam T_IDLE    = 4'd0;
    localparam T_CONV1   = 4'd1;
    localparam T_CONV2   = 4'd2;
    localparam T_WAIT    = 4'd5;
    localparam T_MAXPOOL = 4'd3;
    localparam T_FC_WAIT = 4'd7;
    localparam T_FC      = 4'd6;
    localparam T_DONE    = 4'd4;
    localparam T_ARGMAX  = 4'd8;
 
    reg [3:0] top_state;

    reg conv1_start;
    reg conv2_start;
    reg maxpool_start;
    reg fc_start;
    reg argmax_start;
 
    wire conv1_done;
    wire conv2_done;
    wire maxpool_done;
    wire fc_done;
    wire argmax_done;

    assign done = (top_state == T_DONE);
 
    // -------------------------------------------------------------------------
    // Top FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            top_state     <= T_IDLE;
            conv1_start   <= 1'b0;
            conv2_start   <= 1'b0;
            maxpool_start <= 1'b0;
            fc_start      <= 1'b0;
            argmax_start  <= 1'b0;
        end else begin
            conv1_start   <= 1'b0;
            conv2_start   <= 1'b0;
            maxpool_start <= 1'b0;
            fc_start      <= 1'b0;
            argmax_start  <= 1'b0;
 
            case (top_state)
                T_IDLE: begin
                    if (start) begin
                        conv1_start <= 1'b1;
                        top_state   <= T_CONV1;
                    end
                end
 
                T_CONV1: begin
                    if (conv1_done) begin
                        conv2_start <= 1'b1;
                        top_state   <= T_CONV2;
                    end
                end
 
                T_CONV2: begin
                    if (conv2_done) begin
                        top_state <= T_WAIT;
                    end
                end
 
                T_WAIT: begin
                    maxpool_start <= 1'b1;
                    top_state     <= T_MAXPOOL;
                end
 
                T_MAXPOOL: begin
                    if (maxpool_done) begin
                        top_state <= T_FC_WAIT;
                    end
                end

                T_FC_WAIT: begin
                    fc_start  <= 1'b1;
                    top_state <= T_FC;
                end
 
                T_FC: begin
                    if (fc_done) begin
                        argmax_start <= 1'b1;
                        top_state    <= T_ARGMAX;
                    end
                end

                T_ARGMAX: begin
                    if (argmax_done) begin
                        top_state <= T_DONE;
                    end
                end

                T_DONE: begin
                    top_state <= T_DONE;
                end
 
                default: begin
                    top_state <= T_IDLE;
                end
            endcase
        end
    end
 
    // -------------------------------------------------------------------------
    // Conv1 internal wires
    // -------------------------------------------------------------------------
    wire [9:0]         conv1_img_addr;
    wire signed [7:0]  conv1_img_dout;

    wire [6:0]         conv1_w_addr;
    wire signed [7:0]  conv1_w_dout;

    wire [9:0]         conv1_fm1_addr;
    wire signed [63:0] conv1_fm1_din_vec;
    wire [7:0]         conv1_fm1_we_vec;
 
    // -------------------------------------------------------------------------
    // Conv2 internal wires
    // -------------------------------------------------------------------------
    wire [9:0]        conv2_fm1_addr0;
    wire [9:0]        conv2_fm1_addr1;
    wire [9:0]        conv2_fm1_addr2;
    wire [9:0]        conv2_fm1_addr3;

    wire signed [7:0] conv2_fm1_dout0;
    wire signed [7:0] conv2_fm1_dout1;
    wire signed [7:0] conv2_fm1_dout2;
    wire signed [7:0] conv2_fm1_dout3;

    wire              conv2_fm1_pass_sel;

    wire signed [7:0] fm1_ch0_dout;
    wire signed [7:0] fm1_ch1_dout;
    wire signed [7:0] fm1_ch2_dout;
    wire signed [7:0] fm1_ch3_dout;
    wire signed [7:0] fm1_ch4_dout;
    wire signed [7:0] fm1_ch5_dout;
    wire signed [7:0] fm1_ch6_dout;
    wire signed [7:0] fm1_ch7_dout;

    wire [10:0]       conv2_w_addr;
    wire signed [7:0] conv2_w_dout;

    wire [13:0]       conv2_fm2_addr;
    wire signed [7:0] conv2_fm2_din;
    wire              conv2_fm2_we;
    
    // -------------------------------------------------------------------------
    // MaxPool internal wires
    // -------------------------------------------------------------------------
    wire [13:0]       maxpool_fm2_addr;
    wire [7:0]        fm2_douta_int;
    wire [7:0]        fm2_doutb_int;

    wire [11:0]       pool_addr;
    wire signed [7:0] pool_din;
    wire              pool_we;

    // -------------------------------------------------------------------------
    // FC internal wires
    // -------------------------------------------------------------------------
    wire [11:0]        fc_pool_addr;
    wire signed [7:0]  fc_pool_dout;

    wire [14:0]        fc_w_addr_int;
    wire signed [7:0]  fc_w_dout_int;

    wire [3:0]         fc_out_addr_int;
    wire signed [31:0] fc_out_din_int;
    wire               fc_out_we_int;

    wire [3:0]         argmax_fc_out_addr;
    wire signed [31:0] argmax_fc_out_dout;

    wire [7:0]         pool_mem_douta_int;
    wire [31:0]        fc_out_douta_int;

    assign pool_ext_dout = pool_mem_douta_int;
    assign fc_pool_dout  = pool_mem_douta_int;

    assign fm2_douta = fm2_douta_int;

    assign argmax_fc_out_dout = fc_out_douta_int;
    assign fc_out_douta       = fc_out_douta_int;

    // -------------------------------------------------------------------------
    // Conv1 Instance
    // -------------------------------------------------------------------------
    conv1 u_conv1 (
        .clk          (clk),
        .resetn       (resetn),
        .start        (conv1_start),
        .done         (conv1_done),

        .img_addr     (conv1_img_addr),
        .img_dout     (conv1_img_dout),

        .w_addr       (conv1_w_addr),
        .w_dout       (conv1_w_dout),

        .fm1_addr     (conv1_fm1_addr),
        .fm1_din_vec  (conv1_fm1_din_vec),
        .fm1_we_vec   (conv1_fm1_we_vec)
    );
 
    // -------------------------------------------------------------------------
    // Conv2 Instance
    // IC 4 parallel × OC 4 parallel × 3×3 = 144 MACs
    // -------------------------------------------------------------------------
    conv2 #(
        .NUM_OC_PAR(4),
        .NUM_IC_PAR(4)
    ) u_conv2 (
        .clk       (clk),
        .resetn    (resetn),
        .start     (conv2_start),
        .done      (conv2_done),

        .fm1_addr0 (conv2_fm1_addr0),
        .fm1_addr1 (conv2_fm1_addr1),
        .fm1_addr2 (conv2_fm1_addr2),
        .fm1_addr3 (conv2_fm1_addr3),

        .fm1_dout0 (conv2_fm1_dout0),
        .fm1_dout1 (conv2_fm1_dout1),
        .fm1_dout2 (conv2_fm1_dout2),
        .fm1_dout3 (conv2_fm1_dout3),

        .fm1_pass_sel (conv2_fm1_pass_sel),

        .w_addr    (conv2_w_addr),
        .w_dout    (conv2_w_dout),

        .fm2_addr  (conv2_fm2_addr),
        .fm2_din   (conv2_fm2_din),
        .fm2_we    (conv2_fm2_we)
    );
 
    // -------------------------------------------------------------------------
    // MaxPool Instance
    // -------------------------------------------------------------------------
    maxpool u_maxpool (
        .clk       (clk),
        .resetn    (resetn),
        .start     (maxpool_start),
        .done      (maxpool_done),

        .fm2_addr  (maxpool_fm2_addr),
        .fm2_dout  (fm2_douta_int),

        .pool_addr (pool_addr),
        .pool_din  (pool_din),
        .pool_we   (pool_we)
    );

    // -------------------------------------------------------------------------
    // FC Instance
    // -------------------------------------------------------------------------
    FC u_fc (
        .clk         (clk),
        .resetn      (resetn),
        .start       (fc_start),
        .done        (fc_done),

        .pool_addr   (fc_pool_addr),
        .pool_dout   (fc_pool_dout),

        .fc_w_addr   (fc_w_addr_int),
        .fc_w_dout   (fc_w_dout_int),

        .fc_out_addr (fc_out_addr_int),
        .fc_out_din  (fc_out_din_int),
        .fc_out_we   (fc_out_we_int)
    );
    
    // -------------------------------------------------------------------------
    // Argmax Instance
    // -------------------------------------------------------------------------
    argmax10 u_argmax10 (
        .clk          (clk),
        .resetn       (resetn),
        .start        (argmax_start),
        .done         (argmax_done),

        .fc_out_addr  (argmax_fc_out_addr),
        .fc_out_dout  (argmax_fc_out_dout),

        .predicted_digit (predicted_digit),
        .max_logit       (max_logit)
    );
    
    // -------------------------------------------------------------------------
    // Memory enable routing
    // -------------------------------------------------------------------------
    wire image_mem_en;
    wire w1_mem_en;
    wire w2_mem_en;
    wire fm1_mem_en;
    wire fm2_mem_en_b;
 
    assign image_mem_en = (top_state == T_CONV1);
    assign w1_mem_en    = (top_state == T_CONV1);
    assign w2_mem_en    = (top_state == T_CONV2);

    assign fm1_mem_en   = (top_state == T_CONV1) || (top_state == T_CONV2);

    assign fm2_mem_en_b = (top_state == T_CONV2) || (top_state == T_WAIT);

    // -------------------------------------------------------------------------
    // Image RAM
    // -------------------------------------------------------------------------
    image_mem u_image_mem (
        .clka  (image_clka),
        .ena   (image_ena),
        .wea   (image_wea),
        .addra (image_addra),
        .dina  (image_dina),
        .douta (image_douta),

        .clkb  (clk),
        .enb   (image_mem_en),
        .web   (1'b0),
        .addrb (conv1_img_addr),
        .dinb  (8'd0),
        .doutb (conv1_img_dout)
    );
 
    // -------------------------------------------------------------------------
    // Conv1 Weights RAM
    // -------------------------------------------------------------------------
    conv1_w_mem u_conv1_w_mem (
        .clka  (w1_clka),
        .ena   (w1_ena),
        .wea   (w1_wea),
        .addra (w1_addra),
        .dina  (w1_dina),
        .douta (w1_douta),

        .clkb  (clk),
        .enb   (w1_mem_en),
        .web   (1'b0),
        .addrb (conv1_w_addr),
        .dinb  (8'd0),
        .doutb (conv1_w_dout)
    );
 
    // -------------------------------------------------------------------------
    // Conv2 FM1 read mux
    //
    // pass_sel = 0:
    //   dout0 = ch0, dout1 = ch1, dout2 = ch2, dout3 = ch3
    //
    // pass_sel = 1:
    //   dout0 = ch4, dout1 = ch5, dout2 = ch6, dout3 = ch7
    // -------------------------------------------------------------------------
    assign conv2_fm1_dout0 = (conv2_fm1_pass_sel == 1'b0) ? fm1_ch0_dout : fm1_ch4_dout;
    assign conv2_fm1_dout1 = (conv2_fm1_pass_sel == 1'b0) ? fm1_ch1_dout : fm1_ch5_dout;
    assign conv2_fm1_dout2 = (conv2_fm1_pass_sel == 1'b0) ? fm1_ch2_dout : fm1_ch6_dout;
    assign conv2_fm1_dout3 = (conv2_fm1_pass_sel == 1'b0) ? fm1_ch3_dout : fm1_ch7_dout;
 
    // -------------------------------------------------------------------------
    // Conv2 Weights RAM
    // -------------------------------------------------------------------------
    conv2_w_mem u_conv2_w_mem (
        .clka  (w2_clka),
        .ena   (w2_ena),
        .wea   (w2_wea),
        .addra (w2_addra),
        .dina  (w2_dina),
        .douta (w2_douta),

        .clkb  (clk),
        .enb   (w2_mem_en),
        .web   (1'b0),
        .addrb (conv2_w_addr),
        .dinb  (8'd0),
        .doutb (conv2_w_dout)
    );
 
    // -------------------------------------------------------------------------
    // FM1 channel memory banks
    //
    // Port A is unused.
    // Port B is shared:
    //   T_CONV1: Conv1 writes all 8 channels in parallel.
    //   T_CONV2: Conv2 reads 4 channels in parallel.
    //
    // Conv1:
    //   ch0~ch7 all use conv1_fm1_addr.
    //   ch0 data = conv1_fm1_din_vec[0*8 +: 8]
    //   ch1 data = conv1_fm1_din_vec[1*8 +: 8]
    //   ...
    //
    // Conv2 address mapping:
    //   ch0/ch4 <- conv2_fm1_addr0
    //   ch1/ch5 <- conv2_fm1_addr1
    //   ch2/ch6 <- conv2_fm1_addr2
    //   ch3/ch7 <- conv2_fm1_addr3
    // -------------------------------------------------------------------------

    fm1_ch0_mem u_fm1_ch0_mem (
        .clka  (clk),
        .ena   (1'b0),
        .wea   (1'b0),
        .addra (10'd0),
        .dina  (8'd0),
        .douta (),

        .clkb  (clk),
        .enb   (fm1_mem_en),
        .web   ((top_state == T_CONV1) ? conv1_fm1_we_vec[0] : 1'b0),
        .addrb ((top_state == T_CONV1) ? conv1_fm1_addr : conv2_fm1_addr0),
        .dinb  (conv1_fm1_din_vec[0*8 +: 8]),
        .doutb (fm1_ch0_dout)
    );

    fm1_ch1_mem u_fm1_ch1_mem (
        .clka  (clk),
        .ena   (1'b0),
        .wea   (1'b0),
        .addra (10'd0),
        .dina  (8'd0),
        .douta (),

        .clkb  (clk),
        .enb   (fm1_mem_en),
        .web   ((top_state == T_CONV1) ? conv1_fm1_we_vec[1] : 1'b0),
        .addrb ((top_state == T_CONV1) ? conv1_fm1_addr : conv2_fm1_addr1),
        .dinb  (conv1_fm1_din_vec[1*8 +: 8]),
        .doutb (fm1_ch1_dout)
    );

    fm1_ch2_mem u_fm1_ch2_mem (
        .clka  (clk),
        .ena   (1'b0),
        .wea   (1'b0),
        .addra (10'd0),
        .dina  (8'd0),
        .douta (),

        .clkb  (clk),
        .enb   (fm1_mem_en),
        .web   ((top_state == T_CONV1) ? conv1_fm1_we_vec[2] : 1'b0),
        .addrb ((top_state == T_CONV1) ? conv1_fm1_addr : conv2_fm1_addr2),
        .dinb  (conv1_fm1_din_vec[2*8 +: 8]),
        .doutb (fm1_ch2_dout)
    );

    fm1_ch3_mem u_fm1_ch3_mem (
        .clka  (clk),
        .ena   (1'b0),
        .wea   (1'b0),
        .addra (10'd0),
        .dina  (8'd0),
        .douta (),

        .clkb  (clk),
        .enb   (fm1_mem_en),
        .web   ((top_state == T_CONV1) ? conv1_fm1_we_vec[3] : 1'b0),
        .addrb ((top_state == T_CONV1) ? conv1_fm1_addr : conv2_fm1_addr3),
        .dinb  (conv1_fm1_din_vec[3*8 +: 8]),
        .doutb (fm1_ch3_dout)
    );

    fm1_ch4_mem u_fm1_ch4_mem (
        .clka  (clk),
        .ena   (1'b0),
        .wea   (1'b0),
        .addra (10'd0),
        .dina  (8'd0),
        .douta (),

        .clkb  (clk),
        .enb   (fm1_mem_en),
        .web   ((top_state == T_CONV1) ? conv1_fm1_we_vec[4] : 1'b0),
        .addrb ((top_state == T_CONV1) ? conv1_fm1_addr : conv2_fm1_addr0),
        .dinb  (conv1_fm1_din_vec[4*8 +: 8]),
        .doutb (fm1_ch4_dout)
    );

    fm1_ch5_mem u_fm1_ch5_mem (
        .clka  (clk),
        .ena   (1'b0),
        .wea   (1'b0),
        .addra (10'd0),
        .dina  (8'd0),
        .douta (),

        .clkb  (clk),
        .enb   (fm1_mem_en),
        .web   ((top_state == T_CONV1) ? conv1_fm1_we_vec[5] : 1'b0),
        .addrb ((top_state == T_CONV1) ? conv1_fm1_addr : conv2_fm1_addr1),
        .dinb  (conv1_fm1_din_vec[5*8 +: 8]),
        .doutb (fm1_ch5_dout)
    );

    fm1_ch6_mem u_fm1_ch6_mem (
        .clka  (clk),
        .ena   (1'b0),
        .wea   (1'b0),
        .addra (10'd0),
        .dina  (8'd0),
        .douta (),

        .clkb  (clk),
        .enb   (fm1_mem_en),
        .web   ((top_state == T_CONV1) ? conv1_fm1_we_vec[6] : 1'b0),
        .addrb ((top_state == T_CONV1) ? conv1_fm1_addr : conv2_fm1_addr2),
        .dinb  (conv1_fm1_din_vec[6*8 +: 8]),
        .doutb (fm1_ch6_dout)
    );

    fm1_ch7_mem u_fm1_ch7_mem (
        .clka  (clk),
        .ena   (1'b0),
        .wea   (1'b0),
        .addra (10'd0),
        .dina  (8'd0),
        .douta (),

        .clkb  (clk),
        .enb   (fm1_mem_en),
        .web   ((top_state == T_CONV1) ? conv1_fm1_we_vec[7] : 1'b0),
        .addrb ((top_state == T_CONV1) ? conv1_fm1_addr : conv2_fm1_addr3),
        .dinb  (conv1_fm1_din_vec[7*8 +: 8]),
        .doutb (fm1_ch7_dout)
    );
 
    // -------------------------------------------------------------------------
    // FM2 RAM
    // Port A:
    //   TB external access or MaxPool read
    // Port B:
    //   Conv2 write
    // -------------------------------------------------------------------------
    fm2_mem u_fm2_mem (
        .clka  (fm2_clka),
        .ena   ((top_state == T_MAXPOOL) ? 1'b1 : fm2_ena),
        .wea   ((top_state == T_MAXPOOL) ? 1'b0 : fm2_wea),
        .addra ((top_state == T_MAXPOOL) ? maxpool_fm2_addr : fm2_addra),
        .dina  (fm2_dina),
        .douta (fm2_douta_int),

        .clkb  (clk),
        .enb   (fm2_mem_en_b),
        .web   ((top_state == T_CONV2) ? conv2_fm2_we : 1'b0),
        .addrb ((top_state == T_CONV2) ? conv2_fm2_addr : 14'd0),
        .dinb  ((top_state == T_CONV2) ? conv2_fm2_din  : 8'd0),
        .doutb (fm2_doutb_int)
    );
    
    // -------------------------------------------------------------------------
    // Pool RAM
    // Port A: FC reads during T_FC, TB readback during T_DONE
    // Port B: MaxPool writes during T_MAXPOOL
    // -------------------------------------------------------------------------
    pool_mem u_pool_mem (
        .clka  (clk),
        .ena   ((top_state == T_FC) || (top_state == T_FC_WAIT) || (top_state == T_DONE)),
        .wea   (1'b0),
        .addra ((top_state == T_FC) ? fc_pool_addr : pool_ext_addr),
        .dina  (8'd0),
        .douta (pool_mem_douta_int),

        .clkb  (clk),
        .enb   (top_state == T_MAXPOOL),
        .web   (pool_we),
        .addrb (pool_addr),
        .dinb  (pool_din),
        .doutb ()
    );

    // -------------------------------------------------------------------------
    // FC Weights RAM
    // Port A: external load from TB
    // Port B: FC reads during T_FC
    // -------------------------------------------------------------------------
    fc_w_mem u_fc_w_mem (
        .clka  (fc_w_clka),
        .ena   (fc_w_ena),
        .wea   (fc_w_wea),
        .addra (fc_w_addra),
        .dina  (fc_w_dina),
        .douta (fc_w_douta),

        .clkb  (clk),
        .enb   (top_state == T_FC),
        .web   (1'b0),
        .addrb (fc_w_addr_int),
        .dinb  (8'd0),
        .doutb (fc_w_dout_int)
    );

    // -------------------------------------------------------------------------
    // FC Output RAM
    // Port A:
    //   T_ARGMAX: argmax reads
    //   T_DONE  : TB reads
    // Port B:
    //   T_FC: FC writes
    // -------------------------------------------------------------------------
    fc_out_mem u_fc_out_mem (
        .clka  (fc_out_clka),
        .ena   ((top_state == T_DONE) || (top_state == T_ARGMAX)),
        .wea   (1'b0),
        .addra ((top_state == T_ARGMAX) ? argmax_fc_out_addr : fc_out_addra),
        .dina  (32'd0),
        .douta (fc_out_douta_int),

        .clkb  (clk),
        .enb   (top_state == T_FC),
        .web   (fc_out_we_int),
        .addrb (fc_out_addr_int),
        .dinb  (fc_out_din_int),
        .doutb ()
    );
 
endmodule