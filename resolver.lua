local vec3_t, entity_ext, ffi, weapon_ext = require("vector"), require("gamesense/entity"), require("ffi"), require("gamesense/csgo_weapons")

local classes = {}

local function class(classes, name)
    return function(tab)
        if not tab then return classes[name] end
        tab.__index, tab.__classname = tab, name
        if tab.call then tab.__call = tab.call end
        setmetatable(tab, tab)
        classes[name] = tab
        return tab
    end
end

local g_ctx = {
    local_player = nil, weapon = nil,
    structs = {
        animstate_t = ffi.typeof 'struct { int layer_order_preset; bool first_run_since_init; bool first_foot_plant_since_init; int last_update_tick; float eye_position_smooth_lerp; float strafe_change_weight_smooth_fall_off; float stand_walk_duration_state_has_been_valid; float stand_walk_duration_state_has_been_invalid; float stand_walk_how_long_to_wait_until_transition_can_blend_in; float stand_walk_how_long_to_wait_until_transition_can_blend_out; float stand_walk_blend_value; float stand_run_duration_state_has_been_valid; float stand_run_duration_state_has_been_invalid; float stand_run_how_long_to_wait_until_transition_can_blend_in; float stand_run_how_long_to_wait_until_transition_can_blend_out; float stand_run_blend_value; float crouch_walk_duration_state_has_been_valid; float crouch_walk_duration_state_has_been_invalid; float crouch_walk_how_long_to_wait_until_transition_can_blend_in; float crouch_walk_how_long_to_wait_until_transition_can_blend_out; float crouch_walk_blend_value; int cached_model_index; float step_height_left; float step_height_right; void* weapon_last_bone_setup; void* player; void* weapon; void* weapon_last; float last_update_time; int last_update_frame; float last_update_increment; float eye_yaw; float eye_pitch; float abs_yaw; float abs_yaw_last; float move_yaw; float move_yaw_ideal; float move_yaw_current_to_ideal; char pad1[4]; float primary_cycle; float move_weight; float move_weight_smoothed; float anim_duck_amount; float duck_additional; float recrouch_weight; float position_current[3]; float position_last[3]; float velocity[3]; float velocity_normalized[3]; float velocity_normalized_non_zero[3]; float velocity_length_xy; float velocity_length_z; float speed_as_portion_of_run_top_speed; float speed_as_portion_of_walk_top_speed; float speed_as_portion_of_crouch_top_speed; float duration_moving; float duration_still; bool on_ground; bool landing; float jump_to_fall; float duration_in_air; float left_ground_height; float land_anim_multiplier; float walk_run_transition; bool landed_on_ground_this_frame; bool left_the_ground_this_frame; float in_air_smooth_value; bool on_ladder; float ladder_weight; float ladder_speed; bool walk_to_run_transition_state; bool defuse_started; bool plant_anim_started; bool twitch_anim_started; bool adjust_started; char activity_modifiers_server[20]; float next_twitch_time; float time_of_last_known_injury; float last_velocity_test_time; float velocity_last[3]; float target_acceleration[3]; float acceleration[3]; float acceleration_weight; float aim_matrix_transition; float aim_matrix_transition_delay; bool flashed; float strafe_change_weight; float strafe_change_target_weight; float strafe_change_cycle; int strafe_sequence; bool strafe_changing; float duration_strafing; float foot_lerp; bool feet_crossed; bool player_is_accelerating; char pad2[24]; float duration_move_weight_is_too_high; float static_approach_speed; int previous_move_state; float stutter_step; float action_weight_bias_remainder; char pad3[112]; float camera_smooth_height; bool smooth_height_valid; float last_time_velocity_over_ten; float unk; float aim_yaw_min; float aim_yaw_max; float aim_pitch_min; float aim_pitch_max; int animstate_model_version; } **',
        animlayer_t = ffi.typeof 'struct { bool client_blend; float blend_in; void *studio_hdr; int dispatch_sequence; int second_dispatch_sequence; uint32_t order; uint32_t sequence; float prev_cycle; float weight; float weight_delta_rate; float playback_rate; float cycle; void *entity; char pad_0x0038[0x4]; } **'
    },
    native = {
        get_client_entity = vtable_bind("client.dll", "VClientEntityList003", 3, "void*(__thiscall*)(void*, int)"),
    }
}

