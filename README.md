# ZModSim - Modbus TCP Slave Simulator

一个使用 Zig 语言编写的高性能 Modbus TCP 从站模拟器。

## 功能特性

- **完整的 Modbus TCP 协议支持** - 支持常用的读写功能码
- **同时模拟多种寄存器** - 线圈、离散输入、保持寄存器、输入寄存器可同时配置
- **任意数量寄存器** - 每种类型可独立配置数量
- **独立自动增加** - Holding 和 Input 寄存器可分别配置自动增加
- **高性能** - 多线程处理，低延迟响应
- **JSON 配置文件** - 支持从 JSON 配置文件加载参数
- **命令行灵活** - 命令行参数可覆盖配置文件
- **跨平台** - 支持 Windows、macOS、Linux

## 下载

从 [Releases](../../releases) 页面下载对应平台的压缩包：

| 平台 | 架构 | 文件 |
|------|------|------|
| Linux | x86_64 | `zmodsim-x.x.x-linux-x86_64.tar.gz` |
| Linux | aarch64 | `zmodsim-x.x.x-linux-aarch64.tar.gz` |
| macOS | x86_64 (Intel) | `zmodsim-x.x.x-macos-x86_64.tar.gz` |
| macOS | aarch64 (Apple Silicon) | `zmodsim-x.x.x-macos-aarch64.tar.gz` |
| Windows | x86_64 | `zmodsim-x.x.x-windows-x86_64.zip` |
| Windows | aarch64 | `zmodsim-x.x.x-windows-aarch64.zip` |

## 编译

需要 Zig 0.15.2 或更高版本。

```bash
# 编译 (本地平台)
zig build

# 编译优化版本
zig build -Doptimize=ReleaseFast

# 运行测试
zig build test

# 交叉编译所有平台
zig build release

# 创建分发包 (编译 + 打包)
zig build dist

# 清理构建文件
zig build clean
```

### 构建命令说明

| 命令 | 说明 |
|------|------|
| `zig build` | 编译本地平台 Debug 版本 |
| `zig build -Doptimize=ReleaseFast` | 编译本地平台优化版本 |
| `zig build run` | 编译并运行 |
| `zig build test` | 运行测试 |
| `zig build release` | 交叉编译所有平台 (ReleaseFast) |
| `zig build dist` | 编译并打包所有平台分发包 |
| `zig build clean` | 清理构建文件和分发包 |

### 分发包

执行 `zig build dist` 后，分发包将生成在 `dist/` 目录：

```
dist/
├── zmodsim-1.0.0-linux-x86_64.tar.gz
├── zmodsim-1.0.0-linux-aarch64.tar.gz
├── zmodsim-1.0.0-macos-x86_64.tar.gz
├── zmodsim-1.0.0-macos-aarch64.tar.gz
├── zmodsim-1.0.0-windows-x86_64.zip
└── zmodsim-1.0.0-windows-aarch64.zip
```

每个压缩包包含：
- `zmodsim` (或 `zmodsim.exe`) - 可执行文件
- `README.md` - 项目说明
- `USAGE.md` - 使用手册

## 快速开始

```bash
# 启动默认配置 (各类寄存器各100个)
./zmodsim

# 查看帮助
./zmodsim --help

# 生成示例配置文件
./zmodsim --generate-config > config.json

# 使用配置文件启动
./zmodsim -f config.json
```

## 命令行参数

### 基本选项

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-f, --config <file>` | JSON 配置文件路径 | - |
| `-u, --unit-id <id>` | 从站地址 (1-247) | 1 |
| `-p, --port <port>` | TCP 监听端口 | 502 |
| `-h, --help` | 显示帮助信息 | - |
| `--generate-config` | 生成示例 JSON 配置文件 | - |

### 寄存器数量设置

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--coils <count>` | 线圈数量 (1位, 读写) | 100 |
| `--discrete <count>` | 离散输入数量 (1位, 只读) | 100 |
| `--holding <count>` | 保持寄存器数量 (16位, 读写) | 100 |
| `--input <count>` | 输入寄存器数量 (16位, 只读) | 100 |

