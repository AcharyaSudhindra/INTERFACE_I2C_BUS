`timescale 1ns / 1ps

// ============================================================
// i2c_slave.v  –  Fixed behavioral I2C slave (simulation only)
//
// Fixes vs previous version:
//   1. start/stop detection uses counters (no multiple-driver).
//   2. shift_reg samples on posedge SCL (data stable during SCL HIGH).
//   3. Address phase: bit_count increments on negedge SCL after capture.
//   4. ACK released correctly after address + data phases.
//   5. READ data phase starts from bit 7 after ACK (bit_count reset to 0).
//   6. WRITE data ACK at correct bit position (bit 8).
// ============================================================
module i2c_slave #(
    parameter SLAVE_ADDR = 7'h3C,
    parameter READ_DATA  = 8'hBB
)(
    inout wire sda,
    input wire scl
);

    // ---- SDA tri-state driver ----
    reg sda_out = 1'b1;
    reg sda_dir = 1'b0;    // 1 = slave drives, 0 = slave releases
    assign sda = (sda_dir) ? sda_out : 1'bz;

    // ---- State registers ----
    reg [7:0] shift_reg   = 8'h00;
    reg [3:0] bit_count   = 4'h0;
    reg       is_addressed= 1'b0;
    reg       is_read     = 1'b0;

    // ====================================================================
    // START / STOP detection using counters (no multiple-driver issue)
    // start_count increments on every SDA-falling-while-SCL-HIGH event.
    // stop_count  increments on every SDA-rising-while-SCL-HIGH event.
    // The negedge-SCL state machine compares to shadow copies to detect
    // new START / STOP events without racing with the SDA-edge blocks.
    // ====================================================================
    reg [7:0] start_count      = 8'h00;
    reg [7:0] stop_count       = 8'h00;
    reg [7:0] last_start_count = 8'h00;
    reg [7:0] last_stop_count  = 8'h00;

    always @(negedge sda) begin
        if (scl === 1'b1) start_count <= start_count + 1;
    end

    always @(posedge sda) begin
        if (scl === 1'b1) stop_count <= stop_count + 1;
    end

    // ====================================================================
    // DATA SAMPLING  – posedge SCL captures SDA into shift_reg / is_read
    // (SDA is stable during SCL HIGH per I2C spec)
    // ====================================================================
    always @(posedge scl) begin
        if (!is_addressed) begin
            // Address phase: collect 7 addr bits then the R/W bit
            if (bit_count < 4'd7)
                shift_reg[6 - bit_count] <= sda;   // MSB first → [6],[5]...[0]
            else if (bit_count == 4'd7)
                is_read <= sda;                     // 8th bit = R/W
        end else begin
            // Data phase (WRITE): master sends data, slave receives
            if (!is_read && bit_count < 4'd8)
                shift_reg[7 - bit_count] <= sda;   // MSB first
        end
    end

    // ====================================================================
    // STATE MACHINE  – runs on negedge SCL (after master has clocked bit)
    // ====================================================================
    always @(negedge scl) begin

        // ---- START detected since last negedge SCL? ----
        if (start_count != last_start_count) begin
            last_start_count <= start_count;
            bit_count    <= 4'd0;
            sda_dir      <= 1'b0;
            is_addressed <= 1'b0;

        // ---- STOP detected since last negedge SCL? ----
        end else if (stop_count != last_stop_count) begin
            last_stop_count <= stop_count;
            sda_dir      <= 1'b0;
            is_addressed <= 1'b0;

        // ---- Normal bit clock ----
        end else begin

            if (!is_addressed) begin
                // ---- ADDRESS PHASE ----
                // Bits are sampled on posedge SCL above.
                // After 8 posedge SCL (7 addr + 1 RW), we have full info.
                // bit_count here reflects how many negedge SCL we've seen.

                if (bit_count < 4'd7) begin
                    // Still capturing address bits
                    bit_count <= bit_count + 1;

                end else if (bit_count == 4'd7) begin
                    // All 8 bits captured (addr + RW) — decide ACK/NACK
                    $display("[%0t ns] SLAVE 0x%02h: received addr byte, shift_reg=0x%02h is_read=%b",
                             $time, SLAVE_ADDR, {shift_reg[6:0], is_read}, is_read);

                    if (shift_reg[6:0] == SLAVE_ADDR) begin
                        $display("[%0t ns] SLAVE 0x%02h: ADDRESS MATCH — sending ACK", $time, SLAVE_ADDR);
                        sda_dir <= 1'b1;
                        sda_out <= 1'b0;  // pull SDA LOW = ACK
                    end else begin
                        $display("[%0t ns] SLAVE 0x%02h: no match (got 0x%02h) — NACK",
                                 $time, SLAVE_ADDR, shift_reg[6:0]);
                        sda_dir <= 1'b0;  // release SDA = NACK
                    end
                    bit_count <= bit_count + 1;

                end else if (bit_count == 4'd8) begin
                    // ACK/NACK has been clocked — release SDA, go to data phase
                    sda_dir      <= 1'b0;
                    bit_count    <= 4'd0;
                    if (shift_reg[6:0] == SLAVE_ADDR) begin
                        is_addressed <= 1'b1;
                        // If READ: pre-load shift_reg with data to transmit
                        if (is_read)
                            shift_reg <= READ_DATA;
                    end
                end

            end else begin
                // ---- DATA PHASE ----

                if (is_read) begin
                    // ---- SLAVE TRANSMITS (master reads) ----
                    if (bit_count < 4'd8) begin
                        sda_dir <= 1'b1;
                        sda_out <= shift_reg[7 - bit_count];   // MSB first
                        bit_count <= bit_count + 1;
                    end else begin
                        // All 8 bits sent — release for master NACK/ACK
                        sda_dir      <= 1'b0;
                        bit_count    <= 4'd0;
                        is_addressed <= 1'b0;
                    end

                end else begin
                    // ---- SLAVE RECEIVES (master writes) ----
                    // Data bits captured by posedge-SCL block above.
                    if (bit_count < 4'd8) begin
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 4'd8) begin
                        // Send ACK for received data byte
                        sda_dir <= 1'b1;
                        sda_out <= 1'b0;        // ACK
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
