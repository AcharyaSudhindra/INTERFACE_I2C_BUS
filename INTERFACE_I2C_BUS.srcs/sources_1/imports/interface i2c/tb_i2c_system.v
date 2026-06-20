`timescale 1ns / 1ps

// ============================================================
// tb_i2c_system.v
//
// WHY sda/scl look flat in Vivado:
//   Default sim runs only 1000 ns.  I2C needs microseconds.
//   Fix: re-launch sim, then in Tcl Console type:  run 200us
//   Or press F3 (Run All).
//
// Input bytes below go onto the SDA bus when start_demo fires:
//   oled_wdata  = 0xA5  → written to OLED  (addr 0x3C)
//   eeprom_ptr  = 0x00  → EEPROM pointer  (addr 0x50)
// ============================================================
module tb_i2c_system;

    // Fast I2C for simulation ONLY (hardware stays 100 kHz in top_controller default)
    localparam SIM_I2C_FREQ = 5_000_000;  // 5 MHz → SDA/SCL toggle every ~400 ns
    localparam SIM_DELAY    = 16'd50;     // 50 clk = 1 us gap between transactions

    reg        clk;
    reg        rst_n;
    reg        start_demo;
    reg [7:0]  oled_wdata;   // data byte sent to OLED  — watch on waveform
    reg [7:0]  eeprom_ptr;   // pointer byte sent to EEPROM

    wire [7:0] eeprom_data;
    wire       demo_done;
    wire       error_flag;
    wire       sda;
    wire       scl;

    wire [3:0] master_state;
    wire [3:0] ctrl_state;
    wire       oled_addressed;
    wire       eeprom_addressed;
    wire [7:0] oled_shift_reg;
    wire [7:0] eeprom_shift_reg;

    pullup (sda);
    pullup (scl);

    top_controller #(
        .INPUT_CLK_FREQ(50_000_000),
        .I2C_CLK_FREQ  (SIM_I2C_FREQ),
        .INTER_TX_DELAY(SIM_DELAY)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_demo (start_demo),
        .oled_wdata (oled_wdata),
        .eeprom_ptr (eeprom_ptr),
        .eeprom_data(eeprom_data),
        .demo_done  (demo_done),
        .error_flag (error_flag),
        .sda        (sda),
        .scl        (scl)
    );

    assign master_state     = dut.master_inst.state;
    assign ctrl_state       = dut.state;
    assign oled_addressed   = oled_slave.is_addressed;
    assign eeprom_addressed = eeprom_slave.is_addressed;
    assign oled_shift_reg   = oled_slave.shift_reg;
    assign eeprom_shift_reg = eeprom_slave.shift_reg;

    i2c_slave #(.SLAVE_ADDR(7'h3C), .READ_DATA(8'h00)) oled_slave   (.sda(sda), .scl(scl));
    i2c_slave #(.SLAVE_ADDR(7'h50), .READ_DATA(8'h42)) eeprom_slave (.sda(sda), .scl(scl));

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;   // 50 MHz
    end

    initial begin
        #2_000_000;   // watchdog 2 ms
        $display("[%0t ns] WATCHDOG timeout", $time);
        $finish;
    end

    initial begin
        $display("==================================================");
        $display("  I2C test — sim I2C %0d MHz", SIM_I2C_FREQ / 1_000_000);
        $display("  Input: oled_wdata=0x%02h  eeprom_ptr=0x%02h", oled_wdata, eeprom_ptr);
        $display("  Run at least 200 us in Vivado to see sda/scl toggle");
        $display("==================================================");

        rst_n      = 1'b0;
        start_demo = 1'b0;
        oled_wdata = 8'hA5;   // ← this byte appears on SDA during OLED write
        eeprom_ptr = 8'h00;   // ← this byte appears on SDA during EEPROM write

        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(10) @(posedge clk);

        @(posedge clk); #1;
        start_demo = 1'b1;
        $display("[%0t ns] start_demo HIGH", $time);
        repeat(5) @(posedge clk); #1;
        start_demo = 1'b0;
        $display("[%0t ns] start_demo LOW  — I2C bus should start toggling now", $time);

        wait (demo_done === 1'b1 || error_flag === 1'b1);
        #50_000;   // hold 50 us so final values visible on waveform

        if (error_flag)
            $display("RESULT: FAILED (NACK)");
        else if (eeprom_data === 8'h42)
            $display("RESULT: PASSED  eeprom_data=0x%02h  oled_shift=0x%02h",
                     eeprom_data, oled_shift_reg);
        else
            $display("RESULT: FAILED  eeprom_data=0x%02h", eeprom_data);

        $finish;
    end

    initial begin
        $dumpfile("i2c_sim.vcd");
        $dumpvars(0, tb_i2c_system);
    end

endmodule
