// This code handles player movement, audio and rendering.

package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:time"
import "core:math/linalg"
import rl "vendor:raylib"

PLAYER_SIZE                 :: 12
PLAYER_TURN_SPEED           :: 50
PLAYER_TURN_DRAG            :: 5
PLAYER_ACCELERATION         :: 350
PLAYER_BRAKING_ACCELERATION :: 3        // Force multiplier when thrusting against current velocity (braking.) This basically adds drifting 🤘
PLAYER_THRUST_EMIT_DELAY    :: 0.02     // Note: would be nice to express this as a rate over time instead
PLAYER_THRUST_VOLUME_ATTACK :: 10
PLAYER_MAX_SPEED            :: 400

EmitThrustParticleAction :: proc(game : ^Game)

// I have no idea compelled me to use 3-character abbreviations, but I can't rename them easily with OLS :(
Player :: struct {
    max_hth     : int,          // Max health
    hth         : int,          // Current health
    rot         : f32,          // Rotation (radians)
    pos         : rl.Vector2,   // Position
    vel         : rl.Vector2,   // Velocity
    dash_vel    : rl.Vector2,   // Dash velocity. Added to regular velocity and decreases rapidly
    dash_ref    : rl.Vector2,   // Velocity used for smoothly damping the dash velocity towards zero. A velocity for the velocity!
    dash_dur    : f32,          // Dash duration. How quickly dash_vel decreases by
    dash_spd    : f32,          // Dash speed. The initial dash velocity magnitude
    acc         : f32,          // Acceleration
    trq         : f32,          // Turn speed
    avel        : f32,          // Angular velocity
    adrg        : f32,          // Angular drag
    siz         : f32,          // Size
    alive       : bool,         // Is the player currently alive?
    knockback   : f32,          // Force applied to player when hit by enemy

    on_tick_player_thruster_particles : ActionStack(bool, Game),

    thruster_volume         : f32,
    thruster_particle_timer : Timer,    // How fast thruster particles are spawned
    thruster_proj_timer     : Timer,    // The "thruster projectiles" modifier is responsible for ticking this timer. It uses it to determine the projectile fire rate
    dash_particle_timer     : Timer,    // How fast dash particles are spawned
    last_damage_time        : f64,      // The last time the player was damaged
}

init_player :: proc(using player : ^Player) {
    half_width   := f32(rl.rlGetFramebufferWidth()) / 2
    half_height  := f32(rl.rlGetFramebufferHeight()) / 2

    max_hth = 100
    hth = 100
    rot = -math.PI / 2
    pos = { half_width, half_height + 50 }
    vel = 0
    dash_vel = 0
    dash_ref = 0
    dash_dur = 0.15
    dash_spd = 250
    acc = PLAYER_ACCELERATION
    trq = PLAYER_TURN_SPEED
    avel = 0
    adrg = PLAYER_TURN_DRAG
    siz = PLAYER_SIZE
    alive = true
    knockback = 500

    thruster_volume = 0
    last_damage_time = -1000

    thruster_particle_timer = { rate = 200 }
    dash_particle_timer = { rate = 100 }

    init_action_stack(&on_tick_player_thruster_particles)
}

unload_player :: proc(using player : ^Player) {
    unload_action_stack(&on_tick_player_thruster_particles)
}

