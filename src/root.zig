//! Modbus TCP Slave Simulator Library
//! 支持模拟任意数量的寄存器，并支持数值自动增加功能

const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;

/// Modbus 功能码
pub const FunctionCode = enum(u8) {
    read_coils = 0x01,
    read_discrete_inputs = 0x02,
    read_holding_registers = 0x03,
    read_input_registers = 0x04,
    write_single_coil = 0x05,
    write_single_register = 0x06,
    write_multiple_coils = 0x0F,
    write_multiple_registers = 0x10,
    _,
};

/// 寄存器类型
pub const RegisterType = enum {
    coils, // 线圈 (读写，1位)
    discrete_inputs, // 离散输入 (只读，1位)
    holding_registers, // 保持寄存器 (读写，16位)
    input_registers, // 输入寄存器 (只读，16位)

    pub fn fromString(s: []const u8) ?RegisterType {
        const map = std.StaticStringMap(RegisterType).initComptime(.{
            .{ "coils", .coils },
            .{ "discrete", .discrete_inputs },
            .{ "holding", .holding_registers },
            .{ "input", .input_registers },
        });
        return map.get(s);
    }
};

/// Modbus 异常码
pub const ExceptionCode = enum(u8) {
    illegal_function = 0x01,
    illegal_data_address = 0x02,
    illegal_data_value = 0x03,
    slave_device_failure = 0x04,
};

/// MBAP 头部 (Modbus Application Protocol Header)
pub const MbapHeader = struct {
    transaction_id: u16,
    protocol_id: u16,
    length: u16,
    unit_id: u8,

    pub const SIZE = 7;

    pub fn parse(data: []const u8) ?MbapHeader {
        if (data.len < SIZE) return null;
        return MbapHeader{
            .transaction_id = std.mem.readInt(u16, data[0..2], .big),
            .protocol_id = std.mem.readInt(u16, data[2..4], .big),
            .length = std.mem.readInt(u16, data[4..6], .big),
            .unit_id = data[6],
        };
    }

    pub fn serialize(self: MbapHeader, buf: []u8) void {
        std.mem.writeInt(u16, buf[0..2], self.transaction_id, .big);
        std.mem.writeInt(u16, buf[2..4], self.protocol_id, .big);
        std.mem.writeInt(u16, buf[4..6], self.length, .big);
        buf[6] = self.unit_id;
    }
};

/// Modbus PDU (Protocol Data Unit)
pub const ModbusPdu = struct {
    function_code: u8,
    data: []const u8,

    pub fn parse(data: []const u8) ?ModbusPdu {
        if (data.len < 1) return null;
        return ModbusPdu{
            .function_code = data[0],
            .data = data[1..],
        };
    }
};

/// 自动增加配置
pub const AutoIncrementConfig = struct {
    enabled: bool = false,
    registers: []const u16 = &.{},
    interval_ms: u64 = 1000,
    increment_value: u16 = 1,
    max_value: u16 = 65535,
};

