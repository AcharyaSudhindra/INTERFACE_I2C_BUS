# I2C Bus Interface in Verilog

This project implements an I2C (Inter-Integrated Circuit) bus interface in Verilog. It includes a custom I2C Master module, a top-level controller, a mock I2C slave for simulation, and a comprehensive testbench.

## Components

- **`i2c_master.v`**: The core I2C master controller, featuring a state machine that handles START, ADDR, ACK1, WRITE, READ, ACK2, and STOP conditions. It features a configurable clock divider to generate the appropriate I2C clock (SCL) frequency from a higher-frequency system clock.
- **`top_controller.v`**: A top-level module that interfaces with the `i2c_master` to execute higher-level sequences or transactions.
- **`mock_i2c_slave.v`**: A mock I2C slave device used for simulation and verification. It responds to specific I2C addresses and supports both read and write transactions.
- **`tb_i2c_system.v`**: The testbench for simulating the entire I2C system. It instantiates the top controller and two mock slaves (simulating an OLED display at address `0x3C` and an EEPROM at `0x50`). It runs a test sequence and checks for expected read-back values to verify correct operation.

## Simulation

The testbench (`tb_i2c_system.v`) can be run using any standard Verilog simulator (e.g., Vivado, ModelSim, Icarus Verilog). It generates a VCD file (`i2c_sim.vcd`) for waveform analysis.

To run the simulation, compile all the Verilog files in the `INTERFACE_I2C_BUS.srcs/sources_1/imports/interface i2c/` directory and execute the testbench.

## Configuration

The `i2c_master` module exposes parameters for easy configuration:
- `INPUT_CLK_FREQ`: The system clock frequency (default: 50 MHz).
- `I2C_FREQ`: The desired I2C bus clock frequency (default: 100 kHz).
