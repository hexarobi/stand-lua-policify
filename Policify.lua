-- Policify 1.5
-- by Hexarobi
-- Enable Policify option to modify current vehicle, disable option to remove modifications
-- Modifies horn, paint, neon, and headlights. Flashes headlights and neon between red and blue.

util.require_natives(1651208000)

local function show_busyspinner(text)
    HUD.BEGIN_TEXT_COMMAND_BUSYSPINNER_ON("STRING")
    HUD.ADD_TEXT_COMPONENT_SUBSTRING_PLAYER_NAME(text)
    HUD.END_TEXT_COMMAND_BUSYSPINNER_ON(2)
end

-- From Jackz Vehicle Options script
-- Gets the player's vehicle, attempts to request control. Returns 0 if unable to get control
local function get_player_vehicle_in_control(pid, opts)
    local my_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(players.user()) -- Needed to turn off spectating while getting control
    local target_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)

    -- Calculate how far away from target
    local pos1 = ENTITY.GET_ENTITY_COORDS(target_ped)
    local pos2 = ENTITY.GET_ENTITY_COORDS(my_ped)
    local dist = SYSTEM.VDIST2(pos1.x, pos1.y, 0, pos2.x, pos2.y, 0)

    local was_spectating = NETWORK.NETWORK_IS_IN_SPECTATOR_MODE() -- Needed to toggle it back on if currently spectating
    -- If they out of range (value may need tweaking), auto spectate.
    local vehicle = PED.GET_VEHICLE_PED_IS_IN(target_ped, true)
    if opts and opts.near_only and vehicle == 0 then
        return 0
    end
    if vehicle == 0 and target_ped ~= my_ped and dist > 340000 and not was_spectating then
        util.toast("Player is too far, auto-spectating for upto 3s.")
        show_busyspinner("Player is too far, auto-spectating for upto 3s.")
        NETWORK.NETWORK_SET_IN_SPECTATOR_MODE(true, target_ped)
        -- To prevent a hard 3s loop, we keep waiting upto 3s or until vehicle is acquired
        local loop = (opts and opts.loops ~= nil) and opts.loops or 30 -- 3000 / 100
        while vehicle == 0 and loop > 0 do
            util.yield(100)
            vehicle = PED.GET_VEHICLE_PED_IS_IN(target_ped, true)
            loop = loop - 1
        end
        HUD.BUSYSPINNER_OFF()
    end

    if vehicle > 0 then
        if NETWORK.NETWORK_HAS_CONTROL_OF_ENTITY(vehicle) then
            return vehicle
        end
        -- Loop until we get control
        local netid = NETWORK.NETWORK_GET_NETWORK_ID_FROM_ENTITY(vehicle)
        local has_control_ent = false
        local loops = 15
        NETWORK.SET_NETWORK_ID_CAN_MIGRATE(netid, true)

        -- Attempts 15 times, with 8ms per attempt
        while not has_control_ent do
            has_control_ent = NETWORK.NETWORK_REQUEST_CONTROL_OF_ENTITY(vehicle)
            loops = loops - 1
            -- wait for control
            util.yield(15)
            if loops <= 0 then
                break
            end
        end
    end
    if not was_spectating then
        NETWORK.NETWORK_SET_IN_SPECTATOR_MODE(false, target_ped)
    end
    return vehicle
end

local saveData = {
    Horn = nil,
    Headlights_Color = nil,
    Lights = {
        Neon = {
            Color = {
                r = 0,
                g = 0,
                b = 0,
            },
            Left = false,
            Right = false,
            Front = false,
            Back = false
        }
    },
    Livery = {
        Style = nil
    }
}

local function save_headlights(vehicle)
    saveData.Headlights_Color = VEHICLE._GET_VEHICLE_XENON_LIGHTS_COLOR(vehicle)
    saveData.Headlights_Type = VEHICLE.IS_TOGGLE_MOD_ON(vehicle, 22)
end

local function restore_headlights(vehicle)
    VEHICLE._SET_VEHICLE_XENON_LIGHTS_COLOR(vehicle, saveData.Headlights_Color)
    VEHICLE.TOGGLE_VEHICLE_MOD(vehicle, saveData.Headlights_Type or false)
end

