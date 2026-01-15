# ZModSim 使用手册

ZModSim 是一个高性能 Modbus TCP 从站模拟器，支持同时模拟多种寄存器类型。

## 目录

- [快速开始](#快速开始)
- [命令行参数](#命令行参数)
- [JSON 配置文件](#json-配置文件)
- [使用示例](#使用示例)
- [Modbus 功能码](#modbus-功能码)
- [测试连接](#测试连接)

---

## 快速开始

```bash
# 使用默认配置启动 (从站地址1, 端口502, 各类寄存器各100个)
./zmodsim

# 查看帮助
./zmodsim --help

# 生成示例配置文件
./zmodsim --generate-config > config.json

# 使用配置文件启动
./zmodsim -f config.json
```

---

## 命令行参数

### 基本选项

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-f, --config <file>` | JSON 配置文件路径 | - |
| `-u, --unit-id <id>` | 从站地址 (1-247) | 1 |
| `-p, --port <port>` | TCP 监听端口 | 502 |
| `-h, --help` | 显示帮助信息 | - |
| `--generate-config` | 生成示例配置文件到标准输出 | - |

### 寄存器数量

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
| `--holding-regs <list>` | 寄存器列表 | 全部 |
| `--holding-interval <ms>` | 增加间隔 (毫秒) | 1000 |
| `--holding-inc <value>` | 每次增加的值 | 1 |
| `--holding-max <value>` | 最大值 (归零阈值) | 65535 |

### Input 寄存器自动增加

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--input-auto` | 启用自动增加 | 禁用 |
| `--input-regs <list>` | 寄存器列表 | 全部 |
| `--input-interval <ms>` | 增加间隔 (毫秒) | 1000 |
| `--input-inc <value>` | 每次增加的值 | 1 |
| `--input-max <value>` | 最大值 (归零阈值) | 65535 |

### 寄存器列表格式

寄存器列表支持以下格式：

| 格式 | 示例 | 说明 |
|------|------|------|
| 单个地址 | `0,1,2,5` | 指定单个寄存器地址 |
| 范围 | `0-9` | 指定连续范围 |
| 混合 | `0,1,5-10,20,30-35` | 混合使用 |

---

## JSON 配置文件

### 生成配置文件

```bash
./zmodsim --generate-config > config.json
```

### 配置文件结构

```json
{
  "unit_id": 1,
  "port": 502,

  "coils": 100,
  "discrete": 100,
  "holding": 100,
  "input": 100,

  "holding_auto": {
    "enabled": false,
    "registers": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    "interval": 1000,
    "increment": 1,
    "max": 65535
  },

  "input_auto": {
    "enabled": false,
    "registers_range": "0-9",
    "interval": 1000,
    "increment": 1,
    "max": 65535
  }
}
```

### 配置项说明

#### 基本配置

| 字段 | 类型 | 说明 | 默认值 |
|------|------|------|--------|
| `unit_id` | number | 从站地址 (1-247) | 1 |
| `port` | number | TCP 监听端口 | 502 |
| `coils` | number | 线圈数量 | 100 |
| `discrete` | number | 离散输入数量 | 100 |
| `holding` | number | 保持寄存器数量 | 100 |
| `input` | number | 输入寄存器数量 | 100 |

#### 自动增加配置 (`holding_auto` / `input_auto`)

| 字段 | 类型 | 说明 | 默认值 |
|------|------|------|--------|
| `enabled` | boolean | 是否启用自动增加 | false |
| `registers` | number[] | 寄存器地址数组 | - |
| `registers_range` | string | 寄存器范围字符串 | - |
| `interval` | number | 增加间隔 (毫秒) | 1000 |
| `increment` | number | 每次增加的值 | 1 |
| `max` | number | 最大值 (达到后归零) | 65535 |

> **注意**: `registers` 和 `registers_range` 二选一使用，`registers` 优先级更高。如果都不指定，则对所有寄存器生效。

### 配置优先级

```
命令行参数 > 配置文件 > 默认值
```

命令行参数可以覆盖配置文件中的设置：

```bash
# 使用配置文件，但覆盖端口号
./zmodsim -f config.json -p 5020
```

---

## 使用示例

### 基本使用

```bash
# 默认配置启动
./zmodsim

# 指定从站地址和端口
./zmodsim -u 2 -p 5020

# 指定各类寄存器数量
./zmodsim --coils 500 --discrete 400 --holding 1000 --input 800
```

### 模拟大量寄存器

```bash
# 模拟 10000 个保持寄存器
./zmodsim --holding 10000

# 同时模拟大量各类寄存器
./zmodsim --coils 5000 --discrete 5000 --holding 10000 --input 10000
```

### 模拟动态数据 (自动增加)

```bash
# Holding 寄存器 0-9 每秒自动增加 1
./zmodsim --holding-auto --holding-regs 0-9

# Input 寄存器 0-4 每 500ms 自动增加 5，最大值 1000
./zmodsim --input-auto --input-regs 0-4 --input-interval 500 --input-inc 5 --input-max 1000

# 同时启用 Holding 和 Input 自动增加，使用不同参数
./zmodsim \
    --holding-auto --holding-regs 0-9 --holding-interval 1000 --holding-inc 1 \
    --input-auto --input-regs 0-4 --input-interval 500 --input-inc 5
```

### 使用配置文件

```bash
# 生成配置文件
./zmodsim --generate-config > config.json

# 编辑 config.json 后启动
./zmodsim -f config.json

# 配置文件 + 命令行覆盖
./zmodsim -f config.json -p 5020 -u 3
./zmodsim -f config.json --holding 500 --holding-auto
```

### 模拟传感器场景

```bash
# 模拟温度传感器 (Input 寄存器, 每秒更新)
./zmodsim --input 10 --input-auto --input-regs 0-9 --input-interval 1000 --input-max 100

# 模拟计数器 (Holding 寄存器, 快速递增)
./zmodsim --holding 100 --holding-auto --holding-regs 0 --holding-interval 100 --holding-inc 1

# 模拟多个传感器组
./zmodsim \
    --holding 100 --input 100 \
    --holding-auto --holding-regs 0-9 --holding-interval 2000 \
    --input-auto --input-regs 0-4 --input-interval 500
```

### 配置文件示例

#### 基本模拟器

```json
{
  "unit_id": 1,
  "port": 502,
  "coils": 100,
  "discrete": 100,
  "holding": 100,
  "input": 100
}
```

#### 传感器模拟

```json
{
  "unit_id": 1,
  "port": 502,
  "holding": 50,
  "input": 50,

  "input_auto": {
    "enabled": true,
    "registers": [0, 1, 2, 3, 4],
    "interval": 1000,
    "increment": 1,
    "max": 100
  }
}
```

#### 完整配置

```json
{
  "unit_id": 2,
  "port": 5020,

  "coils": 200,
  "discrete": 150,
  "holding": 300,
  "input": 250,

  "holding_auto": {
    "enabled": true,
    "registers": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    "interval": 500,
    "increment": 2,
    "max": 1000
  },

  "input_auto": {
    "enabled": true,
    "registers_range": "0-4,10,20-25",
    "interval": 300,
    "increment": 5,
    "max": 500
  }
}
```

---

## Modbus 功能码

ZModSim 支持以下 Modbus 功能码：

| 功能码 | 名称 | 操作 | 寄存器类型 |
|--------|------|------|------------|
| 0x01 | Read Coils | 读取 | 线圈 |
| 0x02 | Read Discrete Inputs | 读取 | 离散输入 |
| 0x03 | Read Holding Registers | 读取 | 保持寄存器 |
| 0x04 | Read Input Registers | 读取 | 输入寄存器 |
| 0x05 | Write Single Coil | 写入 | 线圈 |
| 0x06 | Write Single Register | 写入 | 保持寄存器 |
| 0x0F | Write Multiple Coils | 写入 | 线圈 |
| 0x10 | Write Multiple Registers | 写入 | 保持寄存器 |

### 寄存器类型说明

| 类型 | 数据宽度 | 读写权限 | 功能码 |
|------|----------|----------|--------|
| 线圈 (Coils) | 1 位 | 读写 | 0x01, 0x05, 0x0F |
| 离散输入 (Discrete Inputs) | 1 位 | 只读 | 0x02 |
| 保持寄存器 (Holding Registers) | 16 位 | 读写 | 0x03, 0x06, 0x10 |
| 输入寄存器 (Input Registers) | 16 位 | 只读 | 0x04 |

---

## 测试连接

### 使用 modbus-cli (Python)

```bash
# 安装
pip install modbus-cli

# 读取保持寄存器 0-9 (从站地址 1)
modbus read -s 1 localhost:502 h@0/10

# 读取输入寄存器 0-4
modbus read -s 1 localhost:502 i@0/5

# 读取线圈 0-15
modbus read -s 1 localhost:502 c@0/16

# 读取离散输入 0-7
modbus read -s 1 localhost:502 d@0/8

# 写入保持寄存器
modbus write -s 1 localhost:502 h@0=100
modbus write -s 1 localhost:502 h@0=100,200,300

# 写入线圈
modbus write -s 1 localhost:502 c@0=1
```

### 使用 mbpoll

```bash
# 读取保持寄存器 (默认)
mbpoll -a 1 -r 1 -c 10 localhost

# 读取输入寄存器
mbpoll -a 1 -r 1 -c 10 -t 3 localhost

# 读取线圈
mbpoll -a 1 -r 1 -c 16 -t 0 localhost

# 写入保持寄存器
mbpoll -a 1 -r 1 localhost 100 200 300
```

### 使用 netcat

```bash
# 读取保持寄存器 0-9 (功能码 0x03)
# MBAP: 事务ID=0001, 协议ID=0000, 长度=0006, 单元ID=01
# PDU: 功能码=03, 起始地址=0000, 数量=000A
echo -e '\x00\x01\x00\x00\x00\x06\x01\x03\x00\x00\x00\x0A' | nc localhost 502 | xxd

# 读取输入寄存器 0-9 (功能码 0x04)
echo -e '\x00\x01\x00\x00\x00\x06\x01\x04\x00\x00\x00\x0A' | nc localhost 502 | xxd

# 读取线圈 0-15 (功能码 0x01)
echo -e '\x00\x01\x00\x00\x00\x06\x01\x01\x00\x00\x00\x10' | nc localhost 502 | xxd

# 读取离散输入 0-15 (功能码 0x02)
echo -e '\x00\x01\x00\x00\x00\x06\x01\x02\x00\x00\x00\x10' | nc localhost 502 | xxd

# 写入单个保持寄存器 (功能码 0x06)
# 地址=0000, 值=0064 (100)
echo -e '\x00\x01\x00\x00\x00\x06\x01\x06\x00\x00\x00\x64' | nc localhost 502 | xxd

# 写入单个线圈 ON (功能码 0x05)
# 地址=0000, 值=FF00
echo -e '\x00\x01\x00\x00\x00\x06\x01\x05\x00\x00\xFF\x00' | nc localhost 502 | xxd
```

### 使用 Python pymodbus

```python
from pymodbus.client import ModbusTcpClient

# 连接
client = ModbusTcpClient('localhost', port=502)
client.connect()

# 读取保持寄存器
result = client.read_holding_registers(address=0, count=10, slave=1)
print(result.registers)

# 读取输入寄存器
result = client.read_input_registers(address=0, count=10, slave=1)
print(result.registers)

# 读取线圈
result = client.read_coils(address=0, count=16, slave=1)
print(result.bits)

# 写入保持寄存器
client.write_register(address=0, value=100, slave=1)
client.write_registers(address=0, values=[100, 200, 300], slave=1)

# 写入线圈
client.write_coil(address=0, value=True, slave=1)

client.close()
```

---

## 运行输出示例

启动模拟器后，会显示当前配置信息：

```
加载配置文件: config.json
Modbus TCP Slave listening on port 5020
Unit ID: 2

配置信息:
  配置文件: config.json
  从站地址: 2
  监听端口: 5020

寄存器配置:
  线圈 (Coils):           200
  离散输入 (Discrete):    150
  保持寄存器 (Holding):   300
  输入寄存器 (Input):     250

自动增加配置:
  Holding 寄存器: 已启用
    寄存器数量: 10, 间隔: 500ms, 增量: 2, 最大值: 1000
  Input 寄存器: 已启用
    寄存器数量: 5, 间隔: 300ms, 增量: 5, 最大值: 500

按 Ctrl+C 停止服务器
```

---

## 常见问题

### Q: 如何模拟多个从站？

A: 运行多个 ZModSim 实例，使用不同的端口和从站地址：

```bash
./zmodsim -u 1 -p 502 &
./zmodsim -u 2 -p 503 &
./zmodsim -u 3 -p 504 &
```

### Q: 端口 502 需要 root 权限？

A: 是的，小于 1024 的端口需要管理员权限。可以使用更高的端口号：

```bash
./zmodsim -p 5020
```

### Q: 如何让寄存器值持续变化？

A: 使用自动增加功能：

```bash
./zmodsim --holding-auto --holding-regs 0-9 --holding-interval 1000
```

### Q: 配置文件中如何指定不连续的寄存器？

A: 使用数组格式或范围字符串：

```json
{
  "holding_auto": {
    "enabled": true,
    "registers": [0, 1, 2, 10, 20, 30]
  }
}
```

或

```json
{
  "holding_auto": {
    "enabled": true,
    "registers_range": "0-2,10,20,30"
  }
}
```
