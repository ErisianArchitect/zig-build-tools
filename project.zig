// DO NOT MODIFY THIS FILE IF YOU ARE NOT IN THE `build_tools` REPOSITORY!
// version: 0.1.0

const std = @import("std");

const Allocator = std.mem.Allocator;

const Build = std.Build;

pub const Module = Build.Module;
pub const Import = Module.Import;

pub const ExecutableOptions = Build.ExecutableOptions;
pub const Step = Build.Step;
pub const Compile = Step.Compile;

pub fn imp(name: []const u8, module: *Module) Import {
    return .{.name = name, .module = module};
}

/// Connect modules together using `addImport`. This will connect every module
/// to every other module.
pub fn connectImports(imports: []const Import) void {
    for (imports) |a| {
        for (imports) |b| {
            a.module.addImport(b.name, b.module);
        }
    }
}

pub const ConnectionType = enum {
    OneWay,
    TwoWay,
};

pub const ProjectInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8 = "",
    homepage: ?[]const u8 = null,
    documentation: ?[]const u8 = null,
    repository: ?[]const u8 = null,
    licenses: []const []const u8 = &.{},
    authors: []const []const u8 = &.{},
};

/// Use a fixed_buffer_capacity that will fit the number of imports
/// you want to connect. A good recommended size is 16 for small projects,
/// 32 for medium projects, and 64 or more for much larger ones. But you
/// can use whatever number you want.
pub fn Imports(comptime fixed_buffer_capacity: usize) type {
    return struct {
        const Self = @This();

        buf: [fixed_buffer_capacity]Import,
        connection_types: [fixed_buffer_capacity]ConnectionType,
        len: usize,

        pub fn init() Self {
            return .{.buf = undefined, .connection_types = undefined, .len = 0,};
        }

        pub fn slice(self: *const Self) []const Import {
            return self.buf[0..self.len];
        }

        pub fn sliceMut(self: *Self) []Import {
            return self.buf[0..self.len];
        }

        pub fn connectAdv(self: *Self, comptime connection_type: ConnectionType, import: Import) void {
            if (self.len >= self.buf.len) @panic("Buffer overflow. Use a higher number for fixed_buffer_capacity, nimwit.");
            for (self.slice(), 0..) |other, i| {
                if (self.connection_types[i] == .OneWay) continue;
                switch (comptime connection_type) {
                    .OneWay => {
                        other.module.addImport(import.name, import.module);
                    },
                    .TwoWay => {
                        other.module.addImport(import.name, import.module);
                        import.module.addImport(other.name, other.module);
                        import.module.addImport(import.name, import.module);
                    }
                }
            }
            self.buf[self.len] = import;
            self.connection_types[self.len] = connection_type;
            self.len += 1;
        }

        pub fn connect(self: *Self, import: Import) void {
            self.connectAdv(.TwoWay, import);
        }

        pub fn connectOneWay(self: *Self, import: Import) void {
            self.connectAdv(.OneWay, import);
        }

        /// This should be done after all modules are connected but before dependencies are added.
        pub fn addOptions(self: *Self, name: []const u8, options: *Build.Step.Options) void {
            if (self.len == 0) @panic("No modules to add options to.");
            const opts = options.createModule();
            self.connectAdv(.OneWay, imp(name, opts));
        }

        /// This should be done after all modules are connected and all options are added.
        pub fn addDependency(self: *Self, name: []const u8, module: *Module) void {
            self.connectOneWay(imp(name, module));
        }
    };
}

/// Use this to manage dual imports for a main build and a checking build.
pub fn BuildCheckImports(comptime buffer_size: usize) type {
    return struct {
        const Self = @This();

        build: Imports(buffer_size),
        check: Imports(buffer_size),

        pub fn init() Self {
            return .{.build = .init(), .check = .init()};
        }

        pub fn connect(self: *Self, name: []const u8, build_module: *Module, check_module: *Module) void {
            self.build.connect(imp(name, build_module));
            self.check.connect(imp(name, check_module));
        }

        /// Can be paired with Project.dupedCreateModule.
        pub fn connectDuped(self: *Self, name: []const u8, modules: [2]*Module) void {
            self.connect(name, modules[0], modules[1]);
        }

        /// This should be done after all modules are connected but before dependencies are added.
        pub fn addOptions(self: *Self, name: []const u8, build_options: *Build.Step.Options, check_options: *Build.Step.Options) void {
            self.build.addOptions(name, build_options);
            self.check.addOptions(name, check_options);
        }

        /// This should be done after all modules are connected and all options are added.
        pub fn addDependency(self: *Self, name: []const u8, build_dep: *Module, check_dep: ?*Module) void {
            self.build.addDependency(name, build_dep);
            self.check.addDependency(name, check_dep orelse build_dep);
        }
    };
}

