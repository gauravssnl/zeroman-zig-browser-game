const std = @import("std");
const builtin = @import("builtin");

const web = @import("web.zig");
const keys = @import("keys.zig");

const Renderer = @import("Renderer.zig");
const Rect2 = Renderer.Rect2;
const Sprite = Renderer.Sprite;
const Box = @import("Box.zig");
const Tile = @import("Tile.zig");
const Room = @import("Room.zig");
const Stage = @import("Stage.zig");
const Player = @import("Player.zig");
const needleman = @import("stages/needleman.zig").needleman;

// Overwrite default log handler
pub const log = web.log;

const screen_width = 256;
const screen_height = 240;
const target_frame_time = 1.0 / 60.0;
const min_frame_time = 1.0 / 10.0;

var title_tex: Renderer.Texture = undefined;

var door_sprite: Renderer.Texture = undefined;
var spike_sprite: Renderer.Texture = undefined;

var tiles_tex: Renderer.Texture = undefined;
var prev_room_tex: Renderer.Texture = undefined;
var cur_room_tex: Renderer.Texture = undefined;

var effects_tex: Renderer.Texture = undefined;

var font_tex: Renderer.Texture = undefined;
var text_tex: Renderer.Texture = undefined;
const text_w = screen_width / 8;
const text_h = screen_height / 8;
var text_buffer: [text_w * text_h]u8 = undefined;

const GameState = enum {
    title,
    start,
    playing,
    gameover,

    pub fn jsonStringify(value: GameState, options: std.json.StringifyOptions, out_stream: anytype) !void {
        _ = options;
        try out_stream.writeByte('"');
        try out_stream.writeAll(std.meta.tagName(value));
        try out_stream.writeByte('"');
    }
};

const RoomTransition = enum(u8) {
    none,
    vertical,
    door_ltr,
    door_rtl,
};

const door_duration = 16;
var room_transition: RoomTransition = .none;
var mode_frame: i32 = 0;