tick_player :: proc(using game : ^Game) {
    width   := f32(rl.rlGetFramebufferWidth())
    height  := f32(rl.rlGetFramebufferHeight())

    thruster_target_volume : f32 = 0

    // Movement
    if player.alive {
        turn_left   := rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A);
        turn_right  := rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D);
        thrust      := rl.IsKeyDown(.UP) || rl.IsKeyDown(.W);
        dash        := rl.IsKeyPressed(.LEFT_SHIFT)

        if turn_left {
            player.avel -= player.trq * game_delta_time
        }
        if turn_right {
            player.avel += player.trq * game_delta_time
        }
        if thrust {
            dir := get_player_dir(player)

            // To help the controls feel more responsive, we'll calculate how much the player is braking by comparing the direction they're moving to
            // the direction they're thrusting. We can use this to apply more acceleration when braking
            brake_factor := 1 - (linalg.dot(player.vel / (linalg.length(player.vel) + 0.001), dir) / 2 + 0.5) // 1 = braking, 0 = accelerating
            acceleration := player.acc * (1 + brake_factor * PLAYER_BRAKING_ACCELERATION) 

            player.vel += dir * acceleration * game_delta_time

            thruster_target_volume += 1

            should_emit := true // this will probably never be false
            execute_action_stack(player.on_tick_player_thruster_particles, &should_emit, game)
            if should_emit {
                // Spawn thruster particles
                emit_count  := tick_timer(&player.thruster_particle_timer, game_delta_time)

                spawn_particles_direction(
                    particle_system = &line_trail_particles, 
                    center          = get_player_base(player),
                    direction       = -dir, 
                    count           = emit_count, 
                    min_speed       = 100,
                    max_speed       = 400,
                    min_lifetime    = 0.1,
                    max_lifetime    = 0.3,
                    size            = { 1, 10 },
                    color           = rl.Color{ 102, 191, 255, 50 },
                    angle           = .3,
                    drag            = 5,
                )
            }
        }

        if dash {
            player.dash_vel = get_player_dir(player) * player.dash_spd
            try_play_sound(&audio, audio.dash)
        }

        dash_speed := linalg.length(player.dash_vel)

        if dash_speed > 1 {
            emit_count := tick_timer(&player.dash_particle_timer, game_delta_time)
            spawn_particles_direction(&pixel_particles, 
                center = get_player_base(player),
                direction = -get_player_dir(player),
                count = emit_count,
                min_speed = dash_speed * 0.1,
                max_speed = dash_speed * 0.4,
                min_lifetime = 0.1,
                max_lifetime = 1.2,
                color = rl.SKYBLUE, // Sky blue + some brighness
                angle = linalg.to_radians(f32(10)),
                drag = 2,
                size = { 1, 30 },
                emit_radius = { 0, 10 }
            )
        }
    }

    thruster_target_volume = math.saturate(thruster_target_volume) * 0.2
    player.thruster_volume = math.lerp(player.thruster_volume, thruster_target_volume, 1 - math.exp(-game_delta_time * PLAYER_THRUST_VOLUME_ATTACK))

    rl.SetMusicVolume(audio.thrust, player.thruster_volume)

    // Horizontal Edge collision
    if player.pos.x - player.siz < 0 {
        player.pos.x = player.siz
        player.vel.x *= -1;
    }
    if player.pos.x + player.siz > width {
        player.pos.x = width - player.siz
        player.vel.x *= -1;
    }
    // Vertical Edge collision
    if player.pos.y - player.siz < 0 {
        player.pos.y = player.siz
        player.vel.y *= -1;
    }
    if player.pos.y + player.siz > height {
        player.pos.y = height - player.siz
        player.vel.y *= -1;
    }

    // Angular drag
    player.avel *= 1 / (1 + player.adrg * game_delta_time)
    player.vel = limit_length(player.vel, PLAYER_MAX_SPEED)
    player.vel += player.dash_vel

    // Rotate and move player along velocity
    player.rot += player.avel * game_delta_time
    player.pos += (player.vel + player.dash_vel) * game_delta_time

    // Animate dash velocity towards 0 over dash duration
    player.dash_vel = smooth_damp(player.dash_vel, { 0, 0 }, &player.dash_ref, player.dash_dur, game_delta_time)
}

tick_killed_player :: proc(using game : ^Game) {
    // If the players health is 0, indicate they are no longer alive and spawn some death particles.
    if player.hth <= 0 && player.alive {
        player.alive = false
        player.hth = 0

        spawn_particles_triangle_segments(&line_particles, get_player_corners(player), rl.RAYWHITE, player.vel, 0.4, 2.0, 50, 150, 2, 2, 3)
        spawn_particles_burst(&line_trail_particles, player.pos, player.vel, 128, 200, 1200, 0.2, 1.5, rl.RAYWHITE, drag = 3)
        spawn_particles_burst(&line_particles, player.pos, player.vel, 64, 100, 1500, 0.3, 1.5, rl.SKYBLUE, drag = 2)
        try_play_sound(&audio, audio.die)
    }
}

draw_player :: proc(using game : ^Game) {
    if !player.alive do return
    radius  := player.siz / 2
    corners := get_player_corners(player)

    rl.DrawCircleV(player.pos, pickups.attraction_radius, { 255, 255, 255, 2 })

    color := rl.RAYWHITE

    time_since_damaged : f32 = f32(game_time - player.last_damage_time)
    if time_since_damaged < PLAYER_DAMAGE_DEBOUNCE {
        color = rl.RED if (math.mod(time_since_damaged, 0.15) > 0.15 / 2) else color
    }

    rl.DrawTriangle(corners[0], corners[2], corners[1], color)
}