pub const ProjectImports = struct {
    const Self = @This();

    list: [*]Import,
    connection_types: [*]ConnectionType,
    len: usize,
    capacity: usize,

    pub fn init(allocator: Allocator, capacity: usize) Self {
        const list = allocator.alloc(Import, capacity) catch @panic("Out of memory.");
        const connections = allocator.alloc(ConnectionType, capacity) catch @panic("Out of memory.");
        return .{
            .list = list.ptr,
            .connection_types = connections.ptr,
            .capacity = capacity,
            .len = 0,
        };
    }

    pub fn slice(self: Self) []const Import {
        return self.list[0..self.len];
    }

    fn importsSlice(self: Self) []Import {
        return self.list[0..self.len];
    }

    fn connectionsSlice(self: Self) []ConnectionType {
        return self.connection_types[0..self.len];
    }

    pub fn isFull(self: Self) bool {
        // len shouldn't ever be greater than the capacity,
        // but we'll use `>=` anyway.
        return self.len >= self.capacity;
    }

    pub fn isEmpty(self: Self) bool {
        return self.len == 0;
    }

    pub fn connectAdv(self: *Self, comptime connection_type: ConnectionType, name: []const u8, module: *Module) void {
        if (self.isFull()) @panic("Ran out of room. Allocate a greater capacity, this is not dynamic.");
        for (self.importsSlice(), self.connectionsSlice()) |import, conn| {
            if (conn == .OneWay) continue;
            switch (comptime connection_type) {
                .OneWay => {
                    import.module.addImport(name, module);
                },
                .TwoWay => {
                    import.module.addImport(name, module);
                    module.addImport(import.name, import.module);
                    module.addImport(name, module);
                },
            }
        }
        const index = self.len;
        self.list[index] = imp(name, module);
        self.connection_types[index] = connection_type;
        self.len += 1;
    }

    pub fn connect(self: *Self, name: []const u8, module: *Module) void {
        self.connectAdv(.TwoWay, name, module);
    }

    pub fn connectOneWay(self: *Self, name: []const u8, module: *Module) void {
        self.connectAdv(.OneWay, name, module);
    }

    pub fn addOptions(self: *Self, name: []const u8, options_module: *Module) void {
        if (self.isEmpty()) @panic("No imports have been added.");
        const has_twoway: bool = for (self.connectionsSlice()) |conn| {
            if (conn == .TwoWay) break true;
        } else false;
        if (!has_twoway) @panic("No two-way connections present.");
        self.connectAdv(.OneWay, name, options_module);
    }

    pub fn addDependency(self: *Self, name: []const u8, module: *Module) void {
        self.connectOneWay(name, module);
    }
};

