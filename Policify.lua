-- Policify
-- by Hexarobi
-- Enable Policify option to modify current vehicle, disable option to remove modifications
-- Modifies horn, paint, ne[on, and headlights. Flashes headlights and neon between red and blue.

local SCRIPT_VERSION = "2.4.1"

local auto_update_source_url = "https://raw.githubusercontent.com/hexarobi/stand-lua-policify/main/Policify.lua"
local status, lib = pcall(require, "auto-updater")
if not status then
    async_http.init("raw.githubusercontent.com", "/hexarobi/stand-lua-auto-updater/main/auto-updater.lua",
        function(result, headers, status_code) local error_prefix = "Error downloading auto-updater: "
            if status_code ~= 200 then util.toast(error_prefix..status_code) return false end
            if not result or result == "" then util.toast(error_prefix.."Found empty file.") return false end
            local file = io.open(filesystem.scripts_dir() .. "lib\\auto-updater.lua", "wb")
            if file == nil then util.toast(error_prefix.."Could not open file for writing.") return false end
            file:write(result) file:close() util.toast("Successfully installed auto-updater lib")
        end, function() util.toast("Error downloading auto-updater lib. Update failed to download.") end)
    async_http.dispatch() util.yield(3000) require("auto-updater")
end
run_auto_update({source_url=auto_update_source_url, script_relpath=SCRIPT_RELPATH, verify_file_begins_with="--"})

util.require_natives(1660775568)

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

local attachments = {}
local attached_invis_police_sirens = {}

local config = {
    plate_text = "FIB",
    siren_attachment = {
        name="Police Cruiser",
        model="policeb",
    }
}

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
        name="Lights",
        objects={
            {
                name = "Red Spinning Light",
                model = "hei_prop_wall_light_10a_cr",
                offset = { x = 0, y = 0, z = 1 },
                rotation = { x = 180, y = 0, z = 0 },
                is_light_disabled = true,
                children = {
                    {
                        model = "prop_wall_light_10a",
                        offset = { x = 0, y = 0.01, z = 0 },
                        is_light_disabled = false,
                        bone_index = 1,
                    },
                },
            },
            {
                name = "Blue Spinning Light",
                model = "hei_prop_wall_light_10a_cr",
                offset = { x = 0, y = 0, z = 1 },
                rotation = { x = 180, y = 0, z = 0 },
                is_light_disabled = true,
                children = {
                    {
                        model = "prop_wall_light_10b",
                        offset = { x = 0, y = 0.01, z = 0 },
                        is_light_disabled = false,
                        bone_index = 1,
                    },
                },
            },
            {
                name = "Yellow Spinning Light",
                model = "hei_prop_wall_light_10a_cr",
                offset = { x = 0, y = 0, z = 1 },
                rotation = { x = 180, y = 0, z = 0 },
                is_light_disabled = true,
                children = {
                    {
                        model = "prop_wall_light_10c",
                        offset = { x = 0, y = 0.01, z = 0 },
                        is_light_disabled = false,
                        bone_index = 1,
                    },
                },
            },

            {
                name = "Pair of Spinning Lights",
                model = "hei_prop_wall_light_10a_cr",
                offset = { x = 0.3, y = 0, z = 1 },
                rotation = { x = 180, y = 0, z = 0 },
                is_light_disabled = true,
                children = {
                    {
                        model = "prop_wall_light_10b",
                        offset = { x = 0, y = 0.01, z = 0 },
                        is_light_disabled = false,
                        bone_index = 1,
                    },
                },
                reflection = {
                    model = "hei_prop_wall_light_10a_cr",
                    reflection_axis = { x = true, y = false, z = false },
                    is_light_disabled = true,
                    children = {
                        {
                            model = "prop_wall_light_10a",
                            offset = { x = 0, y = 0.01, z = 0 },
                            rotation = { x = 0, y = 0, z = 180 },
                            is_light_disabled = false,
                            bone_index = 1,
                        },
                    },
                }
            },

            {
                name = "Short Spinning Red Light",
                model = "hei_prop_wall_alarm_on",
                offset = { x = 0, y = 0, z = 1 },
                rotation = { x = -90, y = 0, z = 0 },
            },

            {
                name = "Blue Recessed Light",
                model = "h4_prop_battle_lights_floorblue",
                offset = { x = 0, y = 0, z = 0.75 },
            },
            {
                name = "Red Recessed Light",
                model = "h4_prop_battle_lights_floorred",
                offset = { x = 0, y = 0, z = 0.75 },
            },
            {
                name = "Red/Blue Pair of Recessed Lights",
                model = "h4_prop_battle_lights_floorred",
                offset = { x = 0.3, y = 0, z = 1 },
                reflection = {
                    model = "h4_prop_battle_lights_floorblue",
                    reflection_axis = { x = true, y = false, z = false },
                }
            },
            {
                name = "Blue/Red Pair of Recessed Lights",
                model = "h4_prop_battle_lights_floorblue",
                offset = { x = 0.3, y = 0, z = 1 },
                reflection = {
                    model = "h4_prop_battle_lights_floorred",
                    reflection_axis = { x = true, y = false, z = false },
                }
            },

            -- Flashing is still kinda wonky for networking
            {
                name="Flashing Recessed Lights",
                model="h4_prop_battle_lights_floorred",
                offset={ x=0.3, y=0, z=1 },
                flash_start_on=false,
                reflection={
                    model="h4_prop_battle_lights_floorblue",
                    reflection_axis={ x=true, y=false, z=false },
                    flash_start_on=true,
                }
            },
            {
                name="Alternating Pair of Recessed Lights",
                model="h4_prop_battle_lights_floorred",
                offset={ x=0.3, y=0, z=1 },
                flash_start_on=true,
                flash_model="h4_prop_battle_lights_floorblue",
                reflection={
                    model="h4_prop_battle_lights_floorred",
                    reflection_axis={ x=true, y=false, z=false },
                    flash_start_on=false,
                    flash_model="h4_prop_battle_lights_floorblue",
                }
            }
        },
    },
    {
        name="Props",
        objects = {
            {
                name = "Riot Shield",
                model = "prop_riot_shield",
                offset = { x = 0, y = 0, z = 0 },
                rotation = { x = 180, y = 180, z = 0 },
            },
            {
                name = "Ballistic Shield",
                model = "prop_ballistic_shield",
                offset = { x = 0, y = 0, z = 0 },
                rotation = { x = 180, y = 180, z = 0 },
            },
            {
                name = "Minigun",
                model = "prop_minigun_01",
                offset = { x = 0, y = 0, z = 0 },
                rotation = { x = 0, y = 0, z = 90 },
            },
        },
    },
    {
        name="Vehicles",
        objects={
            {
                name = "Police Cruiser",
                type = "vehicle",
                model = "police",
            },
            {
                name = "Police Buffalo",
                type = "vehicle",
                model = "police2",
            },
            {
                name = "Police Sports",
                type = "vehicle",
                model = "police3",
            },
            {
                name = "Police Van",
                type = "vehicle",
                model = "policet",
            },
            {
                name = "Police Bike",
                type = "vehicle",
                model = "policeb",
            },
            {
                name = "FIB Cruiser",
                type = "vehicle",
                model = "fbi",
            },
            {
                name = "FIB SUV",
                type = "vehicle",
                model = "fbi2",
            },
            {
                name = "Sheriff Cruiser",
                type = "vehicle",
                model = "sheriff",
            },
            {
                name = "Sheriff SUV",
                type = "vehicle",
                model = "sheriff2",
            },
            {
                name = "Unmarked Cruiser",
                type = "vehicle",
                model = "police3",
            },
            {
                name = "Snowy Rancher",
                type = "vehicle",
                model = "policeold1",
            },
            {
                name = "Snowy Cruiser",
                type = "vehicle",
                model = "policeold2",
            },
            {
                name = "Park Ranger",
                type = "vehicle",
                model = "pranger",
            },
            {
                name = "Riot Van",
                type = "vehicle",
                model = "rior",
            },
            {
                name = "Riot Control Vehicle (RCV)",
                type = "vehicle",
                model = "riot2",
            },
        },
    },
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
        util.log("[attach_entity_to_entity] Error: Position or Rotation not set. " .. debug.traceback())
        return
    end
    if args.parent == args.handle then
        ENTITY.SET_ENTITY_ROTATION(args.handle, args.rotation.x or 0, args.rotation.y or 0, args.rotation.z or 0)
    else
        ENTITY.ATTACH_ENTITY_TO_ENTITY(
            args.handle, args.parent or args.root, args.bone_index or 0,
            args.offset.x or 0, args.offset.y or 0, args.offset.z or 0,
            args.rotation.x or 0, args.rotation.y or 0, args.rotation.z or 0,
            false, true, false, false, 2, true
        )
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
        args.handle = OBJECT.CREATE_OBJECT_NO_OFFSET(hash, pos.x, pos.y, pos.z, true, true, false)
        --args.handle = entities.create_object(hash, ENTITY.GET_ENTITY_COORDS(args.root))
    end

    if args.is_visible ~= nil then
        ENTITY.SET_ENTITY_VISIBLE(args.handle, args.is_visible, 0)
    end
    if args.flash_start_on ~= nil then
        ENTITY.SET_ENTITY_VISIBLE(args.handle, args.flash_start_on, 0)
    end

    ENTITY.SET_ENTITY_INVINCIBLE(args.handle, false)
    ENTITY.SET_ENTITY_HAS_GRAVITY(args.handle, false)

    attach_entity_to_entity(args)

    ENTITY.SET_ENTITY_NO_COLLISION_ENTITY(args.root, args.handle)
    for _, attachment in pairs(attachments) do
        ENTITY.SET_ENTITY_NO_COLLISION_ENTITY(args.handle, attachment.handle)
    end
    table.insert(attachments, args)

    ENTITY.FREEZE_ENTITY_POSITION(args.root, false)

    return args
