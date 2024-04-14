package game

import "core:math"
import "core:time"
import "core:math/linalg"
import rl "vendor:raylib"

PLAYER_SIZE                 :: 20
PLAYER_SPEED                :: 1000
PLAYER_ACCELERATION         :: 1.0
PLAYER_THRUST_EMIT_DELAY    :: 0.01
PLAYER_THRUST_VOLUME_ATTACK :: 10

Player :: struct {
    max_hth : f32,
    hth     : f32,
    pos     : rl.Vector2,
    vel     : rl.Vector2,
    spd     : f32,
    acc     : f32,
    siz     : f32,
    alive   : bool,
    thruster_volume : f32,
    last_thruster_emit_tick : time.Tick,
}


init_player :: proc(using player : ^Player) {
    half_width   := f32(rl.rlGetFramebufferWidth()) / 2
    half_height  := f32(rl.rlGetFramebufferHeight()) / 2

    max_hth = 100
    hth = 100
    alive = true
    pos = { half_width, half_height }
    siz = PLAYER_SIZE
    spd = PLAYER_SPEED
    acc = PLAYER_ACCELERATION
    thruster_volume = 0
}

tick_player :: proc(using player : ^Player, audio : ^Audio, ps : ^ParticleSystem, dt : f32) {
    width   := f32(rl.rlGetFramebufferWidth())
    height  := f32(rl.rlGetFramebufferHeight())

    thruster_emit_time_elapsed := time.duration_seconds(time.tick_since(last_thruster_emit_tick))
    can_emit := thruster_emit_time_elapsed >= PLAYER_THRUST_EMIT_DELAY
        
    thruster_target_volume : f32 = 0

    // Movement
    if alive {
        move_left   := rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A);
        move_right  := rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D);
        move_up     := rl.IsKeyDown(.UP) || rl.IsKeyDown(.W);
        move_down   := rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S);

        if move_left {
            dir := rl.Vector2{-spd, 0}
            vel = linalg.lerp(vel, dir, 1 - math.exp(-dt * acc))
            thruster_target_volume += 1
            if can_emit do emit_thruster_particles(player, ps, -dir)
        }
        if move_right {
            dir := rl.Vector2{+spd, 0}
            vel = linalg.lerp(vel, dir, 1 - math.exp(-dt * acc))
            thruster_target_volume += 1
            if can_emit do emit_thruster_particles(player, ps, -dir)
        }
        if move_up {
            dir := rl.Vector2{0, -spd}
            vel = linalg.lerp(vel, dir, 1 - math.exp(-dt * acc))
            thruster_target_volume += 1
            if can_emit do emit_thruster_particles(player, ps, -dir)
        }
        if move_down {
            dir := rl.Vector2{0, +spd}
            vel = linalg.lerp(vel, dir, 1 - math.exp(-dt * acc))
            thruster_target_volume += 1
            if can_emit do emit_thruster_particles(player, ps, -dir)
        }
    }

    thruster_target_volume = math.saturate(thruster_target_volume) * 0.2
    thruster_volume = math.lerp(thruster_volume, thruster_target_volume, 1 - math.exp(-dt * PLAYER_THRUST_VOLUME_ATTACK))

    rl.SetMusicVolume(audio.thrust, thruster_volume)

    // Edge collision
    {
        // Horizontal
        if pos.x - siz < 0 {
            pos.x = siz
            vel.x *= -1;
        }
        if pos.x + siz > width {
            pos.x = width - siz
            vel.x *= -1;
        }
        // Vertical
        if pos.y - siz < 0 {
            pos.y = siz
            vel.y *= -1;
        }
        if pos.y + siz > height {
            pos.y = height - siz
            vel.y *= -1;
        }
    }

    pos += vel * dt
}

draw_player :: proc(using player : ^Player) {
    if !alive do return
    size := rl.Vector2{siz, siz}
    rl.DrawRectangleV(position = pos - size/2, size = size, color = rl.WHITE)
}

get_player_rect :: proc(using player : ^Player) -> rl.Rectangle {
    rect_pos := pos - siz/2
    return {rect_pos.x, rect_pos.y, siz, siz}
}

get_player_corners :: proc(using player : ^Player) -> [4]rl.Vector2 {
    half_size := siz / 2
    return [4]rl.Vector2 {
        pos + {-half_size, -half_size}, // top left
        pos + {+half_size, -half_size}, // top right
        pos + {+half_size, +half_size}, // bottom right
        pos + {-half_size, +half_size}, // bottom left
    }
}

@(private) emit_thruster_particles :: proc(using player : ^Player, ps : ^ParticleSystem, dir : rl.Vector2) {
    player.last_thruster_emit_tick = time.tick_now()
    norm_dir := linalg.normalize(dir)
    spawn_particles_direction(
        particle_system = ps, 
        center          = pos,
        direction       = norm_dir, 
        count           = 1, 
        min_speed       = 200,
        max_speed       = 1000,
        min_lifetime    = 0.1,
        max_lifetime    = 0.5,
        color           = rl.GRAY,
        angle           = .2,
        drag            = 5,
    )
}