pub const Project = struct {
    const Self = @This();
    
    build: *Build,
    release_imports: ProjectImports,
    check_imports: ProjectImports,

    pub fn init(build: *Build, import_capacity: usize) Self {
        return .{
            .build = build,
            .release_imports = .init(build.allocator, import_capacity),
            .check_imports = .init(build.allocator, import_capacity),
        };
    }

    pub fn releaseImports(self: Self) []const Import {
        return self.release_imports.slice();
    }

    pub fn checkImports(self: Self) []const Import {
        return self.check_imports.slice();
    }

    pub fn dupedCreateModule(
        self: Self,
        comptime count: usize,
        options: Module.CreateOptions,
    ) [count]*Module {
        var modules: [count]*Module = undefined;
        inline for(0..count) |i| {
            modules[i] = self.build.createModule(options);
        }
        return modules;
    }

    pub fn connectRelease(self: *Self, name: []const u8, out: ?**Module, options: Module.CreateOptions) void {
        const mod = self.build.createModule(options);
        if (out) |ptr| ptr.* = mod;
        self.release_imports.connect(name, mod);
    }

    pub fn connectCheck(self: *Self, name: []const u8, out: ?**Module, options: Module.CreateOptions) void {
        const mod = self.build.createModule(options);
        if (out) |ptr| ptr.* = mod;
        self.check_imports.connect(name, mod);
    }

    pub fn connectDuped(self: *Self, name: []const u8, options: Module.CreateOptions) void {
        self.connectRelease(name, null, options);
        self.connectCheck(name, null, options);
    }

    pub fn addReleaseDep(self: *Self, name: []const u8, module: *Module) void {
        self.release_imports.addDependency(name, module);
    }

    pub fn addCheckDep(self: *Self, name: []const u8, module: *Module) void {
        self.check_imports.addDependency(name, module);
    }

    pub fn addCommonDep(self: *Self, name: []const u8, module: *Module) void {
        self.addReleaseDep(name, module);
        self.addCheckDep(name, module);
    }

    pub fn addReleaseOptions(self: *Self, name: []const u8, options_module: *Module) void {
        self.release_imports.addOptions(name, options_module);
    }

    pub fn addCheckOptions(self: *Self, name: []const u8, options_module: *Module) void {
        self.check_imports.addOptions(name, options_module);
    }

    pub fn addCommonOptions(self: *Self, name: []const u8, options_module: *Module) void {
        self.addReleaseOptions(name, options_module);
        self.addCheckOptions(name, options_module);
    }

    const ImportsTarget = enum {
        release,
        check,
        both,
    };

    fn addFlatOptionsTo(self: *Self, comptime target: ImportsTarget, name: []const u8, options: anytype) void {
        const opts = self.build.addOptions();
        const inf = @typeInfo(@TypeOf(options)).@"struct";
        if (inf.is_tuple) {
            inline for (inf.field_names, inf.field_types) |field, t| {
                const subinf = @typeInfo(t).@"struct";
                inline for (subinf.field_names, subinf.field_types) |sfield, st| {
                    opts.addOption(st, sfield, @field(@field(options, field), sfield));
                }
            }
        } else {
            inline for (inf.field_names, inf.field_types) |field, t| {
                opts.addOption(t, field, @field(options, field));
            }
        }
        const mod = opts.createModule();
        switch (target) {
            .release => self.release_imports.addOptions(name, mod),
            .check => self.check_imports.addOptions(name, mod),
            .both => {
                self.release_imports.addOptions(name, mod);
                self.check_imports.addOptions(name, mod);
            }
        }
    }

    /// Add flattened options to the release imports.
    ///
    /// The behavior when `options` is a tuple is to
    /// flatten each of the fields within the tuple.
    pub fn addFlatReleaseOptions(self: *Self, name: []const u8, options: anytype) void {
        self.addFlatOptionsTo(.release, name, options);
    }

    /// Add flattened options to the check imports.
    ///
    /// The behavior when `options` is a tuple is to
    /// flatten each of the fields within the tuple.
    pub fn addFlatCheckOptions(self: *Self, name: []const u8, options: anytype) void {
        self.addFlatOptionsTo(.check, name, options);
    }

    /// Add flattened options to both imports lists.
    ///
    /// The behavior when `options` is a tuple is to
    /// flatten each of the fields within the tuple.
    pub fn addFlatCommonOptions(self: *Self, name: []const u8, options: anytype) void {
        self.addFlatOptionsTo(.both, name, options);
    }

    /// Adds ProjectInfo as a module to both release and check imports list.
    pub fn addProjectInfo(self: *Self, name: []const u8, info: ProjectInfo) void {
        self.addFlatCommonOptions(name, info);
    }

    pub fn addInstallExecutable(self: Self, step_name: ?[]const u8, out: ?**Compile, options: ExecutableOptions) void {
        const exe = self.build.addExecutable(options);
        if (out) |ptr| ptr.* = exe;
        self.build.installArtifact(exe);
        if (step_name) |name| {
            const run_step = self.build.step(name, "Run main executable.");
            const run_cmd = self.build.addRunArtifact(exe);
            run_step.dependOn(&run_cmd.step);
            run_cmd.step.dependOn(self.build.getInstallStep());
            run_cmd.addPassthruArgs();
        }
    }
};

pub const SimpleModule = struct {
    name: []const u8,
    path: []const u8,
};

pub const SimpleDependencyModule = struct {
    name: []const u8,
    rename: ?[]const u8,
};

pub const SimpleDependency = struct {
    name: []const u8,
    modules: []const SimpleDependencyModule,
};

