# I2C Bus Interface in Verilog

This project implements a comprehensive, highly robust **Inter-Integrated Circuit (I2C) Master and Peripheral Simulation Environment** written entirely in Verilog HDL. It is designed to demonstrate a bit-banged I2C controller capable of driving standard 100 kHz I2C bus transactions from a high-frequency system clock (50 MHz), alongside a behavioral I2C slave model used to simulate real-world I2C peripherals.

## Features

- **Custom I2C Master Engine:** Strictly timed Finite State Machine (FSM) executing I2C protocol bit-banging with internal 4-phase clocking for guaranteed setup and hold times.
- **Dynamic Clock Divider:** Configurable parameters for system clock (`INPUT_CLK_FREQ`) and I2C bus speed (`I2C_FREQ`).
- **Robust I2C Behavioral Slave Model:** Parameterized slave address and read data. It dynamically monitors `SDA` and `SCL` for START and STOP conditions and precisely samples data to avoid race conditions.
- **Top-Level Application Layer:** An application controller orchestrating multi-byte I2C transactions including a write phase (to a simulated OLED display at `0x3C`) and a read phase (from a simulated EEPROM at `0x50`).
- **Comprehensive Verification:** A unified Vivado testbench (`tb_i2c_system.v`) that correctly models the bidirectional open-drain nature of I2C using pull-up resistors and verifies functional correctness.

---

## Directory Structure

- **`interface i2c/`** - Contains the core Verilog source files:
  - `i2c_master.v`: The low-level I2C protocol engine.
  - `top_controller.v`: The application layer initiating transactions.
  - `mock_i2c_slave.v` (or `i2c_slave.v`): The behavioral model for I2C peripherals.
  - `tb_i2c_system.v`: The unified global testbench for simulation.
- **`INTERFACE_I2C_BUS.xpr`**: The Xilinx Vivado project file.
- **`Comprehensive_I2C_Project_Report.md/pdf`**: In-depth technical report discussing the architecture, design choices, and bug resolutions.

---

## Theory of Operation

The I2C bus is a synchronous, multi-master, multi-slave, packet-switched serial communication bus requiring only two bidirectional open-drain lines: **SDA** (Serial Data) and **SCL** (Serial Clock). 

### 4-Phase Clocking
To guarantee strict adherence to I2C timing requirements, the Master divides the 100 kHz clock into 4 internal phases per cycle:
- **Phase 0:** Master changes the data on the SDA line.
- **Phase 1:** SCL is driven high.
- **Phase 2:** Master (or Slave) samples the data (setup time is thus guaranteed).
- **Phase 3:** SCL is driven low.

### State Machine Architecture
The `i2c_master` uses an FSM transitioning through the standard I2C framing steps: `IDLE` -> `START` -> `ADDR` (7-bit address + R/W bit) -> `ACK1` -> `WRITE`/`READ` (8-bit data) -> `ACK2` -> `STOP`.

---

## Getting Started

### Prerequisites
- **Xilinx Vivado** (or any standard Verilog simulator capable of handling bidirectional nets and pull-ups).
- Git (for cloning the repository).

### Running the Simulation in Vivado
1. **Open the Project:** Open `INTERFACE_I2C_BUS.xpr` in Vivado.
2. **Run Simulation:**
   - In the Flow Navigator, click **Run Simulation** -> **Run Behavioral Simulation**.
   - Vivado will compile the testbench (`tb_i2c_system.v`) and launch the XSIM simulator.
3. **Analyze Waveforms:**
   - The simulation will run for `300us`. 
   - You can observe the `sda` and `scl` lines.
   - At `t = 0 to 100 µs`, the master addresses the OLED (`0x3C`), receives an ACK, transmits `0xA5`, and stops.
   - At `t = 150 µs to 250 µs`, the master addresses the EEPROM (`0x50`) to read, and the slave replies with `0x42`.
4. **Console Output:** The TCL console will print the success message indicating the EEPROM data was correctly received.

Alternatively, you can simulate using ModelSim or Icarus Verilog by compiling the files in the `interface i2c/` directory and running `tb_i2c_system.v`.

---

## Engineering Details

During development, several complex digital design challenges were addressed:
1. **Floating Bus Issues:** Accurately simulating the open-drain nature of I2C using Verilog `pullup(sda)` to avoid immediate NACKs.
2. **Race Conditions / Hold-Time:** Separating the sampling (`posedge scl`) and state-transition (`negedge scl`) domains within the behavioral slave to prevent bit-shifting errors during address resolution.
3. **Multi-Driver Synthesizer Errors:** Refactoring START/STOP condition detectors inside the slave to avoid driving internal registers from multiple asynchronous edge detectors, making the model safe for strict compilers like Vivado's `xelab`.

*For an exhaustive breakdown of the state machines, timing diagrams, and bug fixes, refer to the included `Comprehensive_I2C_Project_Report`.*