const GameData = struct {
    state: GameState = .title,
    counter: u8 = 0, // number of frames to wait in a state
    title_any_key_pressed: bool = false,
    player: Player = .{},
    input: Player.Input = std.mem.zeroes(Player.Input),
    prev_input: Player.Input = std.mem.zeroes(Player.Input),

    cur_room_index: u8 = 0,
    prev_room_index: u8 = 0,
    door1_h: u8 = 4,
    door2_h: u8 = 4,

    scrollr: Box = Box{
        .x = 0,
        .y = 0,
        .w = screen_width,
        .h = screen_height,
    },

    fn reset(self: *GameData) void {
        self.state = .start;
        self.counter = 0;
        self.player.box.h = Player.height;
        self.player.vx = 0;
        self.player.vy = Player.vmax;
        self.player.state = .jumping;
        self.player.face_left = false;
        self.input = std.mem.zeroes(Player.Input);
        self.prev_input = std.mem.zeroes(Player.Input);
        self.cur_room_index = 0;
        self.prev_room_index = 0;
        self.scrollr.x = cur_stage.rooms[self.cur_room_index].bounds.x;
        self.scrollr.y = cur_stage.rooms[self.cur_room_index].bounds.y;
        self.player.box.x = self.scrollr.x + (screen_width - Player.width) / 2;
        self.player.box.y = self.scrollr.y - Player.height;
        uploadRoomTexture(&cur_room_tex, cur_stage.rooms[self.cur_room_index]);
    }

    fn saveSnapshot(self: GameData) void {
        var buf: [1000]u8 = undefined; // FIXME
        var stream = std.io.fixedBufferStream(&buf);
        std.json.stringify(self, .{}, stream.writer()) catch unreachable;
        web.LocalStorage.setString("snapshot", stream.getWritten());
        std.log.info("snapshot saved", .{});
    }

    fn loadSnapshot(self: *GameData) void {
        const value = web.LocalStorage.getString("snapshot");
        var ts = std.json.TokenStream.init(value);
        self.* = std.json.parse(GameData, &ts, .{
            .ignore_unknown_fields = true,
        }) catch return;
        uploadRoomTexture(&cur_room_tex, cur_stage.rooms[self.cur_room_index]); // FIXME
        std.log.info("snapshot loaded", .{});
    }

    fn tickTitle(self: *GameData) void {
        if (self.counter % 8 < 4) {
            setText("PRESS ANY KEY", text_w / 2 - 6, text_h / 2 + 3);
        }
        if (self.input.left or self.input.right or self.input.up or self.input.down or self.input.jump) {
            self.title_any_key_pressed = true;
        }
        if (self.title_any_key_pressed) {
            self.counter += 1;
        }
        if (self.counter == 80) {
            self.counter = 0;
            self.state = .start;
        }
    }

    fn tickStart(self: *GameData) void {
        if (self.counter % 40 < 20) {
            setText("READY", text_w / 2 - 2, text_h / 2);
        }
        self.counter += 1;
        if (self.counter == 120) {
            self.counter = 0;
            self.state = .playing;
        }
    }

    fn tickGameOver(self: *GameData) void {
        if (self.counter > 60) {
            setText("GAME OVER", text_w / 2 - 4, text_h / 2);

            if (self.input.jump and !self.prev_input.jump) {
                self.reset();
            }
        } else {
            self.counter += 1;
        }
    }

    fn doVerticalRoomTransition(self: *GameData) void {
        mode_frame += 1;
        const cur_room = cur_stage.rooms[self.cur_room_index];
        const prev_room = cur_stage.rooms[self.prev_room_index];
        if (cur_room.bounds.y >= prev_room.bounds.y + prev_room.bounds.h) {
            // scroll down
            self.scrollr.y = prev_room.bounds.y + @divTrunc(mode_frame * screen_height, 60);
            self.player.box.y = cur_room.bounds.y - self.player.box.h + @divTrunc(mode_frame * self.player.box.h, 60);
        }
        if (cur_room.bounds.y + cur_room.bounds.h <= prev_room.bounds.y) {
            // scroll up
            self.scrollr.y = prev_room.bounds.y - @divTrunc(mode_frame * screen_height, 60);
            self.player.box.y = prev_room.bounds.y - @divTrunc(mode_frame * self.player.box.h, 60);
        }
        if (mode_frame == 60) {
            //player.vy = 0;
            room_transition = .none;
        }
    }

    fn doLtrDoorTransition(self: *GameData) void {
        mode_frame += 1;
        if (mode_frame <= door_duration) {
            self.door1_h = 4 - @intCast(u8, @divTrunc(4 * mode_frame, door_duration));
        } else if (mode_frame <= door_duration + 64) {
            self.player.tick();
            const cur_room = cur_stage.rooms[self.cur_room_index];
            // const prev_room = cur_stage.rooms[self.prev_room_index];
            self.scrollr.x = cur_room.bounds.x - screen_width + @divTrunc((mode_frame - door_duration) * screen_width, 64);
            self.player.box.x = cur_room.bounds.x - 2 * self.player.box.w + @divTrunc(3 * self.player.box.w * (mode_frame - door_duration), 64);
        } else if (mode_frame <= door_duration + 64 + door_duration) {
            self.door1_h = @intCast(u8, @divTrunc(4 * (mode_frame - 64 - door_duration), door_duration));
        }
        if (mode_frame == door_duration + 64 + door_duration) {
            room_transition = .none;
        }
    }

    fn doRtlDoorTransition(self: *GameData) void {
        mode_frame += 1;
        if (mode_frame <= door_duration) {
            self.door2_h = 4 - @intCast(u8, @divTrunc(4 * mode_frame, door_duration));
        } else if (mode_frame <= door_duration + 64) {
            self.player.tick();
            // const cur_room = cur_stage.rooms[self.cur_room_index];
            const prev_room = cur_stage.rooms[self.prev_room_index];
            self.scrollr.x = prev_room.bounds.x - @divTrunc((mode_frame - door_duration) * screen_width, 64);
            self.player.box.x = prev_room.bounds.x + self.player.box.w - @divTrunc(3 * self.player.box.w * (mode_frame - door_duration), 64);
        } else if (mode_frame <= door_duration + 64 + door_duration) {
            self.door2_h = @intCast(u8, @divTrunc(4 * (mode_frame - 64 - door_duration), door_duration));
        }
        if (mode_frame == door_duration + 64 + door_duration) {
            room_transition = .none;
        }
    }

    fn killPlayer(self: *GameData) void {
        if (!self.player.no_clip) {
            self.state = .gameover;
            self.counter = 0;
            death_frame_counter = 0;
        }
    }

    fn tickPlaying(self: *GameData) void {
        if (room_transition != .none) {
            switch (room_transition) {
                .vertical => self.doVerticalRoomTransition(),
                .door_ltr => self.doLtrDoorTransition(),
                .door_rtl => self.doRtlDoorTransition(),
                .none => {},
            }
            return;
        }

        updatePlayer(&self.player);

        if (findNextRoom(cur_stage.rooms, self.cur_room_index, self.player.box)) |next_room_index| {
            setNextRoom(next_room_index);
            room_transition = .vertical;
            mode_frame = 0;
        }

        const cur_room = cur_stage.rooms[self.cur_room_index];
        if (!cur_room.bounds.overlap(self.player.box)) {
            if (self.player.box.y > cur_room.bounds.y + cur_room.bounds.h) {
                self.killPlayer();
                return;
            }
        }

        // check door 1
        if (cur_room.door1_y != Room.no_door) {
            var door_box = Box{
                .x = cur_room.bounds.x,
                .y = cur_room.bounds.y + @intCast(i32, cur_room.door1_y) * Tile.size,
                .w = Tile.size,
                .h = 4 * Tile.size,
            };
            if (self.player.box.overlap(door_box)) {
                door_box.x -= 1;
                if (findNextRoom(cur_stage.rooms, self.cur_room_index, door_box)) |next_room_index| {
                    setNextRoom(next_room_index);
                    room_transition = .door_rtl;
                    mode_frame = 0;
                }
            }
        }

        // check door 2
        if (cur_room.door2_y != Room.no_door) {
            var door_box = Box{
                .x = cur_room.bounds.x + cur_room.bounds.w - Tile.size,
                .y = cur_room.bounds.y + @intCast(i32, cur_room.door2_y) * Tile.size,
                .w = Tile.size,
                .h = 4 * Tile.size,
            };
            if (self.player.box.overlap(door_box)) {
                door_box.x += 1;
                if (findNextRoom(cur_stage.rooms, self.cur_room_index, door_box)) |next_room_index| {
                    setNextRoom(next_room_index);
                    room_transition = .door_ltr;
                    mode_frame = 0;
                }
            }
        }

        // check spikes
        for (cur_room.entities) |entity| {
            if (entity.class == .spike) {
                if (self.player.box.overlap(entity.box)) {
                    self.killPlayer();
                }
            }
        }
    }

    fn tick(self: *GameData) void {
        clearText();
        self.prev_input = self.input;
        self.input = Player.Input.combine(Player.Input.scanKeyboard(), Player.Input.scanGamepad());
        switch (self.state) {
            .title => self.tickTitle(),
            .start => self.tickStart(),
            .playing => self.tickPlaying(),
            .gameover => self.tickGameOver(),
        }
    }
};