local function save_neon(vehicle)
    local Color = {
        r = memory.alloc(4),
        g = memory.alloc(4),
        b = memory.alloc(4),
    }
    VEHICLE._GET_VEHICLE_NEON_LIGHTS_COLOUR(vehicle, Color.r, Color.g, Color.b)
    saveData.Lights.Neon = {
        Color = {
            r = memory.read_int(Color.r),
            g = memory.read_int(Color.g),
            b = memory.read_int(Color.b),
        },
        Left = VEHICLE._IS_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 0),
        Right = VEHICLE._IS_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 1),
        Front = VEHICLE._IS_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 2),
        Back = VEHICLE._IS_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 3),
    }
end

local function restore_neon(vehicle)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 0, saveData.Lights.Neon.Left or false)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 1, saveData.Lights.Neon.Right or false)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 2, saveData.Lights.Neon.Front or false)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 3, saveData.Lights.Neon.Back or false)
    VEHICLE._SET_VEHICLE_NEON_LIGHTS_COLOUR(vehicle, saveData.Lights.Neon.Color.r, saveData.Lights.Neon.Color.g, saveData.Lights.Neon.Color.b)
end

local function save_paint(vehicle)
    local Primary = {
        Custom = VEHICLE.GET_IS_VEHICLE_PRIMARY_COLOUR_CUSTOM(vehicle),
    }
    local Secondary = {
        Custom = VEHICLE.GET_IS_VEHICLE_SECONDARY_COLOUR_CUSTOM(vehicle),
    }
    local Color = {
        r = memory.alloc(4),
        g = memory.alloc(4),
        b = memory.alloc(4),
    }

    if Primary.Custom then
        VEHICLE.GET_VEHICLE_CUSTOM_PRIMARY_COLOUR(vehicle, Color.r, Color.g, Color.b)
        Primary["Custom Color"] = {
            r = memory.read_int(Color.r),
            b = memory.read_int(Color.g),
            g = memory.read_int(Color.b)
        }
    else
        VEHICLE.GET_VEHICLE_MOD_COLOR_1(vehicle, Color.r, Color.b, Color.g)
        Primary["Paint Type"] = memory.read_int(Color.r)
        Primary["Color"] = memory.read_int(Color.g)
        Primary["Pearlescent Color"] = memory.read_int(Color.b)
    end
    if Secondary.Custom then
        VEHICLE.GET_VEHICLE_CUSTOM_SECONDARY_COLOUR(vehicle, Color.r, Color.g, Color.b)
        Secondary["Custom Color"] = {
            r = memory.read_int(Color.r),
            b = memory.read_int(Color.g),
            g = memory.read_int(Color.b)
        }
    else
        VEHICLE.GET_VEHICLE_MOD_COLOR_2(vehicle, Color.r, Color.b)
        Secondary["Paint Type"] = memory.read_int(Color.r)
        Secondary["Color"] = memory.read_int(Color.g)
    end
    VEHICLE.GET_VEHICLE_COLOR(vehicle, Color.r, Color.g, Color.b)
    local Vehicle = {
        r = memory.read_int(Color.r),
        g = memory.read_int(Color.g),
        b = memory.read_int(Color.b),
    }
    VEHICLE.GET_VEHICLE_EXTRA_COLOURS(vehicle, Color.r, Color.g)
    local ColorExtras = {
        pearlescent = memory.read_int(Color.r),
        wheel = memory.read_int(Color.g),
    }
    VEHICLE.GET_VEHICLE_COLOURS(vehicle, Color.r, Color.g)
    Vehicle["Primary"] = memory.read_int(Color.r)
    Vehicle["Secondary"] = memory.read_int(Color.g)
    memory.free(Color.r)
    memory.free(Color.g)
    memory.free(Color.b)
    saveData.Colors = {
        Primary = Primary,
        Secondary = Secondary,
        ["Color Combo"] = VEHICLE.GET_VEHICLE_COLOUR_COMBINATION(vehicle),
        ["Paint Fade"] = VEHICLE.GET_VEHICLE_ENVEFF_SCALE(vehicle),
        Vehicle = Vehicle,
        Extras = ColorExtras
    }
    saveData.Livery.style = VEHICLE.GET_VEHICLE_MOD(vehicle, 48)
end

