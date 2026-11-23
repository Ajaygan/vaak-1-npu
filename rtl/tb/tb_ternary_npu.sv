module tb_ternary_npu;
    logic               clk = 0;
    logic               rst_n;
    logic               valid_in;
    logic signed [63:0] act_packed;
    logic        [15:0] weight_packed;
    logic signed [15:0] acc_out;
    logic               valid_out;

    always #5 clk = ~clk;

    ternary_npu_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .act_packed(act_packed),
        .weight_packed(weight_packed),
        .acc_out(acc_out),
        .valid_out(valid_out)
    );

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_ternary_npu);

        rst_n = 0; valid_in = 0;
        act_packed = 64'd0; weight_packed = 16'd0;
        #15 rst_n = 1;

        // Frame 1: [6, 15, -4, 8, 12, -5, 20, 10] dot [+1, 0, -1, +1, 0, +1, -1, +1] = 3
        @(posedge clk);
        valid_in <= 1;
        act_packed    <= {8'sd6, 8'sd15, -8'sd4, 8'sd8, 8'sd12, -8'sd5, 8'sd20, 8'sd10};
        weight_packed <= {2'b01, 2'b00, 2'b11, 2'b01, 2'b00, 2'b01, 2'b11, 2'b01};

        // Frame 2: [50, 0, -10, -10, 25, 25, 25, 25] dot [+1, +1, +1, -1, 0, -1, +1, +1] = 75
        @(posedge clk);
        act_packed    <= {8'sd50, 8'sd0, -8'sd10, -8'sd10, 8'sd25, 8'sd25, 8'sd25, 8'sd25};
        weight_packed <= {2'b01, 2'b01, 2'b01, 2'b11, 2'b00, 2'b11, 2'b01, 2'b01};

        @(posedge clk);
        valid_in <= 0;
        #30 $finish;
    end

    always @(posedge clk) begin
        if (valid_out)
            $display("[Time %0t ns] VAAK-1 NPU Output = %0d", $time, acc_out);
    end
endmodule