var game_data = GameData{};
var cur_stage: Stage = needleman;

fn uploadRoomTexture(texture: *Renderer.Texture, room: Room) void {
    texture.loadFromData(room.data, room.width, room.height);
}

fn clearText() void {
    std.mem.set(u8, text_buffer[0..], ' ');
}

fn setText(text: []const u8, x: usize, y: usize) void {
    std.debug.assert(x < 32 and y < 30);
    std.mem.copy(u8, text_buffer[text_w * y + x ..], text);
}

export fn onInit() void {
    Renderer.init();
    Player.load();
    title_tex.loadFromUrl("img/title.png", 192, 56);
    door_sprite.loadFromUrl("img/door.png", 16, 16);
    spike_sprite.loadFromUrl("img/spike.png", 16, 24);
    tiles_tex.loadFromUrl("img/needleman.png", 16, 8);
    effects_tex.loadFromUrl("img/effects.png", 120, 24);
    font_tex.loadFromUrl("img/font.png", 16, 8);
    clearText();
    text_tex.loadFromData(text_buffer[0..], text_w, text_h);

    game_data.reset();
    if (builtin.mode != .Debug) {
        game_data.state = .title;
    }
    if (web.hasLoadSnapshot()) {
        game_data.loadSnapshot();
    }
}

