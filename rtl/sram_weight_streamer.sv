// VAAK-1 - On-Chip DRAM-Free SRAM Weight Streamer
// Packs 8 x 2-bit ternary weights per 16-bit SRAM word (4 weights/byte)
// Streams 16-bit bursts into ternary_npu_core with 0 external DRAM accesses
module sram_weight_streamer #(
    parameter ADDR_WIDTH = 20,      // 2^20 x 16-bit words = 2,097,152 bytes (2 MB SRAM)
    parameter MEM_DEPTH  = 256      // Synthesizable behavioral slice for RTL simulation
) (
    input  logic                  clk,
    input  logic                  rst_n,
    // Control Interface (from RISC-V Host Core)
    input  logic                  start_burst,
    input  logic [ADDR_WIDTH-1:0] base_addr,
    input  logic [15:0]           burst_len,
    // SRAM Write Port (Initial weight load from MRAM/Flash)
    input  logic                  sram_we,
    input  logic [ADDR_WIDTH-1:0] sram_waddr,
    input  logic [15:0]           sram_wdata,
    // Streaming Output to ternary_npu_core
    output logic [15:0]           weight_packed,
    output logic                  weight_valid,
    output logic                  burst_done
);

    // On-chip SRAM bank (16-bit wide: holds 8 ternary weights per address)
    logic [15:0] sram_bank [0:MEM_DEPTH-1];

    logic [ADDR_WIDTH-1:0] current_addr;
    logic [15:0]           words_remaining;
    logic                  streaming;

    // Synchronous SRAM Write Port
    always @(posedge clk) begin
        if (sram_we) begin
            sram_bank[sram_waddr[7:0]] <= sram_wdata;
        end
    end

    // Zero-Stall Burst Controller & Synchronous SRAM Read Port
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_addr    <= {ADDR_WIDTH{1'b0}};
            words_remaining <= 16'd0;
            streaming       <= 1'b0;
            weight_packed   <= 16'd0;
            weight_valid    <= 1'b0;
            burst_done      <= 1'b0;
        end else begin
            burst_done <= 1'b0;

            if (start_burst && (burst_len > 16'd0)) begin
                streaming       <= 1'b1;
                current_addr    <= base_addr;
                words_remaining <= burst_len;
                weight_valid    <= 1'b0;
            end else if (streaming) begin
                // Read 8 packed ternary weights in 1 clock cycle
                weight_packed <= sram_bank[current_addr[7:0]];
                weight_valid  <= 1'b1;

                if (words_remaining == 16'd1) begin
                    streaming       <= 1'b0;
                    words_remaining <= 16'd0;
                    burst_done      <= 1'b1;
                end else begin
                    current_addr    <= current_addr + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                    words_remaining <= words_remaining - 16'd1;
                end
            end else begin
                weight_valid <= 1'b0;
            end
        end
    end

endmodule
