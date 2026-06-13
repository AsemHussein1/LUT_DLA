//=============================================================================
// cdc_pulse_sync.v
// Pulse/Handshake Clock Domain Crossing Synchronizer
//
// note on source side: (dont think it will occur)
// Consecutive pulses must be separated by atleast (N_SYNC+2) dst_clk cycles to guarantee distinctness
//=============================================================================
`timescale 1ns / 1ps

module cdc_pulse_sync #(
    parameter N_SYNC = 3   // synchroniser FF-chain depth (must be >= 2)
)(
    // Source clock domain 
    input  wire  src_clk,       // source clock
    input  wire  src_resetn,    // source reset
    input  wire  src_pulse_i,   // single-cycle pulse in src_clk domain

    // Destination clock domain 
    input  wire  dst_clk,       // destination clock
    input  wire  dst_resetn,    // destination reset
    output wire  dst_pulse_o    // reconstructed single-cycle pulse in dst_clk domain
);

// Source-domain toggle latch
// Each incoming pulse flips the toggle; the change propagates through the synchronizer chain
reg src_toggle;
always @(posedge src_clk or negedge src_resetn) begin
    if (!src_resetn)
        src_toggle <= 1'b0;
    else if (src_pulse_i)
        src_toggle <= ~src_toggle;
end

// Destination-domain synchroniser chain
(* ASYNC_REG = "TRUE" *) reg [N_SYNC-1:0] sync_chain;

always @(posedge dst_clk or negedge dst_resetn) begin
    if (!dst_resetn)
        sync_chain <= {N_SYNC{1'b0}};
    else
        sync_chain <= {sync_chain[N_SYNC-2:0], src_toggle};
end

// Edge detection to reconstruct single-cycle pulse
assign dst_pulse_o = sync_chain[N_SYNC-1] ^ sync_chain[N_SYNC-2];
endmodule