export fn onResize(width: c_uint, height: c_uint, scale: f32) void {
    Renderer.resize(@intToFloat(f32, width), @intToFloat(f32, height), scale);
}

export fn onKeyDown(key: c_uint) void {
    if (game_data.state == .title) {
        game_data.title_any_key_pressed = true;
    }
    if (builtin.mode == .Debug) {
        switch (key) {
            keys.KEY_1 => game_data.saveSnapshot(),
            keys.KEY_2 => game_data.loadSnapshot(),
            keys.KEY_3 => game_data.player.no_clip = !game_data.player.no_clip,
            else => {},
        }
    }
}

fn updatePlayer(player: *Player) void {
    player.tick();

    const room = cur_stage.rooms[game_data.cur_room_index];
    const player_old_x = player.box.x;

    player.handleInput(room, cur_stage.attribs, game_data.input, game_data.prev_input);

    // physics
    const amount_x = player.vx >> 8;
    const amount_y = player.vy >> 8;
    if (player.no_clip) {
        player.box.x += amount_x;
        player.box.y += amount_y;
    } else {
        const clipped_x = room.clipX(cur_stage.attribs, player.box, amount_x);
        player.box.x += clipped_x;
        const clipped_y = room.clipY(cur_stage.attribs, player.box, amount_y);
        player.box.y += clipped_y;
        const blocked_y = clipped_y != amount_y;

        if (blocked_y and player.vy < 0) player.vy = 0; // bump head
    }

    // scrolling
    if (player.box.x != player_old_x) {
        const diff_x = player.box.x - player_old_x;
        const target_x = player.box.x + 8 - screen_width / 2;
        if (game_data.scrollr.x < target_x and diff_x > 0) game_data.scrollr.x += diff_x;
        if (game_data.scrollr.x > target_x and diff_x < 0) game_data.scrollr.x += diff_x;
    }
    if (game_data.scrollr.x < room.bounds.x) game_data.scrollr.x = room.bounds.x;
    if (game_data.scrollr.x > room.bounds.x + room.bounds.w - screen_width) game_data.scrollr.x = room.bounds.x + room.bounds.w - screen_width;
}

// Find a room which overlaps box
fn findNextRoom(rooms: []const Room, skip_room_index: u8, box: Box) ?u8 {
    var room_index: u8 = 0;
    while (room_index < rooms.len) : (room_index += 1) {
        if (room_index == skip_room_index) continue;
        if (rooms[room_index].bounds.overlap(box)) {
            return room_index;
        }
    }
    return null;
}

fn setNextRoom(next_room_index: u8) void {
    game_data.prev_room_index = game_data.cur_room_index;
    game_data.cur_room_index = next_room_index;
    std.mem.swap(Renderer.Texture, &cur_room_tex, &prev_room_tex);
    uploadRoomTexture(&cur_room_tex, cur_stage.rooms[game_data.cur_room_index]);
}