/// 寄存器存储
pub const RegisterStorage = struct {
    allocator: Allocator,
    coils: []u8, // 位打包
    discrete_inputs: []u8, // 位打包
    holding_registers: []u16,
    input_registers: []u16,
    coil_count: u16,
    discrete_count: u16,
    holding_count: u16,
    input_count: u16,
    mutex: std.Thread.Mutex = .{},

    pub fn init(
        allocator: Allocator,
        coil_count: u16,
        discrete_count: u16,
        holding_count: u16,
        input_count: u16,
    ) !RegisterStorage {
        const coil_bytes = (coil_count + 7) / 8;
        const discrete_bytes = (discrete_count + 7) / 8;

        return RegisterStorage{
            .allocator = allocator,
            .coils = try allocator.alloc(u8, coil_bytes),
            .discrete_inputs = try allocator.alloc(u8, discrete_bytes),
            .holding_registers = try allocator.alloc(u16, holding_count),
            .input_registers = try allocator.alloc(u16, input_count),
            .coil_count = coil_count,
            .discrete_count = discrete_count,
            .holding_count = holding_count,
            .input_count = input_count,
        };
    }

    pub fn deinit(self: *RegisterStorage) void {
        self.allocator.free(self.coils);
        self.allocator.free(self.discrete_inputs);
        self.allocator.free(self.holding_registers);
        self.allocator.free(self.input_registers);
    }

    /// 初始化所有寄存器为指定值
    pub fn initRegisters(self: *RegisterStorage, initial_value: u16) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        @memset(self.coils, 0);
        @memset(self.discrete_inputs, 0);
        @memset(self.holding_registers, initial_value);
        @memset(self.input_registers, initial_value);
    }

    /// 读取线圈
    pub fn readCoils(self: *RegisterStorage, start: u16, count: u16, buf: []u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (start + count > self.coil_count) return false;

        const byte_count = (count + 7) / 8;
        @memset(buf[0..byte_count], 0);

        for (0..count) |i| {
            const addr = start + @as(u16, @intCast(i));
            const byte_idx = addr / 8;
            const bit_idx: u3 = @intCast(addr % 8);
            const value = (self.coils[byte_idx] >> bit_idx) & 1;

            const out_byte_idx = i / 8;
            const out_bit_idx: u3 = @intCast(i % 8);
            buf[out_byte_idx] |= value << out_bit_idx;
        }
        return true;
    }

    /// 读取离散输入
    pub fn readDiscreteInputs(self: *RegisterStorage, start: u16, count: u16, buf: []u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (start + count > self.discrete_count) return false;

        const byte_count = (count + 7) / 8;
        @memset(buf[0..byte_count], 0);

        for (0..count) |i| {
            const addr = start + @as(u16, @intCast(i));
            const byte_idx = addr / 8;
            const bit_idx: u3 = @intCast(addr % 8);
            const value = (self.discrete_inputs[byte_idx] >> bit_idx) & 1;

            const out_byte_idx = i / 8;
            const out_bit_idx: u3 = @intCast(i % 8);
            buf[out_byte_idx] |= value << out_bit_idx;
        }
        return true;
    }

    /// 读取保持寄存器
    pub fn readHoldingRegisters(self: *RegisterStorage, start: u16, count: u16, buf: []u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (start + count > self.holding_count) return false;

        for (0..count) |i| {
            const value = self.holding_registers[start + @as(u16, @intCast(i))];
            std.mem.writeInt(u16, buf[i * 2 ..][0..2], value, .big);
        }
        return true;
    }

    /// 读取输入寄存器
    pub fn readInputRegisters(self: *RegisterStorage, start: u16, count: u16, buf: []u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (start + count > self.input_count) return false;

        for (0..count) |i| {
            const value = self.input_registers[start + @as(u16, @intCast(i))];
            std.mem.writeInt(u16, buf[i * 2 ..][0..2], value, .big);
        }
        return true;
    }

    /// 写入单个线圈
    pub fn writeSingleCoil(self: *RegisterStorage, addr: u16, value: bool) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (addr >= self.coil_count) return false;

        const byte_idx = addr / 8;
        const bit_idx: u3 = @intCast(addr % 8);

        if (value) {
            self.coils[byte_idx] |= @as(u8, 1) << bit_idx;
        } else {
            self.coils[byte_idx] &= ~(@as(u8, 1) << bit_idx);
        }
        return true;
    }

    /// 写入单个寄存器
    pub fn writeSingleRegister(self: *RegisterStorage, addr: u16, value: u16) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (addr >= self.holding_count) return false;
        self.holding_registers[addr] = value;
        return true;
    }

    /// 写入多个线圈
    pub fn writeMultipleCoils(self: *RegisterStorage, start: u16, count: u16, data: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (start + count > self.coil_count) return false;

        for (0..count) |i| {
            const addr = start + @as(u16, @intCast(i));
            const byte_idx = addr / 8;
            const bit_idx: u3 = @intCast(addr % 8);

            const in_byte_idx = i / 8;
            const in_bit_idx: u3 = @intCast(i % 8);
            const value = (data[in_byte_idx] >> in_bit_idx) & 1;

            if (value == 1) {
                self.coils[byte_idx] |= @as(u8, 1) << bit_idx;
            } else {
                self.coils[byte_idx] &= ~(@as(u8, 1) << bit_idx);
            }
        }
        return true;
    }

    /// 写入多个寄存器
    pub fn writeMultipleRegisters(self: *RegisterStorage, start: u16, count: u16, data: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (start + count > self.holding_count) return false;

        for (0..count) |i| {
            const value = std.mem.readInt(u16, data[i * 2 ..][0..2], .big);
            self.holding_registers[start + @as(u16, @intCast(i))] = value;
        }
        return true;
    }

    /// 自动增加指定寄存器的值
    pub fn incrementRegisters(self: *RegisterStorage, reg_type: RegisterType, addresses: []const u16, increment: u16, max_value: u16) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (addresses) |addr| {
            switch (reg_type) {
                .holding_registers => {
                    if (addr < self.holding_count) {
                        const current = self.holding_registers[addr];
                        if (current >= max_value - increment) {
                            self.holding_registers[addr] = 0;
                        } else {
                            self.holding_registers[addr] = current + increment;
                        }
                    }
                },
                .input_registers => {
                    if (addr < self.input_count) {
                        const current = self.input_registers[addr];
                        if (current >= max_value - increment) {
                            self.input_registers[addr] = 0;
                        } else {
                            self.input_registers[addr] = current + increment;
                        }
                    }
                },
                else => {},
            }
        }
    }
};