### Holding 寄存器自动增加

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--holding-auto` | 启用自动增加 | 禁用 |
| `--holding-regs <list>` | 寄存器列表 (如: 0-9,20,30) | 全部 |
| `--holding-interval <ms>` | 增加间隔 (毫秒) | 1000 |
| `--holding-inc <value>` | 每次增加的值 | 1 |
| `--holding-max <value>` | 最大值 (归零阈值) | 65535 |

### Input 寄存器自动增加

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--input-auto` | 启用自动增加 | 禁用 |
| `--input-regs <list>` | 寄存器列表 (如: 0-9,20,30) | 全部 |
| `--input-interval <ms>` | 增加间隔 (毫秒) | 1000 |
| `--input-inc <value>` | 每次增加的值 | 1 |
| `--input-max <value>` | 最大值 (归零阈值) | 65535 |

### 寄存器列表格式

支持以下格式：
- 单个地址：`0,1,2,5`
- 范围：`0-9`
- 混合：`0,1,5-10,20,30-35`

## JSON 配置文件

配置文件使用 JSON 格式，结构清晰，易于阅读和编辑。

### 配置文件示例

```json
{
  "unit_id": 1,
  "port": 502,

  "coils": 100,
  "discrete": 100,
  "holding": 100,
  "input": 100,

  "holding_auto": {
    "enabled": true,
    "registers": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    "interval": 1000,
    "increment": 1,
    "max": 65535
  },

  "input_auto": {
    "enabled": true,
    "registers_range": "0-9",
    "interval": 500,
    "increment": 2,
    "max": 1000
  }
}
```

### 配置项说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `unit_id` | number | 从站地址 (1-247) |
| `port` | number | TCP 监听端口 |
| `coils` | number | 线圈数量 |
| `discrete` | number | 离散输入数量 |
| `holding` | number | 保持寄存器数量 |
| `input` | number | 输入寄存器数量 |
| `holding_auto` | object | Holding 寄存器自动增加配置 |
| `input_auto` | object | Input 寄存器自动增加配置 |

### 自动增加配置

| 字段 | 类型 | 说明 |
|------|------|------|
| `enabled` | boolean | 是否启用 |
| `registers` | number[] | 寄存器地址数组 |
| `registers_range` | string | 寄存器范围字符串 (如 "0-9,20,30") |
| `interval` | number | 增加间隔 (毫秒) |
| `increment` | number | 每次增加的值 |
| `max` | number | 最大值 (达到后归零) |

> **注意**: `registers` 和 `registers_range` 二选一，`registers` 优先级更高

### 配置优先级

命令行参数 > 配置文件 > 默认值

## 使用示例

### 同时模拟多种寄存器

```bash
# 同时模拟 1000 个 Holding、500 个 Input、2000 个线圈
./zmodsim --holding 1000 --input 500 --coils 2000

# 大规模模拟
./zmodsim --holding 10000 --input 10000 --coils 10000 --discrete 10000
```

### 独立配置自动增加

```bash
# 只有 Holding 寄存器自动增加
./zmodsim --holding-auto --holding-regs 0-9 --holding-interval 1000

# 只有 Input 寄存器自动增加
./zmodsim --input-auto --input-regs 0-4 --input-interval 500

# 两种都自动增加，使用不同配置
./zmodsim \
    --holding-auto --holding-regs 0-9 --holding-interval 1000 --holding-inc 1 \
    --input-auto --input-regs 0-4 --input-interval 500 --input-inc 5
```

### 使用配置文件

```bash
# 生成配置文件模板
./zmodsim --generate-config > config.json

# 编辑配置文件后启动
./zmodsim -f config.json

# 配置文件 + 命令行覆盖
./zmodsim -f config.json -p 5020 --holding 500
```

## 支持的 Modbus 功能码

