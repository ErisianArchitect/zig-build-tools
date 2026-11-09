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

pub const ProjectAuthor = struct {
    name: []const u8,
    homepage: ?[]const u8 = null,
    email: ?[]const u8 = null,
};

pub const ProjectLicense = struct {
    const Self = @This();
    
    name: []const u8,
    file: ?[]const u8 = null,

    pub inline fn embedFile(comptime self: Self) [:0]const u8 {
        if (comptime self.file == null) @compileError("No file path was specified.");
        return struct {
            pub const file = @embedFile(self.file.?);
        }.file;
    }
};

pub const ProjectInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8 = "",
    homepage: ?[]const u8 = null,
    documentation: ?[]const u8 = null,
    repository: ?[]const u8 = null,
    license: []const ProjectLicense = &.{},
    authors: []const ProjectAuthor = &.{},
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
            .connections = connections.ptr,
            .capacity = capacity
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

