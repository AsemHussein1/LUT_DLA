module Scratchpad #(
    parameter MEM_ADDR_WIDTH = 10,
    parameter DATA_WIDTH_LUT_VALUE = 16,
    parameter DATA_WIDTH = 32,      
    parameter M = 15,               
    parameter N_COLS = 16,          
    parameter K_SUBS = 16           
)(
    input wire clk,             
    input wire rst_n,  

    // Controller
    input wire [MEM_ADDR_WIDTH-1:0] ctrl2spad_start_addr,
    input wire ctrl2spad_addr_valid,
    output reg spad2ctrl_addr_ready,
    
    // PsumLUT Interface
    input wire [DATA_WIDTH_LUT_VALUE-1:0] psum2spad_value,  
    input wire psum2spad_valid,           
    output reg spad2psum_ready,

    // Output Interface
    output reg spad2out_we,     
    output reg [DATA_WIDTH-1:0] spad2out_data,
    output reg [MEM_ADDR_WIDTH-1:0] spad2out_addr,

    output reg spad2ctrl_done
);
    
    localparam TOTAL_ELEMENTS = M * N_COLS;
    localparam INT_ADDR_WIDTH = $clog2(TOTAL_ELEMENTS);
    
    // Memory declaration
    reg [DATA_WIDTH-1:0] mem_array [0 : TOTAL_ELEMENTS - 1];

    // ---- Internal counters and registers ----
    //Accumulation
    reg [$clog2(M)-1:0] m_count;
    reg [$clog2(K_SUBS)-1:0] k_sub_count;
    reg [$clog2(N_COLS)-1:0] n_col_count;
    reg [INT_ADDR_WIDTH-1:0] acc_col_base; //current column start
    // Streaming
    reg [INT_ADDR_WIDTH-1:0] stream_count;
    reg [$clog2(M)-1:0] stream_row;
    reg [$clog2(N_COLS)-1:0] stream_col;
    reg [INT_ADDR_WIDTH-1:0] stream_row_base; // row start for row-major output
    reg [MEM_ADDR_WIDTH-1:0] base_addr; // Saved start address from controller

    // Internal wire for current write index (Column-Major)
    wire [INT_ADDR_WIDTH-1:0] acc_current_addr = acc_col_base + m_count;

    // FSM States
    localparam IDLE      = 3'b000;
    localparam ACCUM     = 3'b001;
    localparam GET_ADDR  = 3'b010;
    localparam STREAM    = 3'b011;
    localparam DONE      = 3'b100;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            m_count <= 0;
            k_sub_count <= 0;
            n_col_count <= 0;

            acc_col_base <= 0;

            stream_count <= 0;
            stream_row <= 0;
            stream_col <= 0;
            stream_row_base <= 0;
            
            base_addr <= 0;

            spad2psum_ready <= 1'b1;
            spad2out_we <= 1'b0;
            spad2ctrl_addr_ready <= 1'b0;
            spad2ctrl_done <= 1'b0;
        end else begin
            case (state)
                
                IDLE: begin
                    spad2psum_ready <= 1'b1;
                    spad2ctrl_done <= 1'b0;
                    spad2ctrl_addr_ready <= 1'b0;

                    if (psum2spad_valid && spad2psum_ready) begin
                        state <= ACCUM;
                        mem_array[acc_current_addr] <= psum2spad_value;
                        m_count <= m_count + 1;
                    end
                end

                ACCUM: begin
                    if (psum2spad_valid && spad2psum_ready) begin
                        // Accumulation: Read-Modify-Write
                        if (k_sub_count == 0)
                            mem_array[acc_current_addr] <= psum2spad_value;
                        else
                            mem_array[acc_current_addr] <= mem_array[acc_current_addr] + psum2spad_value;

                        // Increment Row
                        if (m_count == M - 1) begin
                            m_count <= 0;
                            // Increment Subspace
                            if (k_sub_count == K_SUBS - 1) begin
                                k_sub_count <= 0;
                                // Increment Column
                                if (n_col_count == N_COLS - 1) begin
                                    n_col_count <= 0;
                                    acc_col_base <= 0;
                                    state <= GET_ADDR;
                                    spad2psum_ready <= 1'b0;
                                    spad2ctrl_addr_ready <= 1'b1;
                                end else begin
                                    n_col_count <= n_col_count + 1;
                                    acc_col_base <= acc_col_base + M;
                                end
                            end else begin
                                k_sub_count <= k_sub_count + 1;
                            end
                        end else begin
                            m_count <= m_count + 1;
                        end
                    end
                end

                GET_ADDR: begin
                    if (ctrl2spad_addr_valid && spad2ctrl_addr_ready) begin
                        base_addr <= ctrl2spad_start_addr;
                        spad2ctrl_addr_ready <= 1'b0;
                        state <= STREAM;
                        
                        // Reset stream counters
                        stream_count <= 0;
                        stream_row <= 0;
                        stream_col <= 0;
                        stream_row_base <= 0;

                        // Pre-fetch first element (Row 0, Col 0)
                        spad2out_data <= mem_array[0]; 
                        spad2out_addr <= ctrl2spad_start_addr;
                        spad2out_we <= 1'b1;
                    end
                end

                STREAM: begin
                    if (stream_count == TOTAL_ELEMENTS - 1) begin
                        spad2out_we <= 1'b0;
                        state <= DONE;
                    end else begin
                        // Logic for Row-Major Output from Column-Major Memory
                        if (stream_col == N_COLS - 1) begin
                            stream_col <= 0;
                            stream_row <= stream_row + 1;
                            // Start of next row is just stream_row + 1
                            spad2out_data <= mem_array[stream_row + 1];
                            stream_row_base <= 0; 
                        end else begin
                            stream_col <= stream_col + 1;
                            // Next element in same row is current index + M
                            spad2out_data <= mem_array[(stream_row_base + M) + stream_row];
                            stream_row_base <= stream_row_base + M;
                        end
                        
                        stream_count <= stream_count + 1;
                        spad2out_addr <= base_addr + (stream_count + 1);
                        spad2out_we <= 1'b1;
                    end
                end

                DONE: begin
                    spad2ctrl_done <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule