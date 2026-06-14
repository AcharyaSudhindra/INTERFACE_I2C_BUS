`timescale 1ns / 1ps

module mock_i2c_slave #(
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

    // Event counters to detect START and STOP without multi-driver conflicts
    reg [7:0] start_count = 0;
    reg [7:0] stop_count = 0;
    reg [7:0] last_start_count = 0;
    reg [7:0] last_stop_count = 0;
    
    always @(negedge sda) begin
        if (scl == 1'b1) start_count <= start_count + 1; // START
    end
    
    always @(posedge sda) begin
        if (scl == 1'b1) stop_count <= stop_count + 1; // STOP
    end
    
    // State machine based on SCL
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
                    shift_reg[6 - bit_count] <= sda;
                    bit_count <= bit_count + 1;
                end else if (bit_count == 7) begin
                    is_read <= sda;
                    $display("Time: %0t, SLAVE_ADDR: %h, shift_reg: %h", $time, SLAVE_ADDR, shift_reg[6:0]);
                    if (shift_reg[6:0] == SLAVE_ADDR) begin
                        sda_dir <= 1;
                        sda_out <= 0; // ACK
                        $display("ACK ASSERTED!");
                    end else begin
                        $display("NACK! shift_reg mismatch.");
                    end
                    bit_count <= bit_count + 1;
                end else if (bit_count == 8) begin
                    if (shift_reg[6:0] == SLAVE_ADDR) begin
                        is_addressed <= 1;
                        if (is_read) begin
                            shift_reg <= READ_DATA;
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
                // Data phase
                if (is_read) begin
                    // Read phase (slave transmits)
                    if (bit_count < 8) begin
                        sda_dir <= 1;
                        sda_out <= shift_reg[7 - bit_count];
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 8) begin
                        sda_dir <= 0; // Release for Master ACK
                        bit_count <= 0;
                        is_addressed <= 0; // End after 1 byte for simplicity
                    end
                end else begin
                    // Write phase (slave receives)
                    if (bit_count < 7) begin
                        sda_dir <= 0;
                        shift_reg[7 - bit_count] <= sda;
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 7) begin
                        sda_dir <= 1;
                        sda_out <= 0; // ACK
                        shift_reg[0] <= sda;
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 8) begin
                        sda_dir <= 0;
                        bit_count <= 0;
                        is_addressed <= 0; // End after 1 byte
                    end
                end
            end
        end
    end

endmodule
