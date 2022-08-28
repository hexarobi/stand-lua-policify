-- Policify 1.9
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

local function set_headlights(vehicle)
    VEHICLE.TOGGLE_VEHICLE_MOD(vehicle, 22, true)
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

local function set_neon(vehicle)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 0, true)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 1, true)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 2, true)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle, 3, true)
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

local function set_paint(vehicle)
    -- Paint matte black
    VEHICLE.SET_VEHICLE_CUSTOM_PRIMARY_COLOUR(vehicle, 0, 0, 0)
    VEHICLE.SET_VEHICLE_MOD_COLOR_1(vehicle, 3, 0, 0)
    VEHICLE.SET_VEHICLE_CUSTOM_SECONDARY_COLOUR(vehicle, 0, 0, 0)
    VEHICLE.SET_VEHICLE_MOD_COLOR_2(vehicle, 3, 0, 0)

    -- Clear livery
    VEHICLE.SET_VEHICLE_MOD(vehicle, 48, -1)
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

local function set_horn(vehicle)
    -- Police Horn
    VEHICLE.SET_VEHICLE_MOD(vehicle, 14, 1)
end

local function restore_horn(vehicle)
    VEHICLE.SET_VEHICLE_MOD(vehicle, 14, saveData.Horn)
    VEHICLE.SET_VEHICLE_SIREN(vehicle, false)
end

local attachments = {
    vehicles = nil,
    additional_lights = nil,
}

local attachments_handles = {}

-- Good props for cop lights
-- prop_air_lights_02a blue
-- prop_air_lights_02b red
-- h4_prop_battle_lights_floorblue
-- h4_prop_battle_lights_floorred
-- prop_wall_light_10a
-- prop_wall_light_10b
-- prop_wall_light_10c
-- hei_prop_wall_light_10a_cr

