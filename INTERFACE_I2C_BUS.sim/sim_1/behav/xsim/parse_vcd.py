def parse_vcd(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    sda_id = None
    scl_id = None
    ack_error_id = None
    state_id = None
    
    for line in lines:
        if ' sda ' in line and sda_id is None:
            sda_id = line.split()[3]
        if ' scl ' in line and scl_id is None:
            scl_id = line.split()[3]
        if ' ack_error ' in line and ack_error_id is None:
            ack_error_id = line.split()[3]
        if ' state [3:0]' in line and state_id is None:
            state_id = line.split()[3]
        if '$enddefinitions' in line:
            break
            
    time = 0
    sda = '1'
    scl = '1'
    ack_error = '0'
    state = '0'
    
    for line in lines:
        if line.startswith('#'):
            time = int(line.strip()[1:])
        elif sda_id and line.endswith(sda_id + '\n'):
            sda = line[0]
            print(f'{time/1000.0:>10} ns | SCL: {scl} | SDA: {sda} | ACK: {ack_error} | ST: {state}')
        elif scl_id and line.endswith(scl_id + '\n'):
            scl = line[0]
            print(f'{time/1000.0:>10} ns | SCL: {scl} | SDA: {sda} | ACK: {ack_error} | ST: {state}')
        elif ack_error_id and line.endswith(ack_error_id + '\n'):
            ack_error = line[0]
            print(f'{time/1000.0:>10} ns | SCL: {scl} | SDA: {sda} | ACK: {ack_error} | ST: {state}')
        elif state_id and line.endswith(state_id + '\n'):
            state = line.split()[0][1:]
            print(f'{time/1000.0:>10} ns | SCL: {scl} | SDA: {sda} | ACK: {ack_error} | ST: {state}')

parse_vcd('i2c_sim.vcd')