pub fn isString(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| switch (@typeInfo(p.child)) {
            .array => |a| a.child == u8,
            else => p.child == u8 and p.size == .slice,
        },
        else => return false,
    };
}

pub const SimpleValue = union(enum) {
    const Self = @This();
    
    Bool: bool,
    U8: u8,
    U16: u16,
    U32: u32,
    U64: u64,
    U128: u128,
    I8: i8,
    I16: i16,
    I32: i32,
    I64: i64,
    I128: i128,
    F16: f16,
    F32: f32,
    F64: f64,
    F128: f128,
    Usize: usize,
    Isize: isize,
    Bytes: []const u8,

    pub fn init(value: anytype) Self {
        if (comptime isString(@TypeOf(value))) {
            return .{.Bytes = value};
        }
        const inf = @typeInfo(Self).@"union";
        const field_names = inf.field_names;
        const field_types = inf.field_types;
        inline for (field_names, field_types) |field, t| {
            if (@TypeOf(value) == t) {
                return @unionInit(Self, field, value);
            }
        }
        @compileError("Not a valid value type.");
    }
};

pub const SimpleOption = struct {
    const Self = @This();

    name: []const u8,
    value: SimpleValue,

    pub inline fn init(name: []const u8, value: anytype) Self {
        return .{
            .name = name,
            .value = SimpleValue.init(value),
        };
    }
};

