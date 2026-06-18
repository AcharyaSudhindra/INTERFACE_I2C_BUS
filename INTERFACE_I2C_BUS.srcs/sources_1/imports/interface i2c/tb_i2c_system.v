`timescale 1ns / 1ps

module tb_i2c_system;

    reg clk;
    reg rst_n;
    reg start_demo;
    
    wire [7:0] eeprom_data;
    wire demo_done;
    wire error_flag;
    
    wire sda;
    wire scl;

    // Pull-ups for I2C bus (simulated by pulling weak high)
    pullup (sda);
    pullup (scl);

    // Instantiate Top Controller (Master)
    top_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_demo(start_demo),
        .eeprom_data(eeprom_data),
        .demo_done(demo_done),
        .error_flag(error_flag),
        .sda(sda),
        .scl(scl)
    );

    // I2C Devices on the bus:
    // Instantiate OLED Display Slave (Address: 0x3C)
    i2c_slave #(
        .SLAVE_ADDR(7'h3C),
        .READ_DATA(8'h00)
    ) oled_slave (
        .sda(sda),
        .scl(scl)
    );

    // Instantiate EEPROM Slave (Address: 0x50)
    // Setup to return 0x42 when read
    i2c_slave #(
        .SLAVE_ADDR(7'h50),
        .READ_DATA(8'h42)
    ) eeprom_slave (
        .sda(sda),
        .scl(scl)
    );
    // Clock generation (50 MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk; 
    end

    // Test sequence
    initial begin
        // Initialize
        rst_n = 0;
        start_demo = 0;
        
        #100;
        rst_n = 1;
        
        #100;
        // Start transaction sequence
        start_demo = 1;
        #20;
        start_demo = 0;

        // Wait for demo to finish
        wait (demo_done == 1'b1 || error_flag == 1'b1);
        
        #1000;
        if (error_flag) begin
            $display("TEST FAILED: I2C transaction error detected.");
        end else if (eeprom_data == 8'h42) begin
            $display("TEST PASSED: EEPROM data read successfully (0x42).");
        end else begin
            $display("TEST FAILED: Incorrect data read from EEPROM: %h", eeprom_data);
        end
        
        $finish;
    end

    // Dump waves
    initial begin
        $dumpfile("i2c_sim.vcd");
        $dumpvars(0, tb_i2c_system);
    end

endmodule
