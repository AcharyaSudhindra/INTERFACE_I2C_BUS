# PROJECT BRIEFING: I2C Bus Interface in Verilog HDL
# Author: Acharya Sudhindra
# Repository: AcharyaSudhindra/INTERFACE_I2C_BUS
# Tool: Xilinx Vivado 2024 + xSim Simulator
# Language: Verilog HDL (IEEE 1364-2001)
# Date: June 2026

---

## WHAT THIS PROJECT IS

This project implements a complete I2C (Inter-Integrated Circuit) Master-Slave
communication system in Verilog HDL, built and simulated inside Xilinx Vivado.
It is a digital hardware design project — not software — meaning every module
describes real logic that can be synthesized onto an FPGA chip.

The project demonstrates:
- A custom bit-banged I2C Master controller running at 100 kHz
- Two behavioral I2C Slave models (for simulation)
- An application-layer controller that runs real I2C transactions
- A unified testbench that verifies all of it works correctly

---

## I2C PROTOCOL BASICS (needed to understand the code)

I2C is a 2-wire serial communication protocol invented by Philips (now NXP).
It uses only two signals:
  - SDA  : Serial Data Line  (bidirectional)
  - SCL  : Serial Clock Line (driven by master)

Both lines are "open-drain" — any device can pull a line LOW (to 0), but
lines float HIGH (to 1) through external pull-up resistors when no one drives
them. This allows multiple devices to share the same two wires.

A standard I2C transaction has these phases, in order:
  1. START condition   : SDA goes LOW while SCL is HIGH
  2. Address phase     : Master sends 7-bit device address (MSB first)
  3. R/W bit           : 1 bit — 0 = Master wants to Write, 1 = Master wants to Read
  4. ACK 1             : Slave pulls SDA LOW to acknowledge its address was received
  5. Data phase        : 8 bits of data (direction depends on R/W bit)
  6. ACK 2             : Receiver acknowledges the data byte
  7. STOP condition    : SDA goes HIGH while SCL is HIGH (releases the bus)

Data is ALWAYS valid (stable) while SCL is HIGH.
Data can ONLY change while SCL is LOW.
This timing rule is the foundation of how the master and slave were designed.

---

## PROJECT FILE STRUCTURE

  INTERFACE_I2C_BUS/
  |
  |-- interface i2c/                  <-- all Verilog source files
  |   |-- i2c_master.v                (228 lines) - the core I2C engine
  |   |-- top_controller.v            (184 lines) - application layer
  |   |-- i2c_slave.v                 (196 lines) - behavioral slave v1
  |   |-- mock_i2c_slave.v            (168 lines) - behavioral slave v2 (improved)
  |   |-- tb_i2c_system.v             (125 lines) - testbench
  |
  |-- INTERFACE_I2C_BUS.xpr           - Xilinx Vivado project file
  |-- INTERFACE_I2C_BUS.srcs/         - Vivado source management folder
  |-- INTERFACE_I2C_BUS.sim/          - Vivado simulation folder

---

## MODULE 1: i2c_master.v  (THE CORE ENGINE)

File size : 228 lines, 9004 bytes
Role      : Implements the complete I2C protocol for the Master side.
            Handles bit-banging: generates SCL, controls SDA, sequences all
            I2C phases (START, ADDR, ACK, WRITE/READ, STOP).

### Port List:
  Inputs:
    clk        - System clock (default 50 MHz)
    rst_n      - Active-low asynchronous reset
    enable     - Pulse HIGH for 1 cycle to start a transaction
    rw         - 0 = Write transaction, 1 = Read transaction
    addr[6:0]  - 7-bit I2C slave address to target
    data_in[7:0] - Byte to write (used when rw=0)

  Outputs:
    data_out[7:0] - Byte read from slave (valid when rw=1 and busy falls)
    busy          - HIGH throughout the entire transaction
    ack_error     - Goes HIGH if slave sends NACK instead of ACK

  Bidirectional:
    sda  - The I2C Serial Data Line (inout, tri-state)

  Output:
    scl  - The I2C Serial Clock Line (driven by master only)