| 功能码 | 名称 | 说明 |
|--------|------|------|
| 0x01 | Read Coils | 读线圈 |
| 0x02 | Read Discrete Inputs | 读离散输入 |
| 0x03 | Read Holding Registers | 读保持寄存器 |
| 0x04 | Read Input Registers | 读输入寄存器 |
| 0x05 | Write Single Coil | 写单个线圈 |
| 0x06 | Write Single Register | 写单个寄存器 |
| 0x0F | Write Multiple Coils | 写多个线圈 |
| 0x10 | Write Multiple Registers | 写多个寄存器 |

## 测试连接

### 使用 modbus-cli (Python)

```bash
pip install modbus-cli

# 读取保持寄存器 0-9
modbus read -s 1 localhost:502 h@0/10

# 读取输入寄存器 0-4
modbus read -s 1 localhost:502 i@0/5

# 读取线圈 0-15
modbus read -s 1 localhost:502 c@0/16
```

### 使用 mbpoll

```bash
# 读取 Holding 寄存器
mbpoll -a 1 -r 1 -c 10 localhost

# 读取 Input 寄存器
mbpoll -a 1 -r 1 -c 10 -t 3 localhost
```

### 使用 netcat 测试

```bash
# 读取 Holding 寄存器 (功能码 03)
echo -e '\x00\x01\x00\x00\x00\x06\x01\x03\x00\x00\x00\x0A' | nc localhost 502 | xxd

# 读取 Input 寄存器 (功能码 04)
echo -e '\x00\x01\x00\x00\x00\x06\x01\x04\x00\x00\x00\x0A' | nc localhost 502 | xxd

# 读取线圈 (功能码 01)
echo -e '\x00\x01\x00\x00\x00\x06\x01\x01\x00\x00\x00\x10' | nc localhost 502 | xxd
```

## 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                         TCP Server                               │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐                    │
│  │ Client 1  │  │ Client 2  │  │ Client N  │                    │
│  │  Handler  │  │  Handler  │  │  Handler  │                    │
│  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘                    │
│        └──────────────┼──────────────┘                          │
│                       │                                          │
│              ┌────────▼────────┐                                │
│              │  Modbus Slave   │                                │
│              │   (Protocol)    │                                │
│              └────────┬────────┘                                │
│                       │                                          │
│              ┌────────▼────────┐                                │
│              │ Register Storage │                                │
│              │  (Thread-safe)  │                                │
│              └────────┬────────┘                                │
│                       │                                          │
│     ┌─────────────────┼─────────────────┐                       │
│     │                 │                 │                       │
│     ▼                 ▼                 ▼                       │
│ ┌────────┐      ┌──────────┐      ┌──────────┐                 │
│ │ Coils  │      │ Holding  │      │  Input   │                 │
│ │Discrete│      │ Registers│      │Registers │                 │
│ └────────┘      └────┬─────┘      └────┬─────┘                 │
│                      │                 │                        │
│                      ▼                 ▼                        │
│               ┌────────────┐   ┌────────────┐                  │
│               │ Auto-Inc   │   │ Auto-Inc   │                  │
│               │  Thread    │   │  Thread    │                  │
│               └────────────┘   └────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
```

## 性能特性

- **多线程客户端处理** - 每个客户端连接独立线程
- **独立自动增加线程** - Holding 和 Input 可使用不同更新频率
- **TCP_NODELAY** - 禁用 Nagle 算法减少延迟
- **原子操作** - 线程安全的状态管理
- **互斥锁保护** - 寄存器访问的线程安全

## 应用场景

- **开发测试** - 在没有真实 Modbus 设备时进行软件开发和测试
- **协议学习** - 学习和理解 Modbus TCP 协议
- **性能测试** - 测试 Modbus 主站的性能和稳定性
- **演示展示** - 模拟设备进行产品演示
- **CI/CD** - 在自动化测试中模拟 Modbus 设备
- **传感器模拟** - 模拟动态变化的传感器数据

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
