`timescale 1ns / 1ps

// ============================================================
// mock_i2c_slave.v
// Behavioral I2C slave for simulation only.
//
// Architecture:
//   - START/STOP are detected asynchronously by SDA edges while SCL=1
//   - SDA data bits are sampled on posedge SCL (when slave is not driving)
//   - FSM runs on negedge SCL with EDGE detection of start/stop flags
//     to avoid the "stuck start_seen" bug where a level-sensitive check
//     caused bit_count to reset on every SCL cycle.
// ============================================================
module mock_i2c_slave #(
    parameter SLAVE_ADDR = 7'h3C,
    parameter READ_DATA  = 8'hBB
)(
    inout wire sda,
    input wire scl
);

    // ---- Tri-state SDA driver ----
    reg sda_out;
    reg sda_dir;   // 1 = slave drives SDA, 0 = slave releases SDA
    assign sda = (sda_dir) ? sda_out : 1'bz;

    // ---- Internal state ----
    reg [7:0] shift_reg;   // Accumulate bits; also holds READ_DATA for TX
    reg [3:0] bit_count;   // Counts negedge SCL events within a phase
    reg       is_addressed;
    reg       is_read;

    // ---- START / STOP flags (each written by exactly one always block) ----
    reg start_seen;
    reg stop_seen;

    always @(negedge sda) begin
        if (scl === 1'b1)
            start_seen <= 1'b1;
        else
            start_seen <= 1'b0;
    end

    always @(posedge sda) begin
        if (scl === 1'b1)
            stop_seen <= 1'b1;
        else
            stop_seen <= 1'b0;
    end

    // ---- Edge-detection registers for start/stop ----
    reg start_seen_d;
    reg stop_seen_d;

    // ---- Initialise all regs ----
    initial begin
        sda_out      = 1'b1;
        sda_dir      = 1'b0;
        shift_reg    = 8'h00;
        bit_count    = 4'h0;
        is_addressed = 1'b0;
        is_read      = 1'b0;
        start_seen   = 1'b0;
        stop_seen    = 1'b0;
        start_seen_d = 1'b0;
        stop_seen_d  = 1'b0;
    end

    // ====================================================================
    // SAMPLING: Capture SDA into shift_reg on posedge SCL
    //   (only when slave is NOT driving — i.e. not during ACK or READ TX)
    // ====================================================================
    always @(posedge scl) begin
        if (!sda_dir) begin
            shift_reg <= {shift_reg[6:0], sda};
        end
    end

    // ====================================================================
    // STATE MACHINE: runs purely on negedge SCL
    //   Uses rising-edge detection of start_seen/stop_seen so that
    //   the START/STOP condition is processed exactly ONCE.
    // ====================================================================
    always @(negedge scl) begin
        // Capture previous values for edge detection (non-blocking)
        start_seen_d <= start_seen;
        stop_seen_d  <= stop_seen;

        // ---------- START condition (rising edge of start_seen) ----------
        if (start_seen && !start_seen_d) begin
            bit_count    <= 4'd0;
            is_addressed <= 1'b0;
            sda_dir      <= 1'b0;
            $display("[%0t ns] SLAVE 0x%02h: START detected", $time, SLAVE_ADDR);

        // ---------- STOP condition (rising edge of stop_seen) ----------
        end else if (stop_seen && !stop_seen_d) begin
            is_addressed <= 1'b0;
            sda_dir      <= 1'b0;
            $display("[%0t ns] SLAVE 0x%02h: STOP detected", $time, SLAVE_ADDR);

        // ---------- Normal SCL falling edge: advance state machine -------
        end else begin

            if (!is_addressed) begin
                // ---- ADDRESS PHASE ----
                // shift_reg is filled by the posedge-SCL sampling block.
                // bit_count tracks negedge SCL events since START.
                // After 8 posedge SCLs, shift_reg has the full address byte.
                // We check at bit_count==7 (the 8th negedge SCL after START).
                if (bit_count < 4'd7) begin
                    bit_count <= bit_count + 1;

                end else if (bit_count == 4'd7) begin
                    // All 8 bits received: shift_reg[7:1]=addr, shift_reg[0]=R/W
                    is_read <= shift_reg[0];
                    if (shift_reg[7:1] == SLAVE_ADDR) begin
                        // Address match — send ACK (pull SDA low)
                        is_addressed <= 1'b1;
                        sda_dir      <= 1'b1;
                        sda_out      <= 1'b0; // ACK
                        $display("[%0t ns] SLAVE 0x%02h: ADDRESS MATCH 0x%02h rw=%b — ACK",
                                 $time, SLAVE_ADDR, shift_reg[7:1], shift_reg[0]);
                    end else begin
                        // Not our address — release SDA (NACK)
                        sda_dir <= 1'b0;
                        $display("[%0t ns] SLAVE 0x%02h: no match (got 0x%02h) — NACK",
                                 $time, SLAVE_ADDR, shift_reg[7:1]);
                    end
                    bit_count <= bit_count + 1;

                end else if (bit_count == 4'd8) begin
                    // ACK bit done — release SDA, reset bit counter
                    sda_dir   <= 1'b0;
                    bit_count <= 4'd0;
                    // If a READ transaction, pre-load shift_reg with data to send
                    if (is_read)
                        shift_reg <= READ_DATA;
                end

            end else begin
                // ---- DATA PHASE ----

                if (is_read) begin
                    // ---- Slave TRANSMITS (master reads) ----
                    if (bit_count < 4'd8) begin
                        sda_dir <= 1'b1;
                        sda_out <= shift_reg[7 - bit_count]; // MSB first
                        bit_count <= bit_count + 1;
                    end else begin
                        // Release SDA so master can send NACK/ACK
                        sda_dir      <= 1'b0;
                        bit_count    <= 4'd0;
                        is_addressed <= 1'b0;
                    end

                end else begin
                    // ---- Slave RECEIVES (master writes) ----
                    if (bit_count < 4'd8) begin
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 4'd8) begin
                        // All 8 data bits received — send ACK
                        sda_dir <= 1'b1;
                        sda_out <= 1'b0; // ACK
                        $display("[%0t ns] SLAVE 0x%02h: received data 0x%02h — ACK",
                                 $time, SLAVE_ADDR, shift_reg);
                        bit_count <= bit_count + 1;
                    end else begin
                        // Done — release SDA
                        sda_dir      <= 1'b0;
                        bit_count    <= 4'd0;
                        is_addressed <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
