`timescale 1ns / 1ps

module IMM #(
    parameter NUM_CENTROIDS = 16,                           
    parameter CENTROID_ADDR_WIDTH = $clog2(NUM_CENTROIDS),  
    parameter MEM_ADDR_WIDTH = 10,                          
    parameter VALUE_WIDTH_LUT = 8,                          
    parameter DATA_WIDTH_Spad = 32,                         
    parameter M = 20,         
    parameter N = 16,                                       
    parameter K = 16    
) (
    // General input signals
    input wire clk,
    input wire rst_n,

    // PSum LUT input signals
    input wire [MEM_ADDR_WIDTH-1:0] ctrl2psum_start_addr,
    input wire ctrl2psum_addr_valid,
    input wire [VALUE_WIDTH_LUT-1:0] mem2psum_lut_value,
 
    input wire fifo2psum_valid,
    input wire [CENTROID_ADDR_WIDTH-1:0] fifo2psum_index,

    // PSum LUT output signals
    output wire psum2ctrl_addr_ready,
    output wire psum2mem_re, 
    output wire [MEM_ADDR_WIDTH-1:0] psum2mem_addr,
    output wire psum2fifo_ready,

    // Scratchpad input signals
    input wire [MEM_ADDR_WIDTH-1:0] ctrl2spad_start_addr,
    input wire ctrl2spad_addr_valid,

    // Scratchpad output signals
    output wire spad2ctrl_addr_ready,
    output wire spad2out_we,      
    output wire [DATA_WIDTH_Spad-1:0] spad2out_data,
    output wire [MEM_ADDR_WIDTH-1:0] spad2out_addr,
    output wire spad2ctrl_done
);

    // Internal wires between Psum LUT & Scratchpad 
    wire spad2psum_ready;
    wire psum2spad_valid;
    wire [VALUE_WIDTH_LUT-1:0] psum2spad_value;

    // PSum LUT Instantiation
    PSUM_LUT #(
        .NUM_CENTROIDS(NUM_CENTROIDS),                       
        .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),                       
        .VALUE_WIDTH(VALUE_WIDTH_LUT),                        
        .INNER_LOOP_LIMIT(M),                     
        .CENTROID_ADDR_WIDTH(CENTROID_ADDR_WIDTH) 
    ) PSum_LUT_inst (
        .clk(clk),
        .rst_n(rst_n),
        .ctrl2psum_start_addr(ctrl2psum_start_addr),   
        .ctrl2psum_addr_valid(ctrl2psum_addr_valid),   
        .psum2ctrl_addr_ready(psum2ctrl_addr_ready),   
    
        .mem2psum_lut_value(mem2psum_lut_value),         
        .psum2mem_re(psum2mem_re),     
        .psum2mem_addr(psum2mem_addr),                 
        
        .fifo2psum_valid(fifo2psum_valid),   
        .fifo2psum_index(fifo2psum_index),             
        .psum2fifo_ready(psum2fifo_ready),             
        
        .spad2psum_ready(spad2psum_ready),             
        .psum2spad_valid(psum2spad_valid),             
        .psum2spad_value(psum2spad_value)              
    );

    // Scratchpad Instantiation
    Scratchpad #(
        .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
        .DATA_WIDTH_LUT_VALUE(VALUE_WIDTH_LUT),
        .DATA_WIDTH(DATA_WIDTH_Spad),      
        .M(M),               
        .N_COLS(N),          
        .K_SUBS(K)          
    ) Scratchpad_inst (
        .clk(clk),
        .rst_n(rst_n), 
        .ctrl2spad_start_addr(ctrl2spad_start_addr),
        .ctrl2spad_addr_valid(ctrl2spad_addr_valid),
        .spad2ctrl_addr_ready(spad2ctrl_addr_ready),
        
        .psum2spad_valid(psum2spad_valid),             
        .psum2spad_value(psum2spad_value),             
        .spad2psum_ready(spad2psum_ready), 
       
        .spad2out_we(spad2out_we),
        .spad2out_data(spad2out_data),
        .spad2out_addr(spad2out_addr),
        .spad2ctrl_done(spad2ctrl_done)
    );

endmodule