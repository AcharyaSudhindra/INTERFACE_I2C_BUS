module test;
    reg [7:0] shift_reg;
    initial begin
        shift_reg[6] = 0;
        shift_reg[5] = 1;
        shift_reg[4] = 1;
        shift_reg[3] = 1;
        shift_reg[2] = 1;
        shift_reg[1] = 0;
        shift_reg[0] = 0;
        $display("shift_reg[6:0] = %h", shift_reg[6:0]);
        $display("shift_reg = %h", shift_reg);
    end
endmodule