local function restore_paint(vehicle)
    VEHICLE.SET_VEHICLE_MOD_KIT(vehicle, 0)
    VEHICLE.SET_VEHICLE_COLOUR_COMBINATION(vehicle, saveData.Colors["Color Combo"] or -1)
    if saveData.Colors.Extra then
        VEHICLE.SET_VEHICLE_EXTRA_COLOURS(vehicle, saveData.Colors.Extras.pearlescent, saveData.Colors.Extras.wheel)
    end
    VEHICLE.SET_VEHICLE_CUSTOM_PRIMARY_COLOUR(vehicle, saveData.Colors.Vehicle.r, saveData.Colors.Vehicle.g, saveData.Colors.Vehicle.b)
    VEHICLE.SET_VEHICLE_CUSTOM_SECONDARY_COLOUR(vehicle, saveData.Colors.Vehicle.r, saveData.Colors.Vehicle.g, saveData.Colors.Vehicle.b)
    VEHICLE.SET_VEHICLE_COLOURS(vehicle, saveData.Colors.Vehicle.Primary or 0, saveData.Colors.Vehicle.Secondary or 0)
    if saveData.Colors.Primary.Custom and saveData.Colors.Primary["Custom Color"] then
        VEHICLE.SET_VEHICLE_CUSTOM_PRIMARY_COLOUR(vehicle, saveData.Colors.Primary["Custom Color"].r, saveData.Colors.Primary["Custom Color"].b, saveData.Colors.Primary["Custom Color"].g)
    else
        VEHICLE.SET_VEHICLE_MOD_COLOR_1(vehicle, saveData.Colors.Primary["Paint Type"], saveData.Colors.Primary.Color, saveData.Colors.Primary["Pearlescent Color"])
    end
    if saveData.Colors.Secondary.Custom and saveData.Colors.Secondary["Custom Color"] then
        VEHICLE.SET_VEHICLE_CUSTOM_SECONDARY_COLOUR(vehicle, saveData.Colors.Secondary["Custom Color"].r,  saveData.Colors.Secondary["Custom Color"].b, saveData.Colors.Secondary["Custom Color"].g)
    else
        VEHICLE.SET_VEHICLE_MOD_COLOR_2(vehicle, saveData.Colors.Secondary["Paint Type"], saveData.Colors.Secondary.Color)
    end
    VEHICLE.SET_VEHICLE_ENVEFF_SCALE(vehicle, saveData["Colors"]["Paint Fade"] or 0)

    VEHICLE.SET_VEHICLE_MOD(vehicle, 48, saveData.Livery.style or -1)
end

local function save_horn(vehicle)
    saveData.Horn = VEHICLE.GET_VEHICLE_MOD(vehicle, 14)
    VEHICLE.SET_VEHICLE_SIREN(vehicle, true)
end

local function restore_horn(vehicle)
    VEHICLE.SET_VEHICLE_MOD(vehicle, 14, saveData.Horn)
    VEHICLE.SET_VEHICLE_SIREN(vehicle, false)
end

local attachments = {
    siren = nil
}

local function load_hash(hash)
    STREAMING.REQUEST_MODEL(hash)
    while not STREAMING.HAS_MODEL_LOADED(hash) do
        util.yield()
    end
end

local function attach_model_to_vehicle(vehicle, vehicle_name, pos, rot)
    local hash = util.joaat(vehicle_name)
    if not STREAMING.IS_MODEL_VALID(hash) then
        util.toast("Failing to spawn vehicle due to invalid model.")
        return
    end
    load_hash(hash)
    if pos == nil then
        pos = { x=0, y=0, z=0 }
    end
    if rot == nil then
        rot = { x=0, y=0, z=0 }
    end
    local heading = ENTITY.GET_ENTITY_HEADING(vehicle)
    local handle = entities.create_vehicle(hash, pos, heading)
    ENTITY.SET_ENTITY_INVINCIBLE(handle, true)
    ENTITY.SET_ENTITY_NO_COLLISION_ENTITY(vehicle, handle)
    ENTITY.SET_ENTITY_HAS_GRAVITY(handle, false)
    ENTITY.ATTACH_ENTITY_TO_ENTITY(handle, vehicle, 0,
            pos.x or 0, pos.y or 0, pos.z or 0,
            rot.x or 0, rot.y or 0, rot.z or 0,
            false, true, true, false, 2, true
    )
    return handle
end


