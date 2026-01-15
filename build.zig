const std = @import("std");

const version = "1.0.0";

// 支持的目标平台
const Target = struct {
    query: std.Target.Query,
    name: []const u8,
    ext: []const u8,
    link_libc: bool,
};

const targets: []const Target = &.{
    .{ .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl }, .name = "linux-x86_64", .ext = "", .link_libc = false },
    .{ .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl }, .name = "linux-aarch64", .ext = "", .link_libc = false },
    .{ .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu }, .name = "windows-x86_64", .ext = ".exe", .link_libc = true },
    .{ .query = .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu }, .name = "windows-aarch64", .ext = ".exe", .link_libc = true },
    .{ .query = .{ .cpu_arch = .x86_64, .os_tag = .macos }, .name = "macos-x86_64", .ext = "", .link_libc = true },
    .{ .query = .{ .cpu_arch = .aarch64, .os_tag = .macos }, .name = "macos-aarch64", .ext = "", .link_libc = true },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 核心模块
    const mod = b.addModule("zmodsim", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // ========================================================================
    // 默认构建 (本地平台)
    // ========================================================================
    const exe = b.addExecutable(.{
        .name = "zmodsim",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zmodsim", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    // 运行命令
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // 测试命令
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // ========================================================================
    // 交叉编译所有平台 (zig build release)
    // ========================================================================
    const release_step = b.step("release", "Build release binaries for all platforms");

    for (targets) |t| {
        const release_target = b.resolveTargetQuery(t.query);

        const release_mod = b.addModule(b.fmt("zmodsim-{s}", .{t.name}), .{
            .root_source_file = b.path("src/root.zig"),
            .target = release_target,
            .link_libc = t.link_libc,
        });

        const release_exe = b.addExecutable(.{
            .name = "zmodsim",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = release_target,
                .optimize = .ReleaseFast,
                .link_libc = t.link_libc,
                .imports = &.{
                    .{ .name = "zmodsim", .module = release_mod },
                },
            }),
        });

        const install = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{ .override = .{ .custom = t.name } },
        });

        release_step.dependOn(&install.step);
    }

    // ========================================================================
    // 打包分发 (zig build dist)
    // ========================================================================
    const dist_step = b.step("dist", "Create distribution packages for all platforms");

    // 首先依赖 release 步骤
    dist_step.dependOn(release_step);

    // 添加打包步骤
    const pack_step = b.addSystemCommand(&.{"sh"});
    pack_step.addArgs(&.{ "-c", packScript() });
    pack_step.step.dependOn(release_step);
    dist_step.dependOn(&pack_step.step);

    // ========================================================================
    // 清理 (zig build clean)
    // ========================================================================
    const clean_step = b.step("clean", "Clean build artifacts and dist packages");
    const clean_cmd = b.addSystemCommand(&.{ "rm", "-rf", "zig-out", "zig-cache", ".zig-cache", "dist" });
    clean_step.dependOn(&clean_cmd.step);
}