pub const SimpleProject = struct {
    const Self = @This();

    info: ProjectInfo,
    root: []const u8,
    main: ?[]const u8 = null,
    modules: []const SimpleModule = &.{},
    dependencies: []const SimpleDependency = &.{},
    target: ?Build.ResolvedTarget = null,
    optimize: ?std.builtin.Optimize = null,
    options: []const SimpleOption = &.{},

    fn importCount(self: Self) usize {
        // 1 for the ProjectInfo options module.
        var count = 1 + self.modules.len;
        for (self.dependencies) |dep| {
            count += dep.modules.len;
        }
    }

    pub fn build(self: Self, b: *Build) void {
        const target = self.target orelse b.standardTargetOptions(.{});
        const optimize = self.optimize orelse b.standardOptimizeOption(.{});

        var proj = Project.init(b, std.math.ceilPowerOfTwo(self.importCount()));

        const build_root_create_options: Module.CreateOptions = .{
            .root_source_file = b.path(self.root),
            .target = target,
            .optimize = optimize,
        };

        const check_root_create_options: Module.CreateOptions = .{
            .root_source_file = b.path(self.root),
            .target = target,
            .optimize = .debug,
        };

        var build_root_module: *Module = undefined;
        proj.connectRelease(self.info.name, &build_root_module, build_root_create_options);
        
        const check_suffix: []const u8 = "_check";
        const check_root_name: []u8 = b.allocator.alloc(u8, self.info.name.len + check_suffix.len);
        @memcpy(check_root_name[0..self.info.name.len], self.info.name);
        @memcpy(check_root_name[self.info.name.len..], check_suffix);

        var check_root_module: *Module = undefined;
        proj.connectCheck(check_root_name, &check_root_module, check_root_create_options);

        for (self.modules) |module| {
            const build_mod_create_opts: Module.CreateOptions = .{
                .root_source_file = b.path(module.path),
                .target = target,
                .optimize = optimize,
            };
            const check_mod_create_opts: Module.CreateOptions = .{
                .root_source_file = b.path(module.path),
                .target = target,
                .optimize = .debug,
            };
            proj.connectRelease(module.name, null, build_mod_create_opts);
            proj.connectCheck(module.name, null, check_mod_create_opts);
        }

        proj.addProjectInfo("PROJECT", self.info);

        if (self.options.len > 0) {
            const options = b.addOptions();
            for (self.options) |opt| {
                switch (opt.value) {
                    .Bool => |v| options.addOption(bool, opt.name, v),
                    .U8 => |v| options.addOption(u8, opt.name, v),
                    .U16 => |v| options.addOption(u16, opt.name, v),
                    .U32 => |v| options.addOption(u32, opt.name, v),
                    .U64 => |v| options.addOption(u64, opt.name, v),
                    .U128 => |v| options.addOption(u128, opt.name, v),
                    .I8 => |v| options.addOption(i8, opt.name, v),
                    .I16 => |v| options.addOption(i16, opt.name, v),
                    .I32 => |v| options.addOption(i32, opt.name, v),
                    .I64 => |v| options.addOption(i64, opt.name, v),
                    .I128 => |v| options.addOption(i128, opt.name, v),
                    .Usize => |v| options.addOption(usize, opt.name, v),
                    .Isize => |v| options.addOption(isize, opt.name, v),
                    .F16 => |v| options.addOption(f16, opt.name, v),
                    .F32 => |v| options.addOption(f32, opt.name, v),
                    .F64 => |v| options.addOption(f64, opt.name, v),
                    .F128 => |v| options.addOption(f128, opt.name, v),
                    .Bytes => |v| options.addOption([]const u8, opt.name, v),
                }
            }
            const opts_mod = options.createModule(options);

            proj.addCommonOptions("OPTIONS", opts_mod);
        }

        const build_compile_options = b.addOptions();
        const check_compile_options = b.addOptions();

        build_compile_options.addOption(bool, "checking", false);
        check_compile_options.addOption(bool, "checking", true);

        const build_compile_options_mod = build_compile_options.createModule();
        const check_compile_options_mod = check_compile_options.createModule();

        proj.addReleaseOptions("COMPILE", build_compile_options_mod);
        proj.addCheckOptions("COMPILE", check_compile_options_mod);

        for (self.dependencies) |dep| {
            const dependency = b.dependency(dep.name, .{});
            for (dep.modules) |mod| {
                const dep_mod = dependency.module(mod.name);
                proj.addCommonDep(mod.rename orelse mod.name, dep_mod);
            }
        }
        // const mod_tests = b.addTest(.{
        //     .root_module = coreo_mod,
        // });
        // const run_mod_tests = b.addRunArtifact(mod_tests);
        // const exe_tests = b.addTest(.{
        //     .root_module = exe.root_module,
        // });
        // const run_exe_tests = b.addRunArtifact(exe_tests);
        // const test_step = b.step("test", "Run tests");
        // test_step.dependOn(&run_mod_tests.step);
        // test_step.dependOn(&run_exe_tests.step);

        const check_mod_tests = b.addTest(.{
            .root_module = check_root_module,
        });
        const run_check_mod_tests = b.addRunArtifact(check_mod_tests);

        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&run_check_mod_tests.step);
        
        const check_step = b.step("check", "Special step for performing checking (where COMPILE.checking == true).");

        if (self.main) |main_file| {
            var main_exe: *Compile = undefined;
            const main_mod_opts: Module.CreateOptions = .{
                .root_source_file = b.path(main_file),
                .target = target,
                .optimize = optimize,
                .imports = proj.releaseImports(),
            };
            const main_mod = b.createModule(main_mod_opts);
            const exe_opts: ExecutableOptions = .{
                .name = "main",
                .root_module = main_mod,
            };
            proj.addInstallExecutable("run", &main_exe, exe_opts);
            const check_main_opts: Module.CreateOptions = .{
                .root_source_file = b.path(main_file),
                .target = target,
                .optimize = .debug,
                .imports = proj.checkImports(),
            };
            const check_main_mod = b.createModule(check_main_opts);
            const check_opts: ExecutableOptions = .{
                .name = "main_check",
                .root_module = check_main_mod,
            };
            const check_exe: *Compile = b.addExecutable(check_opts);

            check_step.dependOn(&check_exe.step);

            const main_run_tests = b.addTest(Build.TestOptions{
                .root_module = check_exe.root_module,
            });
            const main_tests_runner = b.addRunArtifact(main_run_tests);
            test_step.dependOn(&main_tests_runner.step);
        }
        const lib_opts: Build.LibraryOptions = .{
            .name = "checking",
            .root_module = check_root_module,
        };
        const check_lib: *Compile = b.addLibrary(lib_opts);
        check_step.dependOn(&check_lib.step);

        const check_run_tests = b.addTest(Build.TestOptions{
            .root_module = check_lib.root_module,
        });
        const check_tests_runner = b.addRunArtifact(check_run_tests);
        test_step.dependOn(&check_tests_runner.step);

        const build_lib_opts: Build.LibraryOptions = .{
            .name = self.info.name,
            .root_module = build_root_module,
        };
        const build_lib_artifact = b.addLibrary(build_lib_opts);
        b.installArtifact(build_lib_artifact);
    }
};