end

local function get_reflection_with_offsets(attachment)
    --- This function isn't quite right, it breaks with certain root rotations, but close enough for now
    local reflection = attachment.reflection
    reflection.parent = attachment.handle
    reflection.offset = {x=0, y=0, z=0}
    reflection.rotation = {x=0, y=0, z=0}
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
    if attachment.spawned_children then
        for _, child in pairs(attachment.spawned_children) do
            detach(child)
        end
    end
    for i, attachment2 in pairs(attachments) do
        if attachment2.handle == attachment.handle then
            table.remove(attachments, i)
        end
    end
    entities.delete_by_handle(attachment.handle)
end

function table.table_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = setmetatable({}, getmetatable(obj))
    for k, v in pairs(obj) do res[table.table_copy(k)] = table.table_copy(v) end
    return res
end

function table.is_equal( a, b )
    return table.concat(a) == table.concat(b)
end

local attachment_counter
local attachment_name
local function attach_available_attachment_to_vehicle(root_vehicle, available_attachment)
    attachment_counter = attachment_counter + 1
    local attachment_args = table.table_copy(available_attachment)
    attachment_args.root = root_vehicle
    if attachment_name == nil then
        attachment_name = available_attachment.name
    end
    if attachment_counter == 1 then
        attachment_args.name = attachment_name .. " (Base)"
    else
        attachment_args.name = attachment_name .. " (Child #" .. attachment_counter-1 .. ")"
    end
    local attachment = attach(attachment_args)
    attachment_args.spawned_children = {}
    if available_attachment.children then
        for _, child in pairs(available_attachment.children) do
            child.parent = attachment.handle
            local spawned = attach_available_attachment_to_vehicle(root_vehicle, child)
            table.insert(attachment_args.spawned_children, spawned)
        end
    end
    if attachment.flash_model then
        local flash_version = {
            model=attachment.flash_model,
            flash_start_on=(not attachment.flash_start_on),
            parent=attachment.handle
        }
        local spawned = attach_available_attachment_to_vehicle(root_vehicle, flash_version)
        table.insert(attachment_args.spawned_children, spawned)
    end
    if attachment_args.reflection then
        local reflection = get_reflection_with_offsets(attachment_args)
        local spawned = attach_available_attachment_to_vehicle(root_vehicle, reflection)
        table.insert(attachment_args.spawned_children, spawned)
    end
    return attachment
