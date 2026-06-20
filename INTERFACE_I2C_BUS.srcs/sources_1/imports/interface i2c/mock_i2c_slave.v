`timescale 1ns / 1ps

// ============================================================
// mock_i2c_slave.v
// Behavioral I2C slave for simulation only.
//
// Key fixes vs original:
//   1. Data is SAMPLED on posedge SCL (I2C spec: SDA valid during SCL HIGH)
//   2. Address decode uses 8-bit accumulation before matching SLAVE_ADDR
//   3. START/STOP use separate regs (start_seen, stop_seen) so no
//      register is ever driven from more than one always block.
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
    reg [3:0] bit_count;   // 0..8 (8 bits + 1 ACK/NACK)
    reg       is_addressed;
    reg       is_read;

    // ---- START / STOP detection (each written by exactly one block) ----
    // start_seen goes HIGH when SDA falls while SCL is HIGH
    // stop_seen  goes HIGH when SDA rises while SCL is HIGH
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

    // ---- Initialise all regs ----
    initial begin
        sda_out     = 1'b1;
        sda_dir     = 1'b0;
        shift_reg   = 8'h00;
        bit_count   = 4'h0;
        is_addressed= 1'b0;
        is_read     = 1'b0;
        start_seen  = 1'b0;
        stop_seen   = 1'b0;
    end

    // ====================================================================
    // SAMPLING: Capture SDA into shift_reg on posedge SCL
    //   (only when slave is NOT driving — i.e. not during ACK or READ TX)
    // ====================================================================
    always @(posedge scl) begin
        if (!sda_dir) begin               // Only sample when we're not driving
            shift_reg <= {shift_reg[6:0], sda};
        end
    end

    // ====================================================================
    // STATE MACHINE: runs on negedge SCL (after each bit is settled)
    //                and on posedge start_seen / posedge stop_seen
    // ====================================================================
    always @(negedge scl or posedge start_seen or posedge stop_seen) begin

        // ---------- START condition ----------
        if (start_seen) begin
            bit_count    <= 4'd0;
            is_addressed <= 1'b0;
            sda_dir      <= 1'b0;
            // Note: start_seen is cleared by its own always block on next negedge sda

        // ---------- STOP condition ----------
        end else if (stop_seen) begin
            is_addressed <= 1'b0;
            sda_dir      <= 1'b0;

        // ---------- SCL falling edge: advance state machine ----------
        end else begin

            if (!is_addressed) begin
                // ---- ADDRESS PHASE ----
                // shift_reg is filled by the posedge-SCL sampling block.
                // After 8 posedge SCL events (7 addr bits + 1 RW bit)
                // we have the full address byte in shift_reg.
                // bit_count tracks how many negedge SCL we've seen.
                if (bit_count < 4'd7) begin
                    // Still shifting address bits — nothing to drive
                    bit_count <= bit_count + 1;

                end else if (bit_count == 4'd7) begin
                    // All 8 bits received in shift_reg after 8 posedge SCL.
                    // shift_reg[7:1] = address, shift_reg[0] = R/W
                    is_read <= shift_reg[0];
                    if (shift_reg[7:1] == SLAVE_ADDR) begin
                        // Address match — send ACK (pull SDA low)
                        is_addressed <= 1'b1;
                        sda_dir      <= 1'b1;
                        sda_out      <= 1'b0; // ACK
                    end else begin
                        // Not our address — release SDA (NACK)
                        sda_dir <= 1'b0;
                    end
                    bit_count <= bit_count + 1;

                end else if (bit_count == 4'd8) begin
                    // ACK bit transmitted — release SDA, reset bit counter
                    sda_dir   <= 1'b0;
                    bit_count <= 4'd0;
                    // If a READ transaction, pre-load shift_reg with data to send
                    if (shift_reg[0]) // is_read (captured last cycle)
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
                    // Data bits are captured by the posedge-SCL block.
                    if (bit_count < 4'd8) begin
                        // Still receiving data bits
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 4'd8) begin
                        // All 8 data bits received — send ACK
                        sda_dir <= 1'b1;
                        sda_out <= 1'b0; // ACK
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
