`timescale 1ns / 1ps

module i2c_master #(
    parameter INPUT_CLK_FREQ = 50_000_000, // 50 MHz default
    parameter I2C_FREQ       = 100_000     // 100 kHz I2C clock
)(
    input  wire       clk,
    input  wire       rst_n,
    
    // Control interface
    input  wire       enable,      // Pulse high to start transaction
    input  wire       rw,          // 0 = write, 1 = read
    input  wire [6:0] addr,        // 7-bit target address
    input  wire [7:0] data_in,     // Data to write
    output reg  [7:0] data_out,    // Data read
    output reg        busy,        // High while transaction is ongoing
    output reg        ack_error,   // High if slave NACKs
    
    // I2C bus signals
    inout  wire       sda,
    output wire       scl
);

    // Derived parameters
    localparam DIVIDER = (INPUT_CLK_FREQ / I2C_FREQ) / 4; 
    // We divide by 4 because an I2C clock cycle has 4 phases: SCL low, SCL low-to-high, SCL high, SCL high-to-low

    // State Machine
    localparam IDLE    = 4'd0;
    localparam START   = 4'd1;
    localparam ADDR    = 4'd2;
    localparam ACK1    = 4'd3;
    localparam WRITE   = 4'd4;
    localparam READ    = 4'd5;
    localparam ACK2    = 4'd6;
    localparam STOP    = 4'd7;

    reg [3:0] state, next_state;
    reg [15:0] clk_count;
    reg [1:0]  i2c_phase;  // 00: SCL=0, 01: SCL=1 edge, 10: SCL=1, 11: SCL=0 edge
    reg i2c_clk_en;

    reg [7:0] tx_data;
    reg [7:0] rx_data;
    reg [2:0] bit_count;

    reg sda_out, sda_dir, scl_out;
    
    // Tri-state buffer for SDA
    assign sda = (sda_dir == 1'b1) ? sda_out : 1'bz;
    assign scl = scl_out;

    // Clock divider
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_count <= 0;
            i2c_phase <= 0;
            i2c_clk_en <= 0;
        end else begin
            if (clk_count == DIVIDER - 1) begin
                clk_count <= 0;
                i2c_phase <= i2c_phase + 1;
                i2c_clk_en <= 1'b1;
            end else begin
                clk_count <= clk_count + 1;
                i2c_clk_en <= 1'b0;
            end
        end
    end

    // FSM sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 0;
            ack_error <= 0;
            bit_count <= 0;
            tx_data <= 0;
            rx_data <= 0;
            data_out <= 0;
            sda_out <= 1;
            sda_dir <= 1;
            scl_out <= 1;
        end else begin
            if (i2c_clk_en) begin
                case (state)
                    IDLE: begin
                        sda_out <= 1;
                        sda_dir <= 1;
                        scl_out <= 1;
                        busy <= 0;
                        if (enable) begin
                            state <= START;
                            tx_data <= {addr, rw};
                            busy <= 1;
                            ack_error <= 0;
                        end
                    end

                    START: begin
                        busy <= 1;
                        case (i2c_phase)
                            2'b00: begin sda_out <= 1; sda_dir <= 1; scl_out <= 1; end
                            2'b01: begin sda_out <= 1; scl_out <= 1; end
                            2'b10: begin sda_out <= 0; scl_out <= 1; end
                            2'b11: begin sda_out <= 0; scl_out <= 0; end
                        endcase
                        if (i2c_phase == 2'b11) begin
                            state <= ADDR;
                            bit_count <= 7;
                        end
                    end

                    ADDR: begin
                        case (i2c_phase)
                            2'b00: begin sda_dir <= 1; sda_out <= tx_data[bit_count]; scl_out <= 0; end
                            2'b01: scl_out <= 1;
                            2'b10: scl_out <= 1;
                            2'b11: scl_out <= 0;
                        endcase
                        if (i2c_phase == 2'b11) begin
                            if (bit_count == 0) state <= ACK1;
                            else bit_count <= bit_count - 1;
                        end
                    end

                    ACK1: begin
                        case (i2c_phase)
                            2'b00: begin sda_dir <= 0; scl_out <= 0; end // Release SDA for slave ACK
                            2'b01: scl_out <= 1;
                            2'b10: begin scl_out <= 1; ack_error <= sda; end // Sample ACK
                            2'b11: scl_out <= 0;
                        endcase
                        if (i2c_phase == 2'b11) begin
                            if (ack_error) begin
                                state <= STOP; // Stop on NACK
                            end else begin
                                bit_count <= 7;
                                if (rw == 0) begin // Write
                                    tx_data <= data_in;
                                    state <= WRITE;
                                end else begin // Read
                                    state <= READ;
                                end
                            end
                        end
                    end

                    WRITE: begin
                        case (i2c_phase)
                            2'b00: begin sda_dir <= 1; sda_out <= tx_data[bit_count]; scl_out <= 0; end
                            2'b01: scl_out <= 1;
                            2'b10: scl_out <= 1;
                            2'b11: scl_out <= 0;
                        endcase
                        if (i2c_phase == 2'b11) begin
                            if (bit_count == 0) state <= ACK2;
                            else bit_count <= bit_count - 1;
                        end
                    end

                    READ: begin
                        case (i2c_phase)
                            2'b00: begin sda_dir <= 0; scl_out <= 0; end // Release SDA to read
                            2'b01: scl_out <= 1;
                            2'b10: begin scl_out <= 1; rx_data[bit_count] <= sda; end // Sample Data
                            2'b11: scl_out <= 0;
                        endcase
                        if (i2c_phase == 2'b11) begin
                            if (bit_count == 0) begin
                                data_out <= rx_data;
                                state <= ACK2;
                            end else begin
                                bit_count <= bit_count - 1;
                            end
                        end
                    end

                    ACK2: begin
                        case (i2c_phase)
                            2'b00: begin 
                                if (rw == 0) begin
                                    sda_dir <= 0; // Wait for slave ACK if we wrote
                                end else begin
                                    sda_dir <= 1; sda_out <= 1; // Master NACK after read (for 1 byte read)
                                end
                                scl_out <= 0; 
                            end
                            2'b01: scl_out <= 1;
                            2'b10: begin 
                                scl_out <= 1; 
                                if (rw == 0) ack_error <= sda; // Check ACK from slave
                            end 
                            2'b11: scl_out <= 0;
                        endcase
                        if (i2c_phase == 2'b11) begin
                            state <= STOP;
                        end
                    end

                    STOP: begin
                        case (i2c_phase)
                            2'b00: begin sda_dir <= 1; sda_out <= 0; scl_out <= 0; end
                            2'b01: begin scl_out <= 1; end
                            2'b10: begin sda_out <= 1; scl_out <= 1; end // SDA low to high while SCL is high -> STOP
                            2'b11: begin sda_out <= 1; scl_out <= 1; end
                        endcase
                        if (i2c_phase == 2'b11) begin
                            state <= IDLE;
                            busy <= 0;
                        end
                    end

                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule
