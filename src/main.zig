//! Modbus TCP Slave Simulator
//! 一个高性能的 Modbus TCP 从站模拟器
//!
//! 支持同时模拟多种寄存器类型

const std = @import("std");
const zmodsim = @import("zmodsim");

const ModbusSlave = zmodsim.ModbusSlave;
const TcpServer = zmodsim.TcpServer;
const RegisterType = zmodsim.RegisterType;
const AutoIncrementConfig = zmodsim.AutoIncrementConfig;

/// 自动增加配置（针对特定寄存器类型）
const AutoIncConfig = struct {
    enabled: bool = false,
    registers: []u16 = &.{},
    interval_ms: u64 = 1000,
    increment_value: u16 = 1,
    max_value: u16 = 65535,
};

/// 运行时配置 - 支持同时配置多种寄存器
const Config = struct {
    unit_id: u8 = 1,
    port: u16 = 502,

    // 各类寄存器数量
    coil_count: u16 = 100,
    discrete_count: u16 = 100,
    holding_count: u16 = 100,
    input_count: u16 = 100,

    // 自动增加配置（针对 holding 和 input 寄存器）
    holding_auto_inc: AutoIncConfig = .{},
    input_auto_inc: AutoIncConfig = .{},
};

// ============================================================================
// JSON 配置文件结构
// ============================================================================

/// JSON 自动增加配置
const JsonAutoIncConfig = struct {
    enabled: bool = false,
    registers: ?[]const i64 = null, // JSON 数组
    registers_range: ?[]const u8 = null, // 字符串格式如 "0-9,20,30"
    interval: u64 = 1000,
    increment: u16 = 1,
    max: u16 = 65535,
};

/// JSON 配置文件结构
const JsonConfig = struct {
    unit_id: u8 = 1,
    port: u16 = 502,

    coils: u16 = 100,
    discrete: u16 = 100,
    holding: u16 = 100,
    input: u16 = 100,

    holding_auto: ?JsonAutoIncConfig = null,
    input_auto: ?JsonAutoIncConfig = null,
};

// ============================================================================
// 配置文件解析器 (JSON)
// ============================================================================

fn parseConfigFile(allocator: std.mem.Allocator, path: []const u8) !Config {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("错误: 无法打开配置文件 '{s}': {}\n", .{ path, err });
        return error.ConfigFileNotFound;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        std.debug.print("错误: 读取配置文件失败: {}\n", .{err});
        return error.ConfigFileReadError;
    };
    defer allocator.free(content);

    return parseJsonConfig(allocator, content);
}