local utils = class(classes, "utils") {
    clamp = function(self, value, min, max) return math.min(math.max(value, min), max) end,
    angle_modifier = function(self, a) return (360 / 65536) * bit.band(math.floor(a * (65536 / 360)), 65535) end,
    normalize_yaw = function(self, yaw)
        if not yaw then return 0 end
        while yaw > 180 do yaw = yaw - 360 end
        while yaw < -180 do yaw = yaw + 360 end
        return yaw
    end,
    angle_difference = function(self, dest_angle, src_angle)
        local delta = math.fmod(dest_angle - src_angle, 360)
        if dest_angle > src_angle then
            if delta >= 180 then delta = delta - 360 end
        else
            if delta <= -180 then delta = delta + 360 end
        end
        return delta
    end,
    angle_to_vector = function(self, pitch, yaw)
        if pitch ~= nil and yaw ~= nil then 
            local p, y = math.rad(pitch), math.rad(yaw)
            local sp, cp, sy, cy = math.sin(p), math.cos(p), math.sin(y), math.cos(y)
            return cp*cy, cp*sy, -sp
        end
        return 0,0,0
    end,
    deg2rad = function(self, deg) return deg * (math.pi / 180) end,
    rad2deg = function(self, rad) return rad * (180 / math.pi) end,
    lerp = function(self, a, b, t) return a + (b - a) * t end,
    get_smoothed_velocity = function(self, min_delta, a, b)
        local delta = vec3_t(a) - vec3_t(b)
        local delta_length = delta:length2d()

        if delta_length <= min_delta then
            local result = vec3_t()
            if -min_delta <= delta_length then
                return a
            else
                local iradius = 1.0 / (delta_length + FLT_EPSILON)
                return b - ((delta * iradius) * min_delta)
            end
        else
            local iradius = 1.0 / (delta_length + FLT_EPSILON)
            return b + ((delta * iradius) * min_delta)
        end
    end,
    powf = function(self, a, b)
        local a_float = tonumber(a)
        local b_float = tonumber(b)
        if a_float == nil or b_float == nil then return 0 end
        return a_float ^ b_float
    end,
    fabsf = function(self, x) return x < 0 and -x or x end,
    remainderf = function(self, x, y)
        local result = x % y
        local sign = function(x) if x > 0 then return 1 elseif x < 0 then return -1 else return 0 end end
        if math.abs(result) > math.abs(y) / 2 then
            result = result - y * sign(result)
        end
        return result
    end,
    approach = function(self, current, target, step)
        if current < target then
            current = math.min(current + step, target)
        elseif current > target then
            current = math.max(current - step, target)
        end
        return current
    end,
    calculate_angle = function(self, src, dest)
        local angle = vec3_t(0, 0, 0)
        local delta = vec3_t(src.x - dest.x, src.y - dest.y, src.z - dest.z)
        local hyp = math.sqrt(delta.x * delta.x + delta.y * delta.y)
        angle.x = math.atan(delta.z / hyp) * 57.295779513082
        angle.y = math.atan(delta.y / delta.x) * 57.295779513082
        angle.z = 0.0
        if delta.x >= 0.0 then angle.y = angle.y + 180.0 end
        return angle
    end
}

