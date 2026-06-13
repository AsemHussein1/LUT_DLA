module input_buffer #(
    parameter VECTOR_LENGTH = 2,    // number of values per vector
    parameter INPUT_VALUE_WIDTH = 8,   // number of bits in a single value
    parameter NUM_INPUTS = 16,   // number of inputs (number of rows)
    parameter INPUT_ADDR_WIDTH = $clog2(NUM_INPUTS), // number of bits to count the inputs
    parameter ISRAM_ADDR_WIDTH = 10   // number of bits in the address of the input memory
)(
    // General signals
    input clk, 
    input rst_n,
    // controller signals
    input [ISRAM_ADDR_WIDTH-1:0] ctrl2ib_start_addr, 
    input ctrl2ib_valid, 
    output reg ib2ctrl_ready,

    // Port b ISRAM memory signals
    output reg ib2isb_re,                          // Read enable
    output reg [ISRAM_ADDR_WIDTH-1:0] ib2isb_addr,   // Read address
    input wire [INPUT_VALUE_WIDTH*VECTOR_LENGTH-1:0] isb2ib_data,  // Read data from SRAM

    // CCU signals
    input ccu2ib_ready,
    output reg ib2ccu_valid, 
    output reg [INPUT_VALUE_WIDTH*VECTOR_LENGTH-1:0] ib2ccu_ip_vector
);

// State Encodings
localparam IDLE      = 2'b00;
localparam READ      = 2'b01;
localparam STREAMING = 2'b10;

integer i;
reg [1:0] cs, ns;

// Counter and Flags
reg [ISRAM_ADDR_WIDTH-1:0] base_addr;
reg [INPUT_ADDR_WIDTH-1:0] addr_count, data_count; 
reg read_active; 

// Memory Array Declaration
reg [INPUT_VALUE_WIDTH*VECTOR_LENGTH-1:0] mem [0:NUM_INPUTS-1]; 

// State Memory
always @(posedge clk or negedge rst_n) begin 
    if(~rst_n)
        cs <= IDLE; 
    else 
        cs <= ns; 
end 

// Next State Logic
always @(*) begin
    ns = cs;
    case(cs)
        IDLE: 
            if(ib2ctrl_ready && ctrl2ib_valid)
                ns = READ;
        READ: 
            if(data_count == NUM_INPUTS-1)
                ns = STREAMING;
        STREAMING: 
            if(data_count == 0 && (ccu2ib_ready && ib2ccu_valid))
                ns = IDLE; 
    endcase 
end

// Output and Counter Logic
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        // Clear all outputs and tell controller we can accept data
        ib2ctrl_ready <= 1;  

        ib2isb_re <= 0;
        ib2isb_addr <= 0;
        read_active <= 0;

        ib2ccu_valid <= 0;
        ib2ccu_ip_vector <= 0;
        base_addr <= 0;
        // Empty the buffer entries and reset counter
        addr_count <= 0;
        data_count <= 0;
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin
        mem[i] <= 0;
        end
    end
    else begin
        case(cs)
            IDLE: begin
                // Clear all outputs and tell controller we can accept data
                ib2ccu_valid <= 0;
                ib2ccu_ip_vector <= 0;
                // Empty the buffer entries and reset counter
                addr_count <= 0;
                data_count <= 0;
                for (i = 0; i < NUM_INPUTS; i = i + 1) begin
                mem[i] <= 0;
                end

                if (ib2ctrl_ready && ctrl2ib_valid) begin
                    ib2ctrl_ready <= 0;
                    base_addr <= ctrl2ib_start_addr;

                    ib2isb_addr <= ctrl2ib_start_addr;
                    ib2isb_re <= 1;
                    read_active <= 1;

                end else begin
                    ib2ctrl_ready <= 1;
                    base_addr <= 0;

                    ib2isb_addr <= 0;
                    ib2isb_re <= 0;
                    read_active <= 0;
                end
            end

            READ: begin
                // Address generation logic
                if (read_active) begin
                    if (addr_count < NUM_INPUTS-1) begin        
                        addr_count <= addr_count + 1;
                        ib2isb_addr <= base_addr + addr_count +1;
                        ib2isb_re <= 1;
                    end else begin
                        ib2isb_addr <= 0;
                        ib2isb_re <= 0;
                        read_active <= 0;
                    end   
                end 
                // Data capture logic
                if (addr_count > 0) begin
                    mem[data_count] <= isb2ib_data;
                    if (data_count < NUM_INPUTS-1) begin
                        data_count <= data_count + 1;
                    end
                end

                if (data_count == NUM_INPUTS-1) begin
                    ib2ccu_valid <= 1;
                    ib2ccu_ip_vector <= mem[NUM_INPUTS - data_count -1];
                end
            end
            STREAMING: begin
                // Turn off valid signal immediately when buffer empties
                //if (data_count == 0 && (ccu2ib_ready && ib2ccu_valid)) begin
                //    ib2ccu_valid <= 0;
                //end else begin
                //    ib2ccu_valid <= 1;
                //    //ib2ccu_ip_vector <= mem[NUM_INPUTS - data_count -1];
                //    if (ccu2ib_ready && ib2ccu_valid) begin
                //        data_count <= data_count - 1;
                //        ib2ccu_ip_vector <= mem[NUM_INPUTS - data_count];
                //    end
                //end

                //if (ccu2ib_ready && ib2ccu_valid) begin
                //    if (data_count == 0) begin
                //        ib2ccu_valid <= 0;
                //    end else begin
                //        ib2ccu_valid <= 1;
                //        data_count <= data_count - 1;
                //        ib2ccu_ip_vector <= mem[NUM_INPUTS - data_count];
                //    end
                //end 

                if (ccu2ib_ready && ib2ccu_valid) begin
                    if (data_count == 0) begin
                        ib2ccu_valid <= 0;
                    end else begin
                        data_count <= data_count - 1;
                        ib2ccu_ip_vector <= mem[NUM_INPUTS - data_count];
                    end
                end else begin
                    ib2ccu_valid <= 1;
                end
            end
        endcase
    end
end
endmodule