-- Policify
-- by Hexarobi
-- Turns any vehicle into a police vehicle, with controllable flashing lights and sirens.
-- Save and share your policified vehicles.
-- https://github.com/hexarobi/stand-lua-policify

local SCRIPT_VERSION = "3.0"
local AUTO_UPDATE_BRANCHES = {
    { "main", {}, "More stable, but updatbed less often.", "main", },
    { "dev", {}, "Cutting edge updates, but less stable.", "dev", },
}
local SELECTED_BRANCH_INDEX = 2

---
--- Auto-Updater
---

local auto_update_source_url = "https://raw.githubusercontent.com/hexarobi/stand-lua-policify/main/Policify.lua"

-- Auto Updater from https://github.com/hexarobi/stand-lua-auto-updater
local status, lib = pcall(require, "auto-updater")
if not status then
    auto_update_complete = nil util.toast("Installing auto-updater...", TOAST_ALL)
    async_http.init("raw.githubusercontent.com", "/hexarobi/stand-lua-auto-updater/main/auto-updater.lua",
            function(result, headers, status_code)
                local function parse_auto_update_result(result, headers, status_code)
                    local error_prefix = "Error downloading auto-updater: "
                    if status_code ~= 200 then util.toast(error_prefix..status_code, TOAST_ALL) return false end
                    if not result or result == "" then util.toast(error_prefix.."Found empty file.", TOAST_ALL) return false end
                    local file = io.open(filesystem.scripts_dir() .. "lib\\auto-updater.lua", "wb")
                    if file == nil then util.toast(error_prefix.."Could not open file for writing.", TOAST_ALL) return false end
                    file:write(result) file:close() util.toast("Successfully installed auto-updater lib", TOAST_ALL) return true
                end
                auto_update_complete = parse_auto_update_result(result, headers, status_code)
            end, function() util.toast("Error downloading auto-updater lib. Update failed to download.", TOAST_ALL) end)
    async_http.dispatch() local i = 1 while (auto_update_complete == nil and i < 10) do util.yield(250) i = i + 1 end
    require("auto-updater")
end

local function auto_update_branch(selected_branch)
    local branch_source_url = auto_update_source_url:gsub("/main/", "/"..selected_branch.."/")
    run_auto_update({source_url=branch_source_url, script_relpath=SCRIPT_RELPATH, verify_file_begins_with="--"})
end
auto_update_branch(AUTO_UPDATE_BRANCHES[SELECTED_BRANCH_INDEX][1])

---
--- Data
---

local SIRENS_OFF = 1
local SIRENS_LIGHTS_ONLY = 2
local SIRENS_ALL_ON = 3

local config = {
    flash_delay = 50,
    override_paint = true,
    override_headlights = true,
    override_neon = true,
    override_plate = true,
    override_horn = true,
    override_light_multiplier = 1,
    attach_invis_police_siren = true,
    plate_text = "FIB",
    siren_attachment = {
        name = "Police Cruiser",
        model = "police",
    },
    source_code_branch = "main",
    edit_offset_step = 1,
    edit_rotation_step = 1,
}

local VEHICLE_STORE_DIR = filesystem.store_dir() .. 'Policify\\vehicles\\'

local function ensure_directory_exists(path)
    path = path:gsub("\\", "/")
    local dirpath = ""
    for dirname in path:gmatch("[^/]+") do
        dirpath = dirpath .. dirname .. "/"
        if not filesystem.exists(dirpath) then filesystem.mkdir(dirpath) end
    end
end
ensure_directory_exists(VEHICLE_STORE_DIR)

local policified_vehicles = {}
local last_policified_vehicle

--local example_policified_vehicle = {
--    name="Police",
--    model="police",
--    handle=1234,
--    options = {},
--    save_data = {},
--    attachments = {},
--}
--
--local example_attachment = {
--    name="Child #1",            -- Name for this attachment
--    handle=5678,                -- Handle for this attachment
--    root=example_policified_vehicle,
--    parent=1234,                -- Parent Handle
--    bone_index = 0,             -- Which bone of the parent should this attach to
--    offset = { x=0, y=0, z=0 },  -- Offset coords from parent
--    rotation = { x=0, y=0, z=0 },-- Rotation from parent
--    children = {
--        -- Other attachments
--        reflection_axis = { x = true, y = false, z = false },   -- Which axis should be reflected about
--    },
--    is_visible = true,
--    has_collision = true,
--    has_gravity = true,
--    is_light_disabled = true,   -- If true this light will always be off, regardless of siren settings
--}

local policified_vehicle_base = {
    target_version = SCRIPT_VERSION,
    children = {},
    options = {
        override_paint = config.override_paint,
        override_headlights = config.override_headlights,
        override_neon = config.override_neon,
        override_plate = config.override_plate,
        override_horn = config.override_horn,
        override_light_multiplier = config.override_light_multiplier,
        attach_invis_police_siren = config.attach_invis_police_siren,
        plate_text = config.plate_text,
        siren_attachment = config.siren_attachment,
        siren_status = SIRENS_OFF,
    },
    save_data = {
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
        },
    },
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
        name = "Lights",
        objects = {
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
                name = "Combo Red+Blue Spinning Light",
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
                    {
                        model = "prop_wall_light_10a",
                        offset = { x = 0, y = 0.01, z = 0 },
                        rotation = { x = 0, y = 0, z = 180 },
                        is_light_disabled = false,
                        bone_index = 1,
                    },
                },
                --reflection = {
                --    model = "hei_prop_wall_light_10a_cr",
                --    reflection_axis = { x = true, y = false, z = false },
                --    is_light_disabled = true,
                --    children = {
                --        {
                --            model = "prop_wall_light_10a",
                --            offset = { x = 0, y = 0.01, z = 0 },
                --            rotation = { x = 0, y = 0, z = 180 },
                --            is_light_disabled = false,
                --            bone_index = 1,
                --        },
                --    },
                --}
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
                    {
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
            },

            {
                name = "Short Spinning Red Light",
                model = "hei_prop_wall_alarm_on",
                offset = { x = 0, y = 0, z = 1 },
                rotation = { x = -90, y = 0, z = 0 },
            },
            {
                name = "Small Red Warning Light",
                model = "prop_warninglight_01",
                offset = { x = 0, y = 0, z = 1 },
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
                children = {
                    {
                        model = "h4_prop_battle_lights_floorblue",
                        reflection_axis = { x = true, y = false, z = false },
                    }
                }
            },
            {
                name = "Blue/Red Pair of Recessed Lights",
                model = "h4_prop_battle_lights_floorblue",
                offset = { x = 0.3, y = 0, z = 1 },
                children = {
                    {
                        model = "h4_prop_battle_lights_floorred",
                        reflection_axis = { x = true, y = false, z = false },
                    }
                }
            },

            -- Flashing is still kinda wonky for networking
            {
                name = "Flashing Recessed Lights",
                model = "h4_prop_battle_lights_floorred",
                offset = { x = 0.3, y = 0, z = 1 },
                flash_start_on = false,
                children = {
                    {
                        model = "h4_prop_battle_lights_floorblue",
                        reflection_axis = { x = true, y = false, z = false },
                        flash_start_on = true,
                    }
                }
            },
            {
                name = "Alternating Pair of Recessed Lights",
                model = "h4_prop_battle_lights_floorred",
                offset = { x = 0.3, y = 0, z = 1 },
                flash_start_on = true,
                children = {
                    {
                        model = "h4_prop_battle_lights_floorred",
                        reflection_axis = { x = true, y = false, z = false },
                        flash_start_on = false,
                        children = {
                            {
                                model = "h4_prop_battle_lights_floorblue",
                                flash_start_on = true,
                            }
                        }
                    },
                    {
                        model = "h4_prop_battle_lights_floorblue",
                        flash_start_on = true,
                    }
                }
            },

            {
                name = "Red Disc Light",
                model = "prop_runlight_r",
                offset = { x = 0, y = 0, z = 1 },
            },
            {
                name = "Blue Disc Light",
                model = "prop_runlight_b",
                offset = { x = 0, y = 0, z = 1 },
            },

            {
                name = "Blue Pole Light",
                model = "prop_air_lights_02a",
                offset = { x = 0, y = 0, z = 1 },
            },
            {
                name = "Red Pole Light",
                model = "prop_air_lights_02b",
                offset = { x = 0, y = 0, z = 1 },
            },

            {
                name = "Red Angled Light",
                model = "prop_air_lights_04a",
                offset = { x = 0, y = 0, z = 1 },
            },
            {
                name = "Blue Angled Light",
                model = "prop_air_lights_05a",
                offset = { x = 0, y = 0, z = 1 },
            },

            {
                name = "Cone Light",
                model = "prop_air_conelight",
                offset = { x = 0, y = 0, z = 1 },
                rotation = { x = 0, y = 0, z = 0 },
            },

            -- This is actually 2 lights, spaced 20 feet apart.
            --{
            --    name="Blinking Red Light",
            --    model="hei_prop_carrier_docklight_01",
            --}
        },
    },
    {
        name = "Props",
        objects = {
            {
                name = "Riot Shield",
                model = "prop_riot_shield",
                rotation = { x = 180, y = 180, z = 0 },
            },
            {
                name = "Ballistic Shield",
                model = "prop_ballistic_shield",
                rotation = { x = 180, y = 180, z = 0 },
            },
            {
                name = "Minigun",
                model = "prop_minigun_01",
                rotation = { x = 0, y = 0, z = 90 },
            },
            {
                name = "Monitor Screen",
                model = "hei_prop_hei_monitor_police_01",
            },
            {
                name = "Bomb",
                model = "prop_ld_bomb_anim",
            },
            {
                name = "Bomb (open)",
                model = "prop_ld_bomb_01_open",
            },


        },
    },
    {
        name = "Vehicles",
        objects = {
            {
                name = "Police Cruiser",
                model = "police",
                type = "VEHICLE",
            },
            {
                name = "Police Buffalo",
                model = "police2",
                type = "VEHICLE",
            },
            {
                name = "Police Sports",
                model = "police3",
                type = "VEHICLE",
            },
            {
                name = "Police Van",
                model = "policet",
                type = "VEHICLE",
            },
            {
                name = "Police Bike",
                model = "policeb",
                type = "VEHICLE",
            },
            {
                name = "FIB Cruiser",
                model = "fbi",
                type = "VEHICLE",
            },
            {
                name = "FIB SUV",
                model = "fbi2",
                type = "VEHICLE",
            },
            {
                name = "Sheriff Cruiser",
                model = "sheriff",
                type = "VEHICLE",
            },
            {
                name = "Sheriff SUV",
                model = "sheriff2",
                type = "VEHICLE",
            },
            {
                name = "Unmarked Cruiser",
                model = "police3",
                type = "VEHICLE",
            },
            {
                name = "Snowy Rancher",
                model = "policeold1",
                type = "VEHICLE",
            },
            {
                name = "Snowy Cruiser",
                model = "policeold2",
                type = "VEHICLE",
            },
            {
                name = "Park Ranger",
                model = "pranger",
                type = "VEHICLE",
            },
            {
                name = "Riot Van",
                model = "rior",
                type = "VEHICLE",
            },
            {
                name = "Riot Control Vehicle (RCV)",
                model = "riot2",
                type = "VEHICLE",
            },
        },
    },
}