fn parseJsonConfig(allocator: std.mem.Allocator, content: []const u8) !Config {
    const parsed = std.json.parseFromSlice(JsonConfig, allocator, content, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        std.debug.print("错误: JSON 解析失败: {}\n", .{err});
        return error.JsonParseError;
    };
    defer parsed.deinit();

    const json_cfg = parsed.value;

    var config = Config{
        .unit_id = json_cfg.unit_id,
        .port = json_cfg.port,
        .coil_count = json_cfg.coils,
        .discrete_count = json_cfg.discrete,
        .holding_count = json_cfg.holding,
        .input_count = json_cfg.input,
    };

    // 解析 Holding 自动增加配置
    if (json_cfg.holding_auto) |ha| {
        config.holding_auto_inc.enabled = ha.enabled;
        config.holding_auto_inc.interval_ms = ha.interval;
        config.holding_auto_inc.increment_value = ha.increment;
        config.holding_auto_inc.max_value = ha.max;

        // 解析寄存器列表
        if (ha.registers) |regs| {
            var reg_list = try allocator.alloc(u16, regs.len);
            for (regs, 0..) |r, i| {
                reg_list[i] = @intCast(r);
            }
            config.holding_auto_inc.registers = reg_list;
        } else if (ha.registers_range) |range| {
            config.holding_auto_inc.registers = try parseRegisterList(allocator, range);
        }
    }

    // 解析 Input 自动增加配置
    if (json_cfg.input_auto) |ia| {
        config.input_auto_inc.enabled = ia.enabled;
        config.input_auto_inc.interval_ms = ia.interval;
        config.input_auto_inc.increment_value = ia.increment;
        config.input_auto_inc.max_value = ia.max;

        if (ia.registers) |regs| {
            var reg_list = try allocator.alloc(u16, regs.len);
            for (regs, 0..) |r, i| {
                reg_list[i] = @intCast(r);
            }
            config.input_auto_inc.registers = reg_list;
        } else if (ia.registers_range) |range| {
            config.input_auto_inc.registers = try parseRegisterList(allocator, range);
        }
    }

    // 如果启用了自动增加但没有指定寄存器，默认使用所有寄存器
    if (config.holding_auto_inc.enabled and config.holding_auto_inc.registers.len == 0) {
        var regs = try allocator.alloc(u16, config.holding_count);
        for (0..config.holding_count) |i| regs[i] = @intCast(i);
        config.holding_auto_inc.registers = regs;
    }

    if (config.input_auto_inc.enabled and config.input_auto_inc.registers.len == 0) {
        var regs = try allocator.alloc(u16, config.input_count);
        for (0..config.input_count) |i| regs[i] = @intCast(i);
        config.input_auto_inc.registers = regs;
    }

    return config;
}

fn parseRegisterList(allocator: std.mem.Allocator, input: []const u8) ![]u16 {
    var registers: std.ArrayListUnmanaged(u16) = .empty;
    errdefer registers.deinit(allocator);

    var it = std.mem.splitSequence(u8, input, ",");
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " ");
        if (trimmed.len == 0) continue;

        if (std.mem.indexOf(u8, trimmed, "-")) |dash_pos| {
            const start_str = std.mem.trim(u8, trimmed[0..dash_pos], " ");
            const end_str = std.mem.trim(u8, trimmed[dash_pos + 1 ..], " ");

            const start = std.fmt.parseInt(u16, start_str, 10) catch {
                std.debug.print("无效的寄存器范围: {s}\n", .{trimmed});
                return error.InvalidArgument;
            };
            const end = std.fmt.parseInt(u16, end_str, 10) catch {
                std.debug.print("无效的寄存器范围: {s}\n", .{trimmed});
                return error.InvalidArgument;
            };

            if (start > end) {
                std.debug.print("无效的寄存器范围: {s}\n", .{trimmed});
                return error.InvalidArgument;
            }

            var i = start;
            while (i <= end) : (i += 1) {
                try registers.append(allocator, i);
            }
        } else {
            const reg = std.fmt.parseInt(u16, trimmed, 10) catch {
                std.debug.print("无效的寄存器地址: {s}\n", .{trimmed});
                return error.InvalidArgument;
            };
            try registers.append(allocator, reg);
        }
    }

    return registers.toOwnedSlice(allocator);
}

// ============================================================================
// 命令行参数解析
// ============================================================================

const CliConfig = struct {
    config_file: ?[]const u8 = null,
    unit_id: ?u8 = null,
    port: ?u16 = null,

    coil_count: ?u16 = null,
    discrete_count: ?u16 = null,
    holding_count: ?u16 = null,
    input_count: ?u16 = null,

    // Holding 自动增加
    holding_auto_increment: ?bool = null,
    holding_registers: []u16 = &.{},
    holding_interval: ?u64 = null,
    holding_increment: ?u16 = null,
    holding_max: ?u16 = null,

    // Input 自动增加
    input_auto_increment: ?bool = null,
    input_registers: []u16 = &.{},
    input_interval: ?u64 = null,
    input_increment: ?u16 = null,
    input_max: ?u16 = null,

    show_help: bool = false,
    generate_config: bool = false,
};

fn printHelp() void {
    const help_text =
        \\Modbus TCP Slave Simulator (zmodsim)
        \\
        \\用法:
        \\  zmodsim [选项]
        \\
        \\基本选项:
        \\  -f, --config <file>       从 JSON 配置文件加载参数
        \\  -u, --unit-id <id>        从站地址 (1-247, 默认: 1)
        \\  -p, --port <port>         监听端口 (默认: 502)
        \\  -h, --help                显示此帮助信息
        \\  --generate-config         生成示例 JSON 配置文件到标准输出
        \\
        \\寄存器数量设置:
        \\  --coils <count>           线圈数量 (默认: 100)
        \\  --discrete <count>        离散输入数量 (默认: 100)
        \\  --holding <count>         保持寄存器数量 (默认: 100)
        \\  --input <count>           输入寄存器数量 (默认: 100)
        \\
        \\Holding 寄存器自动增加:
        \\  --holding-auto            启用 Holding 寄存器自动增加
        \\  --holding-regs <list>     自动增加的寄存器列表 (如: 0-9,20,30)
        \\  --holding-interval <ms>   增加间隔毫秒数 (默认: 1000)
        \\  --holding-inc <value>     每次增加的值 (默认: 1)
        \\  --holding-max <value>     最大值 (默认: 65535)
        \\
        \\Input 寄存器自动增加:
        \\  --input-auto              启用 Input 寄存器自动增加
        \\  --input-regs <list>       自动增加的寄存器列表 (如: 0-9,20,30)
        \\  --input-interval <ms>     增加间隔毫秒数 (默认: 1000)
        \\  --input-inc <value>       每次增加的值 (默认: 1)
        \\  --input-max <value>       最大值 (默认: 65535)
        \\
        \\配置文件:
        \\  配置文件使用 JSON 格式，命令行参数会覆盖配置文件中的同名参数。
        \\  使用 --generate-config 生成示例配置文件。
        \\
        \\示例:
        \\  # 同时模拟 1000 个 Holding 和 500 个 Input 寄存器
        \\  zmodsim --holding 1000 --input 500
        \\
        \\  # Holding 寄存器 0-9 每秒自动增加
        \\  zmodsim --holding-auto --holding-regs 0-9
        \\
        \\  # 同时启用 Holding 和 Input 自动增加
        \\  zmodsim --holding-auto --holding-regs 0-9 --input-auto --input-regs 0-4
        \\
        \\  # 使用配置文件
        \\  zmodsim -f config.json
        \\
        \\  # 生成配置文件
        \\  zmodsim --generate-config > config.json
        \\
        \\支持的 Modbus 功能码:
        \\  0x01 - 读线圈           0x02 - 读离散输入
        \\  0x03 - 读保持寄存器     0x04 - 读输入寄存器
        \\  0x05 - 写单个线圈       0x06 - 写单个寄存器
        \\  0x0F - 写多个线圈       0x10 - 写多个寄存器
        \\
    ;
    std.debug.print("{s}", .{help_text});
}

fn generateSampleConfig() void {
    const sample =
        \\{
        \\  "unit_id": 1,
        \\  "port": 502,
        \\
        \\  "coils": 100,
        \\  "discrete": 100,
        \\  "holding": 100,
        \\  "input": 100,
        \\
        \\  "holding_auto": {
        \\    "enabled": false,
        \\    "registers": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        \\    "interval": 1000,
        \\    "increment": 1,
        \\    "max": 65535
        \\  },
        \\
        \\  "input_auto": {
        \\    "enabled": false,
        \\    "registers_range": "0-9",
        \\    "interval": 1000,
        \\    "increment": 1,
        \\    "max": 65535
        \\  }
        \\}
        \\
    ;

    std.fs.File.stdout().writeAll(sample) catch {};
}

