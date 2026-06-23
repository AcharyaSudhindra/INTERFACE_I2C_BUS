# I2C Bus Interface in Verilog HDL

**Author:** Acharya Sudhindra  
**Repository:** AcharyaSudhindra/INTERFACE_I2C_BUS  
**Tool:** Xilinx Vivado 2024 + xSim Simulator  
**Language:** Verilog HDL (IEEE 1364-2001)  
**Date:** June 2026

---

## 📌 Project Overview

This project implements a complete **I2C (Inter-Integrated Circuit) Master-Slave communication system** in Verilog HDL, built and simulated inside Xilinx Vivado. It is a digital hardware design project—not software—meaning every module describes real logic that can be synthesized onto an FPGA chip.

The project demonstrates:
- A custom bit-banged I2C Master controller running at 100 kHz.
- Two behavioral I2C Slave models (for simulation).
- An application-layer controller that runs real I2C transactions.
- A unified testbench that verifies all components work correctly.

---

## 📚 I2C Protocol Basics

I2C is a 2-wire serial communication protocol that uses only two signals:
- **SDA (Serial Data Line):** Bidirectional data transfer line.
- **SCL (Serial Clock Line):** Driven by the master device.

Both lines are "open-drain", meaning any device can pull a line LOW (to `0`), but lines float HIGH (to `1`) through external pull-up resistors when no one drives them. This allows multiple devices to share the same two wires without causing a short circuit.

### Standard I2C Transaction Phases:
1. **START condition:** SDA goes LOW while SCL is HIGH.
2. **Address phase:** Master sends 7-bit device address (MSB first).
3. **R/W bit:** 1 bit — `0` = Master wants to Write, `1` = Master wants to Read.
4. **ACK 1:** Slave pulls SDA LOW to acknowledge its address was received.
5. **Data phase:** 8 bits of data (direction depends on R/W bit).
6. **ACK 2:** Receiver acknowledges the data byte.
7. **STOP condition:** SDA goes HIGH while SCL is HIGH (releases the bus).

> **Crucial Timing Rule:** Data is ALWAYS valid (stable) while SCL is HIGH. Data can ONLY change while SCL is LOW. This timing rule is the foundation of how the master and slave modules were designed.

---

## 📁 Project File Structure

```text
INTERFACE_I2C_BUS/
|
|-- interface i2c/                  <-- All Verilog source files
|   |-- i2c_master.v                (228 lines) - The core I2C engine
|   |-- top_controller.v            (184 lines) - Application layer
|   |-- i2c_slave.v                 (196 lines) - Behavioral slave v1
|   |-- mock_i2c_slave.v            (168 lines) - Behavioral slave v2 (improved)
|   |-- tb_i2c_system.v             (125 lines) - Testbench
|
|-- INTERFACE_I2C_BUS.xpr           - Xilinx Vivado project file
|-- INTERFACE_I2C_BUS.srcs/         - Vivado source management folder
|-- INTERFACE_I2C_BUS.sim/          - Vivado simulation folder
```

---

## ⚙️ Detailed Module Breakdown

### 1. `i2c_master.v` (The Core Engine)
Implements the complete I2C protocol for the Master side. It handles bit-banging: generating SCL, controlling SDA, and sequencing all I2C phases (START, ADDR, ACK, WRITE/READ, STOP).

#### Ports:
- **Inputs:** `clk` (System clock, default 50 MHz), `rst_n` (Active-low reset), `enable` (Pulse HIGH to start), `rw` (0=Write, 1=Read), `addr[6:0]`, `data_in[7:0]`.
- **Outputs:** `data_out[7:0]`, `busy`, `ack_error`, `scl`.
- **Bidirectional:** `sda` (The I2C Serial Data Line - inout, tri-state).

#### Clock Divider Mechanism:
The master takes a 50 MHz system clock and divides it down to 100 kHz. Each 100 kHz I2C clock cycle is subdivided into **4 PHASES** (125 system clock cycles per phase):
- **Phase 00:** SCL is LOW — master CHANGES SDA here.
- **Phase 01:** SCL goes HIGH (rising edge).
- **Phase 10:** SCL is HIGH — data SAMPLED here.
- **Phase 11:** SCL goes LOW (falling edge).
This guarantees SDA is stable before SCL rises (setup time) and after SCL falls (hold time), satisfying the I2C specification perfectly.

#### FSM States (8 states):
- `IDLE`: Bus is free. Waits for `enable`.
- `START`: Generates the START condition.
- `ADDR`: Shifts out the 8-bit `tx_data` (7-bit address + R/W bit).
- `ACK1`: Releases SDA to let slave respond. Checks for NACK.
- `WRITE`: Shifts out 8 data bits from `tx_data`.
- `READ`: Releases SDA, samples 8 bits from slave.
- `ACK2`: For WRITE: samples slave's ACK. For READ: master sends NACK to stop.
- `STOP`: Generates the STOP condition.

---

### 2. `top_controller.v` (Application Layer)
Acts as the "user application" layer. It does not handle individual bits — it handles entire I2C transactions. It decides WHICH device to talk to, WHAT data to send, and WHAT to do with the result.

#### Functionality:
- Writes to an OLED display (Simulated SSD1306 at address `0x3C`).
- Writes to and reads from an EEPROM (Simulated AT24C at address `0x50`).
- Implements an `INTER_TX_DELAY` (65535 cycles ≈ 1.3 ms) to mimic real hardware write cycle times between transactions.

#### FSM States (10 states):
- Transitions through `S_IDLE`, `S_WRITE_OLED`, `S_WAIT_OLED`, `S_DELAY`, `S_WRITE_EEPROM_ADDR`, `S_WAIT_EEPROM_ADDR`, `S_READ_EEPROM`, `S_WAIT_EEPROM`, `S_DONE`, and `S_ERROR`.