local siren_types = {
    { "Police Cruiser", {}, "The standard siren sound from a Police Cruiser", "police", },
    { "Police Bike", {}, "The fast chirp siren sound from a Police Bike", "policeb", },
    { "Ambulance", {}, "The siren sounds from an Ambulance", "ambulance", },
    { "Fire Truck", {}, "The siren sounds from a Fire Truck", "firetruk", },
}

---
--- Utilities
---

util.require_natives(1660775568)
local json = require("json")
--local inspect = require("inspect")

function table.table_copy(obj)
    if type(obj) ~= 'table' then
        return obj
    end
    local res = setmetatable({}, getmetatable(obj))
    for k, v in pairs(obj) do
        res[table.table_copy(k)] = table.table_copy(v)
    end
    return res
end

function string.starts(String,Start)
    return string.sub(String,1,string.len(Start))==Start
end

-- From https://stackoverflow.com/questions/12394841/safely-remove-items-from-an-array-table-while-iterating
local function array_remove(t, fnKeep)
    local j, n = 1, #t;

    for i=1,n do
        if (fnKeep(t, i, j)) then
            -- Move i's kept value to j's position, if it's not already there.
            if (i ~= j) then
                t[j] = t[i];
                t[i] = nil;
            end
            j = j + 1; -- Increment position of where we'll place the next kept value.
        else
            t[i] = nil;
        end
    end

    return t;
end

local function load_hash(hash)
    STREAMING.REQUEST_MODEL(hash)
    while not STREAMING.HAS_MODEL_LOADED(hash) do
        util.yield()
    end
end

---
--- Tick Phase
---

local phase_options = {
    headlight_colors = {1, 8},
    neon_colors = {{r=255,g=0,b=0}, {r=0,g=0,b=255}},
}

local function policify_tick_phase(attachment, phase)
    if attachment.root.options.siren_status == SIRENS_LIGHTS_ONLY or attachment.root.options.siren_status == SIRENS_ALL_ON then
        if attachment.root.options.override_headlights then
            VEHICLE._SET_VEHICLE_XENON_LIGHTS_COLOR(attachment.handle, phase_options.headlight_colors[phase])
        end
        if attachment.root.options.override_neon then
            local neon_color = phase_options.neon_colors[phase]
            VEHICLE._SET_VEHICLE_NEON_LIGHTS_COLOUR(attachment.handle, neon_color.r, neon_color.g, neon_color.b)
        end
    end
    if attachment.flash_start_on ~= nil then
        local flashing
        if phase == 1 then
            flashing = attachment.flash_start_on
        else
            flashing = not attachment.flash_start_on
        end
        ENTITY.SET_ENTITY_VISIBLE(attachment.handle, flashing, 0)
    end
    for _, child_attachment in pairs(attachment.children) do
        policify_tick_phase(child_attachment, phase)
    end
end

local tick_counter = 0
local function policify_tick()
    local phase = 1
    if tick_counter > config.flash_delay then phase = 2 end
    if tick_counter > (config.flash_delay * 2) then tick_counter = 0 end
    tick_counter = tick_counter + 1

    for _, policified_vehicle in pairs(policified_vehicles) do
        policify_tick_phase(policified_vehicle, phase)
    end
end


---
--- Specific Serializers
---

local function serialize_vehicle_headlights(vehicle, serialized_vehicle)
    if serialized_vehicle.headlights == nil then serialized_vehicle.headlights = {} end
    serialized_vehicle.headlights.headlights_color = VEHICLE._GET_VEHICLE_XENON_LIGHTS_COLOR(vehicle.handle)
    serialized_vehicle.headlights.headlights_type = VEHICLE.IS_TOGGLE_MOD_ON(vehicle.handle, 22)
    return serialized_vehicle
end

local function deserialize_vehicle_headlights(vehicle, serialized_vehicle)
    util.log("deserializing "..vehicle.name)
    --VEHICLE.SET_VEHICLE_LIGHTS(policified_vehicle.handle, 0)    -- Restore full headlight control
    VEHICLE._SET_VEHICLE_XENON_LIGHTS_COLOR(vehicle.handle, serialized_vehicle.headlights.headlights_color)
    VEHICLE.TOGGLE_VEHICLE_MOD(vehicle.handle, 22, serialized_vehicle.headlights.headlights_type or false)
end

local function serialize_vehicle_paint(vehicle, serialized_vehicle)
    if serialized_vehicle.paint == nil then
        serialized_vehicle.paint = {
            primary = {},
            secondary = {},
        }
    end

    -- Create pointers to hold color values
    local color = { r = memory.alloc(4), g = memory.alloc(4), b = memory.alloc(4) }

    VEHICLE.GET_VEHICLE_COLOR(vehicle, color.r, color.g, color.b)
    serialized_vehicle.paint.vehicle_custom_color = { r = memory.read_int(color.r), g = memory.read_int(color.g), b = memory.read_int(color.b) }
    VEHICLE.GET_VEHICLE_COLOURS(vehicle, color.r, color.g)
    serialized_vehicle.paint.primary.vehicle_standard_color = memory.read_int(color.r)
    serialized_vehicle.paint.secondary.vehicle_standard_color = memory.read_int(color.g)

    serialized_vehicle.paint.primary.is_custom = VEHICLE.GET_IS_VEHICLE_PRIMARY_COLOUR_CUSTOM(vehicle.handle)
    if serialized_vehicle.paint.primary.is_custom then
        VEHICLE.GET_VEHICLE_CUSTOM_PRIMARY_COLOUR(vehicle.handle, color.r, color.g, color.b)
        serialized_vehicle.paint.primary.custom_color = { r = memory.read_int(color.r), b = memory.read_int(color.g), g = memory.read_int(color.b) }
    else
        VEHICLE.GET_VEHICLE_MOD_COLOR_1(vehicle.handle, color.r, color.g, color.b)
        serialized_vehicle.paint.primary.paint_type = memory.read_int(color.r)
        serialized_vehicle.paint.primary.color = memory.read_int(color.g)
        serialized_vehicle.paint.primary.pearlescent_color = memory.read_int(color.b)
    end

    serialized_vehicle.paint.secondary.is_custom = VEHICLE.GET_IS_VEHICLE_SECONDARY_COLOUR_CUSTOM(vehicle.handle)
    if serialized_vehicle.paint.secondary.is_custom then
        VEHICLE.GET_VEHICLE_CUSTOM_SECONDARY_COLOUR(vehicle.handle, color.r, color.g, color.b)
        serialized_vehicle.paint.secondary.custom_color = { r = memory.read_int(color.r), b = memory.read_int(color.g), g = memory.read_int(color.b) }
    else
        VEHICLE.GET_VEHICLE_MOD_COLOR_2(vehicle.handle, color.r, color.g)
        serialized_vehicle.paint.secondary.paint_type = memory.read_int(color.r)
        serialized_vehicle.paint.secondary.color = memory.read_int(color.g)
    end

    VEHICLE.GET_VEHICLE_EXTRA_COLOURS(vehicle.handle, color.r, color.g)
    serialized_vehicle.paint.extra_colors = { pearlescent = memory.read_int(color.r), wheel = memory.read_int(color.g) }
    VEHICLE._GET_VEHICLE_DASHBOARD_COLOR(vehicle.handle, color.r)
    serialized_vehicle.paint.dashboard_color = memory.read_int(color.r)
    VEHICLE._GET_VEHICLE_INTERIOR_COLOR(vehicle.handle, color.r)
    serialized_vehicle.paint.interior_color = memory.read_int(color.r)
    serialized_vehicle.paint.fade = VEHICLE.GET_VEHICLE_ENVEFF_SCALE(vehicle.handle)
    serialized_vehicle.paint.dirt_level = VEHICLE.GET_VEHICLE_DIRT_LEVEL(vehicle.handle)
    serialized_vehicle.paint.color_combo = VEHICLE.GET_VEHICLE_COLOUR_COMBINATION(vehicle.handle)

    -- Livery is also part of mods, but capture it here as well for when just saving paint
    serialized_vehicle.paint.livery = VEHICLE.GET_VEHICLE_MOD(vehicle.handle, 48)

    memory.free(color.r) memory.free(color.g) memory.free(color.b)
end

