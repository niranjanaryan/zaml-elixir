const std = @import("std");
const yaml = @cImport({
    @cInclude("yaml.h");
});
const erl_nif = @cImport({
    @cInclude("erl_nif.h");
});

const yaml_alloc = std.heap.c_allocator;

const FrameKind = enum { map, list };

const Frame = struct {
    kind: FrameKind,
    map: erl_nif.ERL_NIF_TERM = 0,
    list_buf: std.ArrayList(erl_nif.ERL_NIF_TERM) = std.ArrayList(erl_nif.ERL_NIF_TERM).empty,
    pending_key: ?erl_nif.ERL_NIF_TERM = null,
};

export fn zaml_load_nif(env: *erl_nif.ErlNifEnv, argc: c_int, argv: [*]const erl_nif.ERL_NIF_TERM) callconv(.c) erl_nif.ERL_NIF_TERM {
    _ = argc;
    const input_term = argv[0];

    var bin: erl_nif.ErlNifBinary = undefined;
    if (erl_nif.enif_inspect_binary(env, input_term, &bin) == 0) {
        return erl_nif.enif_make_atom(env, "error");
    }
    const data: [*]const u8 = @ptrCast(bin.data);
    const input = data[0..bin.size];

    return parse_yaml(env, input) catch {
        return erl_nif.enif_make_atom(env, "parse_error");
    };
}

fn parse_yaml(env: *erl_nif.ErlNifEnv, input: []const u8) !erl_nif.ERL_NIF_TERM {
    var parser: yaml.yaml_parser_t = undefined;
    if (yaml.yaml_parser_initialize(&parser) == 0) return error.NoParser;
    defer yaml.yaml_parser_delete(&parser);

    yaml.yaml_parser_set_input_string(&parser, input.ptr, @intCast(input.len));

    var stack = std.ArrayList(Frame).empty;
    defer {
        for (stack.items) |*f| f.list_buf.deinit(yaml_alloc);
        stack.deinit(yaml_alloc);
    }

    var anchors = std.StringHashMap(erl_nif.ERL_NIF_TERM).init(yaml_alloc);
    defer anchors.deinit();

    var first_doc: ?erl_nif.ERL_NIF_TERM = null;
    var event: yaml.yaml_event_t = undefined;
    var stream_done = false;

    while (!stream_done) {
        if (yaml.yaml_parser_parse(&parser, &event) == 0) return error.ParseError;
        defer yaml.yaml_event_delete(&event);

        switch (event.type) {
            yaml.YAML_NO_EVENT => continue,

            yaml.YAML_STREAM_START_EVENT => {},
            yaml.YAML_STREAM_END_EVENT => stream_done = true,
            yaml.YAML_DOCUMENT_START_EVENT => {},
            yaml.YAML_DOCUMENT_END_EVENT => {},

            yaml.YAML_ALIAS_EVENT => {
                const a = std.mem.span(event.data.alias.anchor);
                const v = anchors.get(a) orelse return error.AliasUnknown;
                try deliver_value(env, &stack, &first_doc, v);
            },

            yaml.YAML_SCALAR_EVENT => {
                const value = std.mem.span(event.data.scalar.value);
                const tag = if (event.data.scalar.tag) |t| std.mem.span(t) else "";
                const term = try scalar_term(env, value, tag);

                if (event.data.scalar.anchor) |a| {
                    try anchors.put(std.mem.span(a), term);
                }
                try deliver_value(env, &stack, &first_doc, term);
            },

            yaml.YAML_SEQUENCE_START_EVENT => {
                try stack.append(yaml_alloc, .{ .kind = .list });
            },
            yaml.YAML_SEQUENCE_END_EVENT => {
                const top = stack.pop() orelse return error.UnexpectedEvent;
                const term = erl_nif.enif_make_list_from_array(env, top.list_buf.items.ptr, @intCast(top.list_buf.items.len));
                try deliver_value(env, &stack, &first_doc, term);
            },

            yaml.YAML_MAPPING_START_EVENT => {
                const m = erl_nif.enif_make_new_map(env);
                try stack.append(yaml_alloc, .{ .kind = .map, .map = m });
            },
            yaml.YAML_MAPPING_END_EVENT => {
                const top = stack.pop() orelse return error.UnexpectedEvent;
                try deliver_value(env, &stack, &first_doc, top.map);
            },

            else => return error.UnknownEvent,
        }
    }

    return first_doc orelse erl_nif.enif_make_atom(env, "nil");
}