fn packScript() []const u8 {
    return 
        \\#!/bin/sh
        \\set -e
        \\
        \\VERSION="1.0.0"
        \\DIST_DIR="dist"
        \\
        \\echo "Creating distribution packages..."
        \\mkdir -p "$DIST_DIR"
        \\
        \\# Linux x86_64
        \\if [ -d "zig-out/linux-x86_64" ]; then
        \\    echo "Packaging linux-x86_64..."
        \\    mkdir -p "$DIST_DIR/zmodsim-$VERSION-linux-x86_64"
        \\    cp zig-out/linux-x86_64/zmodsim "$DIST_DIR/zmodsim-$VERSION-linux-x86_64/"
        \\    cp USAGE.md "$DIST_DIR/zmodsim-$VERSION-linux-x86_64/" 2>/dev/null || true
        \\    cd "$DIST_DIR" && tar -czf "zmodsim-$VERSION-linux-x86_64.tar.gz" "zmodsim-$VERSION-linux-x86_64" && cd ..
        \\    rm -rf "$DIST_DIR/zmodsim-$VERSION-linux-x86_64"
        \\    echo "  Created: $DIST_DIR/zmodsim-$VERSION-linux-x86_64.tar.gz"
        \\fi
        \\
        \\# Linux aarch64
        \\if [ -d "zig-out/linux-aarch64" ]; then
        \\    echo "Packaging linux-aarch64..."
        \\    mkdir -p "$DIST_DIR/zmodsim-$VERSION-linux-aarch64"
        \\    cp zig-out/linux-aarch64/zmodsim "$DIST_DIR/zmodsim-$VERSION-linux-aarch64/"
        \\    cp USAGE.md "$DIST_DIR/zmodsim-$VERSION-linux-aarch64/" 2>/dev/null || true
        \\    cd "$DIST_DIR" && tar -czf "zmodsim-$VERSION-linux-aarch64.tar.gz" "zmodsim-$VERSION-linux-aarch64" && cd ..
        \\    rm -rf "$DIST_DIR/zmodsim-$VERSION-linux-aarch64"
        \\    echo "  Created: $DIST_DIR/zmodsim-$VERSION-linux-aarch64.tar.gz"
        \\fi
        \\
        \\# macOS x86_64
        \\if [ -d "zig-out/macos-x86_64" ]; then
        \\    echo "Packaging macos-x86_64..."
        \\    mkdir -p "$DIST_DIR/zmodsim-$VERSION-macos-x86_64"
        \\    cp zig-out/macos-x86_64/zmodsim "$DIST_DIR/zmodsim-$VERSION-macos-x86_64/"
        \\    cp USAGE.md "$DIST_DIR/zmodsim-$VERSION-macos-x86_64/" 2>/dev/null || true
        \\    cd "$DIST_DIR" && tar -czf "zmodsim-$VERSION-macos-x86_64.tar.gz" "zmodsim-$VERSION-macos-x86_64" && cd ..
        \\    rm -rf "$DIST_DIR/zmodsim-$VERSION-macos-x86_64"
        \\    echo "  Created: $DIST_DIR/zmodsim-$VERSION-macos-x86_64.tar.gz"
        \\fi
        \\
        \\# macOS aarch64 (Apple Silicon)
        \\if [ -d "zig-out/macos-aarch64" ]; then
        \\    echo "Packaging macos-aarch64..."
        \\    mkdir -p "$DIST_DIR/zmodsim-$VERSION-macos-aarch64"
        \\    cp zig-out/macos-aarch64/zmodsim "$DIST_DIR/zmodsim-$VERSION-macos-aarch64/"
        \\    cp USAGE.md "$DIST_DIR/zmodsim-$VERSION-macos-aarch64/" 2>/dev/null || true
        \\    cd "$DIST_DIR" && tar -czf "zmodsim-$VERSION-macos-aarch64.tar.gz" "zmodsim-$VERSION-macos-aarch64" && cd ..
        \\    rm -rf "$DIST_DIR/zmodsim-$VERSION-macos-aarch64"
        \\    echo "  Created: $DIST_DIR/zmodsim-$VERSION-macos-aarch64.tar.gz"
        \\fi
        \\
        \\# Windows x86_64
        \\if [ -d "zig-out/windows-x86_64" ]; then
        \\    echo "Packaging windows-x86_64..."
        \\    mkdir -p "$DIST_DIR/zmodsim-$VERSION-windows-x86_64"
        \\    cp zig-out/windows-x86_64/zmodsim.exe "$DIST_DIR/zmodsim-$VERSION-windows-x86_64/"
        \\    cp USAGE.md "$DIST_DIR/zmodsim-$VERSION-windows-x86_64/" 2>/dev/null || true
        \\    cd "$DIST_DIR" && zip -rq "zmodsim-$VERSION-windows-x86_64.zip" "zmodsim-$VERSION-windows-x86_64" && cd ..
        \\    rm -rf "$DIST_DIR/zmodsim-$VERSION-windows-x86_64"
        \\    echo "  Created: $DIST_DIR/zmodsim-$VERSION-windows-x86_64.zip"
        \\fi
        \\
        \\# Windows aarch64
        \\if [ -d "zig-out/windows-aarch64" ]; then
        \\    echo "Packaging windows-aarch64..."
        \\    mkdir -p "$DIST_DIR/zmodsim-$VERSION-windows-aarch64"
        \\    cp zig-out/windows-aarch64/zmodsim.exe "$DIST_DIR/zmodsim-$VERSION-windows-aarch64/"
        \\    cp USAGE.md "$DIST_DIR/zmodsim-$VERSION-windows-aarch64/" 2>/dev/null || true
        \\    cd "$DIST_DIR" && zip -rq "zmodsim-$VERSION-windows-aarch64.zip" "zmodsim-$VERSION-windows-aarch64" && cd ..
        \\    rm -rf "$DIST_DIR/zmodsim-$VERSION-windows-aarch64"
        \\    echo "  Created: $DIST_DIR/zmodsim-$VERSION-windows-aarch64.zip"
        \\fi
        \\
        \\echo ""
        \\echo "Distribution packages created in $DIST_DIR/"
        \\ls -lh "$DIST_DIR/"
    ;
}