local function deserialize_vehicle_paint(vehicle, serialized_vehicle)

    --VEHICLE.SET_VEHICLE_MOD_KIT(vehicle.handle, 0)

    VEHICLE.SET_VEHICLE_CUSTOM_PRIMARY_COLOUR(
        vehicle,
        serialized_vehicle.paint.vehicle_custom_color.r,
        serialized_vehicle.paint.vehicle_custom_color.g,
        serialized_vehicle.paint.vehicle_custom_color.b
    )
    VEHICLE.SET_VEHICLE_CUSTOM_SECONDARY_COLOUR(
        vehicle,
        serialized_vehicle.paint.vehicle_custom_color.r,
        serialized_vehicle.paint.vehicle_custom_color.g,
        serialized_vehicle.paint.vehicle_custom_color.b
    )
    VEHICLE.SET_VEHICLE_COLOURS(
        vehicle,
        serialized_vehicle.paint.primary.vehicle_standard_color or 0,
        serialized_vehicle.paint.secondary.vehicle_standard_color or 0
    )

    if serialized_vehicle.paint.extra_colors then
        VEHICLE.SET_VEHICLE_EXTRA_COLOURS(
                vehicle.handle,
                serialized_vehicle.paint.extra_colors.pearlescent,
                serialized_vehicle.paint.extra_colors.wheel
        )
    end

    if serialized_vehicle.paint.primary.is_custom then
        VEHICLE.SET_VEHICLE_CUSTOM_PRIMARY_COLOUR(
                vehicle.handle,
                serialized_vehicle.paint.primary.custom_color.r,
                serialized_vehicle.paint.primary.custom_color.g,
                serialized_vehicle.paint.primary.custom_color.b
        )
    else
        VEHICLE.SET_VEHICLE_MOD_COLOR_1(
                vehicle.handle,
                serialized_vehicle.paint.primary.paint_type,
                serialized_vehicle.paint.primary.color,
                serialized_vehicle.paint.primary.pearlescent_color
        )
    end

    if serialized_vehicle.paint.secondary.is_custom then
        VEHICLE.SET_VEHICLE_CUSTOM_SECONDARY_COLOUR(
                vehicle.handle,
                serialized_vehicle.paint.secondary.custom_color.r,
                serialized_vehicle.paint.secondary.custom_color.g,
                serialized_vehicle.paint.secondary.custom_color.b
        )
    else
        VEHICLE.SET_VEHICLE_MOD_COLOR_2(
                vehicle.handle,
                serialized_vehicle.paint.secondary.paint_type,
                serialized_vehicle.paint.secondary.color
        )
    end

    VEHICLE._SET_VEHICLE_XENON_LIGHTS_COLOR(vehicle.handle, serialized_vehicle.headlights_color)
    VEHICLE._SET_VEHICLE_DASHBOARD_COLOR(vehicle.handle, serialized_vehicle.paint.dashboard_color or -1)
    VEHICLE._SET_VEHICLE_INTERIOR_COLOR(vehicle.handle, serialized_vehicle.paint.interior_color or -1)

    VEHICLE.SET_VEHICLE_ENVEFF_SCALE(vehicle.handle, serialized_vehicle.paint.fade or 0)
    VEHICLE.SET_VEHICLE_DIRT_LEVEL(vehicle.handle, serialized_vehicle.paint.dirt_level or 0.0)
    VEHICLE.SET_VEHICLE_COLOUR_COMBINATION(vehicle.handle, serialized_vehicle.paint.color_combo or -1)
    VEHICLE.SET_VEHICLE_MOD(vehicle.handle, 48, serialized_vehicle.paint.livery or -1)
end

local function serialize_vehicle_neon(vehicle, serialized_vehicle)
    if serialized_vehicle.neon == nil then serialized_vehicle.neon = {} end
    serialized_vehicle.neon.lights = {
        left = VEHICLE._IS_VEHICLE_NEON_LIGHT_ENABLED(vehicle.handle, 0),
        right = VEHICLE._IS_VEHICLE_NEON_LIGHT_ENABLED(vehicle.handle, 1),
        front = VEHICLE._IS_VEHICLE_NEON_LIGHT_ENABLED(vehicle.handle, 2),
        back = VEHICLE._IS_VEHICLE_NEON_LIGHT_ENABLED(vehicle.handle, 3),
    }
    local color = { r = memory.alloc(4), g = memory.alloc(4), b = memory.alloc(4) }
    if (serialized_vehicle.neon.lights.left or serialized_vehicle.neon.lights.right
            or serialized_vehicle.neon.lights.front or serialized_vehicle.neon.lights.back) then
        VEHICLE._GET_VEHICLE_NEON_LIGHTS_COLOUR(vehicle.handle, color.r, color.g, color.b)
        serialized_vehicle.neon.color = { r = memory.read_int(color.r), g = memory.read_int(color.g), b = memory.read_int(color.b) }
    end
    memory.free(color.r) memory.free(color.g) memory.free(color.b)
end

local function deserialize_vehicle_neon(vehicle, serialized_vehicle)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle.handle, 0, serialized_vehicle.neon.lights.left or false)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle.handle, 1, serialized_vehicle.neon.lights.right or false)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle.handle, 2, serialized_vehicle.neon.lights.front or false)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(vehicle.handle, 3, serialized_vehicle.neon.lights.back or false)
    if serialized_vehicle.neon.color then
        VEHICLE._SET_VEHICLE_NEON_LIGHTS_COLOUR(
                vehicle.handle,
                serialized_vehicle.neon.color.r,
                serialized_vehicle.neon.color.g,
                serialized_vehicle.neon.color.b
        )
    end
end

local function serialize_vehicle_wheels(vehicle, serialized_vehicle)
    if serialized_vehicle.wheels == nil then serialized_vehicle.wheels = {} end
    serialized_vehicle.wheels.type = VEHICLE.GET_VEHICLE_WHEEL_TYPE(vehicle.handle)
    local color = { r = memory.alloc(4), g = memory.alloc(4), b = memory.alloc(4) }
    VEHICLE.GET_VEHICLE_TYRE_SMOKE_COLOR(vehicle.handle, color.r, color.g, color.b)
    serialized_vehicle.wheels.tire_smoke_color = { r = memory.read_int(color.r), g = memory.read_int(color.g), b = memory.read_int(color.b) }
    memory.free(color.r) memory.free(color.g) memory.free(color.b)
end

local function deserialize_vehicle_wheels(vehicle, serialized_vehicle)
    VEHICLE.SET_VEHICLE_TYRES_CAN_BURST(vehicle.handle, serialized_vehicle.bulletproof_tires or false)
    VEHICLE.SET_VEHICLE_WHEEL_TYPE(vehicle.handle, serialized_vehicle.wheel_type or -1)
    if serialized_vehicle.tire_smoke_color then
        VEHICLE.SET_VEHICLE_TYRE_SMOKE_COLOR(vehicle.handle, serialized_vehicle.tire_smoke_color.r or 255,
                serialized_vehicle.tire_smoke_color.g or 255, serialized_vehicle.tire_smoke_color.b or 255)
    end
end

local function serialize_vehicle_mods(vehicle, serialized_vehicle)
    if serialized_vehicle.mods == nil then serialized_vehicle.mods = {} end
    for mod_index = 0, 49 do
        local mod_value
        if mod_index >= 17 and mod_index <= 22 then
            mod_value = VEHICLE.IS_TOGGLE_MOD_ON(vehicle.handle, mod_index)
        else
            mod_value = VEHICLE.GET_VEHICLE_MOD(vehicle.handle, mod_index)
        end
        serialized_vehicle.mods["_"..mod_index] = mod_value
    end
end

local function deserialize_vehicle_mods(vehicle, serialized_vehicle)
    for mod_index = 0, 49 do
        if mod_index >= 17 and mod_index <= 22 then
            VEHICLE.TOGGLE_VEHICLE_MOD(vehicle.handle, mod_index, serialized_vehicle.mods["_"..mod_index])
        else
            VEHICLE.SET_VEHICLE_MOD(vehicle.handle, mod_index, serialized_vehicle.mods["_"..mod_index] or -1)
        end
    end
end

local function serialize_vehicle_extras(vehicle, serialized_vehicle)
    if serialized_vehicle.extras == nil then serialized_vehicle.extras = {} end
    for extra_index = 0, 14 do
        if VEHICLE.DOES_EXTRA_EXIST(vehicle.handle, extra_index) then
            serialized_vehicle.extras["_"..extra_index] = VEHICLE.IS_VEHICLE_EXTRA_TURNED_ON(vehicle.handle, extra_index)
        end
    end
end

local function deserialize_vehicle_extras(vehicle, serialized_vehicle)
    for extra_index = 0, 14 do
        local state = true
        if serialized_vehicle.extras["_"..extra_index] ~= nil then
            state = serialized_vehicle.extras["_"..extra_index]
        end
        VEHICLE.SET_VEHICLE_EXTRA(vehicle.handle, extra_index, not state)
    end
end

local function serialize_vehicle_options(vehicle, serialized_vehicle)
    if serialized_vehicle.options == nil then serialized_vehicle.options = {} end
    serialized_vehicle.options.headlights_color = VEHICLE._GET_VEHICLE_XENON_LIGHTS_COLOR(vehicle.handle)
    serialized_vehicle.options.bulletproof_tires = VEHICLE.GET_VEHICLE_TYRES_CAN_BURST(vehicle.handle)
    serialized_vehicle.options.window_tint = VEHICLE.GET_VEHICLE_WINDOW_TINT(vehicle.handle)
    serialized_vehicle.options.radio_loud = AUDIO.CAN_VEHICLE_RECEIVE_CB_RADIO(vehicle.handle)
    serialized_vehicle.options.engine_running = VEHICLE.GET_IS_VEHICLE_ENGINE_RUNNING(vehicle.handle)
    serialized_vehicle.options.siren = VEHICLE.IS_VEHICLE_SIREN_AUDIO_ON(vehicle.handle)
    serialized_vehicle.options.emergency_lights = VEHICLE.IS_VEHICLE_SIREN_ON(vehicle.handle)
    serialized_vehicle.options.search_light = VEHICLE.IS_VEHICLE_SEARCHLIGHT_ON(vehicle.handle)
    serialized_vehicle.options.license_plate_text = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT(vehicle.handle)
    serialized_vehicle.options.license_plate_type = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(vehicle.handle)
