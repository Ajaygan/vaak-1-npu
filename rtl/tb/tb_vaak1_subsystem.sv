// VAAK-1 Subsystem Verification: On-Chip SRAM Streamer -> Ternary NPU Core
module tb_vaak1_subsystem;
    logic               clk = 0;
    logic               rst_n;

    // Streamer control & write signals
    logic               start_burst;
    logic [19:0]        base_addr;
    logic [15:0]        burst_len;
    logic               sram_we;
    logic [19:0]        sram_waddr;
    logic [15:0]        sram_wdata;

    // Interconnect wires (SRAM Streamer -> NPU Core)
    logic [15:0]        streamed_weights;
    logic               stream_valid;
    logic               burst_done;

    // NPU activation & output signals
    logic signed [63:0] act_packed;
    logic signed [15:0] acc_out;
    logic               npu_valid_out;

    always #5 clk = ~clk;

    // 1. Instantiate On-Chip SRAM Weight Streamer
    sram_weight_streamer #(
        .ADDR_WIDTH(20),
        .MEM_DEPTH(256)
    ) u_sram (
        .clk(clk),
        .rst_n(rst_n),
        .start_burst(start_burst),
        .base_addr(base_addr),
        .burst_len(burst_len),
        .sram_we(sram_we),
        .sram_waddr(sram_waddr),
        .sram_wdata(sram_wdata),
        .weight_packed(streamed_weights),
        .weight_valid(stream_valid),
        .burst_done(burst_done)
    );

    // 2. Instantiate 1.58-Bit Ternary NPU Core
    ternary_npu_core u_npu (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(stream_valid),
        .act_packed(act_packed),
        .weight_packed(streamed_weights),
        .acc_out(acc_out),
        .valid_out(npu_valid_out)
    );

    initial begin
        $dumpfile("subsystem_dump.vcd");
        $dumpvars(0, tb_vaak1_subsystem);

        rst_n = 0; start_burst = 0; sram_we = 0;
        base_addr = 20'd0; burst_len = 16'd0;
        sram_waddr = 20'd0; sram_wdata = 16'd0;
        act_packed = 64'd0;
        #15 rst_n = 1;

        // Step 1: Preload 2 packed weight vectors into on-chip SRAM (Addr 0x00010 & 0x00011)
        @(posedge clk);
        sram_we    <= 1'b1;
        sram_waddr <= 20'h00010;
        // Weights: [+1, 0, -1, +1, 0, +1, -1, +1]
        sram_wdata <= {2'b01, 2'b00, 2'b11, 2'b01, 2'b00, 2'b01, 2'b11, 2'b01};

        @(posedge clk);
        sram_waddr <= 20'h00011;
        // Weights: [+1, +1, +1, -1, 0, -1, +1, +1]
        sram_wdata <= {2'b01, 2'b01, 2'b01, 2'b11, 2'b00, 2'b11, 2'b01, 2'b01};

        @(posedge clk);
        sram_we <= 1'b0;

        // Step 2: Trigger a 2-word zero-stall burst from SRAM address 0x00010
        @(posedge clk);
        base_addr   <= 20'h00010;
        burst_len   <= 16'd2;
        start_burst <= 1'b1;

        @(posedge clk);
        start_burst <= 1'b0;

        // Align Frame 1 activations with Cycle 1 SRAM read -> Expected NPU output = 3
        @(posedge clk);
        act_packed <= {8'sd6, 8'sd15, -8'sd4, 8'sd8, 8'sd12, -8'sd5, 8'sd20, 8'sd10};

        // Align Frame 2 activations with Cycle 2 SRAM read -> Expected NPU output = 75
        @(posedge clk);
        act_packed <= {8'sd50, 8'sd0, -8'sd10, -8'sd10, 8'sd25, 8'sd25, 8'sd25, 8'sd25};

        #40 $finish;
    end

    always @(posedge clk) begin
        if (npu_valid_out)
            $display("[Time %0t ns] VAAK-1 SRAM->NPU Subsystem Output = %0d", $time, acc_out);
    end
endmodule
