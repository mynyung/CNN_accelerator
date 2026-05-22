`timescale 1ns / 1ps

module FC(
    input  wire        clk, 
    input  wire        resetn, 
    input  wire        start, 
    output reg         done, 
    
    // pool_mem read 
    output reg  [11:0] pool_addr, 
    input  wire signed [7:0] pool_dout, 
    
    // fc weight memory read 
    output reg  [14:0] fc_w_addr, 
    input  wire signed [7:0] fc_w_dout, 
    
    // output logits memory write 
    output reg  [3:0]  fc_out_addr, 
    output reg  signed [31:0] fc_out_din, 
    output reg         fc_out_we
);
    
    localparam IN_SIZE  = 12'd2304; 
    localparam OUT_SIZE = 4'd10; 
    
    localparam S_IDLE      = 3'd0; 
    localparam S_LOAD_ADDR = 3'd1; 
    localparam S_WAIT_READ = 3'd2; 
    localparam S_ACCUM     = 3'd3; 
    localparam S_WRITE     = 3'd4; 
    localparam S_NEXT_OUT  = 3'd5; 
    localparam S_DONE      = 3'd6; 
    
    reg [2:0]  state; 
    reg [11:0] input_idx;
    reg [3:0]  out_idx;
    reg signed [31:0] acc; 
    reg signed [31:0] final_acc; 
    reg [14:0] row_base_addr;

    wire signed [15:0] mult; 
    wire signed [31:0] mult_ext; 
    
    assign mult     = pool_dout * fc_w_dout; 
    assign mult_ext = {{16{mult[15]}}, mult}; 

    always @(posedge clk or negedge resetn) begin 
        if (!resetn) begin 
            state         <= S_IDLE; 
            done          <= 1'b0; 
            pool_addr     <= 12'd0; 
            fc_w_addr     <= 15'd0; 
            fc_out_addr   <= 4'd0; 
            fc_out_din    <= 32'sd0; 
            fc_out_we     <= 1'b0; 
            final_acc     <= 32'sd0;
            input_idx     <= 12'd0; 
            out_idx       <= 4'd0; 
            acc           <= 32'sd0;
            row_base_addr <= 15'd0;
        end else begin 
            case (state) 
                   
                S_IDLE: begin 
                    done          <= 1'b0; 
                    fc_out_we     <= 1'b0; 
                    final_acc     <= 32'sd0;
                    input_idx     <= 12'd0; 
                    out_idx       <= 4'd0; 
                    acc           <= 32'sd0;
                    row_base_addr <= 15'd0;
                    if (start) 
                        state <= S_LOAD_ADDR; 
                end 
                       
                S_LOAD_ADDR: begin 
                    fc_out_we <= 1'b0; 
                    pool_addr <= input_idx; 
                    fc_w_addr <= row_base_addr + {3'd0, input_idx}; 
                    state     <= S_WAIT_READ; 
                end 

                S_WAIT_READ: begin 
                    state <= S_ACCUM; 
                end 

                S_ACCUM: begin  
                    if (input_idx < IN_SIZE - 1) begin 
                        acc       <= acc + mult_ext; 
                        input_idx <= input_idx + 12'd1; 
                        state     <= S_LOAD_ADDR; 
                    end else begin 
                        final_acc <= acc + mult_ext; 
                        state     <= S_WRITE; 
                    end 
                end

                S_WRITE: begin 
                    fc_out_addr <= out_idx; 
                    fc_out_din  <= final_acc>>>10; 
                    fc_out_we   <= 1'b1; 
                    state       <= S_NEXT_OUT; 
                end 

                S_NEXT_OUT: begin 
                    fc_out_we <= 1'b0; 
                    if (out_idx < OUT_SIZE - 1) begin 
                        out_idx       <= out_idx + 4'd1;
                        row_base_addr <= row_base_addr + 15'd2304;
                        input_idx     <= 12'd0; 
                        acc           <= 32'sd0;
                        final_acc     <= 32'sd0; 
                        state         <= S_LOAD_ADDR; 
                    end else begin 
                        state <= S_DONE; 
                    end 
                end 

                S_DONE: begin 
                    done      <= 1'b1; 
                    fc_out_we <= 1'b0; 
                    state     <= S_DONE; 
                end 

                default: state <= S_IDLE; 
                        
            endcase 
        end 
    end 
          
endmodule