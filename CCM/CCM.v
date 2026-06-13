module CCM #(
    // General parameters
    parameter VECTOR_LENGTH = 2,    // number of values per centroid/vector
    parameter VALUE_WIDTH = 8,   // number of bits in a single value
    parameter NUM_INPUTS = 1024,
    // Centroid Buffer parameters
    parameter NUM_CENTROIDS = 16,   // number of centroids
    parameter CENTROID_ADDR_WIDTH = $clog2(NUM_CENTROIDS), // number of bits to count the centroids
    parameter CSRAM_ADDR_WIDTH = 10, // number of bits in the address of the centroid memory
    // Input buffer parameters
    parameter INPUT_ADDR_WIDTH = $clog2(NUM_INPUTS),
    parameter ISRAM_ADDR_WIDTH = 10   // number of bits in the address of the input memory
    
    //parameter CENTROID_INDEX_WIDTH = 8 // number of bits in the centroid index to fifo
    // CCU parameters

) (
    // General input signals
    input clk,
    input rst_n,

    // Centroid buffer input signals
    // controller signals
    input [CSRAM_ADDR_WIDTH-1:0] ctrl2cb_start_addr,
    input ctrl2cb_addr_valid,
    output cb2ctrl_addr_ready,
    // Port b CSRAM memory signals
    output cb2csb_re,                          // Read enable
    output [CSRAM_ADDR_WIDTH-1:0] cb2csb_addr,   // Read address
    input [VALUE_WIDTH*VECTOR_LENGTH-1:0] csb2cb_data,  // Read data from CSRAM

    // Input Buffer input signals
    // controller signals
    input [ISRAM_ADDR_WIDTH-1:0] ctrl2ib_start_addr, 
    input ctrl2ib_valid, 
    output ib2ctrl_ready,
    // Port b ISRAM memory signals
    output ib2isb_re,                          // Read enable
    output [ISRAM_ADDR_WIDTH-1:0] ib2isb_addr,   // Read address
    input [VALUE_WIDTH*VECTOR_LENGTH-1:0] isb2ib_data,  // Read data from SRAM
    
    // CCU signals
    // controller signals
    output ccu_done, 
    // FIFO signals
    input fifo2ccu_ready,
    output [CENTROID_ADDR_WIDTH-1:0] ccu2fifo_idx,
    output ccu2fifo_valid

);

    // Internal wires between Centroid buffer & CCU
    wire ccu2cb_ready;
    wire [NUM_CENTROIDS*VALUE_WIDTH*VECTOR_LENGTH-1:0] cb2ccu_centroids;
    wire cb2ccu_valid;
    
    // Internal wires between Input buffer & CCU
    wire ccu2ib_ready; 
    wire ib2ccu_valid; 
    wire [VALUE_WIDTH*VECTOR_LENGTH-1:0] ib2ccu_ip_vector;

    // Centroid Buffer
    centroid_buffer #(
        .NUM_CENTROIDS(NUM_CENTROIDS),
        .VECTOR_LENGTH(VECTOR_LENGTH),
        .CENTROID_VALUE_WIDTH(VALUE_WIDTH),
        .CENTROID_ADDR_WIDTH(CENTROID_ADDR_WIDTH),
        .CSRAM_ADDR_WIDTH(CSRAM_ADDR_WIDTH)
    ) u_centroid_buffer (
        .clk(clk),
        .rst_n(rst_n),

        // Control & Memory Interface
        .ctrl2cb_start_addr(ctrl2cb_start_addr),        //|< i
        .ctrl2cb_addr_valid(ctrl2cb_addr_valid),        //|< i
        .cb2ctrl_addr_ready(cb2ctrl_addr_ready),        //|< o

        .cb2csb_re(cb2csb_re),                          //|< o                    
        .cb2csb_addr(cb2csb_addr),                      //|< o 
        .csb2cb_data(csb2cb_data),                      //|< i

        // Internal CCU Connections
        .ccu2cb_ready(ccu2cb_ready),                    //|< w
        .cb2ccu_centroids(cb2ccu_centroids),            //|< w
        .cb2ccu_valid(cb2ccu_valid)                     //|< w
    );

    // Instantiate the Input Buffer
    input_buffer #(
        .VECTOR_LENGTH(VECTOR_LENGTH),
        .INPUT_VALUE_WIDTH(VALUE_WIDTH),
        .NUM_INPUTS(NUM_INPUTS),
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .ISRAM_ADDR_WIDTH(ISRAM_ADDR_WIDTH)

        ) u_input_buffer (
        .clk(clk),
        .rst_n(rst_n),

        // Control & Memory Interface
        .ctrl2ib_valid(ctrl2ib_valid),              //|< i
        .ctrl2ib_start_addr(ctrl2ib_start_addr),    //|< i
        .ib2ctrl_ready(ib2ctrl_ready),              //|< o

        .ib2isb_re(ib2isb_re),                      //|< o
        .ib2isb_addr(ib2isb_addr),                  //|< o
        .isb2ib_data(isb2ib_data),                  //|< i
        
        // Internal CCU Connections
        .ccu2ib_ready(ccu2ib_ready),                //|< w
        .ib2ccu_valid(ib2ccu_valid),                //|< w
        .ib2ccu_ip_vector(ib2ccu_ip_vector)         //|< w
    );

    // Instantiate the CCU
    CCU #(
    .NUM_DPES(NUM_CENTROIDS),
    .V_LEN(VECTOR_LENGTH),
    .BW(VALUE_WIDTH),
    .IDX_BW(CENTROID_ADDR_WIDTH),
    .M_ROWS(NUM_INPUTS)
    ) u_ccu (
    .clk(clk),
    .rst_n(rst_n),

    // Control Interface
    .fifo2ccu_ready(fifo2ccu_ready),            //|< i
    .ccu_done(ccu_done),                        //|< o
    .ccu2fifo_idx(ccu2fifo_idx),                //|< o
    .ccu2fifo_valid(ccu2fifo_valid),            //|< o

    // Internal IB Connections
    .ib2ccu_ip_vector(ib2ccu_ip_vector),        //|< w
    .ib2ccu_valid(ib2ccu_valid),             //|< w
    .ccu2ib_ready(ccu2ib_ready),               //|< w

    // Internal CB Connections
    .cb2ccu_valid(cb2ccu_valid),                //|< w
    .cb2ccu_centroids(cb2ccu_centroids),        //|< w 
    .ccu2cb_ready(ccu2cb_ready)                //|< w
    
);
endmodule