fn parseCliArgs(allocator: std.mem.Allocator) !CliConfig {
    var config = CliConfig{};
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // 跳过程序名

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            config.show_help = true;
            return config;
        } else if (std.mem.eql(u8, arg, "--generate-config")) {
            config.generate_config = true;
            return config;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--config")) {
            config.config_file = args.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--unit-id")) {
            const v = args.next() orelse return error.MissingArgument;
            config.unit_id = std.fmt.parseInt(u8, v, 10) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--port")) {
            const v = args.next() orelse return error.MissingArgument;
            config.port = std.fmt.parseInt(u16, v, 10) catch return error.InvalidArgument;
        }
        // 寄存器数量
        else if (std.mem.eql(u8, arg, "--coils")) {
            const v = args.next() orelse return error.MissingArgument;
            config.coil_count = std.fmt.parseInt(u16, v, 10) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--discrete")) {
            const v = args.next() orelse return error.MissingArgument;
            config.discrete_count = std.fmt.parseInt(u16, v, 10) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--holding")) {
            const v = args.next() orelse return error.MissingArgument;
            config.holding_count = std.fmt.parseInt(u16, v, 10) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--input")) {
            const v = args.next() orelse return error.MissingArgument;
            config.input_count = std.fmt.parseInt(u16, v, 10) catch return error.InvalidArgument;
        }
        // Holding 自动增加
        else if (std.mem.eql(u8, arg, "--holding-auto")) {
            config.holding_auto_increment = true;
        } else if (std.mem.eql(u8, arg, "--holding-regs")) {
            const v = args.next() orelse return error.MissingArgument;
            config.holding_registers = try parseRegisterList(allocator, v);
        } else if (std.mem.eql(u8, arg, "--holding-interval")) {
            const v = args.next() orelse return error.MissingArgument;
            config.holding_interval = std.fmt.parseInt(u64, v, 10) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--holding-inc")) {
            const v = args.next() orelse return error.MissingArgument;
            config.holding_increment = std.fmt.parseInt(u16, v, 10) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--holding-max")) {
            const v = args.next() orelse return error.MissingArgument;
            config.holding_max = std.fmt.parseInt(u16, v, 10) catch return error.InvalidArgument;
        }
        // Input 自动增加
        else if (std.mem.eql(u8, arg, "--input-auto")) {
            config.input_auto_increment = true;
        } else if (std.mem.eql(u8, arg, "--input-regs")) {
            const v = args.next() orelse return error.MissingArgument;
            config.input_registers = try parseRegisterList(allocator, v);
        } else if (std.mem.eql(u8, arg, "--input-interval")) {
            const v = args.next() orelse return error.MissingArgument;
            config.input_interval = std.fmt.parseInt(u64, v, 10) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--input-inc")) {
            const v = args.next() orelse return error.MissingArgument;
            config.input_increment = std.fmt.parseInt(u16, v, 10) catch return error.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--input-max")) {
            const v = args.next() orelse return error.MissingArgument;
            config.input_max = std.fmt.parseInt(u16, v, 10) catch return error.InvalidArgument;
        } else {
            std.debug.print("错误: 未知参数: {s}\n", .{arg});
            return error.UnknownArgument;
        }
    }

    return config;
}

