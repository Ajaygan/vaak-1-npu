// VAAK-1 - 8-Lane 1.58-Bit Ternary Dot-Product NPU Core
module ternary_npu_core (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        valid_in,
    input  logic signed [7:0] act [0:7],
    input  logic [1:0]  weight [0:7],
    output logic signed [15:0] acc_out,
    output logic        valid_out
);

    logic signed [15:0] lane_val [0:7];
    logic signed [15:0] dot_sum;

    always_comb begin
        for (int i = 0; i < 8; i++) begin
            case (weight[i])
                2'b01:   lane_val[i] = {{8{act[i][7]}}, act[i]};   // +1
                2'b11:   lane_val[i] = -{{8{act[i][7]}}, act[i]};  // -1
                default: lane_val[i] = 16'sd0;                     //  0
            endcase
        end

        dot_sum = (lane_val[0] + lane_val[1]) + (lane_val[2] + lane_val[3]) +
                  (lane_val[4] + lane_val[5]) + (lane_val[6] + lane_val[7]);
    end

    always_ff @(posedge clk or negedge rst_n) begin
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