local available_attachments = {
    {
        name="Solid Red Light",
        model="prop_wall_light_10a",
        offset={x=0,y=0,z=1},
        rotation={x=180,y=0,z=180},
    },

    {
        name = "Spinning Red Light",
        model = "apa_mp_apa_yacht_radar_01a",
        is_visible = false,
        offset = { x=0, y=0, z=0 },
        children = {
            {
                model = "apa_mp_apa_yacht_radar_01a",
                is_visible = false,
                offset = { x=0, y=0, z=-0.55 },
                bone_index = 1,
                children = {
                    {
                        model = "apa_mp_apa_yacht_radar_01a",
                        is_visible = false,
                        offset = { x = 0, y = 0, z = -0.55 },
                        bone_index = 1,
                        children = {
                            {
                                model = "apa_mp_apa_yacht_radar_01a",
                                is_visible = false,
                                offset = { x = 0, y = 0, z = -0.55 },
                                bone_index = 1,
                                children = {
                                    {
                                        model = "apa_mp_apa_yacht_radar_01a",
                                        is_visible = false,
                                        offset = { x = 0, y = 0, z = -0.55 },
                                        bone_index = 1,
                                        children = {
                                            {
                                                model = "prop_wall_light_10a",
                                                offset = { x = 0, y = 0, z = 0.1 },
                                                rotation = { x = 180, y = 0, z = 0 },
                                                bone_index = 1,
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },

    {
        name="Solid Red and Blue Lights",
        model="prop_wall_light_10a",
        is_visible=true,
        offset={x=0.3, y=0, z=0.7},
        rotation={x=180,y=0,z=0},
        reflection={
            model="prop_wall_light_10b",
            is_visible=true,
            reflection_axis={x=true, y=false, z=false},
            rotation={x=0,y=0,z=180},
        }
    },

    {
        name="Spinning Red and Blue Lights",
        offset={ x=0.3, y=0, z=0.7 },
        model = "apa_mp_apa_yacht_radar_01a",
        is_visible = false,
        children = {
            {
                model = "apa_mp_apa_yacht_radar_01a",
                is_visible = false,
                offset = { x=0, y=0, z=-0.55 },
                bone_index = 1,
                children = {
                    {
                        model = "apa_mp_apa_yacht_radar_01a",
                        is_visible = false,
                        offset = { x=0, y=0, z=-0.55 },
                        bone_index = 1,
                        children = {
                            {
                                model = "apa_mp_apa_yacht_radar_01a",
                                is_visible = false,
                                offset = { x=0, y=0, z=-0.55 },
                                bone_index = 1,
                                children = {
                                    {
                                        model = "apa_mp_apa_yacht_radar_01a",
                                        is_visible = false,
                                        offset = { x=0, y=0, z=-0.55 },
                                        bone_index = 1,
                                        children = {
                                            {
                                                model = "prop_wall_light_10a",
                                                offset = { x=0, y=0, z=-1 },
                                                rotation = { x=180, y=0, z=0 },
                                                bone_index = 1,
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
        reflection={
            model = "apa_mp_apa_yacht_radar_01a",
            is_visible = false,
            reflection_axis={ x=true, y=false, z=false },
            children = {
                {
                    model = "apa_mp_apa_yacht_radar_01a",
                    is_visible = false,
                    offset = { x=0, y=0, z=-0.55 },
                    bone_index = 1,
                    children = {
                        {
                            model = "apa_mp_apa_yacht_radar_01a",
                            is_visible = false,
                            offset = { x=0, y=0, z=-0.55 },
                            bone_index = 1,
                            children = {
                                {
                                    model = "apa_mp_apa_yacht_radar_01a",
                                    is_visible = false,
                                    offset = { x=0, y=0, z=-0.55 },
                                    bone_index = 1,
                                    children = {
                                        {
                                            model = "apa_mp_apa_yacht_radar_01a",
                                            is_visible = false,
                                            offset = { x=0, y=0, z=-0.55 },
                                            bone_index = 1,
                                            children = {
                                                {
                                                    model = "prop_wall_light_10b",
                                                    offset = { x=0, y=0, z=-1 },
                                                    rotation = { x=180, y=0, z=180 },
                                                    bone_index = 1,
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        }
    }
}

local function load_hash(hash)
    STREAMING.REQUEST_MODEL(hash)
    while not STREAMING.HAS_MODEL_LOADED(hash) do
        util.yield()
    end
end

local function attach_entity_to_entity(args)
    if args.offset == nil or args.rotation == nil then
        util.toast("Error: Position or Rotation not set")
        return
    end
    if args.parent == args.handle then
        ENTITY.SET_ENTITY_ROTATION(args.handle, args.rotation.x or 0, args.rotation.y or 0, args.rotation.z or 0)
    else
        ENTITY.ATTACH_ENTITY_TO_ENTITY(
            args.handle, args.force_parent or args.parent or args.root, args.bone_index or 0,
            args.offset.x or 0, args.offset.y or 0, args.offset.z or 0,
            args.rotation.x or 0, args.rotation.y or 0, args.rotation.z or 0,
            false, true, false, false, 2, true
        )
    end
end

local function set_no_collision_with_all_attachments_objects(args)
    ENTITY.SET_ENTITY_NO_COLLISION_ENTITY(args.root, args.handle)
    for _, handle in pairs(attachments_handles) do
        ENTITY.SET_ENTITY_NO_COLLISION_ENTITY(args.handle, handle)
    end
    table.insert(attachments_handles, args.handle)
end

local function insert_attachment_object(args)
    if args.parent == nil or args.parent == args.root then
        table.insert(args.handles, args)
    else
        for _, attachment in pairs(args.handles) do
            if attachment.handle == args.root then
                table.insert(attachment.objects, args)
            end
        end
    end
end

local function attach(args)
    local hash = util.joaat(args.model)
    if not STREAMING.IS_MODEL_VALID(hash) or (args.type ~= "vehicle" and STREAMING.IS_MODEL_A_VEHICLE(hash)) then
        util.toast("Error attaching: Invalid model")
        return
    end
    load_hash(hash)

    if args.offset == nil then
        args.offset = {x=0, y=0, z=0}
    end
    if args.rotation == nil then
        args.rotation = {x=0, y=0, z=0}
    end

    ENTITY.FREEZE_ENTITY_POSITION(args.root, true)

    if args.type == "vehicle" then
        local heading = ENTITY.GET_ENTITY_HEADING(args.root)
        args.handle = entities.create_vehicle(hash, args.offset, heading)
    else
        local pos = ENTITY.GET_ENTITY_COORDS(args.root)
        args.handle = OBJECT.CREATE_OBJECT(hash, pos.x, pos.y, pos.z, false, false, 0)
        -- handle = entities.create_object(hash, ENTITY.GET_ENTITY_COORDS(args.root))
    end
    --STREAMING.SET_MODEL_AS_NO_LONGER_NEEDED(hash)
    ENTITY.SET_ENTITY_INVINCIBLE(args.handle, false)
    ENTITY.SET_ENTITY_HAS_GRAVITY(args.handle, false)

    attach_entity_to_entity(args)
    set_no_collision_with_all_attachments_objects(args)
    insert_attachment_object(args)

    if args.is_visible == false then
        ENTITY.SET_ENTITY_ALPHA(args.handle, 0, false)
    end

    -- local network_handle = NETWORK.OBJ_TO_NET(handle)
    --ENTITY.SET_ENTITY_AS_MISSION_ENTITY(args.handle)
    --ENTITY._SET_ENTITY_CLEANUP_BY_ENGINE(args.handle, false)

    ENTITY.FREEZE_ENTITY_POSITION(args.root, false)

    return args
end

local function get_reflection_with_offsets(attachment)
    --- This function isn't quite right, it breaks with certain root rotations, but close enough for now
    local reflection = attachment.reflection
    reflection.parent = attachment.handle
    reflection.offset = {x=0, y=0, z=0}
    if reflection.reflection_axis.x then
        reflection.offset.x = attachment.offset.x * -2
    end
    if reflection.reflection_axis.y then
        reflection.offset.y = attachment.offset.y * -2
    end
    if reflection.reflection_axis.z then
        reflection.offset.z = attachment.offset.z * -2
    end
    return reflection
end

local function move_attachment(attachment)
    if attachment.reflection then
        local reflection = get_reflection_with_offsets(attachment)
        attach_entity_to_entity(reflection)
    end
    attach_entity_to_entity(attachment)
end

local function detach(attachment)
    if attachment.children then
        for _, child in pairs(attachment.children) do
            detach(child)
        end
    end
    if attachment.reflection then
        detach(attachment.reflection)
    end
    for i, handle in pairs(attachment.handles) do
        if handle == attachment.handle then
            table.remove(attachments.handles, i)
        end
    end
    entities.delete_by_handle(attachment.handle)
end


local function attach_available_attachment_to_vehicle(root_vehicle, available_attachment, attachments_list)
    available_attachment.root = root_vehicle
    available_attachment.handles = attachments_list
    local attachment = attach(available_attachment)
    local parent = available_attachment.handle
    if available_attachment.children then
        for _, child in pairs(available_attachment.children) do
            child.parent = parent
            attach_available_attachment_to_vehicle(root_vehicle, child, attachments_list)
            parent = child
        end
    end
    if available_attachment.reflection then
        local reflection = get_reflection_with_offsets(available_attachment)
        attach_available_attachment_to_vehicle(root_vehicle, reflection, attachments_list)
    end
    return attachment
end

local function set_additional_vehicles(vehicle)
    if attachments.vehicles ~= nil then
        util.toast("Error setting siren. Already set")
        return
    end
    attachments.vehicles = {}
    local args = attach{ root=vehicle, parent=vehicle, handles=attachments.vehicles, model="policeb", type="vehicle", is_visible=false}
    AUDIO.SET_SIREN_WITH_NO_DRIVER(args.handle, true)
    AUDIO._SET_SIREN_KEEP_ON(args.handle, true)
    VEHICLE.SET_VEHICLE_HAS_MUTED_SIRENS(args.handle, false)
    VEHICLE.SET_VEHICLE_SIREN(args.handle, true)
end

local function set_additional_lights()
    if attachments.additional_lights ~= nil then
        util.toast("Error setting additional lights. Already set")
        return
    end
    attachments.additional_lights = {}
end

local function restore_additional_lights()
    if attachments.additional_lights ~= nil then
        for _, attachment in pairs(attachments.additional_lights) do
            detach(attachment)
        end
        attachments.additional_lights = nil
    end
end

local function activate_sirens()
    for _, args in pairs(attachments.vehicles) do
        AUDIO._SET_SIREN_KEEP_ON(args.handle, true)
        VEHICLE.SET_VEHICLE_SIREN(args.handle, true)
        AUDIO._TRIGGER_SIREN(args.handle, true)
    end
end

local function deactivate_sirens()
    for _, args in pairs(attachments.vehicles) do
        AUDIO._SET_SIREN_KEEP_ON(args.handle, false)
        VEHICLE.SET_VEHICLE_SIREN(args.handle, false)
    end
end

local function restore_additional_vehicles()
    if attachments.vehicles ~= nil then
        for _, args in pairs(attachments.vehicles) do
            entities.delete_by_handle(args.handle)
        end
        attachments.vehicles = nil
    end
end

local function save_plate(vehicle)
    saveData["License Plate"] = {
        Text = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT(vehicle),
        Type = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(vehicle)
    }
end

local function set_plate(vehicle)
    -- Set Exempt plate
    ENTITY.SET_ENTITY_AS_MISSION_ENTITY(vehicle, true, true)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(vehicle, 4)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(vehicle, "FIB")
end

local function restore_plate(vehicle)
    ENTITY.SET_ENTITY_AS_MISSION_ENTITY(vehicle, true, true)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(vehicle, saveData["License Plate"].Text)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(vehicle, saveData["License Plate"].Type)
end

local policified_vehicle
local policify_tick_counter
local flash_delay = 50
local override_paint = true
local override_headlights = true
local override_neon = true
local override_plate = true
local override_horn = true
local allow_additional_vehicles = true
local allow_additional_lights = true
local is_active_sirens = false
local is_active_lights = false

local function add_overrides_to_vehicle(vehicle)
    if override_headlights then
        save_headlights(vehicle)
        set_headlights(vehicle)
    end

    if override_neon then
        save_neon(vehicle)
        set_neon(vehicle)
    end

    if override_horn then
        save_horn(vehicle)
        set_horn(vehicle)
    end

    if override_paint then
        save_paint(vehicle)
        set_paint(vehicle)
    end

    if override_plate then
        save_plate(vehicle)
        set_plate(vehicle)
    end

    if allow_additional_vehicles then
        set_additional_vehicles(vehicle)
    end

    if allow_additional_lights then
        set_additional_lights(vehicle)
    end

end

local function remove_overrides_from_vehicle(vehicle)
    if override_headlights then
        restore_headlights(vehicle)
    end
    if override_neon then
        restore_neon(vehicle)
    end
    if override_horn then
        restore_horn(vehicle)
    end
    if override_paint then
        restore_paint(vehicle)
    end
    if override_plate then
        restore_plate(vehicle)
    end
    if allow_additional_vehicles then
        restore_additional_vehicles(vehicle)
    end
    if allow_additional_lights then
        restore_additional_lights(vehicle)
    end
end

local function policify_tick_ying()
    if is_active_lights then
        if override_headlights then
            VEHICLE._SET_VEHICLE_XENON_LIGHTS_COLOR(policified_vehicle, 8)
        end
        if override_neon then
            VEHICLE._SET_VEHICLE_NEON_LIGHTS_COLOUR(policified_vehicle, 0, 0, 255)
        end
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
end

local function policify_tick_yang()
    if is_active_lights then
        if override_headlights then
            VEHICLE._SET_VEHICLE_XENON_LIGHTS_COLOR(policified_vehicle, 1)
        end
        if override_neon then
            VEHICLE._SET_VEHICLE_NEON_LIGHTS_COLOUR(policified_vehicle, 255, 0, 0)
        end
    end
    --for _, light in lights do
    --    ENTITY.SET_ENTITY_ROTATION(light.red, 0, 0, 0, 1, true)
    --    -- ENTITY.SET_ENTITY_LIGHTS(light.red, false)
    --    --ENTITY.SET_ENTITY_ALPHA(light.red, 255)
    --    -- ENTITY.SET_ENTITY_ALPHA(light.blue, 255)
    --end
end

local policify_ticker = function()
    if policified_vehicle == nil then
        util.toast("Invalid vehicle for policify ticker")
    end
    if policify_tick_counter % flash_delay == 0 then
        if policify_tick_counter % (flash_delay * 2) == 0 then
            policify_tick_ying()
        else
            policify_tick_yang()
        end
    end
    policify_tick_counter = policify_tick_counter + 1
end

local function policify_vehicle(vehicle)
    policified_vehicle = vehicle
    add_overrides_to_vehicle(vehicle)

    policify_tick_counter = 0
    util.create_tick_handler(function()
        if policify_tick_counter ~= nil then
            policify_ticker()
        else
            return false
        end
    end)
end

local function depolicify_vehicle()
    policify_tick_counter = nil
    remove_overrides_from_vehicle(policified_vehicle)
end

local function policify_current_vehicle()
    local vehicle = get_player_vehicle_in_control(players.user())
    if vehicle then
        policify_vehicle(vehicle)
    else
        util.toast("Error: could not load current vehicle")
    end
end


menu.toggle(menu.my_root(), "Policify Vehicle", {"policify"}, "Enable Policify options on current vehicle", function(on)
    if on then
        policify_current_vehicle()
    else
        depolicify_vehicle()
    end
end)

menu.action(menu.my_root(), "Siren Warning Blip", {"blip"}, "A quick siren blip to gain attention", function()
    if attachments.vehicles == nil then
        util.toast("Error: No siren enabled")
    end
    AUDIO.BLIP_SIREN(attachments.vehicles[1].handle)
end)

--menu.action(menu.my_root(), "Police Report", {}, "Play police report", function()
--    --AUDIO.SET_AUDIO_FLAG("AllowPoliceScannerWhenPlayerHasNoControl", 0)
--    --AUDIO.SET_AUDIO_FLAG("OnlyAllowScriptTriggerPoliceScanner", 0)
--    --AUDIO.SET_AUDIO_FLAG("PoliceScannerDisabled", 1)
--    AUDIO.SET_AUDIO_FLAG("IsDirectorModeActive", 1)
--    AUDIO.PLAY_POLICE_REPORT("LAMAR_1_POLICE_LOST", 0)
--
--end)

menu.toggle(menu.my_root(), "Toggle Lights", {"coplights"}, "Toggle vehicle lights", function(on)
    is_active_lights = on
    if is_active_lights then
        save_headlights(policified_vehicle)
        save_neon(policified_vehicle)
    else
        restore_headlights(policified_vehicle)
        restore_neon(policified_vehicle)
    end
end)

menu.toggle(menu.my_root(), "Toggle Sirens", {"copsirens"}, "Toggle vehicle sirens", function(on)
    if attachments.vehicles == nil then
        util.toast("Error: No siren enabled")
    end
    is_active_sirens = on
    if is_active_sirens then
        activate_sirens()
    else
        deactivate_sirens()
    end
end)

local attach_additional_lights_menu = menu.list(menu.my_root(), "Add Attachment")
local edit_attachments_menu = menu.list(menu.my_root(), "Edit Attachments")

local function rebuild_edit_attachments_menu()
    for _, attachment in pairs(attachments.additional_lights) do
        if not attachment.is_added_to_edit_menu then
            local edit_menu = menu.list(edit_attachments_menu, attachment.name)
            menu.divider(edit_menu, "Position")
            menu.slider_float(edit_menu, "X: Left / Right", {}, "", -500000, 500000, math.floor(attachment.offset.x * 100), 1, function(value, prev_value)
                attachment.offset.x = value / 100
                move_attachment(attachment)
            end)
            menu.slider_float(edit_menu, "Y: Forward / Back", {}, "", -500000, 500000, math.floor(attachment.offset.y * -100), 1, function(value, prev_value)
                attachment.offset.y = value / -100
                move_attachment(attachment)
            end)
            menu.slider_float(edit_menu, "Z: Up / Down", {}, "", -500000, 500000, math.floor(attachment.offset.z * -100), 1, function(value, prev_value)
                attachment.offset.z = value / -100
                move_attachment(attachment)
            end)
            menu.divider(edit_menu, "Rotation")
            menu.slider(edit_menu, "X: Pitch", {}, "", -175, 180, math.floor(attachment.rotation.x), 5, function(value, prev_value)
                attachment.rotation.x = value
                move_attachment(attachment)
            end)
            menu.slider(edit_menu, "Y: Roll", {}, "", -175, 180, math.floor(attachment.rotation.y), 5, function(value, prev_value)
                attachment.rotation.y = value
                move_attachment(attachment)
            end)
            menu.slider(edit_menu, "Z: Yaw", {}, "", -175, 180, math.floor(attachment.rotation.z), 5, function(value, prev_value)
                attachment.rotation.z = value
                move_attachment(attachment)
            end)
            menu.divider(edit_menu, "Options")
            --menu.toggle(edit_menu, "Visible", {}, "", function(on)
            --    attachment.is_visible = on
            --    attach_entity_to_entity(attachment)
            --end, attachment.is_visible)
            menu.action(edit_menu, "Delete", {}, "", function()
                detach(attachment)
                menu.delete(edit_menu)
            end)
            attachment.is_added_to_edit_menu = true
        end
    end
end

for _, available_attachment in pairs(available_attachments) do
    menu.action(attach_additional_lights_menu, available_attachment.name, {}, "", function()
        attach_available_attachment_to_vehicle(policified_vehicle, available_attachment, attachments.additional_lights)
        rebuild_edit_attachments_menu()
    end)
end

local options_menu = menu.list(menu.my_root(), "Options")

menu.slider(options_menu, "Flash Delay", {"policifydelay"}, "Setting a too low value may not network the colors to other players!", 20, 150, 50, 10, function (value)
    flash_delay = value
end)

menu.toggle(options_menu, "Override Paint", {}, "If enabled, will override vehicle paint to matte black", function(toggle)
    if toggle then
        override_paint = true
        if policify_tick_counter ~= nil then
            save_paint(policified_vehicle)
            set_paint(policified_vehicle)
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
            set_headlights(policified_vehicle)
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
            set_neon(policified_vehicle)
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
        override_horn = true
        if policify_tick_counter ~= nil then
            save_horn(policified_vehicle)
            set_horn(policified_vehicle)
        end
    else
        override_horn = false
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
            set_plate(policified_vehicle)
        end
    else
        override_plate = false
        if policify_tick_counter ~= nil then
            restore_plate(policified_vehicle)
        end
    end
end, true)

menu.toggle(options_menu, "Enable Siren Sounds", {}, "If enabled, will spawn an invisible police bike to play its siren", function(toggle)
    if toggle then
        allow_additional_vehicles = true
        if policify_tick_counter ~= nil then
            set_additional_vehicles(policified_vehicle)
        end
    else
        allow_additional_vehicles = false
        if policify_tick_counter ~= nil then
            restore_additional_vehicles(policified_vehicle)
        end
    end
end, true)

menu.toggle(options_menu, "Enable Attached Lights", {}, "If enabled, will show attached additional lights", function(toggle)
    allow_additional_lights = toggle
    if policify_tick_counter ~= nil then
        if toggle then
            set_additional_lights(policified_vehicle)
        else
            restore_additional_lights(policified_vehicle)
        end
    end
end, true)

util.create_tick_handler(function()
    return true
end)