local function save_siren(vehicle)
    if attachments.siren == nil then
        local handle = attach_model_to_vehicle(vehicle, "policeb")
        attachments.siren = handle
        AUDIO.SET_SIREN_WITH_NO_DRIVER(handle, true)
        AUDIO._SET_SIREN_KEEP_ON(handle, true)
        VEHICLE.SET_VEHICLE_HAS_MUTED_SIRENS(handle, false)
        VEHICLE.SET_VEHICLE_SIREN(handle, true)
        ENTITY.SET_ENTITY_ALPHA(handle, 0, false)
    end
end

local function restore_siren(vehicle)
    if attachments.siren ~= nil then
        entities.delete_by_handle(attachments.siren)
        attachments.siren = nil
    end
end

local function save_plate(vehicle)
    saveData["License Plate"] = {
        Text = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT(vehicle),
        Type = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(vehicle)
    }
end

local function restore_plate(vehicle)
    ENTITY.SET_ENTITY_AS_MISSION_ENTITY(vehicle, true, true)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(vehicle, saveData["License Plate"].Text)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(vehicle, saveData["License Plate"].Type)
end

local function attach_to_vehicle(vehicle, model, pos, rot)
    local hash = util.joaat(model)
    if STREAMING.IS_MODEL_VALID(hash) and not STREAMING.IS_MODEL_A_VEHICLE(hash) then
        STREAMING.REQUEST_MODEL(hash)
        while not STREAMING.HAS_MODEL_LOADED(hash) do
            util.yield()
        end
        if pos == nil then
            pos = {x=0, y=0, z=0}
        end
        if rot == nil then
            rot = {x=0, y=0, z=0}
        end
        local object = entities.create_object(hash, pos)
        ENTITY.ATTACH_ENTITY_TO_ENTITY(object, vehicle, 0,
                pos.x or 0, pos.y or 0, pos.z or 0,
                rot.x or 0, rot.y or 0, rot.z or 0,
                false, true, true, false, 2, true
        )
        STREAMING.SET_MODEL_AS_NO_LONGER_NEEDED(hash)
        return object
    end
end

local policified_vehicle
local policify_tick_counter
local flash_delay = 50
local override_paint = true
local override_headlights = true
local override_neon = true
local override_plate = true
local overide_horn = true
local override_siren = true

local lights = {}

local function attach_hidden_prop_to_vehicle(vehicle, model, pos, rot)
    local handle = attach_to_vehicle(vehicle, model, pos, rot)
    -- ENTITY.SET_ENTITY_ALPHA(handle, 0)
    return handle
end

-- prop_air_lights_02a blue
-- prop_air_lights_02b red

local function add_police_light(vehicle, pos, rot)
    --if pos.x == 0 then
    --    -- Single Light
    --    table.insert(lights, {
    --        red=attach_hidden_prop_to_vehicle(vehicle,"h4_prop_battle_lights_floorred", pos, rot),
    --        blue=attach_hidden_prop_to_vehicle(vehicle,"h4_prop_battle_lights_floorblue", pos, rot)
    --    })
    --else
    --    -- Pair of Lights
    table.insert(lights, {
        red=attach_hidden_prop_to_vehicle(vehicle,"h4_prop_battle_lights_floorred", pos, rot),
        -- blue=attach_hidden_prop_to_vehicle(vehicle,"h4_prop_battle_lights_floorblue", pos, rot)
    })
    --local reflected_pos = pos
    --reflected_pos.x = 0 - pos.x
    --table.insert(lights, {
    --    red=attach_hidden_prop_to_vehicle(vehicle,"h4_prop_battle_lights_floorblue", reflected_pos, rot),
    --    -- blue=attach_hidden_prop_to_vehicle(vehicle,"h4_prop_battle_lights_floorred", reflected_pos, rot)
    --})
    --end
end