/// 合并配置：命令行参数覆盖配置文件
fn mergeConfig(allocator: std.mem.Allocator, file_config: ?Config, cli_config: CliConfig) !Config {
    var config = file_config orelse Config{};

    // 命令行覆盖
    if (cli_config.unit_id) |v| config.unit_id = v;
    if (cli_config.port) |v| config.port = v;
    if (cli_config.coil_count) |v| config.coil_count = v;
    if (cli_config.discrete_count) |v| config.discrete_count = v;
    if (cli_config.holding_count) |v| config.holding_count = v;
    if (cli_config.input_count) |v| config.input_count = v;

    // Holding 自动增加
    if (cli_config.holding_auto_increment) |v| config.holding_auto_inc.enabled = v;
    if (cli_config.holding_registers.len > 0) {
        if (config.holding_auto_inc.registers.len > 0 and file_config != null) {
            allocator.free(config.holding_auto_inc.registers);
        }
        config.holding_auto_inc.registers = cli_config.holding_registers;
    }
    if (cli_config.holding_interval) |v| config.holding_auto_inc.interval_ms = v;
    if (cli_config.holding_increment) |v| config.holding_auto_inc.increment_value = v;
    if (cli_config.holding_max) |v| config.holding_auto_inc.max_value = v;

    // Input 自动增加
    if (cli_config.input_auto_increment) |v| config.input_auto_inc.enabled = v;
    if (cli_config.input_registers.len > 0) {
        if (config.input_auto_inc.registers.len > 0 and file_config != null) {
            allocator.free(config.input_auto_inc.registers);
        }
        config.input_auto_inc.registers = cli_config.input_registers;
    }
    if (cli_config.input_interval) |v| config.input_auto_inc.interval_ms = v;
    if (cli_config.input_increment) |v| config.input_auto_inc.increment_value = v;
    if (cli_config.input_max) |v| config.input_auto_inc.max_value = v;

    // 如果启用了自动增加但没有指定寄存器，默认使用所有寄存器
    if (config.holding_auto_inc.enabled and config.holding_auto_inc.registers.len == 0) {
        var regs = try allocator.alloc(u16, config.holding_count);
        for (0..config.holding_count) |i| regs[i] = @intCast(i);
        config.holding_auto_inc.registers = regs;
    }

    if (config.input_auto_inc.enabled and config.input_auto_inc.registers.len == 0) {
        var regs = try allocator.alloc(u16, config.input_count);
        for (0..config.input_count) |i| regs[i] = @intCast(i);
        config.input_auto_inc.registers = regs;
    }

    return config;
}

// ============================================================================
// 主程序
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 解析命令行参数
    const cli_config = parseCliArgs(allocator) catch |err| {
        std.debug.print("参数解析失败: {}\n", .{err});
        std.process.exit(1);
    };

    if (cli_config.show_help) {
        printHelp();
        return;
    }

    if (cli_config.generate_config) {
        generateSampleConfig();
        return;
    }

    // 解析配置文件
    var file_config: ?Config = null;

    if (cli_config.config_file) |config_path| {
        std.debug.print("加载配置文件: {s}\n", .{config_path});
        file_config = parseConfigFile(allocator, config_path) catch |err| {
            std.debug.print("配置文件解析失败: {}\n", .{err});
            std.process.exit(1);
        };
    }

    // 合并配置
    const config = mergeConfig(allocator, file_config, cli_config) catch |err| {
        std.debug.print("配置合并失败: {}\n", .{err});
        std.process.exit(1);
    };
    defer if (config.holding_auto_inc.registers.len > 0) allocator.free(config.holding_auto_inc.registers);
    defer if (config.input_auto_inc.registers.len > 0) allocator.free(config.input_auto_inc.registers);

    // 创建 Modbus 从站
    var slave = try ModbusSlave.init(
        allocator,
        config.unit_id,
        config.coil_count,
        config.discrete_count,
        config.holding_count,
        config.input_count,
    );
    defer slave.deinit();

    // 配置自动增加
    if (config.holding_auto_inc.enabled) {
        slave.configureAutoIncrement(.{
            .enabled = true,
            .registers = config.holding_auto_inc.registers,
            .interval_ms = config.holding_auto_inc.interval_ms,
            .increment_value = config.holding_auto_inc.increment_value,
            .max_value = config.holding_auto_inc.max_value,
        });
        try slave.startAutoIncrement(.holding_registers);
    }

    if (config.input_auto_inc.enabled) {
        slave.configureAutoIncrement(.{
            .enabled = true,
            .registers = config.input_auto_inc.registers,
            .interval_ms = config.input_auto_inc.interval_ms,
            .increment_value = config.input_auto_inc.increment_value,
            .max_value = config.input_auto_inc.max_value,
        });
        try slave.startAutoIncrement(.input_registers);
    }

    // 启动 TCP 服务器
    var server = TcpServer.init(allocator, &slave, config.port);
    defer server.deinit();

    try server.start();

    // 打印配置信息
    std.debug.print("\n配置信息:\n", .{});
    if (cli_config.config_file) |path| {
        std.debug.print("  配置文件: {s}\n", .{path});
    }
    std.debug.print("  从站地址: {d}\n", .{config.unit_id});
    std.debug.print("  监听端口: {d}\n", .{config.port});
    std.debug.print("\n寄存器配置:\n", .{});
    std.debug.print("  线圈 (Coils):           {d}\n", .{config.coil_count});
    std.debug.print("  离散输入 (Discrete):    {d}\n", .{config.discrete_count});
    std.debug.print("  保持寄存器 (Holding):   {d}\n", .{config.holding_count});
    std.debug.print("  输入寄存器 (Input):     {d}\n", .{config.input_count});

    if (config.holding_auto_inc.enabled or config.input_auto_inc.enabled) {
        std.debug.print("\n自动增加配置:\n", .{});
    }

    if (config.holding_auto_inc.enabled) {
        std.debug.print("  Holding 寄存器: 已启用\n", .{});
        std.debug.print("    寄存器数量: {d}, 间隔: {d}ms, 增量: {d}, 最大值: {d}\n", .{
            config.holding_auto_inc.registers.len,
            config.holding_auto_inc.interval_ms,
            config.holding_auto_inc.increment_value,
            config.holding_auto_inc.max_value,
        });
    }

    if (config.input_auto_inc.enabled) {
        std.debug.print("  Input 寄存器: 已启用\n", .{});
        std.debug.print("    寄存器数量: {d}, 间隔: {d}ms, 增量: {d}, 最大值: {d}\n", .{
            config.input_auto_inc.registers.len,
            config.input_auto_inc.interval_ms,
            config.input_auto_inc.increment_value,
            config.input_auto_inc.max_value,
        });
    }

    std.debug.print("\n按 Ctrl+C 停止服务器\n\n", .{});

    server.wait();
}