local player = class(classes, "player") {
    is_valid = function(self, ent) return (ent and entity.is_alive(ent) and entity.get_player_weapon(ent)) end,
    get_animstate = function(self, ent)
        if not ent then return false end
        local address = type(ent) == "cdata" and ent or g_ctx.native.get_client_entity(ent)
        if not address or address == ffi.NULL then return false end
        local address_vtable = ffi.cast("void***", address)
        return ffi.cast(g_ctx.structs.animstate_t, ffi.cast("char*", address_vtable) + 0x9960)[0]
    end,
    get_animlayer = function(self, ent)
        if not ent then return false end
        local address = type(ent) == "cdata" and ent or g_ctx.native.get_client_entity(ent)
        if not address or address == ffi.NULL then return false end
        local address_vtable = ffi.cast("void***", address)
        local ent_ptr = ffi.cast("void***", g_ctx.native.get_client_entity(ent))
        if ent_ptr == nullptr then return end
        local ent_adr = ffi.cast("char*", ent_ptr)
        return ffi.cast(g_ctx.structs.animlayer_t, ent_adr + 0x2990)[0]
    end,
    get_simulation_time = function(self, ent) 
        local ptr = g_ctx.native.get_client_entity(ent)
        if ptr then return entity.get_prop(ent, "m_flSimulationTime"), ffi.cast("float*", ffi.cast("uintptr_t", ptr) + 0x26C)[0] else return 0 end
    end,
    get_choked_packets = function(self, ent)
        local simulation_time, old_simulation_time = self:get_simulation_time(ent)
        return utils:clamp(toticks(simulation_time - old_simulation_time), 0, 64)
    end,
    get_min_rotation = function(self, ent) 
        local state = self:get_animstate(ent)
        local speed_walk = math.max(.0, math.min(state.speed_as_portion_of_walk_top_speed, 1.0))
        local speed_duck = math.max(.0, math.min(state.speed_as_portion_of_crouch_top_speed, 1.0))
        local modifier = ((state.walk_run_transition * -.30000001) - .19999999) * speed_walk + 1.0
        if state.anim_duck_amount > .0 then modifier = modifier + ((state.anim_duck_amount * speed_duck) * (.5 - modifier)) end
        return -58.0 * modifier
    end,
    get_max_rotation = function(self, ent) 
        local state = self:get_animstate(ent)
        local speed_walk = math.max(.0, math.min(state.speed_as_portion_of_walk_top_speed, 1.0))
        local speed_duck = math.max(.0, math.min(state.speed_as_portion_of_crouch_top_speed, 1.0))
        local modifier = ((state.walk_run_transition * -.30000001) - .19999999) * speed_walk + 1.0
        if state.anim_duck_amount > .0 then modifier = modifier + ((state.anim_duck_amount * speed_duck) * (.5 - modifier)) end
        return 58.0 * modifier
    end,
    rebuild_server_yaw = function(self, ent, side)
        local state = self:get_animstate(ent)
        local networked_abs_angles = .0
    
        local velocity = vec3_t(entity.get_prop(ent, "m_vecVelocity"))
        local speed = velocity:length2dsqr()
        if speed > utils:powf(1.2 * 260.0, 2.0) then velocity = velocity:normalized() * (1.2 * 260.0) end
    
        local min_body_yaw, max_body_yaw = self:get_min_rotation(ent), self:get_max_rotation(ent)
    
        local eye_yaw = state.eye_yaw
        local eye_diff = utils:remainderf(eye_yaw - networked_abs_angles, 360.0)
        if eye_diff <= max_body_yaw then
            if min_body_yaw > eye_diff then
                networked_abs_angles = utils:fabsf(min_body_yaw) + eye_yaw
            end
        else
            networked_abs_angles = eye_yaw - utils:fabsf(max_body_yaw)
        end
    
        networked_abs_angles = utils:remainderf(networked_abs_angles, 360.0)
    
        if speed > .1 or utils:fabsf(velocity.z) > 100.0 then
            networked_abs_angles = utils:approach(eye_yaw, networked_abs_angles, ((state.left_ground_height * 20.0) + 30.0) * state.last_update_time)
        else 
            networked_abs_angles = utils:approach(entity.get_prop(ent, "m_flLowerBodyYawTarget"), networked_abs_angles, state.last_update_time * 100.0)
        end
    
        return ({[-1] = eye_yaw + min_body_yaw, [0] = networked_abs_angles, [1] = eye_yaw + max_body_yaw, [-2] = eye_yaw})[side]
    end
}

