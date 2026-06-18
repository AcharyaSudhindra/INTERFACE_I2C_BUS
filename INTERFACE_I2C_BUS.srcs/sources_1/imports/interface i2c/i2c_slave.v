`timescale 1ns / 1ps

module i2c_slave #(
    parameter SLAVE_ADDR = 7'h3C,
    parameter READ_DATA  = 8'hBB // Data to send when read by master
)(
    inout wire sda,
    input wire scl
);

    reg [7:0] shift_reg = 0;
    reg [3:0] bit_count = 0;
    reg sda_out = 0;
    reg sda_dir = 0; // 1 = output, 0 = input
    reg is_addressed = 0;
    reg is_read = 0;
    
    assign sda = (sda_dir == 1'b1) ? sda_out : 1'bz;

    reg [7:0] start_count = 0;
    reg [7:0] stop_count = 0;
    reg [7:0] last_start_count = 0;
    reg [7:0] last_stop_count = 0;

    // Detect START and STOP on SDA edges without driving FSM signals directly
    always @(negedge sda) begin
        if (scl === 1'b1) start_count <= start_count + 1;
    end

    always @(posedge sda) begin
        if (scl === 1'b1) stop_count <= stop_count + 1;
    end

    // Use a single clock (negedge scl) for state transitions to avoid multi-driver errors
    always @(negedge scl) begin
        if (start_count != last_start_count) begin
            last_start_count <= start_count;
            bit_count <= 0;
            sda_dir <= 0;
            is_addressed <= 0;
        end else if (stop_count != last_stop_count) begin
            last_stop_count <= stop_count;
            sda_dir <= 0;
            is_addressed <= 0;
        end else begin
            if (!is_addressed) begin
                if (bit_count < 7) begin
                    // shift_reg gets assigned in posedge SCL, but bit_count updates here
                    bit_count <= bit_count + 1;
                end else if (bit_count == 7) begin
                    $display("Time: %0t, SLAVE_ADDR: %h, shift_reg: %h", $time, SLAVE_ADDR, shift_reg[6:0]);
                    if (shift_reg[6:0] == SLAVE_ADDR) begin
                        sda_dir <= 1;
                        sda_out <= 0; // ACK
                        $display("ACK ASSERTED!");
                    end else begin
                        $display("NACK! shift_reg mismatch. Expected: %h, Got: %h", SLAVE_ADDR, shift_reg[6:0]);
                    end
                    bit_count <= bit_count + 1;
                end else if (bit_count == 8) begin
                    if (shift_reg[6:0] == SLAVE_ADDR) begin
                        is_addressed <= 1;
                        if (is_read) begin
                            sda_dir <= 1;
                            sda_out <= READ_DATA[7];
                            bit_count <= 1;
                        end else begin
                            sda_dir <= 0;
                            bit_count <= 0;
                        end
                    end else begin
                        sda_dir <= 0;
                        bit_count <= 0;
                    end
                end
            end else begin
                if (is_read) begin
                    if (bit_count < 8) begin
                        sda_dir <= 1;
                        sda_out <= shift_reg[7 - bit_count];
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 8) begin
                        sda_dir <= 0; // Wait for Master ACK
                        bit_count <= 0;
                        is_addressed <= 0;
                    end
                end else begin
                    if (bit_count < 7) begin
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 7) begin
                        sda_dir <= 1;
                        sda_out <= 0; // ACK
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 8) begin
                        sda_dir <= 0;
                        bit_count <= 0;
                        is_addressed <= 0;
                    end
                end
            end
        end
    end

    // Only shift data on posedge scl to ensure it's sampled correctly
    always @(posedge scl) begin
        if (!is_addressed) begin
            if (bit_count < 7) begin
                shift_reg[6 - bit_count] <= sda;
            end else if (bit_count == 7) begin
                is_read <= sda;
            end
        end else begin
            if (!is_read) begin
                if (bit_count < 8) begin
                    shift_reg[7 - bit_count] <= sda;
                end
            end else if (bit_count == 0) begin
                // Preload READ_DATA when address matches and it's a read
                shift_reg <= READ_DATA;
            end
        end
    end

endmodule
