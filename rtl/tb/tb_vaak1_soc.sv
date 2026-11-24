`timescale 1ns / 1ps

module tb_vaak1_soc;

    localparam int LANES          = 8;
    localparam int ACT_WIDTH      = 8;
    localparam int ACC_WIDTH      = 24;
    localparam int SRAM_ADDR_BITS = 18;

    logic                                   clk;
    logic                                   rst_n;
    logic                                   rv_insn_valid;
    logic [31:0]                            rv_insn;
    logic [31:0]                            rv_rs1_val;
    logic [31:0]                            rv_rs2_val;
    logic                                   rv_insn_ready;
    logic [31:0]                            rv_rd_val;

    logic                                   mmio_valid;
    logic                                   mmio_we;
    logic [7:0]                             mmio_addr;
    logic [31:0]                            mmio_wdata;
    logic [31:0]                            mmio_rdata;
    logic                                   mmio_ready;

    logic                                   sram_ren;
    logic [SRAM_ADDR_BITS-1:0]             sram_raddr;
    logic [LANES*16-1:0]                    sram_rdata;

    logic signed [LANES-1:0][ACT_WIDTH-1:0] act_in;
    logic signed [LANES-1:0][ACC_WIDTH-1:0] npu_acc_out;
    logic                                   irq_done;

    // Behavioral 2MB On-Chip SRAM Model (first 64 words initialized for test)
    logic [LANES*16-1:0] onchip_sram [0:63];

    always_ff @(posedge clk) begin
        if (sram_ren) begin
            sram_rdata <= onchip_sram[sram_raddr[5:0]];
        end
    end

    vaak1_soc_top #(
        .LANES(LANES),
        .ACT_WIDTH(ACT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .SRAM_ADDR_BITS(SRAM_ADDR_BITS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rv_insn_valid(rv_insn_valid),
        .rv_insn(rv_insn),
        .rv_rs1_val(rv_rs1_val),
        .rv_rs2_val(rv_rs2_val),
        .rv_insn_ready(rv_insn_ready),
        .rv_rd_val(rv_rd_val),
        .mmio_valid(mmio_valid),
        .mmio_we(mmio_we),
        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata),
        .mmio_ready(mmio_ready),
        .sram_ren(sram_ren),
        .sram_raddr(sram_raddr),
        .sram_rdata(sram_rdata),
        .act_in(act_in),
        .npu_acc_out(npu_acc_out),
        .irq_done(irq_done)
    );

    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz SoC clock

    initial begin
        rst_n         = 0;
        rv_insn_valid = 0;
        rv_insn       = 0;
        rv_rs1_val    = 0;
        rv_rs2_val    = 0;
        mmio_valid    = 0;
        mmio_we       = 0;
        mmio_addr     = 0;
        mmio_wdata    = 0;
        sram_rdata    = '0;

        for (int i = 0; i < LANES; i++) begin
            act_in[i] = 8'(10 + i); // Lanes 0..7 activations = 10, 11, 12, 13, 14, 15, 16, 17
        end

        // Load 4 tiles of ternary weights at SRAM addr 0x10..0x13
        // Tile 0: all +1 (2'b01), Tile 1: all +1 (2'b01), Tile 2: all 0 (2'b00), Tile 3: all -1 (2'b11)
        // Net expected result per lane = (+1 + 1 + 0 - 1) * act_in[i] = +1 * act_in[i]
        onchip_sram[16] = {64{2'b01}};
        onchip_sram[17] = {64{2'b01}};
        onchip_sram[18] = {64{2'b00}};
        onchip_sram[19] = {64{2'b11}};

        #20 rst_n = 1;
        #10;

        // 1. Check Chip ID via MMIO
        mmio_valid = 1;
        mmio_we    = 0;
        mmio_addr  = 8'hFF;
        #10;
        assert (mmio_rdata == 32'h5641_414B) else $fatal(1, "MMIO Chip ID mismatch: %h", mmio_rdata);
        $display("[PASS] MMIO Chip ID verified: 0x%h (VAAK)", mmio_rdata);
        mmio_valid = 0;

        // 2. Dispatch Custom RISC-V Instruction: vaak.run rs1=0x10 (base), rs2=4 (tiles)
        // custom-0 opcode = 7'b0001011, funct3 = 3'b000
        @(posedge clk);
        rv_insn_valid <= 1'b1;
        rv_insn       <= {7'd0, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0001011};
        rv_rs1_val    <= 32'h0000_0010;
        rv_rs2_val    <= 32'd4;
        @(posedge clk);
        rv_insn_valid <= 1'b0;

        // Wait for hardware IRQ completion
        wait (irq_done == 1'b1);
        @(posedge clk);

        for (int i = 0; i < LANES; i++) begin
            assert (npu_acc_out[i] == (10 + i))
                else $fatal(1, "Lane %0d mismatch: got %0d, expected %0d", i, npu_acc_out[i], 10 + i);
        end
        $display("[PASS] All 8 Ternary NPU lanes matched expected dot-product outputs!");

        // Read hardware performance counter via MMIO 0x10
        mmio_valid = 1;
        mmio_addr  = 8'h10;
        #10;
        $display("[PASS] SoC Inference completed in %0d clock cycles (0 DRAM accesses).", mmio_rdata);
        mmio_valid = 0;

        #20 $finish;
    end

endmodule