end

local function attach_invis_police_sirens(vehicle)
    local attachment = attach{
        root=vehicle,
        parent=vehicle,
        name=config.siren_attachment.name,
        attachments=attachments,
        model=config.siren_attachment.model,
        type="vehicle",
        is_visible=false
    }
    table.insert(attached_invis_police_sirens, attachment.handle)

    local ped_hash = util.joaat("s_m_m_pilot_01")
    load_hash(ped_hash)
    local pos = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(attachment.handle, 0, 0, 0)
    local pilot = entities.create_ped(1, ped_hash, pos, 0.0)
    PED.SET_PED_INTO_VEHICLE(pilot, attachment.handle, -1)
    ENTITY.SET_ENTITY_VISIBLE(pilot, false, 0)
    table.insert(attached_invis_police_sirens, pilot)
end

local function remove_invis_police_sirens(vehicle)
    for _, handle in pairs(attached_invis_police_sirens) do
        entities.delete_by_handle(handle)
    end
    attached_invis_police_sirens = {}
end

local function refresh_invis_police_sirens(vehicle)
    remove_invis_police_sirens(vehicle)
    attach_invis_police_sirens(vehicle)
end

local function remove_all_attachments(vehicle)
    for _, attachment in pairs(attachments) do
        if attachment.spawned_children then
            for _, child in pairs(attachment.spawned_children) do
                entities.delete_by_handle(child.handle)
            end
        end
        entities.delete_by_handle(attachment.handle)
    end
    attachments = {}