local function policify_vehicle(vehicle)
    if override_headlights then
        save_headlights(vehicle)
        -- Enable Xenon Headlights
        VEHICLE.TOGGLE_VEHICLE_MOD(vehicle, 22, true)
    end

    if override_neon then
        save_neon(vehicle)
        -- Enable Neon
        VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 0, true)
        VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 1, true)
        VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 2, true)
        VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 3, true)
    end

    if overide_horn then
        save_horn(vehicle)
        -- Police Horn
        VEHICLE.SET_VEHICLE_MOD(vehicle, 14, 1)
    end

    if override_paint then
        save_paint(vehicle)
        -- Paint matte black
        VEHICLE.SET_VEHICLE_CUSTOM_PRIMARY_COLOUR(vehicle, 0, 0, 0)
        VEHICLE.SET_VEHICLE_MOD_COLOR_1(vehicle, 3, 0, 0)
        VEHICLE.SET_VEHICLE_CUSTOM_SECONDARY_COLOUR(vehicle, 0, 0, 0)
        VEHICLE.SET_VEHICLE_MOD_COLOR_2(vehicle, 3, 0, 0)

        -- Clear livery
        VEHICLE.SET_VEHICLE_MOD(vehicle, 48, -1)
    end

    if override_plate then
        save_plate(vehicle)
        -- Set Exempt plate
        ENTITY.SET_ENTITY_AS_MISSION_ENTITY(vehicle, true, true)
        VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(vehicle, 4)
        VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(vehicle, "FIB")
    end

    if override_siren then
        save_siren(vehicle)
    end

    --lights = {
    --    {red=attach_to_vehicle(vehicle, "prop_air_conelight", {x=0.45,y=-0.85,z=0.55}, {x=0, y=0, z=0})}
    --}
    -- add_police_light(vehicle, {x=0.45,y=-0.85,z=0.55}, {x=0, y=0, z=0})

end

local function depolicify_vehicle(vehicle)
    if override_headlights then
        restore_headlights(vehicle)
    end
    if override_neon then
        restore_neon(vehicle)
    end
    if overide_horn then
        restore_horn(vehicle)
    end
    if override_paint then
        restore_paint(vehicle)
    end
    if override_plate then
        restore_plate(vehicle)
    end
    if override_siren then
        restore_siren(vehicle)
    end
    --for _, light in lights do
    --    if ENTITY.IS_ENTITY_ATTACHED_TO_ENTITY(vehicle, light.red) then
    --        entities.delete_by_handle(light.red)
    --    end
    --    if ENTITY.IS_ENTITY_ATTACHED_TO_ENTITY(vehicle, light.blue) then
    --        entities.delete_by_handle(light.blue)
    --    end
    --end
end

local policify_ticker = function()
    if policified_vehicle == nil then
        util.toast("Invalid vehicle for policify ticker")
    end
    if policify_tick_counter % flash_delay == 0 then
        if policify_tick_counter % (flash_delay * 2) == 0 then
            if override_headlights then
                VEHICLE._SET_VEHICLE_XENON_LIGHTS_COLOR(policified_vehicle, 8)
            end
            if override_neon then
                VEHICLE._SET_VEHICLE_NEON_LIGHTS_COLOUR(policified_vehicle, 0, 0, 255)
            end
            --for _, light in lights do
            --    ENTITY.SET_ENTITY_ROTATION(light.red, 90, 0, 0, 1, true)
            --    --local pos = ENTITY.GET_ENTITY_COORDS(light.red, 1)
            --    --local pos = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(light.red, 0, 0, 0)
            --    --util.toast("x="..pos.x.." y="..pos.y.." z="..pos.z)
            --    --ENTITY.SET_ENTITY_COORDS(light.red, pos.x, pos.y, pos.z, true, false, false, true)
            --    --local pos2 = ENTITY.GET_ENTITY_COORDS(light.red, 1)
            --    --util.toast("pos.x="..pos.x.." pos2.x="..pos2.x)
            --    --ENTITY.SET_ENTITY_ALPHA(light.red, 255)
            --    --ENTITY.SET_ENTITY_ALPHA(light.red, 0)
            --    -- ENTITY.SET_ENTITY_LIGHTS(light.red, true)
            --end
        else
            if override_headlights then
                VEHICLE._SET_VEHICLE_XENON_LIGHTS_COLOR(policified_vehicle, 1)
            end
            if override_neon then
                VEHICLE._SET_VEHICLE_NEON_LIGHTS_COLOUR(policified_vehicle, 255, 0, 0)
            end
            --for _, light in lights do
            --    ENTITY.SET_ENTITY_ROTATION(light.red, 0, 0, 0, 1, true)
            --    -- ENTITY.SET_ENTITY_LIGHTS(light.red, false)
            --    --ENTITY.SET_ENTITY_ALPHA(light.red, 255)
            --    -- ENTITY.SET_ENTITY_ALPHA(light.blue, 255)
            --end
        end
    end
    policify_tick_counter = policify_tick_counter + 1
end