end

local function deserialize_vehicle_options(vehicle, serialized_vehicle)
    if serialized_vehicle.options.siren then
        AUDIO.SET_SIREN_WITH_NO_DRIVER(vehicle.handle, true)
        VEHICLE.SET_VEHICLE_HAS_MUTED_SIRENS(vehicle.handle, false)
        AUDIO._SET_SIREN_KEEP_ON(vehicle.handle, true)
        AUDIO._TRIGGER_SIREN(vehicle.handle, true)
    end
    VEHICLE.SET_VEHICLE_SIREN(vehicle.handle, serialized_vehicle.options.emergency_lights or false)
    VEHICLE.SET_VEHICLE_SEARCHLIGHT(vehicle.handle, serialized_vehicle.options.search_light or false, true)
    AUDIO.SET_VEHICLE_RADIO_LOUD(vehicle.handle, serialized_vehicle.options.radio_loud or false)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(vehicle.handle, serialized_vehicle.options.license_plate_text or "UNKNOWN")
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(vehicle.handle, serialized_vehicle.options.license_plate_type or -1)

    if serialized_vehicle.options.engine_running then
        VEHICLE.SET_VEHICLE_ENGINE_ON(vehicle.handle, true, true, false)
    end
end

---
--- Policify Overrides
---

local function save_headlights(policified_vehicle)
    if policified_vehicle.original_vehicle == nil then policified_vehicle.original_vehicle = {} end
    serialize_vehicle_headlights(
        policified_vehicle,
        policified_vehicle.original_vehicle
    )
end

local function set_headlights(policified_vehicle)
    VEHICLE.SET_VEHICLE_LIGHTS(policified_vehicle.handle, 2)
    VEHICLE.TOGGLE_VEHICLE_MOD(policified_vehicle.handle, 22, true)
    VEHICLE.SET_VEHICLE_ENGINE_ON(policified_vehicle.handle, true, true, true)
    VEHICLE.SET_VEHICLE_LIGHT_MULTIPLIER(policified_vehicle.handle, policified_vehicle.options.override_light_multiplier)
end

local function restore_headlights(policified_vehicle)
    deserialize_vehicle_headlights(
        policified_vehicle,
        policified_vehicle.original_vehicle
    )
    VEHICLE.SET_VEHICLE_LIGHTS(policified_vehicle.handle, 0)
end

local function save_neon(policified_vehicle)
    if policified_vehicle.original_vehicle == nil then policified_vehicle.original_vehicle = {} end
    serialize_vehicle_neon(
        policified_vehicle,
        policified_vehicle.original_vehicle
    )
end

local function set_neon(policified_vehicle)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(policified_vehicle.handle, 0, true)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(policified_vehicle.handle, 1, true)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(policified_vehicle.handle, 2, true)
    VEHICLE._SET_VEHICLE_NEON_LIGHT_ENABLED(policified_vehicle.handle, 3, true)
end

local function restore_neon(policified_vehicle)
    deserialize_vehicle_neon(
        policified_vehicle,
        policified_vehicle.original_vehicle
    )
end

local function save_paint(policified_vehicle)
    if policified_vehicle.original_vehicle == nil then policified_vehicle.original_vehicle = {} end
    serialize_vehicle_paint(
        policified_vehicle,
        policified_vehicle.original_vehicle
    )
end

local function set_paint(policified_vehicle)
    -- Paint matte black
    VEHICLE.SET_VEHICLE_CUSTOM_PRIMARY_COLOUR(policified_vehicle.handle, 0, 0, 0)
    VEHICLE.SET_VEHICLE_MOD_COLOR_1(policified_vehicle.handle, 3, 0, 0)
    VEHICLE.SET_VEHICLE_CUSTOM_SECONDARY_COLOUR(policified_vehicle.handle, 0, 0, 0)
    VEHICLE.SET_VEHICLE_MOD_COLOR_2(policified_vehicle.handle, 3, 0, 0)

    -- Clear livery
    VEHICLE.SET_VEHICLE_MOD(policified_vehicle.handle, 48, -1)
end

local function restore_paint(policified_vehicle)
    deserialize_vehicle_paint(
        policified_vehicle,
        policified_vehicle.original_vehicle
    )
end

local function save_horn(policified_vehicle)
    if policified_vehicle.original_vehicle == nil then policified_vehicle.original_vehicle = {} end
    policified_vehicle.original_vehicle.horn = VEHICLE.GET_VEHICLE_MOD(policified_vehicle.handle, 14)
    VEHICLE.SET_VEHICLE_SIREN(policified_vehicle.handle, true)
end

local function set_horn(policified_vehicle)
    VEHICLE.SET_VEHICLE_MOD(policified_vehicle.handle, 14, 1)
end

local function restore_horn(policified_vehicle)
    VEHICLE.SET_VEHICLE_MOD(policified_vehicle.handle, 14, policified_vehicle.original_vehicle.horn)
    VEHICLE.SET_VEHICLE_SIREN(policified_vehicle.handle, false)
end

local function save_plate(policified_vehicle)
    if policified_vehicle.original_vehicle == nil then policified_vehicle.original_vehicle = {} end
    if policified_vehicle.original_vehicle.options == nil then policified_vehicle.original_vehicle.options = {} end
    policified_vehicle.original_vehicle.options.license_plate_text = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT(policified_vehicle.handle)
    policified_vehicle.original_vehicle.options.license_plate_type = VEHICLE.GET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(policified_vehicle.handle)
end

local function set_plate(policified_vehicle)
    -- Set Exempt plate
    ENTITY.SET_ENTITY_AS_MISSION_ENTITY(policified_vehicle.handle, true, true)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(policified_vehicle.handle, 4)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(policified_vehicle.handle, policified_vehicle.options.plate_text)
end

local function restore_plate(policified_vehicle)
    ENTITY.SET_ENTITY_AS_MISSION_ENTITY(policified_vehicle.handle, true, true)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT(policified_vehicle.handle, policified_vehicle.original_vehicle.options.license_plate_text)
    VEHICLE.SET_VEHICLE_NUMBER_PLATE_TEXT_INDEX(policified_vehicle.handle, policified_vehicle.original_vehicle.options.license_plate_type)
end

local function refresh_plate_text(policified_vehicle)
    if policified_vehicle.options.override_plate then
        set_plate(policified_vehicle)
    else
        restore_plate(policified_vehicle)
    end
end

---
--- Attachment Construction
---

local function set_attachment_internal_collisions(attachment, new_attachment)
    ENTITY.SET_ENTITY_NO_COLLISION_ENTITY(attachment.handle, new_attachment.handle)
    for _, child_attachment in pairs(attachment.children) do
        set_attachment_internal_collisions(child_attachment, new_attachment)
    end
end

local function set_attachment_defaults(attachment)
    if attachment.offset == nil then
        attachment.offset = { x = 0, y = 0, z = 0 }
    end
    if attachment.rotation == nil then
        attachment.rotation = { x = 0, y = 0, z = 0 }
    end
    if attachment.is_visible == nil then
        attachment.is_visible = true
    end
    if attachment.has_gravity == nil then
        attachment.has_gravity = false
    end
    if attachment.has_collision == nil then
        attachment.has_collision = false
    end
    if attachment.hash == nil then
        attachment.hash = util.joaat(attachment.model)
    end
    if attachment.children == nil then
        attachment.children = {}
    end
    if attachment.options == nil then
        attachment.options = {}
    end
end

local function update_attachment(attachment)

    ENTITY.SET_ENTITY_VISIBLE(attachment.handle, attachment.is_visible, 0)
    ENTITY.SET_ENTITY_HAS_GRAVITY(attachment.handle, attachment.has_gravity)

    if attachment.parent.handle == attachment.handle then
        ENTITY.SET_ENTITY_ROTATION(attachment.handle, attachment.rotation.x or 0, attachment.rotation.y or 0, attachment.rotation.z or 0)
    else
        ENTITY.ATTACH_ENTITY_TO_ENTITY(
                attachment.handle, attachment.parent.handle, attachment.bone_index or 0,
                attachment.offset.x or 0, attachment.offset.y or 0, attachment.offset.z or 0,
                attachment.rotation.x or 0, attachment.rotation.y or 0, attachment.rotation.z or 0,
                false, true, attachment.has_collision, false, 2, true
        )
    end
end

local function load_hash_for_attachment(attachment)
    if not STREAMING.IS_MODEL_VALID(attachment.hash) or (attachment.type ~= "VEHICLE" and STREAMING.IS_MODEL_A_VEHICLE(attachment.hash)) then
        error("Error attaching: Invalid model: " .. attachment.model)
    end
    load_hash(attachment.hash)
end

local function build_parent_child_relationship(parent_attachment, child_attachment)
    child_attachment.parent = parent_attachment
    child_attachment.root = parent_attachment.root
end

local function attach_attachment(attachment)
    set_attachment_defaults(attachment)
    load_hash_for_attachment(attachment)

    if attachment.root == nil then
        error("Attachment missing root")
    end

    if attachment.type == "VEHICLE" then
        local heading = ENTITY.GET_ENTITY_HEADING(attachment.root.handle)
        attachment.handle = entities.create_vehicle(attachment.hash, attachment.offset, heading)
    elseif attachment.type == "PED" then
        local pos = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(attachment.parent.handle, attachment.offset.x, attachment.offset.y, attachment.offset.z)
        attachment.handle = entities.create_ped(1, attachment.hash, pos, 0.0)
        if attachment.parent.type == "VEHICLE" then
            PED.SET_PED_INTO_VEHICLE(attachment.handle, attachment.parent.handle, -1)
        end
    else
        local pos = ENTITY.GET_ENTITY_COORDS(attachment.root.handle)
        attachment.handle = OBJECT.CREATE_OBJECT_NO_OFFSET(attachment.hash, pos.x, pos.y, pos.z, true, true, false)
        --args.handle = entities.create_object(hash, ENTITY.GET_ENTITY_COORDS(args.root.handle))
    end

    if not attachment.handle then
        error("Error attaching attachment. Could not create handle.")
    end

    STREAMING.SET_MODEL_AS_NO_LONGER_NEEDED(attachment.hash)

    if attachment.type == nil then
        attachment.type = "OBJECT"
        if ENTITY.IS_ENTITY_A_VEHICLE(attachment.handle) then
            attachment.type  = "VEHICLE"
        elseif ENTITY.IS_ENTITY_A_PED(attachment.handle) then
            attachment.type  = "PED"
        end
    end

    if attachment.flash_start_on ~= nil then
        ENTITY.SET_ENTITY_VISIBLE(attachment.handle, attachment.flash_start_on, 0)
    end

    ENTITY.SET_ENTITY_INVINCIBLE(attachment.handle, false)

    update_attachment(attachment)
    set_attachment_internal_collisions(attachment.root, attachment)

    return attachment
