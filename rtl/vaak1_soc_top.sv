`timescale 1ns / 1ps

module vaak1_soc_top #(
    parameter int LANES          = 8,
    parameter int ACT_WIDTH      = 8,
    parameter int ACC_WIDTH      = 24,
    parameter int SRAM_ADDR_BITS = 18  // 256K x 64-bit = 2 MB On-Chip SRAM
)(
    input  logic                                    clk,
    input  logic                                    rst_n,

    // 32-bit RISC-V Custom Instruction Coprocessor Interface (custom-0: 0x0B)
    input  logic                                    rv_insn_valid,
    input  logic [31:0]                             rv_insn,
    input  logic [31:0]                             rv_rs1_val,   // Weight SRAM Base Addr / Config
    input  logic [31:0]                             rv_rs2_val,   // Tile Count
    output logic                                    rv_insn_ready,
    output logic [31:0]                             rv_rd_val,

    // 32-bit RISC-V MMIO Bus Interface (Base: 0x4000_0000)
    input  logic                                    mmio_valid,
    input  logic                                    mmio_we,
    input  logic [7:0]                              mmio_addr,
    input  logic [31:0]                             mmio_wdata,
    output logic [31:0]                             mmio_rdata,
    output logic                                    mmio_ready,

    // On-Chip 2 MB SRAM Read Port (DRAM-Free)
    output logic                                    sram_ren,
    output logic [SRAM_ADDR_BITS-1:0]              sram_raddr,
    input  logic [LANES*16-1:0]                     sram_rdata,   // 8 lanes x 8 trits (2 bits/trit = 16 bits/lane)

    // Streaming Activation Input & Inference Output
    input  logic signed [LANES-1:0][ACT_WIDTH-1:0]  act_in,
    output logic signed [LANES-1:0][ACC_WIDTH-1:0]  npu_acc_out,
    output logic                                    irq_done
);

    // RISC-V Custom-0 Opcode Definition (0001011 = 0x0B)
    localparam logic [6:0] OPCODE_CUSTOM0 = 7'b0001011;

    // Control & Status Registers
    logic [SRAM_ADDR_BITS-1:0] reg_weight_base;
    logic [15:0]               reg_tile_len;
    logic [31:0]               reg_perf_cycles;
    logic                      reg_busy;
    logic                      reg_done;
    logic                      start_pulse;
    logic                      soft_rst_pulse;

    // Internal Streamer & NPU Signals
    logic [SRAM_ADDR_BITS-1:0] ptr_addr;
    logic [15:0]               tiles_remaining;
    logic                      npu_valid_pipe;
    logic [1:0]                trit_code [LANES-1:0];

    // Decode RISC-V Custom Instruction
    wire is_custom0   = rv_insn_valid && (rv_insn[6:0] == OPCODE_CUSTOM0);
    wire [2:0] funct3 = rv_insn[14:12];

    assign rv_insn_ready = !reg_busy;
    assign mmio_ready    = 1'b1;
    assign irq_done      = reg_done;

    // MMIO & Custom Opcode Control Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_weight_base <= '0;
            reg_tile_len    <= 16'd0;
            start_pulse     <= 1'b0;
            soft_rst_pulse  <= 1'b0;
        end else begin
            start_pulse    <= 1'b0;
            soft_rst_pulse <= 1'b0;

            // Priority 1: Direct RISC-V Custom Instruction (Zero-Overhead Hardware Dispatch)
            if (is_custom0 && !reg_busy) begin
                case (funct3)
                    3'b000: begin
                        // vaak.run rs1(base), rs2(len) -> Configure & Launch in 1 cycle
                        reg_weight_base <= rv_rs1_val[SRAM_ADDR_BITS-1:0];
                        reg_tile_len    <= rv_rs2_val[15:0];
                        start_pulse     <= 1'b1;
                    end
                    3'b001: begin
                        // vaak.cfg rs1(base), rs2(len) -> Preload registers
                        reg_weight_base <= rv_rs1_val[SRAM_ADDR_BITS-1:0];
                        reg_tile_len    <= rv_rs2_val[15:0];
                    end
                    default: ;
                endcase
            end
            // Priority 2: Standard MMIO Register Writes
            else if (mmio_valid && mmio_we) begin
                case (mmio_addr)
                    8'h00: begin
                        if (mmio_wdata[0] && !reg_busy) start_pulse    <= 1'b1;
                        if (mmio_wdata[1])              soft_rst_pulse <= 1'b1;
                    end
                    8'h08: reg_weight_base <= mmio_wdata[SRAM_ADDR_BITS-1:0];
                    8'h0C: reg_tile_len    <= mmio_wdata[15:0];
                    default: ;
                endcase
            end
        end
    end

    // MMIO & Custom Instruction Readback
    always_comb begin
        rv_rd_val  = {16'd0, reg_perf_cycles[15:0]};
        mmio_rdata = 32'd0;
        case (mmio_addr)
            8'h00: mmio_rdata = {30'd0, soft_rst_pulse, reg_busy};
            8'h04: mmio_rdata = {16'd0, 8'(LANES), 6'd0, reg_done, reg_busy};
            8'h08: mmio_rdata = {{(32-SRAM_ADDR_BITS){1'b0}}, reg_weight_base};
            8'h0C: mmio_rdata = {16'd0, reg_tile_len};
            8'h10: mmio_rdata = reg_perf_cycles;
            default: mmio_rdata = 32'h5641_414B; // ASCII "VAAK" ID
        endcase
    end

    // DRAM-Free On-Chip SRAM Burst Streamer FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || soft_rst_pulse) begin
            reg_busy        <= 1'b0;
            reg_done        <= 1'b0;
            sram_ren        <= 1'b0;
            sram_raddr      <= '0;
            ptr_addr        <= '0;
            tiles_remaining <= 16'd0;
            npu_valid_pipe  <= 1'b0;
            reg_perf_cycles <= 32'd0;
        end else begin
            npu_valid_pipe <= sram_ren;

            if (start_pulse) begin
                reg_busy        <= 1'b1;
                reg_done        <= 1'b0;
                ptr_addr        <= reg_weight_base;
                tiles_remaining <= reg_tile_len;
                reg_perf_cycles <= 32'd0;
                sram_ren        <= (reg_tile_len > 0);
                sram_raddr      <= reg_weight_base;
            end else if (reg_busy) begin
                reg_perf_cycles <= reg_perf_cycles + 32'd1;

                if (tiles_remaining > 16'd1) begin
                    tiles_remaining <= tiles_remaining - 16'd1;
                    ptr_addr        <= ptr_addr + 1'b1;
                    sram_raddr      <= ptr_addr + 1'b1;
                    sram_ren        <= 1'b1;
                end else begin
                    sram_ren <= 1'b0;
                    if (!npu_valid_pipe) begin
                        reg_busy <= 1'b0;
                        reg_done <= 1'b1;
                    end
                end
            end
        end
    end

    // 8-Lane Multiplier-Free 1.58-Bit Ternary MAC Array ({-1, 0, +1})
    // Encoding per trit: 2'b01 -> +1, 2'b11 -> -1, 2'b00 -> 0 (Zero-skip gated)
    genvar g;
    generate
        for (g = 0; g < LANES; g++) begin : gen_ternary_lanes
            assign trit_code[g] = sram_rdata[g*2 +: 2];

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n || soft_rst_pulse || start_pulse) begin
                    npu_acc_out[g] <= '0;
                end else if (npu_valid_pipe) begin
                    case (trit_code[g])
                        2'b01:   npu_acc_out[g] <= npu_acc_out[g] + ACC_WIDTH'(act_in[g]); // +1
                        2'b11:   npu_acc_out[g] <= npu_acc_out[g] - ACC_WIDTH'(act_in[g]); // -1
                        default: npu_acc_out[g] <= npu_acc_out[g];                         //  0 (Skip)
                    endcase
                end
            end
        end
    endgenerate

endmodule