menu.toggle(menu.my_root(), "Policify Vehicle", {"policify"}, "Enable Policify options on current vehicle", function(on)
    if on then
        policified_vehicle = get_player_vehicle_in_control(players.user())
        if policified_vehicle then
            policify_vehicle(policified_vehicle)

            policify_tick_counter = 0
            util.create_tick_handler(function()
                if policify_tick_counter ~= nil then
                    policify_ticker()
                else
                    return false
                end
            end)
        end
    else
        policify_tick_counter = nil
        depolicify_vehicle(policified_vehicle)
    end
end)

menu.action(menu.my_root(), "Warning Blip", {"blip"}, "A quick siren blip to gain attention", function()
    if attachments.siren then
        AUDIO.BLIP_SIREN(attachments.siren)
    end
end)

menu.toggle(menu.my_root(), "Siren Sounds", {"sirens"}, "Enables siren sounds to notify other vehicles to pull over", function(on)
    if attachments.siren then
        if on then
            AUDIO._SET_SIREN_KEEP_ON(attachments.siren, true)
            VEHICLE.SET_VEHICLE_SIREN(attachments.siren, true)
            AUDIO._TRIGGER_SIREN(attachments.siren, true)
        else
            AUDIO._SET_SIREN_KEEP_ON(attachments.siren, false)
            VEHICLE.SET_VEHICLE_SIREN(attachments.siren, false)
        end
    end
end)

-- menu.divider(menu.my_root(), "Options")

local options_menu = menu.list(menu.my_root(), "Options")

menu.slider(options_menu, "Flash Delay", {"policifydelay"}, "Setting a too low value may not network the colors to other players!", 20, 150, 50, 10, function (value)
    flash_delay = value
end)

menu.toggle(options_menu, "Override Paint", {}, "If enabled, will override vehicle paint to matte black", function(toggle)
    if toggle then
        override_paint = true
        if policify_tick_counter ~= nil then
            save_paint(policified_vehicle)
            policify_vehicle(policified_vehicle)
        end
    else
        override_paint = false
        if policify_tick_counter ~= nil then
            restore_paint(policified_vehicle)
        end
    end
end, true)

menu.toggle(options_menu, "Override Headlights", {}, "If enabled, will override vehicle headlights to flash blue and red", function(toggle)
    if toggle then
        override_headlights = true
        if policify_tick_counter ~= nil then
            save_headlights(policified_vehicle)
            policify_vehicle(policified_vehicle)
        end
    else
        override_headlights = false
        if policify_tick_counter ~= nil then
            restore_headlights(policified_vehicle)
        end
    end
end, true)

menu.toggle(options_menu, "Override Neon", {}, "If enabled, will override vehicle neon to flash red and blue", function(toggle)
    if toggle then
        override_neon = true
        if policify_tick_counter ~= nil then
            save_neon(policified_vehicle)
            policify_vehicle(policified_vehicle)
        end
    else
        override_neon = false
        if policify_tick_counter ~= nil then
            restore_neon(policified_vehicle)
        end
    end
end, true)

menu.toggle(options_menu, "Override Horn", {}, "If enabled, will override vehicle horn to police horn", function(toggle)
    if toggle then
        overide_horn = true
        if policify_tick_counter ~= nil then
            save_horn(policified_vehicle)
            policify_vehicle(policified_vehicle)
        end
    else
        overide_horn = false
        if policify_tick_counter ~= nil then
            restore_horn(policified_vehicle)
        end
    end
end, true)

menu.toggle(options_menu, "Override Plate", {}, "If enabled, will override vehicle plate with FIB Exempt plate", function(toggle)
    if toggle then
        override_plate = true
        if policify_tick_counter ~= nil then
            save_plate(policified_vehicle)
            policify_vehicle(policified_vehicle)
        end
    else
        override_plate = false
        if policify_tick_counter ~= nil then
            restore_plate(policified_vehicle)
        end
    end
end, true)

menu.toggle(options_menu, "Enable Siren", {}, "If enabled, will spawn an invisible police bike to play its siren", function(toggle)
    if toggle then
        override_siren = true
        if policify_tick_counter ~= nil then
            save_siren(policified_vehicle)
            policify_vehicle(policified_vehicle)
        end
    else
        override_siren = false
        if policify_tick_counter ~= nil then
            restore_siren(policified_vehicle)
        end
    end
end, true)

util.create_tick_handler(function()
    return true
end)