end

local function update_reflection_offsets(reflection)
    --- This function isn't quite right, it breaks with certain root rotations, but close enough for now
    reflection.offset = { x = 0, y = 0, z = 0 }
    reflection.rotation = { x = 0, y = 0, z = 0 }
    if reflection.reflection_axis.x then
        reflection.offset.x = reflection.parent.offset.x * -2
    end
    if reflection.reflection_axis.y then
        reflection.offset.y = reflection.parent.offset.y * -2
    end
    if reflection.reflection_axis.z then
        reflection.offset.z = reflection.parent.offset.z * -2
    end
end

local function move_attachment(attachment)
    if attachment.reflection then
        update_reflection_offsets(attachment.reflection)
        update_attachment(attachment.reflection)
    end
    update_attachment(attachment)
end

local function detach_attachment(attachment)
    array_remove(attachment.children, function(t, i, j)
        local child_attachment = t[i]
        detach_attachment(child_attachment)
        return false
    end)
    if attachment ~= attachment.root then
        entities.delete_by_handle(attachment.handle)
    end
    if attachment.menus then
        for _, attachment_menu in pairs(attachment.menus) do
            -- Sometimes these menu handles are invalid but I don't know why,
            -- so wrap them in pcall to avoid errors if delete fails
            pcall(function() menu.delete(attachment_menu) end)
        end
    end
end

local function remove_attachment_from_parent(attachment)
    array_remove(attachment.parent.children, function(t, i, j)
        local child_attachment = t[i]
        if child_attachment.handle == attachment.handle then
            detach_attachment(attachment)
            return false
        end
        return true
    end)
end

local function build_attachment_from_parent(attachment, child_counter)
    if child_counter == 1 then
        if attachment.name == nil then
            error("Cannot build base attachment without a name")
        end
        attachment.base_name = attachment.name
    else
        attachment.base_name = attachment.parent.base_name
    end
    if attachment.name == nil then
        attachment.name = attachment.model
    end
    return attachment
end

local function reattach_attachment_with_children(attachment)
    if attachment.root ~= attachment then
        attach_attachment(attachment)
    end
    for _, child_attachment in pairs(attachment.children) do
        child_attachment.root = attachment.root
        child_attachment.parent = attachment
        reattach_attachment_with_children(child_attachment)
    end
end

local function attach_attachment_with_children(new_attachment, child_counter)
    if child_counter == nil then child_counter = 0 end
    child_counter = child_counter + 1
    local attachment = attach_attachment(build_attachment_from_parent(new_attachment, child_counter))
    if attachment.children then
        for _, child_attachment in pairs(attachment.children) do
            build_parent_child_relationship(attachment, child_attachment)
            if child_attachment.flash_model then
                child_attachment.flash_start_on = (not child_attachment.parent.flash_start_on)
            end
            if child_attachment.reflection_axis then
                update_reflection_offsets(child_attachment)
            end
            attach_attachment_with_children(child_attachment, child_counter)
        end
    end
    if new_attachment.parent == new_attachment.root then
        table.insert(new_attachment.root.children, new_attachment)
    end
    return attachment
end

local function clone_attachment(attachment)
    return {
        root = attachment.root,
        parent = attachment.parent,
        name = attachment.name,
        model = attachment.model,
        type = attachment.type,
        offset = table.table_copy(attachment.offset),
        rotation = table.table_copy(attachment.rotation),
    }
end

---
--- Build Invis Siren
---

local function attach_invis_siren(policified_vehicle)
    if not policified_vehicle.options.attach_invis_police_siren then return end
    attach_attachment_with_children({
        root = policified_vehicle,
        parent = policified_vehicle,
        name = policified_vehicle.options.siren_attachment.name .. " (Siren)",
        model = policified_vehicle.options.siren_attachment.model,
        type = "VEHICLE",
        is_visible = false,
        is_siren = true,
    })
end

local function detach_invis_sirens(policified_vehicle)
    for _, child_attachment in policified_vehicle.children do
        if child_attachment.is_siren then
            remove_attachment_from_parent(child_attachment)
        end
    end
end

local function refresh_invis_police_sirens(policified_vehicle)
    detach_invis_sirens(policified_vehicle)
    attach_invis_siren(policified_vehicle)
end

---
--- Siren Controls
---

local function activate_attachment_lights(attachment)
    if attachment.is_light_disabled then
        ENTITY.SET_ENTITY_LIGHTS(attachment.handle, true)
    else
        VEHICLE.SET_VEHICLE_SIREN(attachment.handle, true)
        VEHICLE.SET_VEHICLE_HAS_MUTED_SIRENS(attachment.handle, true)
        ENTITY.SET_ENTITY_LIGHTS(attachment.handle, false)
        AUDIO._TRIGGER_SIREN(attachment.handle, true)
        AUDIO._SET_SIREN_KEEP_ON(attachment.handle, true)
    end
    for _, child_attachment in pairs(attachment.children) do
        activate_attachment_lights(child_attachment)
    end
end

local function deactivate_attachment_lights(attachment)
    ENTITY.SET_ENTITY_LIGHTS(attachment.handle, true)
    AUDIO._SET_SIREN_KEEP_ON(attachment.handle, false)
    VEHICLE.SET_VEHICLE_SIREN(attachment.handle, false)
    for _, child_attachment in pairs(attachment.children) do
        deactivate_attachment_lights(child_attachment)
    end
end

local function activate_attachment_sirens(attachment)
    if attachment.type == "VEHICLE" and attachment.is_siren then
        VEHICLE.SET_VEHICLE_HAS_MUTED_SIRENS(attachment.handle, false)
        VEHICLE.SET_VEHICLE_SIREN(attachment.handle, true)
        AUDIO._TRIGGER_SIREN(attachment.handle, true)
        AUDIO._SET_SIREN_KEEP_ON(attachment.handle, true)
    end
    for _, child_attachment in pairs(attachment.children) do
        activate_attachment_sirens(child_attachment)
    end
end

local function activate_vehicle_sirens(policified_vehicle)
    -- Vehicle sirens are networked silent without a ped, but adding a ped makes them audible to others
    for _, attachment in pairs(policified_vehicle.children) do
        if attachment.type == "VEHICLE" and attachment.is_siren then
            local child_attachment = attach_attachment({
                root=policified_vehicle,
                parent=attachment,
                name=policified_vehicle.options.siren_attachment.name .. " (Driver)",
                model="s_m_m_pilot_01",
                type="PED",
                is_visible=false,
            })
            table.insert(attachment.children, child_attachment)
        end
    end
    activate_attachment_sirens(policified_vehicle)
end

local function deactivate_vehicle_sirens(policified_vehicle)
    -- Once a vehicle has a ped in it with sirens on they cant be turned back off, so despawn and respawn fresh vehicle
    refresh_invis_police_sirens(policified_vehicle)
end

local function sound_blip(attachment)
    if attachment.type == "VEHICLE" then
        AUDIO.BLIP_SIREN(attachment.handle)
    end
    for _, child_attachment in pairs(attachment.children) do
        sound_blip(child_attachment)
    end
end

local function refresh_siren_status(policified_vehicle)
    if policified_vehicle.options.siren_status == SIRENS_OFF then
        deactivate_attachment_lights(policified_vehicle)
        deactivate_vehicle_sirens(policified_vehicle)
    elseif policified_vehicle.options.siren_status == SIRENS_LIGHTS_ONLY then
        deactivate_vehicle_sirens(policified_vehicle)
        activate_attachment_lights(policified_vehicle)
    elseif policified_vehicle.options.siren_status == SIRENS_ALL_ON then
        activate_attachment_lights(policified_vehicle)
        activate_vehicle_sirens(policified_vehicle)
    end
end

local function update_siren_status(policified_vehicle, previous_siren_status)
    if previous_siren_status == SIRENS_OFF and policified_vehicle.options.siren_status ~= SIRENS_OFF then
        save_headlights(policified_vehicle)
        set_headlights(policified_vehicle)
        save_neon(policified_vehicle)
        set_neon(policified_vehicle)
    end
    if previous_siren_status ~= SIRENS_OFF and policified_vehicle.options.siren_status == SIRENS_OFF then
        restore_headlights(policified_vehicle)
        restore_neon(policified_vehicle)
    end
    refresh_siren_status(policified_vehicle)
end

---
--- Control Overrides
---

local function add_overrides_to_vehicle(policified_vehicle)
    if policified_vehicle.options.override_headlights then
        save_headlights(policified_vehicle)
        set_headlights(policified_vehicle)
    end

    if policified_vehicle.options.override_neon then
        save_neon(policified_vehicle)
        set_neon(policified_vehicle)
    end

    if policified_vehicle.options.override_horn then
        save_horn(policified_vehicle)
        set_horn(policified_vehicle)
    end

    if policified_vehicle.options.override_paint then
        save_paint(policified_vehicle)
        set_paint(policified_vehicle)
    end

    if policified_vehicle.options.override_plate then
        save_plate(policified_vehicle)
        set_plate(policified_vehicle)
    end

    refresh_invis_police_sirens(policified_vehicle)