end

local function activate_lights(vehicle)
    VEHICLE.SET_VEHICLE_SIREN(vehicle, true)
    VEHICLE.SET_VEHICLE_HAS_MUTED_SIRENS(vehicle, true)
    ENTITY.SET_ENTITY_LIGHTS(vehicle, false)
    AUDIO._TRIGGER_SIREN(vehicle, true)
    AUDIO._SET_SIREN_KEEP_ON(vehicle, true)
    for _, attachment in pairs(attachments) do
        if not attachment.is_light_disabled then
            VEHICLE.SET_VEHICLE_SIREN(attachment.handle, true)
            ENTITY.SET_ENTITY_LIGHTS(attachment.handle, false)
            AUDIO._TRIGGER_SIREN(attachment.handle, true)
            AUDIO._SET_SIREN_KEEP_ON(attachment.handle, true)
        end
    end
end

local function deactivate_lights(vehicle)
    ENTITY.SET_ENTITY_LIGHTS(vehicle, true)
    AUDIO._SET_SIREN_KEEP_ON(vehicle, false)
    VEHICLE.SET_VEHICLE_SIREN(vehicle, false)
    for _, attachment in pairs(attachments) do
        ENTITY.SET_ENTITY_LIGHTS(attachment.handle, true)
        VEHICLE.SET_VEHICLE_SIREN(attachment.handle, false)
    end
end

local function activate_vehicle_sirens(vehicle)
    --AUDIO.SET_SIREN_WITH_NO_DRIVER(vehicle, true)
    VEHICLE.SET_VEHICLE_HAS_MUTED_SIRENS(vehicle, false)
    VEHICLE.SET_VEHICLE_SIREN(vehicle, true)
    AUDIO._TRIGGER_SIREN(vehicle, true)
    AUDIO._SET_SIREN_KEEP_ON(vehicle, true)
end

local function deactivate_vehicle_sirens(vehicle)
    --AUDIO._SET_SIREN_KEEP_ON(vehicle, false)
    VEHICLE.SET_VEHICLE_HAS_MUTED_SIRENS(vehicle, true)
    --VEHICLE.SET_VEHICLE_SIREN(vehicle, false)
end

local function activate_sirens(vehicle)
    activate_vehicle_sirens(vehicle)
    for _, attachment in pairs(attachments) do
        if ENTITY.IS_ENTITY_A_VEHICLE(attachment.handle) then
            activate_vehicle_sirens(attachment.handle)
        end
    end
end

local function deactivate_sirens(vehicle)
    deactivate_vehicle_sirens(vehicle)
    for _, attachment in pairs(attachments) do
        if ENTITY.IS_ENTITY_A_VEHICLE(attachment.handle) then
            deactivate_vehicle_sirens(attachment.handle)
        end
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
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(vehicle, config.plate_text)
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
local attach_invis_police_siren = true
local is_active_sirens = false
local is_active_lights = false
local siren_setting = 1