/// Modbus TCP Slave 模拟器
pub const ModbusSlave = struct {
    allocator: Allocator,
    unit_id: u8,
    storage: RegisterStorage,

    // 支持多个自动增加配置（针对不同寄存器类型）
    holding_auto_config: AutoIncrementConfig = .{},
    input_auto_config: AutoIncrementConfig = .{},

    holding_auto_thread: ?std.Thread = null,
    input_auto_thread: ?std.Thread = null,

    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    response_buffer: [260]u8 = undefined,

    pub fn init(
        allocator: Allocator,
        unit_id: u8,
        coil_count: u16,
        discrete_count: u16,
        holding_count: u16,
        input_count: u16,
    ) !ModbusSlave {
        var storage = try RegisterStorage.init(allocator, coil_count, discrete_count, holding_count, input_count);
        storage.initRegisters(0);

        return ModbusSlave{
            .allocator = allocator,
            .unit_id = unit_id,
            .storage = storage,
        };
    }

    pub fn deinit(self: *ModbusSlave) void {
        self.stopAutoIncrement();
        self.storage.deinit();
    }

    /// 配置自动增加功能（根据寄存器类型分别配置）
    pub fn configureAutoIncrement(self: *ModbusSlave, config: AutoIncrementConfig) void {
        // 这个函数保留用于向后兼容，实际使用时会在 startAutoIncrement 之前调用
        // 新代码应该使用 configureHoldingAutoIncrement 和 configureInputAutoIncrement
        self.holding_auto_config = config;
    }

    pub fn configureHoldingAutoIncrement(self: *ModbusSlave, config: AutoIncrementConfig) void {
        self.holding_auto_config = config;
    }

    pub fn configureInputAutoIncrement(self: *ModbusSlave, config: AutoIncrementConfig) void {
        self.input_auto_config = config;
    }

    /// 启动自动增加线程
    pub fn startAutoIncrement(self: *ModbusSlave, reg_type: RegisterType) !void {
        self.running.store(true, .release);

        switch (reg_type) {
            .holding_registers => {
                if (!self.holding_auto_config.enabled) return;
                if (self.holding_auto_thread != null) return;

                self.holding_auto_thread = try std.Thread.spawn(.{}, struct {
                    fn run(slave: *ModbusSlave) void {
                        while (slave.running.load(.acquire)) {
                            std.Thread.sleep(slave.holding_auto_config.interval_ms * std.time.ns_per_ms);
                            if (!slave.running.load(.acquire)) break;

                            slave.storage.incrementRegisters(
                                .holding_registers,
                                slave.holding_auto_config.registers,
                                slave.holding_auto_config.increment_value,
                                slave.holding_auto_config.max_value,
                            );
                        }
                    }
                }.run, .{self});
            },
            .input_registers => {
                if (!self.input_auto_config.enabled) return;
                if (self.input_auto_thread != null) return;

                self.input_auto_thread = try std.Thread.spawn(.{}, struct {
                    fn run(slave: *ModbusSlave) void {
                        while (slave.running.load(.acquire)) {
                            std.Thread.sleep(slave.input_auto_config.interval_ms * std.time.ns_per_ms);
                            if (!slave.running.load(.acquire)) break;

                            slave.storage.incrementRegisters(
                                .input_registers,
                                slave.input_auto_config.registers,
                                slave.input_auto_config.increment_value,
                                slave.input_auto_config.max_value,
                            );
                        }
                    }
                }.run, .{self});
            },
            else => {},
        }
    }

    /// 停止所有自动增加线程
    pub fn stopAutoIncrement(self: *ModbusSlave) void {
        self.running.store(false, .release);

        if (self.holding_auto_thread) |thread| {
            thread.join();
            self.holding_auto_thread = null;
        }

        if (self.input_auto_thread) |thread| {
            thread.join();
            self.input_auto_thread = null;
        }
    }

    /// 处理 Modbus 请求并返回响应
    pub fn processRequest(self: *ModbusSlave, request: []const u8, response: []u8) ?usize {
        // 解析 MBAP 头
        const mbap = MbapHeader.parse(request) orelse return null;

        // 检查协议 ID
        if (mbap.protocol_id != 0) return null;

        // 检查从站地址 (0 表示广播，也接受)
        if (mbap.unit_id != 0 and mbap.unit_id != self.unit_id) return null;

        // 解析 PDU
        if (request.len < MbapHeader.SIZE + 1) return null;
        const pdu = ModbusPdu.parse(request[MbapHeader.SIZE..]) orelse return null;

        // 处理功能码
        return self.handleFunction(mbap, pdu, response);
    }

    fn handleFunction(self: *ModbusSlave, mbap: MbapHeader, pdu: ModbusPdu, response: []u8) ?usize {
        const fc = std.meta.intToEnum(FunctionCode, pdu.function_code) catch {
            return self.buildExceptionResponse(mbap, pdu.function_code, .illegal_function, response);
        };

        return switch (fc) {
            .read_coils => self.handleReadCoils(mbap, pdu.data, response),
            .read_discrete_inputs => self.handleReadDiscreteInputs(mbap, pdu.data, response),
            .read_holding_registers => self.handleReadHoldingRegisters(mbap, pdu.data, response),
            .read_input_registers => self.handleReadInputRegisters(mbap, pdu.data, response),
            .write_single_coil => self.handleWriteSingleCoil(mbap, pdu.data, response),
            .write_single_register => self.handleWriteSingleRegister(mbap, pdu.data, response),
            .write_multiple_coils => self.handleWriteMultipleCoils(mbap, pdu.data, response),
            .write_multiple_registers => self.handleWriteMultipleRegisters(mbap, pdu.data, response),
            _ => self.buildExceptionResponse(mbap, pdu.function_code, .illegal_function, response),
        };
    }

    fn handleReadCoils(self: *ModbusSlave, mbap: MbapHeader, data: []const u8, response: []u8) ?usize {
        if (data.len < 4) return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_coils), .illegal_data_value, response);

        const start_addr = std.mem.readInt(u16, data[0..2], .big);
        const quantity = std.mem.readInt(u16, data[2..4], .big);

        if (quantity == 0 or quantity > 2000) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_coils), .illegal_data_value, response);
        }

        const byte_count: u8 = @intCast((quantity + 7) / 8);

        // 构建响应
        var resp_mbap = mbap;
        resp_mbap.length = 3 + @as(u16, byte_count);
        resp_mbap.serialize(response);
        response[MbapHeader.SIZE] = @intFromEnum(FunctionCode.read_coils);
        response[MbapHeader.SIZE + 1] = byte_count;

        if (!self.storage.readCoils(start_addr, quantity, response[MbapHeader.SIZE + 2 ..])) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_coils), .illegal_data_address, response);
        }

        return MbapHeader.SIZE + 2 + @as(usize, byte_count);
    }

    fn handleReadDiscreteInputs(self: *ModbusSlave, mbap: MbapHeader, data: []const u8, response: []u8) ?usize {
        if (data.len < 4) return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_discrete_inputs), .illegal_data_value, response);

        const start_addr = std.mem.readInt(u16, data[0..2], .big);
        const quantity = std.mem.readInt(u16, data[2..4], .big);

        if (quantity == 0 or quantity > 2000) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_discrete_inputs), .illegal_data_value, response);
        }

        const byte_count: u8 = @intCast((quantity + 7) / 8);

        var resp_mbap = mbap;
        resp_mbap.length = 3 + @as(u16, byte_count);
        resp_mbap.serialize(response);
        response[MbapHeader.SIZE] = @intFromEnum(FunctionCode.read_discrete_inputs);
        response[MbapHeader.SIZE + 1] = byte_count;

        if (!self.storage.readDiscreteInputs(start_addr, quantity, response[MbapHeader.SIZE + 2 ..])) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_discrete_inputs), .illegal_data_address, response);
        }

        return MbapHeader.SIZE + 2 + @as(usize, byte_count);
    }

    fn handleReadHoldingRegisters(self: *ModbusSlave, mbap: MbapHeader, data: []const u8, response: []u8) ?usize {
        if (data.len < 4) return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_holding_registers), .illegal_data_value, response);

        const start_addr = std.mem.readInt(u16, data[0..2], .big);
        const quantity = std.mem.readInt(u16, data[2..4], .big);

        if (quantity == 0 or quantity > 125) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_holding_registers), .illegal_data_value, response);
        }

        const byte_count: u8 = @intCast(quantity * 2);

        var resp_mbap = mbap;
        resp_mbap.length = 3 + @as(u16, byte_count);
        resp_mbap.serialize(response);
        response[MbapHeader.SIZE] = @intFromEnum(FunctionCode.read_holding_registers);
        response[MbapHeader.SIZE + 1] = byte_count;

        if (!self.storage.readHoldingRegisters(start_addr, quantity, response[MbapHeader.SIZE + 2 ..])) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_holding_registers), .illegal_data_address, response);
        }

        return MbapHeader.SIZE + 2 + @as(usize, byte_count);
    }

    fn handleReadInputRegisters(self: *ModbusSlave, mbap: MbapHeader, data: []const u8, response: []u8) ?usize {
        if (data.len < 4) return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_input_registers), .illegal_data_value, response);

        const start_addr = std.mem.readInt(u16, data[0..2], .big);
        const quantity = std.mem.readInt(u16, data[2..4], .big);

        if (quantity == 0 or quantity > 125) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_input_registers), .illegal_data_value, response);
        }

        const byte_count: u8 = @intCast(quantity * 2);

        var resp_mbap = mbap;
        resp_mbap.length = 3 + @as(u16, byte_count);
        resp_mbap.serialize(response);
        response[MbapHeader.SIZE] = @intFromEnum(FunctionCode.read_input_registers);
        response[MbapHeader.SIZE + 1] = byte_count;

        if (!self.storage.readInputRegisters(start_addr, quantity, response[MbapHeader.SIZE + 2 ..])) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.read_input_registers), .illegal_data_address, response);
        }

        return MbapHeader.SIZE + 2 + @as(usize, byte_count);
    }

    fn handleWriteSingleCoil(self: *ModbusSlave, mbap: MbapHeader, data: []const u8, response: []u8) ?usize {
        if (data.len < 4) return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_single_coil), .illegal_data_value, response);

        const addr = std.mem.readInt(u16, data[0..2], .big);
        const value = std.mem.readInt(u16, data[2..4], .big);

        // 值必须是 0x0000 或 0xFF00
        if (value != 0x0000 and value != 0xFF00) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_single_coil), .illegal_data_value, response);
        }

        if (!self.storage.writeSingleCoil(addr, value == 0xFF00)) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_single_coil), .illegal_data_address, response);
        }

        // 响应是请求的回显
        var resp_mbap = mbap;
        resp_mbap.length = 6;
        resp_mbap.serialize(response);
        response[MbapHeader.SIZE] = @intFromEnum(FunctionCode.write_single_coil);
        @memcpy(response[MbapHeader.SIZE + 1 ..][0..4], data[0..4]);

        return MbapHeader.SIZE + 5;
    }

    fn handleWriteSingleRegister(self: *ModbusSlave, mbap: MbapHeader, data: []const u8, response: []u8) ?usize {
        if (data.len < 4) return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_single_register), .illegal_data_value, response);

        const addr = std.mem.readInt(u16, data[0..2], .big);
        const value = std.mem.readInt(u16, data[2..4], .big);

        if (!self.storage.writeSingleRegister(addr, value)) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_single_register), .illegal_data_address, response);
        }

        // 响应是请求的回显
        var resp_mbap = mbap;
        resp_mbap.length = 6;
        resp_mbap.serialize(response);
        response[MbapHeader.SIZE] = @intFromEnum(FunctionCode.write_single_register);
        @memcpy(response[MbapHeader.SIZE + 1 ..][0..4], data[0..4]);

        return MbapHeader.SIZE + 5;
    }

    fn handleWriteMultipleCoils(self: *ModbusSlave, mbap: MbapHeader, data: []const u8, response: []u8) ?usize {
        if (data.len < 5) return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_multiple_coils), .illegal_data_value, response);

        const start_addr = std.mem.readInt(u16, data[0..2], .big);
        const quantity = std.mem.readInt(u16, data[2..4], .big);
        const byte_count = data[4];

        if (quantity == 0 or quantity > 1968 or byte_count != (quantity + 7) / 8) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_multiple_coils), .illegal_data_value, response);
        }

        if (data.len < 5 + byte_count) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_multiple_coils), .illegal_data_value, response);
        }

        if (!self.storage.writeMultipleCoils(start_addr, quantity, data[5..])) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_multiple_coils), .illegal_data_address, response);
        }

        var resp_mbap = mbap;
        resp_mbap.length = 6;
        resp_mbap.serialize(response);
        response[MbapHeader.SIZE] = @intFromEnum(FunctionCode.write_multiple_coils);
        @memcpy(response[MbapHeader.SIZE + 1 ..][0..4], data[0..4]);

        return MbapHeader.SIZE + 5;
    }

    fn handleWriteMultipleRegisters(self: *ModbusSlave, mbap: MbapHeader, data: []const u8, response: []u8) ?usize {
        if (data.len < 5) return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_multiple_registers), .illegal_data_value, response);

        const start_addr = std.mem.readInt(u16, data[0..2], .big);
        const quantity = std.mem.readInt(u16, data[2..4], .big);
        const byte_count = data[4];

        if (quantity == 0 or quantity > 123 or byte_count != quantity * 2) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_multiple_registers), .illegal_data_value, response);
        }

        if (data.len < 5 + byte_count) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_multiple_registers), .illegal_data_value, response);
        }

        if (!self.storage.writeMultipleRegisters(start_addr, quantity, data[5..])) {
            return self.buildExceptionResponse(mbap, @intFromEnum(FunctionCode.write_multiple_registers), .illegal_data_address, response);
        }

        var resp_mbap = mbap;
        resp_mbap.length = 6;
        resp_mbap.serialize(response);
        response[MbapHeader.SIZE] = @intFromEnum(FunctionCode.write_multiple_registers);
        @memcpy(response[MbapHeader.SIZE + 1 ..][0..4], data[0..4]);

        return MbapHeader.SIZE + 5;
    }

    fn buildExceptionResponse(self: *ModbusSlave, mbap: MbapHeader, function_code: u8, exception: ExceptionCode, response: []u8) usize {
        _ = self;
        var resp_mbap = mbap;
        resp_mbap.length = 3;
        resp_mbap.serialize(response);
        response[MbapHeader.SIZE] = function_code | 0x80; // 异常标志
        response[MbapHeader.SIZE + 1] = @intFromEnum(exception);
        return MbapHeader.SIZE + 2;
    }
};

