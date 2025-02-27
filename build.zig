const std = @import("std");
const ProcessAssetsStep = @import("ProcessAssetsStep.zig");
const GitRepoStep = @import("GitRepoStep.zig");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const wasm = b.addSharedLibrary("main", "src/main.zig", .unversioned);
    wasm.setBuildMode(mode);
    wasm.setTarget(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    wasm.install();
    b.step("wasm", "build/install the wasm file").dependOn(&wasm.install_step.?.step);

    {
        const process_assets = ProcessAssetsStep.create(b);
        process_assets.addStage("maps/stages/needleman/needleman.world");
        wasm.step.dependOn(&process_assets.step);
    }
    {
        // format generated files
        const fmt_step = std.build.FmtStep.create(b, &.{"src/stages/needleman.zig"});
        wasm.step.dependOn(&fmt_step.step);
    }

    {
        const apple_pie = GitRepoStep.create(b, .{
            .url = "https://github.com/Luukdegram/apple_pie",
            .branch = null,
            .sha = "5eaaabdced4f9b8d6cee947b465e7ea16ea61f42",
            .fetch_enabled = true,
        });
        const exe = b.addExecutable("webserver", "webserver.zig");
        exe.step.dependOn(&apple_pie.step);
        exe.addPackagePath("apple_pie", b.pathJoin(&.{apple_pie.getPath(&exe.step), "src", "apple_pie.zig"}));
        const run = exe.run();
        run.addArg(b.build_root);
        b.step("serve", "Serve the game files").dependOn(&run.step);
    }
}
