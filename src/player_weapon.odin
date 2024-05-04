// This code manages the functionality and rendering of the player weapon

package game

import "core:fmt"
import "core:time"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import rl "vendor:raylib"

SHOOT_DELAY     :: 0.25
SHOOT_SPEED     :: 1000
SHOOT_SPREAD    :: 0
WEAPON_WIDTH    :: 3
WEAPON_LENGTH   :: 20
WEAPON_KICK     :: 0

// The state of the player weapon
Weapon :: struct {
    delay       : f64,      // Duration between being able to shoot
    speed       : f32,      // Velocity of spawned projectiles
    kick        : f32,      // Force added to player
    spread      : f32,      // Random angle (radians) added to projectile direction
    count       : int,      // Number of projectiles to spawn when shooting
    penetration : int,      // (Unused) Number enemies the projectile passes through before becoming "solid"
    bounces     : int,      // Number of times shot projectiles can bounce/deflect before being detroyed
    last_shoot_time : f64,

    on_calc_delay : ActionStack(f64, Game),
    on_draw_weapon : ActionStack(bool, Game),
}

// Init functions are called when the game first starts.
// Here we can assign default weapon values.
init_weapon :: proc(using weapon : ^Weapon) {
    count   = 1
    bounces = 0
    delay   = SHOOT_DELAY
    speed   = SHOOT_SPEED
    kick    = WEAPON_KICK
    spread  = SHOOT_SPREAD
    last_shoot_time = {}

    init_action_stack(&on_calc_delay)
    init_action_stack(&on_draw_weapon)
}

unload_weapon :: proc(using weapon : ^Weapon) {
    unload_action_stack(&on_calc_delay)
    unload_action_stack(&on_draw_weapon)
}

// Tick functions are called every frame by the game
// Here we'll check player input and shoot if necessary.
tick_player_weapon :: proc(using game : ^Game) {
    if !player.alive do return

    time_since_shoot := game_time - weapon.last_shoot_time

    effective_delay := weapon.delay;
    execute_action_stack(weapon.on_calc_delay, &effective_delay, game)

    if (rl.IsMouseButtonDown(.LEFT) || rl.IsKeyDown(.SPACE)) && time_since_shoot > effective_delay {
        weapon.last_shoot_time = game_time

        // kick
        player.vel -= get_weapon_dir(player) * weapon.kick

        // sfx
        try_play_sound(&audio, audio.laser, debounce = 0.05)

        // vfx
        weapon_tip := get_weapon_tip(player)
        weapon_dir := get_weapon_dir(player)
        emit_muzzle_blast(&pixel_particles, weapon_tip, weapon_dir, rl.BLUE)

        // Spawn `count` number of projectiles.
        for i in 0..<weapon.count {
            shoot_weapon_projectile(&projectiles, weapon, weapon_tip, weapon_dir)
        }
    }
}

emit_muzzle_blast :: proc(ps : ^ParticleSystem, pos, dir : rl.Vector2, col : rl.Color) {
    spawn_particles_direction(ps, pos, +dir, 10, min_speed = 300, max_speed = 2000, min_lifetime = 0.05, max_lifetime = 0.1, color = col, angle = 0.1, drag = 10)
    dir := rl.Vector2Rotate(dir, math.PI / 2)
    spawn_particles_direction(ps, pos, -dir, 5, min_speed = 300, max_speed = 500, min_lifetime = 0.05, max_lifetime = 0.1, color = col, angle = 0.2, drag = 10)
    spawn_particles_direction(ps, pos, +dir, 5, min_speed = 300, max_speed = 500, min_lifetime = 0.05, max_lifetime = 0.1, color = col, angle = 0.2, drag = 10)
}

shoot_weapon_projectile :: proc(projectiles : ^Projectiles, weapon : Weapon, pos, dir : rl.Vector2, color := rl.SKYBLUE, spread_factor : f32 = 1, spread_bias : f32 = 0) {
    dir := rl.Vector2Rotate(dir, rand.float32_range(-(weapon.spread * spread_factor + spread_bias), weapon.spread * spread_factor + spread_bias))
    actual_speed := weapon.speed * rand.float32_range(0.95, 1)
    add_projectile(
        newProjectile = Projectile {
            pos = pos,
            dir = dir,
            spd = actual_speed,
            len = math.max(actual_speed * 0.01, 5),
            col = color,
            bounces = weapon.bounces
        },
        projectiles = projectiles,
    )
}

// Draw functions are called at the end of each frame by the game
draw_player_weapon :: proc(using game : ^Game) {
    if !player.alive do return

    draw_weapon := true
    execute_action_stack(weapon.on_draw_weapon, &draw_weapon, game)

    if draw_weapon {
        weapon_rect  := rl.Rectangle{
            player.pos.x, 
            player.pos.y, 
            WEAPON_WIDTH, 
            WEAPON_LENGTH * (1 + math.log10(weapon.speed / SHOOT_SPEED)), // gets longer as weapon speed increases
        }
    
        weapon_pivot := rl.Vector2{WEAPON_WIDTH / 2, 0}
        weapon_angle := get_weapon_deg(player)
    
        rl.DrawRectanglePro(weapon_rect, weapon_pivot, weapon_angle, rl.GRAY)
    }
}

// Utility function to get the weapon direction (player -> mouse)
get_weapon_dir :: #force_inline proc(using player : Player) -> rl.Vector2 {
    return linalg.normalize(rl.GetMousePosition() - pos)
}

// Utility function to get the weapon angle in radians
get_weapon_rad :: #force_inline proc(using player : Player) -> f32 {
    dir := get_weapon_dir(player)
    return linalg.atan2(dir.y, dir.x) - math.PI / 2
}

// Utility function to get the weapon angle in degrees
get_weapon_deg :: #force_inline proc(using player : Player) -> f32 {
    return linalg.to_degrees(get_weapon_rad(player))
}

// Utility function to get the tip of the weapon. Useful for spawning projectiles/particles
get_weapon_tip :: #force_inline proc(using player : Player) -> rl.Vector2 {
    local_tip := rl.Vector2{0, WEAPON_LENGTH}
    local_tip  = rl.Vector2Rotate(local_tip, get_weapon_rad(player))
    return local_tip + pos
}