var death_frame_counter: u32 = 0;
fn drawDeathEffect(x: f32, y: f32) void {
    const frame = (death_frame_counter / 3) % 6;
    const src_rect = Rect2.init(@intToFloat(f32, frame) * 24, 0, 24, 24);

    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const angle: f32 = std.math.pi * @intToFloat(f32, i) / 4.0;
        const r: f32 = 2 * @intToFloat(f32, death_frame_counter);
        const dst_rect = Rect2.init(x + r * @sin(angle), y + r * @cos(angle), 24, 24);
        Sprite.draw(effects_tex, src_rect, dst_rect);
    }

    death_frame_counter += 1;
}

fn drawTitle() void {
    Sprite.draw(title_tex, Rect2.init(0, 0, 192, 56), Rect2.init(32, 64, 192, 56));
}

fn draw() void {
    Renderer.clear();

    if (game_data.state == .title) {
        drawTitle();
    } else {
        Renderer.scroll.x = @intToFloat(f32, game_data.scrollr.x);
        Renderer.scroll.y = @intToFloat(f32, game_data.scrollr.y);

        // prev room is visible during transition
        if (room_transition != .none) {
            drawRoom(cur_stage.rooms[game_data.prev_room_index], prev_room_tex, game_data.door2_h, game_data.door1_h);
        }

        drawRoom(cur_stage.rooms[game_data.cur_room_index], cur_room_tex, game_data.door1_h, game_data.door2_h);

        if (game_data.state != .start) {
            if (game_data.state != .gameover or (death_frame_counter < 40 and death_frame_counter % 8 < 4)) {
                game_data.player.draw();
            }
        }

        if (game_data.state == .gameover) {
            drawDeathEffect(@intToFloat(f32, game_data.player.box.x) - 4, @intToFloat(f32, game_data.player.box.y));
        }
    }

    // text layer
    text_tex.updateData(text_buffer[0..]);
    Renderer.scroll.x = 0;
    Renderer.scroll.y = 0;
    const text_rect = Rect2.init(0, 0, screen_width, screen_height);
    Renderer.Tilemap.draw(text_tex, font_tex, text_rect);
}

fn drawRoom(room: Room, room_tex: Renderer.Texture, door1_h: u8, door2_h: u8) void {
    Renderer.Tilemap.draw(room_tex, tiles_tex, room.bounds.toRect2());

    if (room.door1_y != Room.no_door) {
        var i: usize = 0;
        while (i < door1_h) : (i += 1) {
            const dst_rect = Rect2.init(
                @intToFloat(f32, room.bounds.x),
                @intToFloat(f32, room.bounds.y + @intCast(i32, room.door1_y + i) * Tile.size),
                Tile.size,
                Tile.size,
            );
            Renderer.Sprite.draw(door_sprite, Rect2.init(0, 0, Tile.size, Tile.size), dst_rect);
        }
    }
    if (room.door2_y != Room.no_door) {
        var i: usize = 0;
        while (i < door2_h) : (i += 1) {
            const dst_rect = Rect2.init(
                @intToFloat(f32, room.bounds.x + room.bounds.w - Tile.size),
                @intToFloat(f32, room.bounds.y + @intCast(i32, room.door2_y + i) * Tile.size),
                Tile.size,
                Tile.size,
            );
            Renderer.Sprite.draw(door_sprite, Rect2.init(0, 0, Tile.size, Tile.size), dst_rect);
        }
    }

    for (room.entities) |entity| {
        switch (entity.class) {
            .spike => Sprite.draw(spike_sprite, Rect2.init(0, 0, 16, 24), entity.box.toRect2()),
        }
    }
}

var prev_timestamp: f64 = 0;
var tick_time: f64 = 0.5 * target_frame_time;

export fn onAnimationFrame(timestamp_ms: f64) void {
    const timestamp = timestamp_ms / 1000.0;
    const delta_time = timestamp - prev_timestamp;
    prev_timestamp = timestamp;
    tick_time += @min(min_frame_time, delta_time);
    while (tick_time > 0) : (tick_time -= target_frame_time) {
        game_data.tick();
    }

    Renderer.beginDraw();
    draw();
    Renderer.endDraw();
}