local c_change_animstate = class(classes, "c_change_animstate") {
    detect_desync_side = function(self, ent, state)
        local side = -2
        local layers = player:get_animlayer(ent)
        local velocity = vec3_t(entity.get_prop(ent, "m_vecVelocity")):length2d()
        if layers[6].weight == 0 or layers[6].weight == 1 then
            side = -2
        elseif velocity <= 5 and layers[6].weight > .001 then
            local delta = utils:normalize_yaw(state.abs_yaw - state.eye_yaw)
            if utils:fabsf(delta) > player:get_max_rotation(ent) then
                side = delta > 0 and -1 or 1
            end
        elseif velocity > 5 then
            side = 0
        end
        return side
    end,
    main = function(self, ent)
        local state = player:get_animstate(ent)
        if not state then return end

        local wpn = entity.get_player_weapon(ent)
        if not wpn then return end

        local data = {
            choke = player:get_choked_packets(ent),
            shot_time = entity.get_prop(wpn, "m_fLastShotTime"),
            simulation_time = entity.get_prop(ent, "m_flSimulationTime"),
            fired_shot = false, has_fake = false
        }
        
        data.fired_shot = data.shot_time + 1 > data.simulation_time

        for i = 0, data.choke do 
            data.has_fake = i > 1
            if data.has_fake then
                if not data.fired_shot then
                    state.abs_yaw = player:rebuild_server_yaw(ent, self:detect_desync_side(ent, state))
                else
                    local head_position, body_position = vec3_t(entity.hitbox_position(ent, 0)), vec3_t(entity.hitbox_position(ent, 8))
                    if (head_position.x ~= 0 and head_position.y ~= 0) and (body_position.x ~= 0 and body_position.y ~= 0) then
                        local rotation_delta = utils:calculate_angle(body_position, head_position)
                        local fire_yaw = utils:normalize_yaw(rotation_delta.y)
                        local left_fire_yaw, right_fire_yaw = utils:fabsf(utils:normalize_yaw(fire_yaw - (state.eye_yaw + player:get_max_rotation(ent)))), utils:fabsf(utils:normalize_yaw(fire_yaw - (state.eye_yaw + player:get_min_rotation(ent))))
                        state.abs_yaw = state.eye_yaw + (left_fire_yaw > right_fire_yaw and player:get_min_rotation(ent) or player:get_max_rotation(ent))
                    end
                    state.eye_yaw = data.shot_time <= data.simulation_time and vec3_t(entity.get_prop(ent, "m_angEyeAngles")).y or state.eye_yaw
                end
            else
                state.abs_yaw = player:rebuild_server_yaw(ent, self:detect_desync_side(ent, state))
            end
        end
    end
}

local hook = {
    on_run_command = function(ctx)
        if not player:is_valid(entity.get_local_player()) then return end
        if not (g_ctx.local_player and (g_ctx.local_player == entity.get_local_player())) then g_ctx.local_player = entity.get_local_player() end
        if not (g_ctx.weapon and (g_ctx.weapon == entity.get_player_weapon(g_ctx.local_player))) then g_ctx.weapon = entity.get_player_weapon(g_ctx.local_player) end
    end,
    on_net_update_end = function()
        if not player:is_valid(g_ctx.local_player) then return end
        local max_players = entity.get_players()
        client.update_player_list()
        for i = 1, #max_players do
            local idx = max_players[i]
            if not idx then goto continue end
            if idx == g_ctx.local_player then goto continue end
            if not entity.is_alive(idx) then goto continue end
            local sim_time, old_sim_time = player:get_simulation_time(idx)
            if sim_time <= old_sim_time then goto continue end
            if entity.is_dormant(idx) then goto continue end
        
            plist.set(idx, "Correction active", false)
            c_change_animstate:main(idx)
            ::continue::
        end
    end,
    on_shutdown = function() collectgarbage("collect") end
}
for k, v in next, hook do client.set_event_callback(k:sub(4), function(ctx) v(ctx) end) end