end

local function remove_overrides_from_vehicle(policified_vehicle)
    if policified_vehicle.options.override_headlights then
        restore_headlights(policified_vehicle)
    end
    if policified_vehicle.options.override_neon then
        restore_neon(policified_vehicle)
    end
    if policified_vehicle.options.override_horn then
        restore_horn(policified_vehicle)
    end
    if policified_vehicle.options.override_paint then
        restore_paint(policified_vehicle)
    end
    if policified_vehicle.options.override_plate then
        restore_plate(policified_vehicle)
    end
    refresh_invis_police_sirens(policified_vehicle)
    detach_attachment(policified_vehicle)
end

local function policify_vehicle(vehicle)
    for _, previously_policified_vehicle in pairs(policified_vehicles) do
        if previously_policified_vehicle.handle == vehicle then
            util.toast("Vehicle is already policified")
            menu.focus(previously_policified_vehicle.menus.siren)
            return
        end
    end
    local policified_vehicle = table.table_copy(policified_vehicle_base)
    policified_vehicle.type = "VEHICLE"
    policified_vehicle.handle = vehicle
    policified_vehicle.root = policified_vehicle
    policified_vehicle.hash = ENTITY.GET_ENTITY_MODEL(vehicle)
    policified_vehicle.model = VEHICLE.GET_DISPLAY_NAME_FROM_VEHICLE_MODEL(policified_vehicle.hash)
    policified_vehicle.name = policified_vehicle.model
    add_overrides_to_vehicle(policified_vehicle)
    refresh_siren_status(policified_vehicle)
    table.insert(policified_vehicles, policified_vehicle)
    last_policified_vehicle = policified_vehicle
    return policified_vehicle
end

local function depolicify_vehicle(policified_vehicle)
    array_remove(policified_vehicles, function(t, i, j)
        local loop_policified_vehicle = t[i]
        if loop_policified_vehicle.handle == policified_vehicle.handle then
            remove_overrides_from_vehicle(policified_vehicle)
            -- Sometimes these menu handles are invalid but I don't know why, so wrap them in pcall to avoid errors if delete fails
            pcall(function() menu.delete(policified_vehicle.menus.main) end)
            return false
        end
        return true
    end)
end

---
--- Serializers
---

local function serialize_vehicle_attributes(vehicle)
    if vehicle.type ~= "VEHICLE" then return end
    local serialized_vehicle = {}

    serialize_vehicle_paint(vehicle, serialized_vehicle)
    serialize_vehicle_neon(vehicle, serialized_vehicle)
    serialize_vehicle_wheels(vehicle, serialized_vehicle)
    serialize_vehicle_headlights(vehicle, serialized_vehicle)
    serialize_vehicle_options(vehicle, serialized_vehicle)
    serialize_vehicle_mods(vehicle, serialized_vehicle)
    serialize_vehicle_extras(vehicle, serialized_vehicle)

    return serialized_vehicle
end

local function deserialize_vehicle_attributes(vehicle)
    if vehicle.vehicle_attributes == nil then return end
    local serialized_vehicle = vehicle.vehicle_attributes

    VEHICLE.SET_VEHICLE_MOD_KIT(vehicle.handle, 0)

    deserialize_vehicle_neon(vehicle, serialized_vehicle)
    deserialize_vehicle_paint(vehicle, serialized_vehicle)
    deserialize_vehicle_wheels(vehicle, serialized_vehicle)
    deserialize_vehicle_headlights(vehicle, serialized_vehicle)
    deserialize_vehicle_options(vehicle, serialized_vehicle)
    deserialize_vehicle_mods(vehicle, serialized_vehicle)
    deserialize_vehicle_extras(vehicle, serialized_vehicle)

    ENTITY.SET_ENTITY_AS_MISSION_ENTITY(vehicle.handle, true, true)

end

local function serialize_attachment(attachment)
    local serialized_attachment = {
        children = {}
    }
    for k, v in pairs(attachment) do
        if not (k == "handle" or k == "root" or k == "parent" or k == "menus" or k == "children"
                or k == "base_name" or k == "rebuild_edit_attachments_menu_function") then
            serialized_attachment[k] = v
        end
    end
    serialized_attachment.vehicle_attributes = serialize_vehicle_attributes(attachment)
    for _, child_attachment in pairs(attachment.children) do
        table.insert(serialized_attachment.children, serialize_attachment(child_attachment))
    end
    --util.toast(inspect(serialized_attachment), TOAST_ALL)
    return serialized_attachment
end

local rebuild_saved_vehicles_menu_function

local function save_vehicle(policified_vehicle)
    local filepath = VEHICLE_STORE_DIR .. policified_vehicle.name .. ".policify.json"
    local file = io.open(filepath, "wb")
    if not file then error("Cannot write to file '" .. filepath .. "'", TOAST_ALL) end
    local content = json.encode(serialize_attachment(policified_vehicle))
    if content == "" or (not string.starts(content, "{")) then
        util.toast("Cannot save vehicle: Error serializing.", TOAST_ALL)
        return
    end
    --util.toast(content, TOAST_ALL)
    file:write(content)
    file:close()
    util.toast("Saved "..policified_vehicle.name)
    rebuild_saved_vehicles_menu_function()
end

local function spawn_vehicle_for_player(policified_vehicle, pid)
    if policified_vehicle.hash == nil then
        policified_vehicle.hash = util.joaat(policified_vehicle.model)
    end
    if not (STREAMING.IS_MODEL_VALID(policified_vehicle.hash) and STREAMING.IS_MODEL_A_VEHICLE(policified_vehicle.hash)) then
        util.toast("Cannot spawn vehicle model: "..policified_vehicle.model)
    end
    load_hash(policified_vehicle.hash)
    local target_ped = PLAYER.GET_PLAYER_PED_SCRIPT_INDEX(pid)
    local pos = ENTITY.GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(target_ped, 0.0, 4.0, 0.5)
    local heading = ENTITY.GET_ENTITY_HEADING(target_ped)
    policified_vehicle.handle = entities.create_vehicle(policified_vehicle.hash, pos, heading)
    STREAMING.SET_MODEL_AS_NO_LONGER_NEEDED(policified_vehicle.hash)
end

local function spawn_loaded_vehicle(loaded_vehicle)
    spawn_vehicle_for_player(loaded_vehicle, players.user())
    deserialize_vehicle_attributes(loaded_vehicle)
    loaded_vehicle.root = loaded_vehicle
    loaded_vehicle.parent = loaded_vehicle
    reattach_attachment_with_children(loaded_vehicle)
    add_overrides_to_vehicle(loaded_vehicle)
    refresh_siren_status(loaded_vehicle)
    table.insert(policified_vehicles, loaded_vehicle)
    last_policified_vehicle = loaded_vehicle
end

---
--- Dynamic Menus
---

local rebuild_policified_vehicle_menu_function

local function rebuild_add_attachments_menu(attachment)
    if attachment.menus.add_attachment_categories ~= nil then
        return
    end
    attachment.menus.add_attachment_categories = {}

    for _, category in pairs(available_attachments) do
        local category_menu = menu.list(attachment.menus.add_attachment, category.name)
        for _, available_attachment in pairs(category.objects) do
            menu.action(category_menu, available_attachment.name, {}, "", function()
                local child_attachment = table.table_copy(available_attachment)
                child_attachment.root = attachment.root
                child_attachment.parent = attachment
                attach_attachment_with_children(child_attachment)
                table.insert(attachment.children, child_attachment)
                refresh_siren_status(attachment.root)
                local newly_added_edit_menu = attachment.rebuild_edit_attachments_menu_function(attachment.root)
                if newly_added_edit_menu then
                    menu.focus(newly_added_edit_menu)
                end
            end)
        end
        table.insert(attachment.menus.add_attachment_categories, category_menu)
    end

    menu.text_input(attachment.menus.add_attachment, "Object by Name", {"policifyattachobject"},
            "Add an in-game object by exact name. To search for objects try https://gtahash.ru/", function (value)
                local new_attachment = {
                    root = attachment.root,
                    parent = attachment,
                    name = value,
                    model = value,
                }
                attach_attachment_with_children(new_attachment)
                refresh_siren_status(new_attachment)
                local newly_added_edit_menu = attachment.rebuild_edit_attachments_menu_function(attachment)
                if newly_added_edit_menu then
                    menu.focus(newly_added_edit_menu)
                end
            end)

    menu.text_input(attachment.menus.add_attachment, "Vehicle by Name", {"policifyattachvehicle"},
            "Add a vehicle by exact name.", function (value)
                local new_attachment = {
                    root = attachment.root,
                    parent = attachment,
                    name = value,
                    model = value,
                    type = "VEHICLE",
                }
                attach_attachment_with_children(new_attachment)
                refresh_siren_status(new_attachment)
                local newly_added_edit_menu = attachment.rebuild_edit_attachments_menu_function(attachment)
                if newly_added_edit_menu then
                    menu.focus(newly_added_edit_menu)
                end
            end)

end