fn deliver_value(env: *erl_nif.ErlNifEnv, stack: *std.ArrayList(Frame), first_doc: *?erl_nif.ERL_NIF_TERM, value: erl_nif.ERL_NIF_TERM) !void {
    if (stack.items.len == 0) {
        if (first_doc.* == null) first_doc.* = value;
        return;
    }
    const top = &stack.items[stack.items.len - 1];
    switch (top.kind) {
        .list => try top.list_buf.append(yaml_alloc, value),
        .map => {
            if (top.pending_key == null) {
                top.pending_key = value;
            } else {
                const k = top.pending_key.?;
                top.pending_key = null;
                if (erl_nif.enif_make_map_put(env, top.map, k, value, &top.map) == 0) return error.MapPutFailed;
            }
        },
    }
}

fn scalar_term(env: *erl_nif.ErlNifEnv, value: []const u8, tag: []const u8) !erl_nif.ERL_NIF_TERM {
    if (tag.len > 0) {
        if (std.mem.endsWith(u8, tag, ":str")) return make_string_term(env, value);
        if (std.mem.endsWith(u8, tag, ":int")) return make_int_term(env, value) catch return make_string_term(env, value);
        if (std.mem.endsWith(u8, tag, ":float")) return make_float_term(env, value) catch return make_string_term(env, value);
        if (std.mem.endsWith(u8, tag, ":bool")) return make_bool_term(env, value);
        if (std.mem.endsWith(u8, tag, ":null")) return erl_nif.enif_make_atom(env, "nil");
    }
    if (is_bool_true(value)) return erl_nif.enif_make_atom(env, "true");
    if (is_bool_false(value)) return erl_nif.enif_make_atom(env, "false");
    if (is_null(value)) return erl_nif.enif_make_atom(env, "nil");
    if (is_int_str(value)) return make_int_term(env, value) catch return make_string_term(env, value);
    if (is_float_str(value)) return make_float_term(env, value) catch return make_string_term(env, value);
    return make_string_term(env, value);
}

fn is_bool_true(s: []const u8) bool {
    return std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "True") or std.mem.eql(u8, s, "TRUE") or
        std.mem.eql(u8, s, "yes") or std.mem.eql(u8, s, "Yes") or std.mem.eql(u8, s, "YES") or
        std.mem.eql(u8, s, "on") or std.mem.eql(u8, s, "On") or std.mem.eql(u8, s, "ON");
}

fn is_bool_false(s: []const u8) bool {
    return std.mem.eql(u8, s, "false") or std.mem.eql(u8, s, "False") or std.mem.eql(u8, s, "FALSE") or
        std.mem.eql(u8, s, "no") or std.mem.eql(u8, s, "No") or std.mem.eql(u8, s, "NO") or
        std.mem.eql(u8, s, "off") or std.mem.eql(u8, s, "Off") or std.mem.eql(u8, s, "OFF");
}

fn is_null(s: []const u8) bool {
    return std.mem.eql(u8, s, "null") or std.mem.eql(u8, s, "Null") or std.mem.eql(u8, s, "NULL") or
        std.mem.eql(u8, s, "~") or s.len == 0;
}

