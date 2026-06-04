# I2C Master Interface for Dual Slaves (OLED and EEPROM)

This project implements an I²C communication system on an FPGA. The FPGA will act as the I²C Master, communicating with two external slave devices: an SSD1306 OLED Display (Slave 1) and an EEPROM/RTC module (Slave 2) over a shared I²C bus.

## User Review Required
> [!IMPORTANT]
> Please review the architecture below. The FPGA will implement the I²C Master and a Top-Level Controller. Since the actual OLED and EEPROM are external hardware, we will provide Verilog "mock" slaves specifically for simulation purposes so you can verify the I²C transactions before synthesis.

## Open Questions
> [!WARNING]
> 1. **FPGA Clock Frequency**: What is the system clock frequency of your target FPGA board? We need this to correctly derive the I²C SCL clock (e.g., 100 kHz or 400 kHz).
> 2. **Top-Level Controller Logic**: Do you want a specific sequence hardcoded in the FPGA for the demo? (e.g., First, write "Hello" to the OLED, then read 1 byte from EEPROM and display it on some LEDs).
> 3. **Vivado Constraints**: Which FPGA board are you using (e.g., Basys 3, Nexys, Zybo)? Providing the board name will help in writing the XDC constraints for SDA and SCL pins.

## Proposed Changes

### Core I²C Master
Implementation of the FSM-based I²C Master capable of generating START/STOP conditions, handling ACK/NACK, and transmitting/receiving data.

#### [NEW] `i2c_master.v`
- Standard I²C Master FSM (Idle, Start, Address, Read/Write, Ack, Stop).
- Configurable clock divider for SCL generation.
- Bi-directional SDA line control.

### Top-Level Controller
A state machine that uses the `i2c_master` to talk to the two specific slaves.

#### [NEW] `top_controller.v`
- Coordinates transactions with Slave 1 (OLED at `0x3C`) and Slave 2 (EEPROM at `0x50` typically for 24C02).
- Executes an initialization sequence and data transfer logic for the demo.

### Simulation Models
Behavioral models of the slave devices to test the bus in Vivado simulation.

#### [NEW] `mock_i2c_slave.v`
- A generic parameterizable I²C slave Verilog model to act as the OLED and EEPROM during simulation.
- Responds to its assigned address and issues ACKs.

#### [NEW] `tb_i2c_system.v`
- Instantiates the `top_controller` and connects it to the two `mock_i2c_slave` instances.
- Verifies the full transaction flow on the simulated SDA/SCL bus.

## Verification Plan

### Automated Tests
- Run Behavioral Simulation in Vivado using `tb_i2c_system.v`.
- Verify START, STOP, Address, and ACK/NACK timing on the waveform viewer.

### Manual Verification
- Synthesize the design in Vivado.
- Assign SDA and SCL to appropriate Pmod or IO headers (with external pull-up resistors if not using internal ones).
- Connect the SSD1306 OLED and EEPROM.
- Observe the OLED display and verify EEPROM read/write using an oscilloscope or logic analyzer.