---

### 3. `i2c_slave.v` & `mock_i2c_slave.v` (Behavioral Slaves)
Simulation-only behavioral models of I2C slave devices. They respond to a specific address, send back a fixed byte on READ, and ACK write data.

- **`i2c_slave.v` (Version 1):** Uses dual-edge sensitivity. Had issues with multi-driver compilation errors in Vivado.
- **`mock_i2c_slave.v` (Version 2, Improved):** Redesigned to fix Vivado multi-driver compilation errors. START/STOP detection uses dedicated single-bit flags (`start_seen`, `stop_seen`) written by exactly one `always` block. The main state machine triggers strictly on `negedge scl` or `posedge` of the start/stop flags.

---

### 4. `tb_i2c_system.v` (Testbench)
The top-level simulation testbench. Connects all modules together, generates stimulus, checks results, and prints PASS/FAIL.

- **Key Feature:** Instantiates the mandatory I2C pull-up resistors (`pullup(sda); pullup(scl);`) which are critical for an open-drain bus simulation.
- **Simulation Flow:**
  1. Asserts reset.
  2. Asserts `start_demo` for 5 clock cycles.
  3. Waits for `demo_done=1` or `error_flag=1`.
  4. Checks if the data read from EEPROM matches the expected value (`0x42`).

---

## 🐞 Bug History & Debugging Journey

During development, several critical hardware and simulation bugs were found and fixed:

### Bug 1: Floating Bus → Immediate NACK
- **Symptom:** The master sent the address `0x3C`, but received an immediate NACK (`ack_error=1`).
- **Root Cause:** The testbench had missing instantiation lines for the slave modules. With no slave modules connected, SDA was held HIGH by the pull-up resistor at all times, which the master interpreted as a NACK.
- **Fix:** Added explicit instantiation lines for both OLED and EEPROM slave modules.

### Bug 2: Wrong Address Decoded (0x78 instead of 0x3C)
- **Symptom:** Slave received address `0x78` instead of `0x3C` (a 1-bit left shift).
- **Root Cause:** Delta-cycle race condition. The slave was sampling SDA on the `negedge SCL` handler, exactly when the master was also changing SDA for the next phase.
- **Fix:** Rewrote the sampling logic to trigger on `posedge SCL` where the data is guaranteed to be stable by the I2C specification.

### Bug 3: Multi-Driver Compilation Error (Vivado xelab VRFC 10-529)
- **Symptom:** Vivado threw a fatal error: `[VRFC 10-529] concurrent assignment to a non-net is not permitted`.
- **Root Cause:** Registers `is_addressed` and `bit_count` were assigned inside two separate `always` blocks (one for START condition, one for clock edges).
- **Fix:** Refactored START/STOP detectors into dedicated single-bit registers. The main state machine now strictly reads these flags instead of being driven by multiple procedural blocks.

---

## 🚀 How to Run the Simulation in Vivado

1. Open `INTERFACE_I2C_BUS.xpr` in **Xilinx Vivado**.
2. In the **Flow Navigator**, click **Simulation → Run Behavioral Simulation**.
3. Vivado will compile all 5 `.v` files and launch **xSim**.
4. By default, Vivado runs for 1000 ns, which is too short. In the **Tcl Console**, type:
   ```tcl
   run 300us
   ```
5. Observe waveforms: `sda` and `scl` will show the complete I2C bus activity.
6. Check the Tcl Console for the final output:
   `RESULT: PASSED  eeprom_data=0x42`

*Note: Simulation runs at a fast I2C frequency of 5 MHz to reduce simulation time, whereas the actual hardware runs at 100 kHz.*

---

## 🔧 Configurable Parameters

| Module | Parameter | Default Value | Description |
| :--- | :--- | :--- | :--- |
| `i2c_master` | `INPUT_CLK_FREQ` | `50_000_000` | System clock frequency (50 MHz) |
| `i2c_master` | `I2C_FREQ` | `100_000` | I2C bus speed (100 kHz Standard Mode) |
| `top_controller` | `INTER_TX_DELAY` | `16'hFFFF` | Gap between transactions (~1.3 ms) |
| `i2c_slave` | `SLAVE_ADDR` | `7'h3C` | Simulated SSD1306 OLED display address |
| `i2c_slave` | `READ_DATA` | `8'hBB` | Byte returned when master reads |

*Note: The EEPROM uses address `0x50`, which is standard for AT24C series.*

---

## 🧠 Key Verilog Concepts Demonstrated

- **Tri-State Logic & Bidirectional Pins:** `inout wire sda` combined with `assign sda = dir ? val : 1'bz;`
- **Simulation Primitives:** Use of `pullup(sda)` to model real-world resistor behavior.
- **Clock Division:** Using counters to create multi-phase sub-clocks for precise setup/hold timing.
- **Finite State Machines (FSM):** Strict state transitions mapping directly to hardware behavior.

---

## 🔮 Future Improvements (What's Next)

- **Multi-master arbitration:** Allowing more than one master on the bus without collisions.
- **Clock stretching:** Allowing slow slaves to hold SCL low to pause transactions.
- **Repeated START:** Supporting multi-byte burst transfers without releasing the bus.
- **10-bit addressing:** Extending beyond the current 7-bit limitation.
- **Fast Mode Support:** Timing validation for 400 kHz (Fast Mode) or 1 MHz (Fast Mode Plus).
- **FPGA Synthesis Constraints:** Adding XDC files and IOBUF primitives for real hardware implementation.
