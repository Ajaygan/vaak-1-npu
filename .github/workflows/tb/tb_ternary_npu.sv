module tb_ternary_npu;
    logic        clk = 0;
    logic        rst_n;
    logic        valid_in;
    logic signed [7:0] act [0:7];
    logic [1:0]  weight [0:7];
    logic signed [15:0] acc_out;
    logic        valid_out;

    always #5 clk = ~clk;

    ternary_npu_core dut (.*);

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_ternary_npu);

        rst_n = 0; valid_in = 0;
        #15 rst_n = 1;

        // Frame 1 -> Expected Output = 3
        @(posedge clk);
        valid_in <= 1;
        act[0]<=8'sd10; act[1]<=8'sd20; act[2]<=-8'sd5; act[3]<=8'sd12;
        act[4]<=8'sd8;  act[5]<=-8'sd4; act[6]<=8'sd15; act[7]<=8'sd6;

        weight[0]<=2'b01; weight[1]<=2'b11; weight[2]<=2'b01; weight[3]<=2'b00;
        weight[4]<=2'b01; weight[5]<=2'b11; weight[6]<=2'b00; weight[7]<=2'b01;

        // Frame 2 -> Expected Output = 75
        @(posedge clk);
        act[0]<=8'sd25;  act[1]<=8'sd25;  act[2]<=8'sd25; act[3]<=8'sd25;
        act[4]<=-8'sd10; act[5]<=-8'sd10; act[6]<=8'sd0;  act[7]<=8'sd50;

        weight[0]<=2'b01; weight[1]<=2'b01; weight[2]<=2'b11; weight[3]<=2'b00;
        weight[4]<=2'b11; weight[5]<=2'b01; weight[6]<=2'b01; weight[7]<=2'b01;

        @(posedge clk);
        valid_in <= 0;
        #30 $finish;
    end

    always @(posedge clk) begin
        if (valid_out)
            $display("[Time %0t ns] VAAK-1 NPU Output = %0d", $time, acc_out);
    end
endmodule
