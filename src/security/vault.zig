const std = @import("std");

pub const Provider = enum(u8) {
    Gemini = 0,
    DeepSeek = 1,
    OpenAiCompatible = 2,

    pub fn displayName(self: Provider) []const u8 {
        return switch (self) {
            .Gemini => "Google Gemini 2.5/Flash",
            .DeepSeek => "DeepSeek V3/R1",
            .OpenAiCompatible => "OpenAI / Local LLM (Ollama/vLLM)",
        };
    }
};

pub const VaultConfig = struct {
    selected_provider: Provider,
    gemini_key: [128]u8,
    gemini_key_len: usize,
    deepseek_key: [128]u8,
    deepseek_key_len: usize,
    openai_endpoint: [256]u8,
    openai_endpoint_len: usize,
    openai_key: [128]u8,
    openai_key_len: usize,

    pub fn default() VaultConfig {
        var v = VaultConfig{
            .selected_provider = .Gemini,
            .gemini_key = @splat(0),
            .gemini_key_len = 0,
            .deepseek_key = @splat(0),
            .deepseek_key_len = 0,
            .openai_endpoint = @splat(0),
            .openai_endpoint_len = 0,
            .openai_key = @splat(0),
            .openai_key_len = 0,
        };
        const def_ep = "https://api.openai.com/v1";
        @memcpy(v.openai_endpoint[0..def_ep.len], def_ep);
        v.openai_endpoint_len = def_ep.len;
        return v;
    }

    pub fn getGeminiKey(self: *const VaultConfig) []const u8 {
        return self.gemini_key[0..self.gemini_key_len];
    }

    pub fn getDeepSeekKey(self: *const VaultConfig) []const u8 {
        return self.deepseek_key[0..self.deepseek_key_len];
    }

    pub fn getOpenAiEndpoint(self: *const VaultConfig) []const u8 {
        return self.openai_endpoint[0..self.openai_endpoint_len];
    }

    pub fn getOpenAiKey(self: *const VaultConfig) []const u8 {
        return self.openai_key[0..self.openai_key_len];
    }

    pub fn setGeminiKey(self: *VaultConfig, key: []const u8) void {
        const len = @min(key.len, 128);
        @memcpy(self.gemini_key[0..len], key[0..len]);
        self.gemini_key_len = len;
    }

    pub fn setDeepSeekKey(self: *VaultConfig, key: []const u8) void {
        const len = @min(key.len, 128);
        @memcpy(self.deepseek_key[0..len], key[0..len]);
        self.deepseek_key_len = len;
    }

    pub fn setOpenAiKey(self: *VaultConfig, endpoint: []const u8, key: []const u8) void {
        const ep_len = @min(endpoint.len, 256);
        @memcpy(self.openai_endpoint[0..ep_len], endpoint[0..ep_len]);
        self.openai_endpoint_len = ep_len;

        const k_len = @min(key.len, 128);
        @memcpy(self.openai_key[0..k_len], key[0..k_len]);
        self.openai_key_len = k_len;
    }
};

const win = struct {
    pub const DATA_BLOB = extern struct {
        cbData: u32,
        pbData: [*]u8,
    };

    pub const CRYPTPROTECT_UI_FORBIDDEN: u32 = 0x1;

    pub extern "crypt32" fn CryptProtectData(
        pDataIn: *DATA_BLOB,
        szDataDescr: ?[*:0]const u16,
        pOptionalEntropy: ?*DATA_BLOB,
        pvReserved: ?*anyopaque,
        pPromptStruct: ?*anyopaque,
        dwFlags: u32,
        pDataOut: *DATA_BLOB,
    ) callconv(.winapi) i32;

    pub extern "crypt32" fn CryptUnprotectData(
        pDataIn: *DATA_BLOB,
        ppszDataDescr: ?*?[*:0]u16,
        pOptionalEntropy: ?*DATA_BLOB,
        pvReserved: ?*anyopaque,
        pPromptStruct: ?*anyopaque,
        dwFlags: u32,
        pDataOut: *DATA_BLOB,
    ) callconv(.winapi) i32;

    pub const GENERIC_READ: u32 = 0x80000000;
    pub const GENERIC_WRITE: u32 = 0x40000000;
    pub const CREATE_ALWAYS: u32 = 2;
    pub const OPEN_EXISTING: u32 = 3;
    pub const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
    pub const INVALID_HANDLE_VALUE: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));

    pub extern "kernel32" fn CreateFileA(
        lpFileName: [*:0]const u8,
        dwDesiredAccess: u32,
        dwShareMode: u32,
        lpSecurityAttributes: ?*anyopaque,
        dwCreationDisposition: u32,
        dwFlagsAndAttributes: u32,
        hTemplateFile: ?*anyopaque,
    ) callconv(.winapi) ?*anyopaque;

    pub extern "kernel32" fn WriteFile(
        hFile: ?*anyopaque,
        lpBuffer: [*]const u8,
        nNumberOfBytesToWrite: u32,
        lpNumberOfBytesWritten: ?*u32,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn ReadFile(
        hFile: ?*anyopaque,
        lpBuffer: [*]u8,
        nNumberOfBytesToRead: u32,
        lpNumberOfBytesRead: ?*u32,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) i32;

    pub extern "kernel32" fn CloseHandle(hObject: ?*anyopaque) callconv(.winapi) i32;
    pub extern "kernel32" fn DeleteFileA(lpFileName: [*:0]const u8) callconv(.winapi) i32;
    pub extern "kernel32" fn LocalFree(hMem: *anyopaque) callconv(.winapi) ?*anyopaque;
};