local function rebuild_edit_attachments_menu(parent_attachment)
    local focus
    for _, attachment in pairs(parent_attachment.children) do
        if not (attachment.menus and attachment.menus.main) then
            attachment.menus = {}
            attachment.menus.main = menu.list(attachment.parent.menus.edit_attachments, attachment.name or "unknown")

            menu.divider(attachment.menus.main, "Position")
            local first_menu = menu.slider_float(attachment.menus.main, "X: Left / Right", {"polposition"..attachment.handle.."x"}, "", -500000, 500000, math.floor(attachment.offset.x * 100), config.edit_offset_step, function(value)
                attachment.offset.x = value / 100
                move_attachment(attachment)
            end)
            if focus == nil then
                focus = first_menu
            end
            menu.slider_float(attachment.menus.main, "Y: Forward / Back", {"polposition"..attachment.handle.."y"}, "", -500000, 500000, math.floor(attachment.offset.y * -100), config.edit_offset_step, function(value)
                attachment.offset.y = value / -100
                move_attachment(attachment)
            end)
            menu.slider_float(attachment.menus.main, "Z: Up / Down", {"polposition"..attachment.handle.."z"}, "", -500000, 500000, math.floor(attachment.offset.z * -100), config.edit_offset_step, function(value)
                attachment.offset.z = value / -100
                move_attachment(attachment)
            end)

            menu.divider(attachment.menus.main, "Rotation")
            menu.slider(attachment.menus.main, "X: Pitch", {"polrotate"..attachment.handle.."x"}, "", -179, 180, attachment.rotation.x, config.edit_rotation_step, function(value)
                attachment.rotation.x = value
                move_attachment(attachment)
            end)
            menu.slider(attachment.menus.main, "Y: Roll", {"polrotate"..attachment.handle.."y"}, "", -179, 180, attachment.rotation.y, config.edit_rotation_step, function(value)
                attachment.rotation.y = value
                move_attachment(attachment)
            end)
            menu.slider(attachment.menus.main, "Z: Yaw", {"polrotate"..attachment.handle.."z"}, "", -179, 180, attachment.rotation.z, config.edit_rotation_step, function(value)
                attachment.rotation.z = value
                move_attachment(attachment)
            end)

            menu.divider(attachment.menus.main, "Toggles")
            --local light_color = {r=0}
            --menu.slider(attachment.menu, "Color: Red", {}, "", 0, 255, light_color.r, 1, function(value)
            --    -- Only seems to work locally :(
            --    OBJECT._SET_OBJECT_LIGHT_COLOR(attachment.handle, 1, light_color.r, 0, 128)
            --end)
            menu.toggle(attachment.menus.main, "Is Visible", {}, "Will the attachment be visible, or invisible", function(on)
                attachment.is_visible = on
                update_attachment(attachment)
            end, attachment.is_visible)
            menu.toggle(attachment.menus.main, "Has Collision", {}, "Will the attachment collide with things, or pass through them", function(on)
                attachment.has_collision = on
                update_attachment(attachment)
            end, attachment.has_collision)
            menu.toggle(attachment.menus.main, "Has Gravity", {}, "Will the attachment be effected by gravity, or be weightless", function(on)
                attachment.has_gravity = on
                update_attachment(attachment)
            end, attachment.has_gravity)
            menu.toggle(attachment.menus.main, "Is Light Disabled", {}, "If attachment is a light, it will be ALWAYS off, regardless of siren settings.", function(on)
                attachment.is_light_disabled = on
                update_attachment(attachment)
            end, attachment.is_light_disabled)

            menu.divider(attachment.menus.main, "Attachments")
            attachment.menus.add_attachment = menu.list(attachment.menus.main, "Add Attachment", {}, "", function()
                rebuild_add_attachments_menu(attachment)
            end)
            attachment.menus.edit_attachments = menu.list(attachment.menus.main, "Edit Attachments ("..#attachment.children..")", {}, "", function()
                rebuild_edit_attachments_menu(attachment)
            end)
            attachment.rebuild_edit_attachments_menu_function = rebuild_edit_attachments_menu

            local clone_menu = menu.list(attachment.menus.main, "Clone")
            menu.action(clone_menu, "Clone (In Place)", {}, "", function()
                local new_attachment = clone_attachment(attachment)
                new_attachment.name = attachment.name .. " (Clone)"
                attach_attachment_with_children(new_attachment)
                refresh_siren_status(new_attachment)
                local newly_added_edit_menu = attachment.rebuild_edit_attachments_menu_function(attachment.root)
                if newly_added_edit_menu then
                    menu.focus(newly_added_edit_menu)
                end
            end)

            menu.action(clone_menu, "Clone Reflection: Left/Right", {}, "", function()
                local new_attachment = clone_attachment(attachment)
                new_attachment.name = attachment.name .. " (Clone)"
                new_attachment.offset = {x=-attachment.offset.x, y=attachment.offset.y, z=attachment.offset.z}
                attach_attachment_with_children(new_attachment)
                refresh_siren_status(new_attachment)
                local newly_added_edit_menu = attachment.rebuild_edit_attachments_menu_function(attachment.root)
                if newly_added_edit_menu then
                    menu.focus(newly_added_edit_menu)
                end
            end)

            menu.divider(attachment.menus.main, "Info")
            menu.readonly(attachment.menus.main, "Handle", attachment.handle)

            menu.divider(attachment.menus.main, "Actions")
            if attachment.type == "VEHICLE" then
                menu.action(attachment.menus.main, "Enter Drivers Seat", {}, "", function()
                    PED.SET_PED_INTO_VEHICLE(PLAYER.PLAYER_PED_ID(), attachment.handle, -1)
                end)
            end
            menu.action(attachment.menus.main, "Delete", {}, "", function()
                menu.show_warning(attachment.menus.main, CLICK_COMMAND, "Are you sure you want to delete this attachment? All children will also be deleted.", function()
                    remove_attachment_from_parent(attachment)
                    menu.focus(attachment.parent.menus.edit_attachments)
                end)
            end)

        end
        local submenu_focus = rebuild_edit_attachments_menu(attachment)
        if focus == nil and submenu_focus ~= nil then
            focus = submenu_focus
        end
    end
    return focus
end

local policified_vehicles_menu

local function rebuild_policified_vehicle_menu(policified_vehicle)
    if policified_vehicle.menus == nil then
        policified_vehicle.menus = {}
        policified_vehicle.menus.main = menu.list(policified_vehicles_menu, policified_vehicle.name)

        menu.text_input(policified_vehicle.menus.main, "Name", {"policifysetvehiclename"}, "Set name of the vehicle", function(value)
            policified_vehicle.name = value
            policified_vehicle.rebuild_edit_attachments_menu_function(policified_vehicle)
        end, policified_vehicle.name)

        policified_vehicle.menus.siren = menu.list_select(policified_vehicle.menus.main, "Sirens", {}, "", { "Off", "Lights Only", "Sirens and Lights" }, 1, function(siren_status)
            config.siren_status = siren_status
            local previous_siren_status = policified_vehicle.options.siren_status
            policified_vehicle.options.siren_status = siren_status
            update_siren_status(policified_vehicle, previous_siren_status)
        end)

        --menu.divider(policified_vehicle.menu, "Options")
        local options_menu = menu.list(policified_vehicle.menus.main, "Options")

        menu.toggle(options_menu, "Override Paint", {}, "If enabled, will override vehicle paint to matte black", function(toggle)
            policified_vehicle.options.override_paint = toggle
            if policified_vehicle.options.override_paint then
                save_paint(policified_vehicle)
                set_paint(policified_vehicle)
            else
                restore_paint(policified_vehicle)
            end
        end, true)

        menu.toggle(options_menu, "Override Headlights", {}, "If enabled, will override vehicle headlights to flash blue and red", function(toggle)
            policified_vehicle.options.override_headlights = toggle
            if policified_vehicle.options.override_headlights then
                save_headlights(policified_vehicle)
                set_headlights(policified_vehicle)
            else
                restore_headlights(policified_vehicle)
            end
        end, true)

        menu.slider(options_menu, "Headlight Multiplier", {}, "Multiplies the brightness of your headlights to extreme levels", 1, 100, policified_vehicle.options.override_light_multiplier, 1, function(value)
            policified_vehicle.options.override_light_multiplier = value
            if policified_vehicle.options.override_headlights then
                set_headlights(policified_vehicle)
            end
        end)

        menu.toggle(options_menu, "Override Neon", {}, "If enabled, will override vehicle neon to flash red and blue", function(toggle)
            policified_vehicle.options.override_neon = toggle
            if policified_vehicle.options.override_neon then
                save_neon(policified_vehicle)
                set_neon(policified_vehicle)
            else
                restore_neon(policified_vehicle)
            end
        end, true)

        menu.toggle(options_menu, "Override Horn", {}, "If enabled, will override vehicle horn to police horn", function(toggle)
            policified_vehicle.options.override_horn = toggle
            if policified_vehicle.options.override_horn then
                save_horn(policified_vehicle)
                set_horn(policified_vehicle)
            else
                restore_horn(policified_vehicle)
            end
        end, true)

        menu.toggle(options_menu, "Override Plate", {}, "If enabled, will override vehicle plate with custom exempt plate", function(toggle)
            policified_vehicle.options.override_plate = toggle
            if policified_vehicle.options.override_plate then
                save_plate(policified_vehicle)
            end
            refresh_plate_text(policified_vehicle)
        end, true)

        menu.text_input(options_menu, "Set Plate Text", {"policifysetvehicleplate"}, "Set the text for the exempt police plates", function(value)
            policified_vehicle.options.plate_text = value
            refresh_plate_text(policified_vehicle)
        end, config.plate_text)

        menu.toggle_loop(options_menu, "Engine Always On", {}, "If enabled, vehicle lights will stay on even when unoccupied", function()
            VEHICLE.SET_VEHICLE_ENGINE_ON(last_policified_vehicle.handle, true, true, true)
        end)

        menu.toggle(options_menu, "Enable Invis Siren", {}, "If enabled, will attach an invisible emergency vehicle to give any vehicle sirens.", function(toggle)
            policified_vehicle.options.attach_invis_police_siren = toggle
            if policified_vehicle.options.attach_invis_police_siren then
                refresh_invis_police_sirens(policified_vehicle)
                refresh_siren_status(policified_vehicle)
                rebuild_edit_attachments_menu(policified_vehicle)
            else
                detach_invis_sirens(policified_vehicle)
            end
        end, true)

        menu.list_select(options_menu, "Invis Siren Type", {}, "Different siren types have slightly different sounds", siren_types, 1, function(index)
            local siren_type = siren_types[index]
            policified_vehicle.options.siren_attachment = {
                name = siren_type[1],
                model = siren_type[4]
            }
            refresh_invis_police_sirens(policified_vehicle)
            refresh_siren_status(policified_vehicle)
            rebuild_edit_attachments_menu(policified_vehicle)
        end)

        menu.divider(policified_vehicle.menus.main, "Attachments")
        policified_vehicle.menus.add_attachment = menu.list(policified_vehicle.menus.main, "Add Attachment", {}, "", function()
            rebuild_add_attachments_menu(policified_vehicle)
        end)
        policified_vehicle.menus.edit_attachments = menu.list(policified_vehicle.menus.main, "Edit Attachments ("..#policified_vehicle.children..")", {}, "", function()
            rebuild_edit_attachments_menu(policified_vehicle)
        end)
        policified_vehicle.rebuild_edit_attachments_menu_function = rebuild_edit_attachments_menu
        rebuild_add_attachments_menu(policified_vehicle)

        menu.divider(policified_vehicle.menus.main, "Actions")
        menu.action(policified_vehicle.menus.main, "Enter Drivers Seat", {}, "", function()
            PED.SET_PED_INTO_VEHICLE(PLAYER.PLAYER_PED_ID(), policified_vehicle.handle, -1)
        end)
        menu.action(policified_vehicle.menus.main, "Save Vehicle", {}, "Save this vehicle so it can be retrieved in the future", function()
            save_vehicle(policified_vehicle)
        end)
        menu.action(policified_vehicle.menus.main, "Depolicify", {}, "Remove policification", function()
            depolicify_vehicle(policified_vehicle)
            menu.trigger_commands("luapolicify")
        end)
        policified_vehicle.menus.delete_vehicle = menu.action(policified_vehicle.menus.main, "Delete", {}, "Delete vehicle and all attachments", function()
            menu.show_warning(policified_vehicle.menus.delete_vehicle, CLICK_COMMAND, "Are you sure you want to delete this vehicle? All children will also be deleted.", function()
                depolicify_vehicle(policified_vehicle)
                entities.delete_by_handle(policified_vehicle.handle)
                menu.trigger_commands("luapolicify")
            end)
        end)

    end
end

---
--- Static Menus
---

menu.action(menu.my_root(), "Policify Vehicle", { "policify" }, "Enable Policify options on current vehicle", function()
    local vehicle = entities.get_user_vehicle_as_handle()
    if vehicle == 0 then
        util.toast("Error: Must be in a vehicle to Policify it")
        return
    end
    local policified_vehicle = policify_vehicle(vehicle)
    if policified_vehicle then
        rebuild_policified_vehicle_menu(policified_vehicle)
        rebuild_edit_attachments_menu(policified_vehicle)
        menu.focus(policified_vehicle.menus.siren)
    end
end)

menu.list_select(menu.my_root(), "All Sirens", {}, "Set siren status for ALL currently policified vehicles", { "Off", "Lights Only", "Sirens and Lights" }, 1, function(siren_status)
    config.siren_status = siren_status
    for _, policified_vehicle in pairs(policified_vehicles) do
        local previous_siren_status = policified_vehicle.options.siren_status
        policified_vehicle.options.siren_status = siren_status
        update_siren_status(policified_vehicle, previous_siren_status)
    end
end)

menu.action(menu.my_root(), "Siren Warning Blip", { "blip" }, "A quick siren blip to gain attention (local only)", function()
    if last_policified_vehicle then
        sound_blip(last_policified_vehicle)
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

menu.action(menu.my_root(), "Call for Backup", {}, "Summons a nearby police unit to your location", function()
    local incident_id = memory.alloc(8)
    MISC.CREATE_INCIDENT_WITH_ENTITY(7, PLAYER.PLAYER_PED_ID(), 3, 3, incident_id)
    AUDIO.PLAY_POLICE_REPORT("SCRIPTED_SCANNER_REPORT_PS_2A_01", 0)
end, true)

policified_vehicles_menu = menu.list(menu.my_root(), "Policified Vehicles")

---
--- Saved Vehicles Menu
---

local saved_vehicles_menu = menu.list(menu.my_root(), "Saved Vehicles")
local saved_vehicles_menu_items = {}

menu.hyperlink(saved_vehicles_menu, "Open Saved Vehicles Folder", "file:///"..filesystem.store_dir() .. 'Policify\\vehicles\\', "Open Saved Vehicles folder")

local function load_vehicle_from_file(filepath)
    local file = io.open(filepath, "r")
    if file then
        local status, data = pcall(function() return json.decode(file:read("*a")) end)
        if not status then
            util.toast("Invalid policify vehicle file format. "..filepath, TOAST_ALL)
            return
        end
        if not data.target_version then
            util.toast("Invalid policify vehicle file format. Missing target_version. "..filepath, TOAST_ALL)
            return
        end
        file:close()
        return data
    else
        error("Could not read file '" .. filepath .. "'", TOAST_ALL)
    end
end

local function load_saved_vehicles(directory)
    local loaded_saved_vehicles = {}
    for _, filepath in ipairs(filesystem.list_files(directory)) do
        local _, filename, ext = string.match(filepath, "(.-)([^\\/]-%.?([^%.\\/]*))$")
        if not filesystem.is_dir(filepath) and ext == "json" then
            local loaded_vehicle = load_vehicle_from_file(filepath)
            if loaded_vehicle then
                table.insert(loaded_saved_vehicles, loaded_vehicle)
            end
        end
    end
    return loaded_saved_vehicles
end

rebuild_saved_vehicles_menu_function = function()
    for _, saved_vehicles_menu_item in pairs(saved_vehicles_menu_items) do
        menu.delete(saved_vehicles_menu_item)
    end
    saved_vehicles_menu_items = {}
    for _, loaded_vehicle in pairs(load_saved_vehicles(VEHICLE_STORE_DIR)) do
        local saved_vehicles_menu_item = menu.action(saved_vehicles_menu, loaded_vehicle.name, {}, "", function()
            local spawn_vehicle = table.table_copy(loaded_vehicle)
            spawn_loaded_vehicle(spawn_vehicle)

            rebuild_policified_vehicle_menu(spawn_vehicle)
            rebuild_edit_attachments_menu(spawn_vehicle)
            menu.focus(spawn_vehicle.menus.siren)
        end)
        table.insert(saved_vehicles_menu_items, saved_vehicles_menu_item)
    end
end

rebuild_saved_vehicles_menu_function()

local options_menu = menu.list(menu.my_root(), "Options")

menu.divider(options_menu, "Global Configs")

menu.slider(options_menu, "Flash Delay", { "policifydelay" }, "Setting a too low value may not network the colors to other players!", 20, 150, config.flash_delay, 10, function(value)
    config.flash_delay = value
end)
menu.slider(options_menu, "Edit Offset Step", {}, "The amount of change each time you edit an attachment offset", 1, 20, config.edit_offset_step, 1, function(value)
    config.edit_offset_step = value
end)
menu.slider(options_menu, "Edit Rotation Step", {}, "The amount of change each time you edit an attachment rotation", 1, 15, config.edit_rotation_step, 1, function(value)
    config.edit_rotation_step = value
end)

menu.divider(options_menu, "Defaults for New Vehicles")

menu.toggle(options_menu, "Override Paint", {}, "If enabled, will override vehicle paint to matte black", function(toggle)
    config.override_paint = toggle
end, config.override_paint)

menu.toggle(options_menu, "Override Headlights", {}, "If enabled, will override vehicle headlights to flash blue and red", function(toggle)
    config.override_headlights = toggle
end, config.override_headlights)

menu.slider(options_menu, "Headlight Multiplier", {}, "Multiplies the brightness of your headlights to extreme levels", 1, 100, config.override_light_multiplier, 1, function(value)
    config.override_light_multiplier = value
end)

menu.toggle(options_menu, "Override Neon", {}, "If enabled, will override vehicle neon to flash red and blue", function(toggle)
    config.override_neon = toggle
end, config.override_neon)

menu.toggle(options_menu, "Override Horn", {}, "If enabled, will override vehicle horn to police horn", function(toggle)
    config.override_horn = toggle
end, config.override_horn)

menu.toggle(options_menu, "Override Plate", {}, "If enabled, will override vehicle plate with custom exempt plate", function(toggle)
    config.override_plate = toggle
end, config.override_plate)

menu.text_input(options_menu, "Set Plate Text", { "setpoliceplatetext" }, "Set the text for the exempt police plates", function(value)
    config.plate_text = value
end, config.plate_text)

menu.toggle(options_menu, "Enable Invis Siren", {}, "If enabled, will attach an invisible emergency vehicle to give any vehicle sirens.", function(toggle)
    config.attach_invis_police_siren = toggle
end, config.attach_invis_police_siren)

menu.list_select(options_menu, "Invis Siren Type", {}, "Different siren types have slightly different sounds", siren_types, 1, function(index)
    local siren_type = siren_types[index]
    config.siren_attachment = {
        name = siren_type[1],
        model = siren_type[4]
    }
end)

local script_meta_menu = menu.list(menu.my_root(), "Script Meta")

menu.divider(script_meta_menu, "Policify")
menu.readonly(script_meta_menu, "Version", SCRIPT_VERSION)
menu.list_select(script_meta_menu, "Release Branch", {}, "Switch from main to dev to get cutting edge updates, but also potentially more bugs.", AUTO_UPDATE_BRANCHES, SELECTED_BRANCH_INDEX, function(index, menu_name, previous_option, click_type)
    if click_type ~= 0 then return end
    auto_update_branch(AUTO_UPDATE_BRANCHES[index][1])
end)
menu.hyperlink(script_meta_menu, "Github Source", "https://github.com/hexarobi/stand-lua-policify", "View source files on Github")
menu.hyperlink(script_meta_menu, "Discord", "https://discord.gg/RF4N7cKz", "Open Discord Server")
menu.divider(script_meta_menu, "Credits")
menu.readonly(script_meta_menu, "Jackz for writing Vehicle Builder", "Much of Policify is based on code from Jackz Vehicle Builder and wouldn't have been possible without this foundation")

util.create_tick_handler(function()
    policify_tick()
    return true
end)
