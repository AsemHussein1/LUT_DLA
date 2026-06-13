module SYNC_R2W #(
	parameter NUM_STAGES = 2 , FIFO_DEPTH = 16, parameter DATA_WIDTH=16,parameter max_fifo_addr= $clog2(FIFO_DEPTH))(
	input  clk,    					  // Clock
	input  rst_n,  					  // Asynchronous reset active low
	input  [max_fifo_addr:0]  r_ptr,  // read pointer
	output [max_fifo_addr:0] SYNC_R2W
);

reg [max_fifo_addr :0] D_FF [NUM_STAGES-1 :0];
integer i;

//multiple flip flop 
always @(posedge clk or negedge rst_n) begin 
	if(~rst_n) begin
		for (i = 0; i < NUM_STAGES; i = i + 1) begin
			D_FF[i] <= {(max_fifo_addr+1){1'b0}};
		end
	end 
	else begin
		D_FF[0] <= r_ptr;
		for (i = 1; i < NUM_STAGES; i = i + 1) begin
			D_FF[i] <= D_FF[i-1];
		end
	end
end

assign SYNC_R2W = D_FF[NUM_STAGES-1];

endmodule : SYNC_R2W