/// Gupta Kosha (गुप्त कोष) — Windows DPAPI Encrypted Vault for AI BYOK credentials
pub const EncryptedVault = struct {
    config: VaultConfig,

    pub fn init() EncryptedVault {
        return .{ .config = VaultConfig.default() };
    }

    /// Encrypts in-memory VaultConfig with Windows DPAPI and writes to disk
    pub fn save(self: *const EncryptedVault, file_path_z: [*:0]const u8) !void {
        var raw_bytes: [@sizeOf(VaultConfig)]u8 = undefined;
        @memcpy(&raw_bytes, std.mem.asBytes(&self.config));

        var in_blob = win.DATA_BLOB{
            .cbData = @sizeOf(VaultConfig),
            .pbData = &raw_bytes,
        };
        var out_blob: win.DATA_BLOB = undefined;

        const res = win.CryptProtectData(
            &in_blob,
            null,
            null,
            null,
            null,
            win.CRYPTPROTECT_UI_FORBIDDEN,
            &out_blob,
        );

        if (res == 0) return error.CryptProtectFailed;
        defer _ = win.LocalFree(out_blob.pbData);

        const hFile = win.CreateFileA(
            file_path_z,
            win.GENERIC_WRITE,
            0,
            null,
            win.CREATE_ALWAYS,
            win.FILE_ATTRIBUTE_NORMAL,
            null,
        );
        if (hFile == win.INVALID_HANDLE_VALUE or hFile == null) return error.FileCreateFailed;
        defer _ = win.CloseHandle(hFile);

        var written: u32 = 0;
        const w_res = win.WriteFile(hFile, out_blob.pbData, out_blob.cbData, &written, null);
        if (w_res == 0) return error.FileWriteFailed;
    }

    /// Reads encrypted vault from disk, decrypts using Windows DPAPI, and restores config
    pub fn load(self: *EncryptedVault, file_path_z: [*:0]const u8) !void {
        const hFile = win.CreateFileA(
            file_path_z,
            win.GENERIC_READ,
            0,
            null,
            win.OPEN_EXISTING,
            win.FILE_ATTRIBUTE_NORMAL,
            null,
        );
        if (hFile == win.INVALID_HANDLE_VALUE or hFile == null) {
            self.config = VaultConfig.default();
            return;
        }
        defer _ = win.CloseHandle(hFile);

        var encrypted_buf: [4096]u8 = undefined;
        var bytes_read: u32 = 0;
        const r_res = win.ReadFile(hFile, &encrypted_buf, @intCast(encrypted_buf.len), &bytes_read, null);
        if (r_res == 0 or bytes_read == 0) {
            self.config = VaultConfig.default();
            return;
        }

        var in_blob = win.DATA_BLOB{
            .cbData = bytes_read,
            .pbData = &encrypted_buf,
        };
        var out_blob: win.DATA_BLOB = undefined;

        const res = win.CryptUnprotectData(
            &in_blob,
            null,
            null,
            null,
            null,
            win.CRYPTPROTECT_UI_FORBIDDEN,
            &out_blob,
        );

        if (res == 0) return error.CryptUnprotectFailed;
        defer _ = win.LocalFree(out_blob.pbData);

        if (out_blob.cbData != @sizeOf(VaultConfig)) {
            return error.InvalidVaultSize;
        }

        @memcpy(std.mem.asBytes(&self.config), out_blob.pbData[0..@sizeOf(VaultConfig)]);
    }
};

test "EncryptedVault DPAPI round-trip encryption" {
    var vault = EncryptedVault.init();
    vault.config.setGeminiKey("AIzaSyD-TEST-GEMINI-KEY-99999");
    vault.config.setDeepSeekKey("sk-deepseek-test-token-777");
    vault.config.setOpenAiKey("http://localhost:11434/v1", "sk-ollama-local");

    const vault_path = "test_sharabha_vault.bin";
    try vault.save(vault_path);
    defer _ = win.DeleteFileA(vault_path);

    var loaded_vault = EncryptedVault.init();
    try loaded_vault.load(vault_path);

    try std.testing.expectEqualStrings("AIzaSyD-TEST-GEMINI-KEY-99999", loaded_vault.config.getGeminiKey());
    try std.testing.expectEqualStrings("sk-deepseek-test-token-777", loaded_vault.config.getDeepSeekKey());
    try std.testing.expectEqualStrings("http://localhost:11434/v1", loaded_vault.config.getOpenAiEndpoint());
    try std.testing.expectEqualStrings("sk-ollama-local", loaded_vault.config.getOpenAiKey());
}
