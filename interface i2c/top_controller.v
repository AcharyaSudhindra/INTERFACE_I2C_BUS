`timescale 1ns / 1ps

module top_controller #(
    // Clock / I2C frequency – override in testbench for fast simulation
    parameter INPUT_CLK_FREQ = 50_000_000,  // System clock (50 MHz default)
    parameter I2C_CLK_FREQ   = 100_000,     // I2C bus clock (100 kHz default)
    // Inter-transaction delay in clock cycles (65535 default ≈ 1.3 ms @ 50 MHz)
    // Set to a small value (e.g. 100) in the testbench for fast simulation.
    parameter INTER_TX_DELAY = 16'hFFFF
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start_demo,
    
    // Transaction payload (driven by testbench / tied on FPGA)
    input  wire [7:0] oled_wdata,
    input  wire [7:0] eeprom_ptr,
    
    // Outputs to observe states
    output wire [7:0] eeprom_data,
    output wire       demo_done,
    output wire       error_flag,
    
    // I2C bus
    inout  wire       sda,
    output wire       scl
);

    // I2C Master Interface
    reg        i2c_enable;
    reg        i2c_rw;
    reg  [6:0] i2c_addr;
    reg  [7:0] i2c_data_in;
    wire [7:0] i2c_data_out;
    wire       i2c_busy;
    wire       i2c_ack_error;
    
    i2c_master #(
        .INPUT_CLK_FREQ(INPUT_CLK_FREQ),
        .I2C_FREQ      (I2C_CLK_FREQ)
    ) master_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(i2c_enable),
        .rw(i2c_rw),
        .addr(i2c_addr),
        .data_in(i2c_data_in),
        .data_out(i2c_data_out),
        .busy(i2c_busy),
        .ack_error(i2c_ack_error),
        .sda(sda),
        .scl(scl)
    );

    // FSM States
    localparam S_IDLE            = 0;
    localparam S_WRITE_OLED      = 1;
    localparam S_WAIT_OLED       = 2;
    localparam S_DELAY           = 3; // Delay between transactions
    localparam S_WRITE_EEPROM_ADDR = 4;
    localparam S_WAIT_EEPROM_ADDR = 5;
    localparam S_READ_EEPROM     = 6;
    localparam S_WAIT_EEPROM     = 7;
    localparam S_DONE            = 8;
    localparam S_ERROR           = 9;

    reg [3:0] state;
    reg [7:0] captured_data;
    reg [15:0] delay_cnt;
    
    assign eeprom_data = captured_data;
    assign demo_done = (state == S_DONE);
    assign error_flag = (state == S_ERROR);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            i2c_enable <= 0;
            i2c_rw <= 0;
            i2c_addr <= 0;
            i2c_data_in <= 0;
            captured_data <= 0;
            delay_cnt <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    i2c_enable <= 0;
                    if (start_demo && !i2c_busy) begin
                        // Start by writing to OLED (0x3C)
                        state <= S_WRITE_OLED;
                        i2c_addr <= 7'h3C;
                        i2c_rw <= 0;
                        i2c_data_in <= oled_wdata;
                        i2c_enable <= 1;
                    end
                end

                S_WRITE_OLED: begin
                    if (i2c_busy) begin
                        i2c_enable <= 0;
                        state <= S_WAIT_OLED;
                    end
                end

                S_WAIT_OLED: begin
                    if (!i2c_busy) begin
                        if (i2c_ack_error) state <= S_ERROR;
                        else begin
                            state <= S_DELAY;
                            delay_cnt <= 0;
                        end
                    end
                end

                S_DELAY: begin
                    if (delay_cnt == INTER_TX_DELAY) begin
                        state <= S_WRITE_EEPROM_ADDR;
                        i2c_addr <= 7'h50; // EEPROM address
                        i2c_rw <= 0;
                        i2c_data_in <= eeprom_ptr; // Memory pointer byte
                        i2c_enable <= 1;
                    end else begin
                        delay_cnt <= delay_cnt + 1;
                    end
                end

                S_WRITE_EEPROM_ADDR: begin
                    if (i2c_busy) begin
                        i2c_enable <= 0;
                        state <= S_WAIT_EEPROM_ADDR;
                    end
                end

                S_WAIT_EEPROM_ADDR: begin
                    if (!i2c_busy) begin
                        if (i2c_ack_error) state <= S_ERROR;
                        else begin
                            state <= S_READ_EEPROM;
                            i2c_addr <= 7'h50;
                            i2c_rw <= 1; // READ mode
                            i2c_enable <= 1;
                        end
                    end
                end

                S_READ_EEPROM: begin
                    if (i2c_busy) begin
                        i2c_enable <= 0;
                        state <= S_WAIT_EEPROM;
                    end
                end

                S_WAIT_EEPROM: begin
                    if (!i2c_busy) begin
                        if (i2c_ack_error) state <= S_ERROR;
                        else begin
                            captured_data <= i2c_data_out;
                            state <= S_DONE;
                        end
                    end
                end

                S_DONE: begin
                    // Allow re-running the demo from the testbench
                    if (start_demo && !i2c_busy) begin
                        state <= S_WRITE_OLED;
                        i2c_addr <= 7'h3C;
                        i2c_rw <= 0;
                        i2c_data_in <= oled_wdata;
                        i2c_enable <= 1;
                    end
                end

                S_ERROR: begin
                    // Stay here
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