fn is_int_str(s: []const u8) bool {
    if (s.len == 0) return false;
    var i: usize = 0;
    if (s[0] == '+' or s[0] == '-') {
        if (s.len == 1) return false;
        i = 1;
    }
    var has_digit = false;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == '_') continue;
        if (c < '0' or c > '9') return false;
        has_digit = true;
    }
    return has_digit;
}

fn is_float_str(s: []const u8) bool {
    if (s.len == 0) return false;
    var i: usize = 0;
    if (s[0] == '+' or s[0] == '-') {
        if (s.len == 1) return false;
        i = 1;
    }
    var has_digit = false;
    var has_dot = false;
    var has_e = false;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == '_') continue;
        if (c == '.') {
            if (has_dot or has_e) return false;
            has_dot = true;
        } else if (c == 'e' or c == 'E') {
            if (has_e or !has_digit) return false;
            has_e = true;
            if (i + 1 < s.len and (s[i + 1] == '+' or s[i + 1] == '-')) i += 1;
        } else if (c < '0' or c > '9') {
            return false;
        } else {
            has_digit = true;
        }
    }
    return (has_dot or has_e) and has_digit;
}

fn make_string_term(env: *erl_nif.ErlNifEnv, s: []const u8) erl_nif.ERL_NIF_TERM {
    var term: erl_nif.ERL_NIF_TERM = 0;
    const data = erl_nif.enif_make_new_binary(env, @intCast(s.len), &term);
    const dst: [*]u8 = @ptrCast(data);
    @memcpy(dst[0..s.len], s);
    return term;
}

fn make_int_term(env: *erl_nif.ErlNifEnv, s: []const u8) !erl_nif.ERL_NIF_TERM {
    var buf: [128]u8 = undefined;
    if (s.len > buf.len) return error.IntTooLong;
    var n: usize = 0;
    for (s) |c| if (c != '_') {
        buf[n] = c;
        n += 1;
    };
    const v = std.fmt.parseInt(i64, buf[0..n], 10) catch return error.IntParseFailed;
    return erl_nif.enif_make_int64(env, v);
}

fn make_float_term(env: *erl_nif.ErlNifEnv, s: []const u8) !erl_nif.ERL_NIF_TERM {
    var buf: [128]u8 = undefined;
    if (s.len > buf.len) return error.FloatTooLong;
    var n: usize = 0;
    for (s) |c| if (c != '_') {
        buf[n] = c;
        n += 1;
    };
    const f = std.fmt.parseFloat(f64, buf[0..n]) catch return error.FloatParseFailed;
    return erl_nif.enif_make_double(env, f);
}

fn make_bool_term(env: *erl_nif.ErlNifEnv, s: []const u8) erl_nif.ERL_NIF_TERM {
    if (is_bool_true(s)) return erl_nif.enif_make_atom(env, "true");
    if (is_bool_false(s)) return erl_nif.enif_make_atom(env, "false");
    return erl_nif.enif_make_atom(env, "true");
}

var nif_funcs = [_]erl_nif.ErlNifFunc{
    .{
        .name = @as([*]const u8, @ptrCast("load")),
        .arity = 1,
        .fptr = @ptrCast(&zaml_load_nif),
        .flags = 0,
    },
};

var nif_entry = erl_nif.ErlNifEntry{
    .major = erl_nif.ERL_NIF_MAJOR_VERSION,
    .minor = erl_nif.ERL_NIF_MINOR_VERSION,
    .name = @as([*]const u8, @ptrCast("Elixir.Zaml")),
    .num_of_funcs = nif_funcs.len,
    .funcs = @as([*]erl_nif.ErlNifFunc, &nif_funcs),
    .load = null,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = @as([*]const u8, @ptrCast(erl_nif.ERL_NIF_VM_VARIANT)),
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = @sizeOf(erl_nif.ErlNifResourceTypeInit),
    .min_erts = null,
};

export fn nif_init() callconv(.c) [*c]erl_nif.ErlNifEntry {
    return &nif_entry;
}