// ============================================================================
// 测试
// ============================================================================

test "parse register list" {
    const allocator = std.testing.allocator;

    const single = try parseRegisterList(allocator, "5");
    defer allocator.free(single);
    try std.testing.expectEqual(@as(usize, 1), single.len);

    const range = try parseRegisterList(allocator, "0-3");
    defer allocator.free(range);
    try std.testing.expectEqual(@as(usize, 4), range.len);

    const mixed = try parseRegisterList(allocator, "0,5-7,10");
    defer allocator.free(mixed);
    try std.testing.expectEqual(@as(usize, 5), mixed.len);
}

test "parse json config" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "unit_id": 5,
        \\  "port": 5020,
        \\  "holding": 200,
        \\  "input": 300,
        \\  "holding_auto": {
        \\    "enabled": true,
        \\    "registers": [0, 1, 2],
        \\    "interval": 500
        \\  }
        \\}
    ;

    const config = try parseJsonConfig(allocator, json);
    defer if (config.holding_auto_inc.registers.len > 0) allocator.free(config.holding_auto_inc.registers);
    defer if (config.input_auto_inc.registers.len > 0) allocator.free(config.input_auto_inc.registers);

    try std.testing.expectEqual(@as(u8, 5), config.unit_id);
    try std.testing.expectEqual(@as(u16, 5020), config.port);
    try std.testing.expectEqual(@as(u16, 200), config.holding_count);
    try std.testing.expectEqual(@as(u16, 300), config.input_count);
    try std.testing.expect(config.holding_auto_inc.enabled);
    try std.testing.expectEqual(@as(usize, 3), config.holding_auto_inc.registers.len);
    try std.testing.expectEqual(@as(u64, 500), config.holding_auto_inc.interval_ms);
}
