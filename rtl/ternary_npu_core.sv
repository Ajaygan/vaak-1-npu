// VAAK-1 - 8-Lane 1.58-Bit Ternary Dot-Product NPU Core
// Synthesizable generate-block RTL (0 hardware multipliers)
module ternary_npu_core (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               valid_in,
    input  logic signed [63:0] act_packed,     // 8 x 8-bit signed activations
    input  logic        [15:0] weight_packed,  // 8 x 2-bit ternary weights
    output logic signed [15:0] acc_out,
    output logic               valid_out
);

    wire signed [15:0] lane_val [0:7];
    wire signed [15:0] dot_sum;

    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : ternary_lane
            wire signed [7:0] act_slice    = act_packed[g*8 +: 8];
            wire        [1:0] weight_slice = weight_packed[g*2 +: 2];

            // 2'b01 = +1 (Pass), 2'b11 = -1 (Negate), 2'b00 = 0 (Zero)
            assign lane_val[g] = (weight_slice == 2'b01) ? {{8{act_slice[7]}}, act_slice} :
                                 (weight_slice == 2'b11) ? -{{8{act_slice[7]}}, act_slice} :
                                 16'sd0;
        end
    endgenerate

    // Parallel adder tree
    assign dot_sum = (lane_val[0] + lane_val[1]) + (lane_val[2] + lane_val[3]) +
                     (lane_val[4] + lane_val[5]) + (lane_val[6] + lane_val[7]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out   <= 16'sd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in)
                acc_out <= dot_sum;
        end
    end

endmodule