draw_player_trail :: proc(using game : ^Game) {
    if !player.alive do return

    color := rl.BLUE
    speed      := linalg.length(player.vel)
    dash_speed := linalg.length(player.dash_vel)
    color.a = 255 if dash_speed > 0.75 else 10

    // dash trail
    corners := get_player_corners(player, 0.5)
    rl.DrawTriangle(corners[0], corners[2], corners[1], color)

    // speed trail
    if speed > 200 || dash_speed > 1 {
        corners = get_player_corners(player)
        alpha := u8(math.lerp(f32(140), 240, math.smoothstep(f32(0.1), 10, dash_speed)))
        rl.DrawRectangleV(corners[0], {2, 2}, {255, 255, 255, alpha})
        rl.DrawRectangleV(corners[1], {2, 2}, {255, 255, 255, alpha})
        rl.DrawRectangleV(corners[2], {2, 2}, {255, 255, 255, alpha})
        rl.DrawRectangleV(get_player_base(player), {2, 2}, {255, 255, 255, alpha})
    }
}

// The direction the player is facing
get_player_dir :: proc(using player : Player) -> rl.Vector2 {
    return { math.cos(rot), math.sin(rot) }
}

// Gets the base of the player. This is where the thruster particles emit from.
get_player_base :: proc(using player : Player) -> rl.Vector2 {
    corners := get_player_corners(player)
    return linalg.lerp(corners[0], corners[1], 0.5)
}

get_player_corners :: proc(using player : Player, scale : f32 = 1) -> [3]rl.Vector2 {
    // Start by defining the offsets of each vertex
    corners := [3]rl.Vector2 { {-0.75, -1}, {+0.75, -1}, {0, +1.5} } * scale
    // We'll add some squash and stretch when dashing
    undershoot :: proc(x: f32) -> f32 { return 2.70158 * x * x * x * x - 1.70158 * x * x; }
    stretch := 1 + undershoot(math.smoothstep(f32(0.1), dash_spd, linalg.length(dash_vel))) * 0.8
    // Iterate over each vertex and transform them based on the player's position, rotation and size
    for &corner in corners {
        corner *= rl.Vector2{ 1 / stretch, stretch }
        corner = rl.Vector2Rotate(corner, rot - math.PI / 2)
        corner *= siz
        corner += pos
    }
    return corners
}

// Returns the distance to the closest enemy in the neighboring cells, if any
near_enemy :: proc(player : Player, enemies : Enemies) -> (near : bool, dist : f32) {
    player_cell := get_cell_coord(enemies.grid, player.pos)

    @(static) CellOffsets := [?][2]int {
        {0, 0}, // Check center cell first
        {-1, +1}, {+0, +1}, {+1, +1},
        {-1, +0},           {+1, +0},
        {-1, -1}, {+0, -1}, {+1, -1},
    }

    closest_sqr_dist : f32 = math.F32_MAX

    for cell_offset, idx in CellOffsets {
        enemy_indices, exists := get_cell_data(enemies.grid, player_cell + cell_offset)
        if !exists do continue

        for enemy_idx in enemy_indices {
            enemy := enemies.instances[enemy_idx]
            sqr_dist := linalg.length2(enemy.pos - player.pos)
            closest_sqr_dist = min(sqr_dist, closest_sqr_dist)
        }

        // If we found an enemy in the center cell we can break because none of the neighboring cells
        // will have a closer enemy
        if idx == 0 && closest_sqr_dist < math.F32_MAX do break
    }

    return closest_sqr_dist < math.F32_MAX, math.sqrt(closest_sqr_dist)
}

// Ported from Unity
@(require_results)
smooth_damp :: proc(current, target : rl.Vector2, velocity : ^rl.Vector2, smooth_time, dt: f32, max_speed : f32 = math.F32_MAX) -> rl.Vector2 {
	smooth_time := max(0.0001, smooth_time)
    omega       := 2 / smooth_time
    x           := omega * dt
    exp         := 1 / (1 + x + 0.48 * x * x + 0.23 * x * x * x)
    change    := current - target
    original_to := target

    max_change  := max_speed * smooth_time

    max_change_sq   := max_change * max_change
    sq_dist         := linalg.length2(change)
    if sq_dist > max_change_sq {
        mag := math.sqrt(sq_dist)
        change = change / mag * max_change
    }


    target      := current - change
    temp        := (velocity^ + omega * change) * dt
    velocity^   = (velocity^ - omega * temp) * exp
    output      := target + (change + temp) * exp
    
    og_minus_current := original_to - current
    out_minus_og     := output - original_to

    if og_minus_current.x * out_minus_og.x + og_minus_current.y * out_minus_og.y > 0 {
        output = original_to
        velocity^ = (output - original_to) / dt
    }

    return output
}