local function refresh_siren_light_status(vehicle)
    if is_active_lights then
        activate_lights(vehicle)
    else
        deactivate_lights(vehicle)
    end
    if is_active_sirens then
        activate_sirens(vehicle)
    else
        deactivate_sirens(vehicle)
    end
end

local function refresh_plate_text(vehicle)
    if override_plate then
        set_plate(vehicle)
    else
        restore_plate(vehicle)
    end
end

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

    if attach_invis_police_siren then
        attach_invis_police_sirens(vehicle)
    end

    --AUDIO.USE_SIREN_AS_HORN(vehicle, true)
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
    if attach_invis_police_siren then
        remove_invis_police_sirens(vehicle)
    end
    remove_all_attachments(vehicle)
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
    for _, attachment in pairs(attachments) do
        if attachment.flash_start_on ~= nil then
            ENTITY.SET_ENTITY_VISIBLE(attachment.handle, (not attachment.flash_start_on), 0)
        end
    end
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
    for _, attachment in pairs(attachments) do
        if attachment.flash_start_on ~= nil then
            ENTITY.SET_ENTITY_VISIBLE(attachment.handle, attachment.flash_start_on, 0)
        end
    end
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
    refresh_siren_light_status(vehicle)

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

local edit_attachments_menu

local function rebuild_edit_attachments_menu()
    local new_attachment_menus = {}
    for _, attachment in pairs(attachments) do
        if not attachment.is_added_to_edit_menu then
            local edit_menu = menu.list(edit_attachments_menu, attachment.name or "unknow")
            menu.divider(edit_menu, "Position")
            local focus = menu.slider_float(edit_menu, "X: Left / Right", {}, "", -500000, 500000, math.floor(attachment.offset.x * 100), 1, function(value)
                attachment.offset.x = value / 100
                move_attachment(attachment)
            end)
            menu.slider_float(edit_menu, "Y: Forward / Back", {}, "", -500000, 500000, math.floor(attachment.offset.y * -100), 1, function(value)
                attachment.offset.y = value / -100
                move_attachment(attachment)
            end)
            menu.slider_float(edit_menu, "Z: Up / Down", {}, "", -500000, 500000, math.floor(attachment.offset.z * -100), 1, function(value)
                attachment.offset.z = value / -100
                move_attachment(attachment)
            end)
            menu.divider(edit_menu, "Rotation")
            menu.slider(edit_menu, "X: Pitch", {}, "", -175, 180, math.floor(attachment.rotation.x), 5, function(value)
                attachment.rotation.x = value
                move_attachment(attachment)
            end)
            menu.slider(edit_menu, "Y: Roll", {}, "", -175, 180, math.floor(attachment.rotation.y), 5, function(value)
                attachment.rotation.y = value
                move_attachment(attachment)
            end)
            menu.slider(edit_menu, "Z: Yaw", {}, "", -175, 180, math.floor(attachment.rotation.z), 5, function(value)
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
                rebuild_edit_attachments_menu()
            end)
            attachment.is_added_to_edit_menu = true
            table.insert(new_attachment_menus, focus)
        end
    end
    return new_attachment_menus[1]
end

---
--- Menu Options
---

menu.toggle(menu.my_root(), "Policify Vehicle", {"policify"}, "Enable Policify options on current vehicle", function(on)
    if on then
        policify_current_vehicle()
        rebuild_edit_attachments_menu()
    else
        depolicify_vehicle()
    end
end)

menu.action(menu.my_root(), "Siren Warning Blip", {"blip"}, "A quick siren blip to gain attention", function()
    for _, attachment in pairs(attachments) do
        if attachment.type == "vehicle" then
            AUDIO.BLIP_SIREN(attachment.handle)
            return
        end
    end
end)