### Parameters:
    INPUT_CLK_FREQ = 50_000_000   (50 MHz system clock)
    I2C_FREQ       = 100_000      (100 kHz I2C clock speed)

### How the Clock Divider Works:
    The master takes the 50 MHz system clock and divides it down to 100 kHz.
    But crucially, each 100 kHz I2C clock cycle is subdivided into 4 PHASES:

    DIVIDER = (INPUT_CLK_FREQ / I2C_FREQ) / 4
            = (50,000,000 / 100,000) / 4
            = 125 system clock cycles per phase

    The 4-phase approach:
      Phase 00 (i2c_phase == 2'b00): SCL is LOW  — master CHANGES SDA here
      Phase 01 (i2c_phase == 2'b01): SCL goes HIGH (rising edge)
      Phase 10 (i2c_phase == 2'b10): SCL is HIGH  — data SAMPLED here
      Phase 11 (i2c_phase == 2'b11): SCL goes LOW  (falling edge)

    This guarantees SDA is stable before SCL rises (setup time) and after
    SCL falls (hold time), satisfying the I2C specification perfectly.

### SDA Tri-State Implementation:
    The SDA line is bidirectional. In Verilog, this is modelled with:
      assign sda = (sda_dir == 1'b1) ? sda_out : 1'bz;
    When sda_dir=1, the master drives SDA to sda_out.
    When sda_dir=0, the master releases SDA (outputs high-impedance 'z'),
    allowing the slave or pull-up resistor to control the line.

### FSM States (8 states total):
    State IDLE  (4'd0): Bus is free. SCL=1, SDA=1. Waits for enable.
                        When enable is seen AND i2c_phase==2'b11, loads
                        address into tx_data and moves to START.

    State START (4'd1): Generates the START condition.
                        Phase 00: SDA=1, SCL=1
                        Phase 01: SDA=1, SCL=1  (hold before drop)
                        Phase 10: SDA=0, SCL=1  (SDA falls while SCL HIGH = START)
                        Phase 11: SDA=0, SCL=0  (pull clock low, ready for data)
                        Then loads bit_count=7 and moves to ADDR.

    State ADDR  (4'd2): Shifts out the 8-bit tx_data (7-bit address + R/W bit).
                        tx_data was loaded as {addr, rw} = 8 bits.
                        Phase 00: SCL=0, SDA = tx_data[bit_count]  (change data)
                        Phase 01: SCL=1
                        Phase 10: SCL=1  (slave samples here)
                        Phase 11: SCL=0
                        After each bit, bit_count decrements.
                        When bit_count reaches 0, moves to ACK1.

    State ACK1  (4'd3): Releases SDA (sda_dir=0) to let slave respond.
                        Phase 00: sda_dir=0, SCL=0
                        Phase 01: SCL=1
                        Phase 10: SCL=1, ack_error = sda  (samples ACK bit)
                                  If sda is LOW here, slave ACKed (ack_error=0).
                                  If sda is HIGH, slave NACKed (ack_error=1).
                        Phase 11: SCL=0
                        If ack_error: goes to STOP.
                        If rw=0: loads data_in into tx_data, goes to WRITE.
                        If rw=1: goes to READ.

    State WRITE (4'd4): Shifts out 8 data bits from tx_data (= data_in).
                        Same bit-shifting logic as ADDR.
                        After all 8 bits, goes to ACK2.

    State READ  (4'd5): Releases SDA (sda_dir=0), samples 8 bits from slave.
                        Phase 10: rx_data[bit_count] = sda  (capture each bit)
                        Special: when bit_count==0, data_out = {rx_data[7:1], sda}
                        After 8 bits, goes to ACK2.

    State ACK2  (4'd6): For WRITE: releases SDA, samples slave's ACK.
                        For READ:  drives SDA=1 (master sends NACK to stop).
                        After phase 11, goes to STOP.

    State STOP  (4'd7): Generates the STOP condition.
                        Phase 00: SDA=0, SCL=0
                        Phase 01: SCL=1
                        Phase 10: SDA=1, SCL=1  (SDA rises while SCL HIGH = STOP)
                        Phase 11: SDA=1, SCL=1
                        Returns to IDLE, clears busy.

---

## MODULE 2: top_controller.v  (APPLICATION LAYER)

File size : 184 lines, 6016 bytes
Role      : Acts as the "user application" layer. It does not handle individual
            bits — it handles entire I2C transactions. It decides WHICH device
            to talk to, WHAT data to send, and WHAT to do with the result.

### Port List:
  Inputs:
    clk           - 50 MHz system clock
    rst_n         - Active-low reset
    start_demo    - Pulse HIGH to begin the demonstration sequence
    oled_wdata[7:0] - The byte to write to the OLED display
    eeprom_ptr[7:0] - The memory pointer byte to send to the EEPROM

  Outputs:
    eeprom_data[7:0] - The byte read back from the EEPROM
    demo_done        - Goes HIGH when the entire sequence completes successfully
    error_flag       - Goes HIGH if any transaction receives a NACK

  Bidirectional / Output:
    sda  - Connected directly to i2c_master's sda
    scl  - Connected directly to i2c_master's scl

### Parameters:
    INPUT_CLK_FREQ = 50_000_000
    I2C_CLK_FREQ   = 100_000
    INTER_TX_DELAY = 16'hFFFF   (65535 cycles ≈ 1.3 ms gap between transactions)
    In testbench, INTER_TX_DELAY is overridden to 16'd200 (4 µs gap).

### Internal Structure:
  Instantiates i2c_master as a submodule:
    i2c_master #(.INPUT_CLK_FREQ(INPUT_CLK_FREQ), .I2C_FREQ(I2C_CLK_FREQ))
    master_inst (.clk, .rst_n, .enable(i2c_enable), .rw(i2c_rw),
                 .addr(i2c_addr), .data_in(i2c_data_in),
                 .data_out(i2c_data_out), .busy(i2c_busy),
                 .ack_error(i2c_ack_error), .sda, .scl);

### FSM States (10 states):
    S_IDLE (0)            : Wait for start_demo=1 and i2c_busy=0.
                            Then: set addr=0x3C, rw=0, data=oled_wdata, enable=1
                            Go to S_WRITE_OLED.

    S_WRITE_OLED (1)      : Wait for i2c_busy to go HIGH (master accepted command).
                            Then: clear enable, go to S_WAIT_OLED.

    S_WAIT_OLED (2)       : Wait for i2c_busy to fall (transaction finished).
                            If ack_error: go to S_ERROR.
                            Else: go to S_DELAY, reset delay_cnt=0.

    S_DELAY (3)           : Count up delay_cnt. When it reaches INTER_TX_DELAY:
                            Set addr=0x50, rw=0, data=eeprom_ptr, enable=1.
                            Go to S_WRITE_EEPROM_ADDR.
                            (This delay mimics real hardware write cycle time.)

    S_WRITE_EEPROM_ADDR (4): Wait for i2c_busy HIGH. Clear enable.
                              Go to S_WAIT_EEPROM_ADDR.

    S_WAIT_EEPROM_ADDR (5): Wait for i2c_busy LOW.
                             If ack_error: go to S_ERROR.
                             Else: Set addr=0x50, rw=1, enable=1.
                             Go to S_READ_EEPROM.
                             (Write the pointer, then immediately do a Read.)

    S_READ_EEPROM (6)     : Wait for i2c_busy HIGH. Clear enable.
                             Go to S_WAIT_EEPROM.

    S_WAIT_EEPROM (7)     : Wait for i2c_busy LOW.
                             If ack_error: go to S_ERROR.
                             Else: capture captured_data = i2c_data_out.
                             Go to S_DONE.

    S_DONE (8)            : demo_done output goes HIGH. Sequence complete.
                            If start_demo is asserted again, re-runs from OLED write.

    S_ERROR (9)           : error_flag output goes HIGH. Stays here permanently.

---

## MODULE 3: i2c_slave.v  (BEHAVIORAL SLAVE — VERSION 1)

File size : 196 lines, 7252 bytes
Role      : Simulation-only behavioral model of an I2C slave device.
            Responds to a specific address, sends back a fixed byte on READ,
            and ACKs write data. Uses $display for debug logging.

### Parameters:
    SLAVE_ADDR = 7'h3C    (can be any 7-bit address)
    READ_DATA  = 8'hBB    (byte returned when master reads)

### Ports:
    inout wire sda
    input wire scl

### Key Design: Dual-edge sensitivity
    Uses a combined always block: always @(posedge scl or negedge scl)
    Inside it checks: if (scl === 1'b1) for rising edge, else for falling edge.

    On rising SCL (posedge): sample data from SDA into shift registers.
    On falling SCL (negedge): drive SDA (for ACK or READ data).

### START/STOP Detection:
    always @(negedge sda): if scl==1, increment start_count
    always @(posedge sda): if scl==1, increment stop_count

    The main SCL block compares start_count to last_start_count to detect
    a new START condition without needing to drive registers from multiple
    always blocks (which would cause multi-driver errors).

### States (7):
    ST_IDLE (0), ST_ADDR (1), ST_ADDR_ACK (2), ST_WRITE (3),
    ST_DATA_ACK (4), ST_READ (5), ST_READ_ACK (6)

### Debug output example:
    "[100 ns] SLAVE 0x3C: received addr byte=0x78 addr=0x3C rw=0"
    "[100 ns] SLAVE 0x3C: ADDRESS MATCH - sending ACK"
    "[250 ns] SLAVE 0x3C: received data byte=0xA5 - sending ACK"

---

## MODULE 4: mock_i2c_slave.v  (BEHAVIORAL SLAVE — VERSION 2, IMPROVED)

File size : 168 lines, 6616 bytes
Role      : Improved version of i2c_slave.v. Same function, but redesigned
            to fix Vivado multi-driver compilation errors that i2c_slave.v
            originally caused. No $display output (cleaner logs).

### Parameters:
    SLAVE_ADDR = 7'h3C
    READ_DATA  = 8'hBB

### Key Difference from i2c_slave.v:
    START/STOP detection uses dedicated single-bit flags:
      start_seen (set by always @(negedge sda) when scl==1)
      stop_seen  (set by always @(posedge sda) when scl==1)

    Each flag is written by EXACTLY ONE always block — no multi-driver.

    The main state machine triggers on:
      always @(negedge scl or posedge start_seen or posedge stop_seen)

### Three always blocks (strictly separated):
    Block 1: always @(negedge sda)
             Sets start_seen=1 if scl==1, else start_seen=0.

    Block 2: always @(posedge sda)
             Sets stop_seen=1 if scl==1, else stop_seen=0.

    Block 3: always @(posedge scl)
             ONLY samples SDA into shift_reg when sda_dir==0 (not driving).
             shift_reg <= {shift_reg[6:0], sda}

    Block 4: always @(negedge scl or posedge start_seen or posedge stop_seen)
             Main state machine. Handles:
             - START: reset bit_count, clear is_addressed, release SDA
             - STOP:  clear is_addressed, release SDA
             - negedge SCL: advance state, drive ACK, drive READ data

### Data flow for a WRITE transaction:
    1. master sends START → start_seen pulses HIGH → slave resets
    2. master clocks 8 bits (7 addr + R/W=0)
       Each posedge SCL: shift_reg shifts in one bit from SDA
    3. After 8 negedge SCL events, bit_count==7 reached:
       slave checks shift_reg[7:1] against SLAVE_ADDR
       If match: sda_dir=1, sda_out=0 (pull SDA LOW = ACK)
       If no match: sda_dir=0 (release = NACK)
    4. master clocks 8 data bits
       Each posedge SCL: shift_reg shifts in one data bit
    5. After 8 data bits: slave pulls SDA LOW for ACK
    6. master sends STOP → stop_seen pulses → slave resets

### Data flow for a READ transaction:
    1. Same as WRITE up to step 3, but R/W bit = 1
    2. After address ACK: slave pre-loads shift_reg = READ_DATA
    3. On each negedge SCL: slave drives sda_out = shift_reg[7 - bit_count]
       (transmits READ_DATA byte MSB first)
    4. After 8 bits: slave releases SDA (sda_dir=0) for master NACK
    5. master sends STOP

---

## MODULE 5: tb_i2c_system.v  (TESTBENCH)

File size : 125 lines, 4260 bytes
Role      : The top-level simulation testbench. Connects all modules together,
            generates stimulus, checks results, prints PASS/FAIL.

### Key Simulation Parameters:
    SIM_I2C_FREQ = 5_000_000   (5 MHz I2C for fast simulation, vs 100 kHz HW)
    SIM_DELAY    = 16'd200     (200 cycles = 4 µs inter-transaction gap)

### What it instantiates:
    top_controller dut (...)       -- the design under test
    i2c_slave oled_slave   with SLAVE_ADDR=7'h3C, READ_DATA=8'h00
    i2c_slave eeprom_slave with SLAVE_ADDR=7'h50, READ_DATA=8'h42

### The pull-up resistors (CRITICAL):
    pullup(sda);
    pullup(scl);
    These model the mandatory I2C pull-up resistors. Without them, SDA/SCL
    would be undriven (X) instead of floating HIGH. This is what caused Bug #1.

### Stimulus sequence:
    1. Assert rst_n=0 for 10 clock cycles (reset all modules)
    2. Release rst_n=1, wait 10 clock cycles
    3. Assert start_demo=1 for 5 clock cycles, then clear it
    4. Wait for demo_done=1 or error_flag=1

### Test data used:
    oled_wdata = 8'hA5   (this byte gets written to OLED at address 0x3C)
    eeprom_ptr = 8'h00   (this pointer byte gets sent to EEPROM at address 0x50)
    Expected read-back from EEPROM: 8'h42 (set by READ_DATA parameter)

### Self-check assertion:
    if (error_flag)
        $display("RESULT: FAILED (NACK)");
    else if (eeprom_data === 8'h42)
        $display("RESULT: PASSED  eeprom_data=0x%02h  oled_shift=0x%02h", ...);
    else
        $display("RESULT: FAILED  eeprom_data=0x%02h", eeprom_data);

### Watchdog:
    #2_000_000; $display("WATCHDOG timeout"); $finish;
    Prevents the simulation from hanging forever (kills after 2 ms sim time).

### Internal probe signals (for waveform viewing):
    assign master_state     = dut.master_inst.state;   // i2c_master FSM state
    assign ctrl_state       = dut.state;               // top_controller FSM state
    assign oled_addressed   = oled_slave.is_addressed; // is OLED slave active?
    assign eeprom_addressed = eeprom_slave.is_addressed;
    assign oled_shift_reg   = oled_slave.shift_reg;    // what slave captured
    assign eeprom_shift_reg = eeprom_slave.shift_reg;

---

## THREE BUGS THAT WERE FOUND AND FIXED

### BUG 1: Floating Bus → Immediate NACK

  Symptom:
    The first simulation run showed the master sending the address 0x3C,
    but receiving a NACK (ack_error=1) immediately. The master went straight
    to STOP without any data transfer.

  Root Cause:
    The testbench had comments describing an OLED and EEPROM slave, but the
    actual Verilog instantiation lines for those modules were missing or
    commented out. With no slave modules connected, SDA was held HIGH by the
    pull-up resistor at all times. In I2C, a HIGH during the ACK slot = NACK.
    The master heard a NACK from a bus that contained nothing.

  Fix:
    Added explicit instantiation lines for both slave modules:
      i2c_slave #(.SLAVE_ADDR(7'h3C), .READ_DATA(8'h00)) oled_slave (.sda(sda),.scl(scl));
      i2c_slave #(.SLAVE_ADDR(7'h50), .READ_DATA(8'h42)) eeprom_slave(.sda(sda),.scl(scl));
    After this fix, both slaves appeared on the bus and sent proper ACK pulses.

### BUG 2: Wrong Address Decoded (0x78 instead of 0x3C)

  Symptom:
    After Bug 1 was fixed, the $display messages showed the slave receiving
    address 0x78 when the master was sending 0x3C. This is exactly a 1-bit
    left shift: binary 0111100 (0x3C) became 1111000 (0x78).

  Root Cause:
    The original i2c_slave.v was sampling SDA inside the negedge SCL handler:
      always @(negedge scl)
        shift_reg <= {shift_reg[6:0], sda};
    The problem: the i2c_master also changes SDA shortly AFTER the falling
    edge of SCL (in Phase 00 of the next bit cycle). Verilog simulates both
    events in the same simulation timestep, causing a delta-cycle race
    condition. The slave captured the new bit instead of the stable old bit,
    shifting the entire byte left by one position.

  Fix:
    Rewrote the sampling logic to trigger on posedge SCL:
      always @(posedge scl)
        if (!sda_dir)
          shift_reg <= {shift_reg[6:0], sda};
    The I2C specification guarantees SDA is stable during SCL HIGH, so
    posedge SCL is always the correct and legal sampling point. The state
    machine (counting bits, driving ACK) was kept on negedge SCL to prevent
    any SDA transitions from creating false START/STOP conditions.

### BUG 3: Multi-Driver Compilation Error (Vivado xelab VRFC 10-529)

  Symptom:
    Vivado's xelab elaborator threw a fatal error:
    "[VRFC 10-529] concurrent assignment to a non-net is not permitted"
    The simulation refused to start at all.

  Root Cause:
    In an attempt to detect START conditions quickly, the registers
    is_addressed and bit_count were being assigned inside two separate
    always blocks:
      Block A: always @(negedge sda)  → reset is_addressed, bit_count on START
      Block B: always @(negedge scl)  → normal state machine updates
    Verilog (IEEE 1364) does NOT allow the same reg variable to be driven
    by more than one always block. Vivado's strict elaborator caught this.

  Fix:
    Refactored the START/STOP detectors into dedicated single-bit registers:
      always @(negedge sda): only sets start_seen flag
      always @(posedge sda): only sets stop_seen flag
    The main state machine (always @(negedge scl or posedge start_seen or
    posedge stop_seen)) now READS these flags and handles them internally.
    Each register has exactly one always block writing it — legally correct.

---

## SIMULATION RESULTS

Simulation was run in Vivado xSim for 300 microseconds.
Fast I2C frequency was used in simulation: 5 MHz (instead of 100 kHz).

Timeline of what happened:

  0 µs to ~100 µs:
    - top_controller sets addr=0x3C, rw=0, data=0xA5, enable=1
    - i2c_master generates: START → address 0x3C (W) → waits ACK
    - oled_slave (SLAVE_ADDR=0x3C) detects match → pulls SDA LOW (ACK)
    - i2c_master sends data byte 0xA5
    - oled_slave ACKs the data
    - i2c_master generates STOP
    - top_controller transitions: S_WAIT_OLED → S_DELAY

  ~100 µs to ~104 µs:
    - INTER_TX_DELAY counter runs (200 cycles at 50 MHz = 4 µs)
    - Bus is quiet (SCL=1, SDA=1)

  ~104 µs to ~200 µs:
    - top_controller sets addr=0x50, rw=0, data=0x00 (EEPROM pointer write)
    - i2c_master: START → 0x50 (W) → ACK ← eeprom_slave → 0x00 → ACK → STOP
    - Immediately after: top_controller sets addr=0x50, rw=1 (EEPROM read)
    - i2c_master: START → 0x50 (R) → ACK ← eeprom_slave
    - eeprom_slave drives 0x42 onto SDA (its READ_DATA parameter)
    - i2c_master captures 0x42 into data_out
    - i2c_master sends NACK (master ends read with NACK)
    - STOP generated

  ~200 µs:
    - top_controller captures i2c_data_out → captured_data = 0x42
    - Sets state = S_DONE → demo_done = 1

  Testbench checks:
    eeprom_data === 8'h42  →  TRUE
    Prints: "RESULT: PASSED  eeprom_data=0x42  oled_shift=0xA5"
    $finish called.

---

## CONFIGURABLE PARAMETERS SUMMARY

  Module: i2c_master
    INPUT_CLK_FREQ  = 50_000_000  (change for different FPGA clock)
    I2C_FREQ        = 100_000     (change for 400 kHz Fast Mode, 1 MHz Fast+)

  Module: top_controller
    INPUT_CLK_FREQ  = 50_000_000  (passed through to i2c_master)
    I2C_CLK_FREQ    = 100_000     (passed through to i2c_master)
    INTER_TX_DELAY  = 16'hFFFF    (65535 cycles ≈ 1.3 ms, for real EEPROM timing)

  Module: i2c_slave / mock_i2c_slave
    SLAVE_ADDR      = 7'h3C       (any 7-bit address from 0x08 to 0x77)
    READ_DATA       = 8'hBB       (any byte to return when master reads)

---

## HOW TO RUN THE SIMULATION IN VIVADO

  1. Open INTERFACE_I2C_BUS.xpr in Xilinx Vivado
  2. In Flow Navigator → Simulation → Run Behavioral Simulation
  3. Vivado compiles all 5 .v files and launches xSim
  4. In Tcl Console, type: run 300us
     (Default run is only 1000 ns which is too short for I2C activity)
  5. Observe waveforms: sda and scl will show I2C bus activity
  6. Check Tcl Console for: RESULT: PASSED  eeprom_data=0x42

  Alternatively, the simulation can be run with Icarus Verilog or ModelSim
  by compiling all files in the "interface i2c/" directory.

---

## DEVICE ADDRESSES USED IN THIS PROJECT

  0x3C  → Simulated SSD1306 OLED display
          (0x3C is the standard real-world I2C address for the SSD1306)
  0x50  → Simulated AT24C EEPROM
          (0x50 is the base address for AT24C series EEPROMs)

---

## KEY VERILOG CONCEPTS USED IN THIS PROJECT

  inout wire sda          : Bidirectional signal (open-drain bus)
  assign sda = dir?val:1'bz : Tri-state buffer (release = high-impedance)
  pullup(sda)             : Verilog primitive for pull-up resistor (testbench)
  always @(posedge clk or negedge rst_n) : Clocked sequential logic with async reset
  localparam              : Named constant inside a module
  parameter               : Overridable constant (set at instantiation time)
  reg [6:0]               : 7-bit register
  wire [7:0]              : 8-bit wire (combinational connection)
  {addr, rw}              : Bit concatenation (makes 8-bit from 7+1)
  shift_reg[6:0], sda}    : Shift register operation (shift left, insert sda at LSB)
  $display                : Print to simulation console
  $finish                 : End simulation
  $dumpfile / $dumpvars   : Generate VCD waveform file

---

## WHAT THIS PROJECT DOES NOT INCLUDE (FUTURE WORK)

  - Multi-master arbitration (only one master in this project)
  - Clock stretching (slave holds SCL low to pause)
  - Repeated START / multi-byte burst transfers
  - 10-bit addressing (only 7-bit used here)
  - Fast Mode (400 kHz) or Fast Mode Plus (1 MHz) timing validation
  - Synthesis constraints / timing analysis for FPGA implementation
  - IOBUF primitives for real FPGA bidirectional I/O (currently uses pullup primitive)

---
END OF PROJECT BRIEFING