/// 高性能 TCP 服务器
pub const TcpServer = struct {
    allocator: Allocator,
    slave: *ModbusSlave,
    listener: ?posix.socket_t = null,
    port: u16,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    accept_thread: ?std.Thread = null,
    client_threads: std.ArrayListUnmanaged(std.Thread) = .empty,

    pub fn init(allocator: Allocator, slave: *ModbusSlave, port: u16) TcpServer {
        return TcpServer{
            .allocator = allocator,
            .slave = slave,
            .port = port,
        };
    }

    pub fn deinit(self: *TcpServer) void {
        self.stop();
        self.client_threads.deinit(self.allocator);
    }

    pub fn start(self: *TcpServer) !void {
        const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, self.port);
        self.listener = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);

        // 设置 SO_REUSEADDR
        try posix.setsockopt(self.listener.?, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        // 设置 TCP_NODELAY 以减少延迟
        try posix.setsockopt(self.listener.?, posix.IPPROTO.TCP, std.posix.TCP.NODELAY, &std.mem.toBytes(@as(c_int, 1)));

        try posix.bind(self.listener.?, &address.any, address.getOsSockLen());
        try posix.listen(self.listener.?, 128);

        self.running.store(true, .release);

        std.debug.print("Modbus TCP Slave listening on port {d}\n", .{self.port});
        std.debug.print("Unit ID: {d}\n", .{self.slave.unit_id});

        self.accept_thread = try std.Thread.spawn(.{}, acceptLoop, .{self});
    }

    pub fn stop(self: *TcpServer) void {
        self.running.store(false, .release);

        if (self.listener) |sock| {
            posix.close(sock);
            self.listener = null;
        }

        if (self.accept_thread) |thread| {
            thread.join();
            self.accept_thread = null;
        }
    }

    fn acceptLoop(self: *TcpServer) void {
        while (self.running.load(.acquire)) {
            const client = posix.accept(self.listener.?, null, null, 0) catch |err| {
                if (err == error.SocketNotListening or !self.running.load(.acquire)) {
                    break;
                }
                continue;
            };

            // 为每个客户端启动一个处理线程
            const thread = std.Thread.spawn(.{}, clientHandler, .{ self, client }) catch {
                posix.close(client);
                continue;
            };

            self.client_threads.append(self.allocator, thread) catch {
                posix.close(client);
            };
        }
    }

    fn clientHandler(srv: *TcpServer, client: posix.socket_t) void {
        defer posix.close(client);

        // 设置 TCP_NODELAY
        posix.setsockopt(client, posix.IPPROTO.TCP, std.posix.TCP.NODELAY, &std.mem.toBytes(@as(c_int, 1))) catch {};

        var recv_buf: [512]u8 = undefined;
        var send_buf: [512]u8 = undefined;

        while (srv.running.load(.acquire)) {
            const n = posix.recv(client, &recv_buf, 0) catch break;
            if (n == 0) break;

            if (srv.slave.processRequest(recv_buf[0..n], &send_buf)) |resp_len| {
                _ = posix.send(client, send_buf[0..resp_len], 0) catch break;
            }
        }
    }

    pub fn wait(self: *TcpServer) void {
        if (self.accept_thread) |thread| {
            thread.join();
        }
    }
};

// 测试
test "register storage basic operations" {
    const allocator = std.testing.allocator;
    var storage = try RegisterStorage.init(allocator, 100, 100, 100, 100);
    defer storage.deinit();

    storage.initRegisters(0);

    // 测试写入和读取保持寄存器
    try std.testing.expect(storage.writeSingleRegister(0, 12345));
    var buf: [2]u8 = undefined;
    try std.testing.expect(storage.readHoldingRegisters(0, 1, &buf));
    const value = std.mem.readInt(u16, &buf, .big);
    try std.testing.expectEqual(@as(u16, 12345), value);
}

test "mbap header parse and serialize" {
    const data = [_]u8{ 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01 };
    const mbap = MbapHeader.parse(&data).?;

    try std.testing.expectEqual(@as(u16, 1), mbap.transaction_id);
    try std.testing.expectEqual(@as(u16, 0), mbap.protocol_id);
    try std.testing.expectEqual(@as(u16, 6), mbap.length);
    try std.testing.expectEqual(@as(u8, 1), mbap.unit_id);

    var out: [7]u8 = undefined;
    mbap.serialize(&out);
    try std.testing.expectEqualSlices(u8, &data, &out);
}