--POLICE_REPORTS = {
--    "DLC_GR_Div_Scanner",
--    "LAMAR_1_POLICE_LOST",
--    "SCRIPTED_SCANNER_REPORT_AH_3B_01",
--    "SCRIPTED_SCANNER_REPORT_AH_MUGGING_01",
--    "SCRIPTED_SCANNER_REPORT_AH_PREP_01",
--    "SCRIPTED_SCANNER_REPORT_AH_PREP_02",
--    "SCRIPTED_SCANNER_REPORT_ARMENIAN_1_01",
--    "SCRIPTED_SCANNER_REPORT_ARMENIAN_1_02",
--    "SCRIPTED_SCANNER_REPORT_ASS_BUS_01",
--    "SCRIPTED_SCANNER_REPORT_ASS_MULTI_01",
--    "SCRIPTED_SCANNER_REPORT_BARRY_3A_01",
--    "SCRIPTED_SCANNER_REPORT_BS_2A_01",
--    "SCRIPTED_SCANNER_REPORT_BS_2B_01",
--    "SCRIPTED_SCANNER_REPORT_BS_2B_02",
--    "SCRIPTED_SCANNER_REPORT_BS_2B_03",
--    "SCRIPTED_SCANNER_REPORT_BS_2B_04",
--    "SCRIPTED_SCANNER_REPORT_BS_PREP_A_01",
--    "SCRIPTED_SCANNER_REPORT_BS_PREP_B_01",
--    "SCRIPTED_SCANNER_REPORT_CAR_STEAL_2_01",
--    "SCRIPTED_SCANNER_REPORT_CAR_STEAL_4_01",
--    "SCRIPTED_SCANNER_REPORT_DH_PREP_1_01",
--    "SCRIPTED_SCANNER_REPORT_FIB_1_01",
--    "SCRIPTED_SCANNER_REPORT_FIN_C2_01",
--    "SCRIPTED_SCANNER_REPORT_Franklin_2_01",
--    "SCRIPTED_SCANNER_REPORT_FRANLIN_0_KIDNAP",
--    "SCRIPTED_SCANNER_REPORT_GETAWAY_01",
--    "SCRIPTED_SCANNER_REPORT_JOSH_3_01",
--    "SCRIPTED_SCANNER_REPORT_JOSH_4_01",
--    "SCRIPTED_SCANNER_REPORT_JSH_2A_01",
--    "SCRIPTED_SCANNER_REPORT_JSH_2A_02",
--    "SCRIPTED_SCANNER_REPORT_JSH_2A_03",
--    "SCRIPTED_SCANNER_REPORT_JSH_2A_04",
--    "SCRIPTED_SCANNER_REPORT_JSH_2A_05",
--    "SCRIPTED_SCANNER_REPORT_JSH_PREP_1A_01",
--    "SCRIPTED_SCANNER_REPORT_JSH_PREP_1B_01",
--    "SCRIPTED_SCANNER_REPORT_JSH_PREP_2A_01",
--    "SCRIPTED_SCANNER_REPORT_JSH_PREP_2A_02",
--    "SCRIPTED_SCANNER_REPORT_LAMAR_1_01",
--    "SCRIPTED_SCANNER_REPORT_MIC_AMANDA_01",
--    "SCRIPTED_SCANNER_REPORT_NIGEL_1A_01",
--    "SCRIPTED_SCANNER_REPORT_NIGEL_1D_01",
--    "SCRIPTED_SCANNER_REPORT_PS_2A_01",
--    "SCRIPTED_SCANNER_REPORT_PS_2A_02",
--    "SCRIPTED_SCANNER_REPORT_PS_2A_03",
--    "SCRIPTED_SCANNER_REPORT_SEC_TRUCK_01",
--    "SCRIPTED_SCANNER_REPORT_SEC_TRUCK_02",
--    "SCRIPTED_SCANNER_REPORT_SEC_TRUCK_03",
--    "SCRIPTED_SCANNER_REPORT_SIMEON_01",
--    "SCRIPTED_SCANNER_REPORT_Sol_3_01",
--    "SCRIPTED_SCANNER_REPORT_Sol_3_02"
--}
--
--chat_commands.add{
--    command="report",
--    help="Play a random police report",
--    func=function(pid, commands)
--        AUDIO.PLAY_POLICE_REPORT("SCRIPTED_SCANNER_REPORT_SEC_TRUCK_02", 1)
--        AUDIO.START_AUDIO_SCENE("SCRIPTED_SCANNER_REPORT_SEC_TRUCK_02")
--    end
--}

--menu.action(menu.my_root(), "Police Report", {}, "Play police report", function()
--    --AUDIO.SET_AUDIO_FLAG("AllowPoliceScannerWhenPlayerHasNoControl", 0)
--    --AUDIO.SET_AUDIO_FLAG("OnlyAllowScriptTriggerPoliceScanner", 0)
--    --AUDIO.SET_AUDIO_FLAG("PoliceScannerDisabled", 1)
--    AUDIO.SET_AUDIO_FLAG("IsDirectorModeActive", 1)
--    AUDIO.PLAY_POLICE_REPORT("LAMAR_1_POLICE_LOST", 0)
--
--end)

menu.list_select(menu.my_root(), "Sirens", {}, "", {"Off", "Lights Only", "Sirens and Lights"}, 1, function(key)
    if key == 1 then
        is_active_lights = false
        is_active_sirens = false
    elseif key == 2 then
        is_active_lights = true
        is_active_sirens = false
    elseif key == 3 then
        is_active_lights = true
        is_active_sirens = true
    end
    if is_active_lights then
        save_headlights(policified_vehicle)
        save_neon(policified_vehicle)
    else
        restore_headlights(policified_vehicle)
        restore_neon(policified_vehicle)
    end
    refresh_siren_light_status(policified_vehicle)
end)

menu.action(menu.my_root(), "Call for Backup", {}, "Call for backup from nearby units", function(toggle)
    local incident_id = memory.alloc(8)
    MISC.CREATE_INCIDENT_WITH_ENTITY(7, PLAYER.PLAYER_PED_ID(), 3, 3, incident_id)
    AUDIO.PLAY_POLICE_REPORT("SCRIPTED_SCANNER_REPORT_PS_2A_01", 0)
end, true)

local attach_additional_lights_menu = menu.list(menu.my_root(), "Add Attachment")
edit_attachments_menu = menu.list(menu.my_root(), "Edit Attachments")

for _, category in pairs(available_attachments) do
    local category_menu = menu.list(attach_additional_lights_menu, category.name)
    for _, available_attachment in pairs(category.objects) do
        menu.action(category_menu, available_attachment.name, {}, "", function()
            attachment_counter = 0
            attachment_name = nil
            attach_available_attachment_to_vehicle(policified_vehicle, available_attachment, attachments)
            refresh_siren_light_status()
            menu.focus(rebuild_edit_attachments_menu())
        end)
    end
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

menu.toggle(options_menu, "Override Plate", {}, "If enabled, will override vehicle plate with custom exempt plate", function(toggle)
    override_plate = toggle
    if policify_tick_counter ~= nil then
        if override_plate then
            save_plate(policified_vehicle)
        end
        refresh_plate_text(policified_vehicle)
    end
end, true)

menu.text_input(options_menu, "Set Plate Text", {"setpoliceplatetext"}, "Set the text for the exempt police plates", function(value)
    config.plate_text = value
    refresh_plate_text(policified_vehicle)
end, config.plate_text)

menu.toggle(options_menu, "Enable Invis Siren", {}, "If enabled, will attach an invisible emergency vehicle to give any vehicle sirens.", function(toggle)
    attach_invis_police_siren = toggle
    if policify_tick_counter ~= nil then
        if attach_invis_police_siren then
            attach_invis_police_sirens(policified_vehicle)
            refresh_siren_light_status(policified_vehicle)
            rebuild_edit_attachments_menu()
        else
            remove_invis_police_sirens(policified_vehicle)
        end
    end
end, true)

local siren_types = {
    {
        "Police Cruiser",
        {},
        "A slow wail",
        "police",
    },
    {
        "Police Bike",
        {},
        "A fast chirp",
        "policeb",
    },
    {
        "Ambulance",
        {},
        "A slightly different wail",
        "ambulance",
    },
}

menu.list_select(options_menu, "Invis Siren Type", {}, "Different siren types have slightly different sounds", siren_types, 1, function(index, name)
    local siren_type = siren_types[index]
    config.siren_attachment = {
        name=siren_type[1],
        model=siren_type[4]
    }
    if policified_vehicle ~= nil then
        refresh_invis_police_sirens(policified_vehicle)
        refresh_siren_light_status(policified_vehicle)
    end
end)

local script_meta_menu = menu.list(menu.my_root(), "Script Meta")

menu.divider(script_meta_menu, "Policify")
menu.readonly(script_meta_menu, "Version", SCRIPT_VERSION)

util.create_tick_handler(function()
    return true
end)
