ESX = exports['es_extended']:getSharedObject()

local spawnedVehs = {}
local blips = {}

local function IsInFreeZone(coords)
    for _, zone in ipairs(Config.FreeZones) do
        if #(coords - vector3(zone.x, zone.y, zone.z)) <= zone.radius then
            return true
        end
    end
    return false
end

local function SpawnVehicle(vehicleData)
    if spawnedVehs[vehicleData.plate] then return end

    local model = vehicleData.model
    if model == nil or model == '' then
        TriggerServerEvent('parking:logToDiscord', '[PARKING][Client] Missing vehicle model for plate: ' .. vehicleData.plate)
        return
    end

    local modelHash = GetHashKey(model)
    RequestModel(modelHash)

    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end

    if timeout >= 100 then
        TriggerServerEvent('parking:logToDiscord', '[PARKING][Client] Vehicle model not loaded: ' .. model)
        return
    end

    local pos = vector3(vehicleData.position.x, vehicleData.position.y, vehicleData.position.z)
    local heading = vehicleData.heading or 0.0

    local veh = CreateVehicle(modelHash, pos.x, pos.y, pos.z, heading, false, false)
    SetVehicleNumberPlateText(veh, vehicleData.plate)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleDoorsLocked(veh, 2)

    if vehicleData.mods then
        local mods = vehicleData.mods
        if mods.colors then
            local primary = mods.colors.primary or 0
            local secondary = mods.colors.secondary or 0
            SetVehicleColours(veh, primary, secondary)
        end
        if mods.mods then
            for k,v in pairs(mods.mods) do
                SetVehicleMod(veh, tonumber(k), tonumber(v), false)
            end
        end
        if mods.wheels then
            SetVehicleWheelType(veh, tonumber(mods.wheels) or 0)
            SetVehicleMod(veh, 23, tonumber(mods.wheelMods) or 0, false)
        end
    end

    spawnedVehs[vehicleData.plate] = veh
    TriggerServerEvent('parking:logToDiscord', '[PARKING][Client] Vehicle spawned: ' .. vehicleData.plate)
end

local function DespawnVehicle(plate)
    local veh = spawnedVehs[plate]
    if veh and DoesEntityExist(veh) then
        DeleteVehicle(veh)
        spawnedVehs[plate] = nil
        TriggerServerEvent('parking:logToDiscord', '[PARKING][Client] Vehicle despawned: ' .. plate)
    end
end

local function CreateOrUpdateBlip(plate, entity, paid)
    if blips[plate] then
        RemoveBlip(blips[plate])
        blips[plate] = nil
    end
    local blip = AddBlipForEntity(entity)
    SetBlipSprite(blip, Config.Blip.sprite)
    SetBlipScale(blip, Config.Blip.scale)
    SetBlipColour(blip, paid and Config.Blip.colorPaid or Config.Blip.colorUnpaid)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString((paid and Config.Blip.textPaid or Config.Blip.textUnpaid) .. ' ' .. plate)
    EndTextCommandSetBlipName(blip)
    blips[plate] = blip

    local pos = GetEntityCoords(entity)
    TriggerServerEvent('parking:updateVehiclePosition', plate, pos.x, pos.y, pos.z)
end

local function RemoveBlipForPlate(plate)
    if blips[plate] then
        RemoveBlip(blips[plate])
        blips[plate] = nil
    end
end

CreateThread(function()
    while true do
        Wait(10000)

        local ped = PlayerPedId()
        local pCoords = GetEntityCoords(ped)
        local vehicles = GetGamePool('CVehicle')
        local platesNearby = {}

        for _, veh in ipairs(vehicles) do
            local vehPos = GetEntityCoords(veh)
            local dist = #(pCoords - vehPos)
            if dist <= Config.BlipDistance then
                local plateRaw = GetVehicleNumberPlateText(veh)
                local plateNoSpace = plateRaw:gsub("%s+", "")
                platesNearby[plateNoSpace] = veh
            end
        end

        ESX.TriggerServerCallback('parking:getVehiclesStatus', function(status)
            for plate, data in pairs(status) do
                local key = plate:gsub("%s+", "")
                local veh = platesNearby[key]

                if veh then
                    local vehPos = GetEntityCoords(veh)
                    local inFree = IsInFreeZone(vehPos)

                    if IsVehicleStopped(veh) and (data.hasTicket or not inFree) then
                        CreateOrUpdateBlip(plate, veh, data.hasTicket)
                    else
                        RemoveBlipForPlate(plate)
                    end
                end
            end

            for plate, veh in pairs(spawnedVehs) do
                if DoesEntityExist(veh) then
                    local vehPos = GetEntityCoords(veh)
                    local data = status[plate]
                    if data and data.position then
                        local savedPos = vector3(data.position.x, data.position.y, data.position.z)
                        local distMoved = #(vehPos - savedPos)
                        if distMoved > 5.0 then
                            TriggerServerEvent('parking:removeTicket', plate)
                            DespawnVehicle(plate)
                            TriggerServerEvent('parking:logToDiscord', '[PARKING][Client] Vehicle ' .. plate .. ' moved, ticket removed.')
                        end
                    end
                end
            end

        end)
    end
end)

local Locales = {}
local localeLoaded = false

local function LoadLocale()
    if localeLoaded then return end
    local lang = Config.Locale or 'en'
    local file = LoadResourceFile(GetCurrentResourceName(), ("locales/%s.json"):format(lang))
    if file then
        Locales = json.decode(file)
    end
    localeLoaded = true
end

local function Notify(msg, type)
    local notifyType = Config.Notification
    if notifyType == 'okokNotify' then
        if exports['okokNotify'] then
            exports['okokNotify']:Alert("Parking", msg, 5000, type or "info")
        else
            ESX.ShowNotification(msg)
        end
    elseif notifyType == 'mythic' then
        if exports['mythic_notify'] then
            exports['mythic_notify']:SendAlert({ type = type or "inform", text = msg })
        else
            ESX.ShowNotification(msg)
        end
    elseif notifyType == 'ox_lib' then
        if exports['ox_lib'] then
            exports['ox_lib']:notify({ title = "Parking", description = msg, type = type or "info" })
        else
            ESX.ShowNotification(msg)
        end
    else
        ESX.ShowNotification(msg)
    end
end

RegisterCommand('buyparkingticket', function(source, args)
    LoadLocale()
    local plateInput, hours
    if Config.PlateWithSpace then
        plateInput = table.concat({args[1], args[2]}, " ")
        hours = tonumber(args[3])
    else
        plateInput = args[1]
        hours = tonumber(args[2])
    end

    -- Debug print
    if Config.Debug then
        print("[PARKING][DEBUG] /buyparkingticket plateInput:", plateInput, "hours:", hours)
    end

    local minHours = Config.Debug and 0.01 or 1
    if not plateInput or not hours or hours < minHours then
        local usageMsg
        if Config.PlateWithSpace then
            usageMsg = Locales.buyticket_usage_withspace or "Use: /buyparkingticket [PLATE with space] [hours]"
        else
            usageMsg = Locales.buyticket_usage_nospace or "Use: /buyparkingticket [PLATE] [hours]"
        end
        if not hours or hours < minHours then
            usageMsg = usageMsg .. (Config.Debug and " (min 0.01)" or " (min 1)")
        end
        Notify(usageMsg, "info")
        return
    end

    --[[
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local foundVehicle = nil

    local vehicles = GetGamePool('CVehicle')
    for _, veh in ipairs(vehicles) do
        local vehPlate = GetVehicleNumberPlateText(veh):gsub("%s+", "")
        if vehPlate == plateInput:gsub("%s+", "") then
            local vehPos = GetEntityCoords(veh)
            if #(playerPos - vehPos) <= 10.0 then
                foundVehicle = veh
                break
            end
        end
    end

    if not foundVehicle then
        Notify(Locales.not_near_vehicle or "You are not near the vehicle with this plate or the vehicle does not exist!", "error")
        return
    end

    local vehPos = GetEntityCoords(foundVehicle)
    local heading = GetEntityHeading(foundVehicle)
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(foundVehicle))

    TriggerServerEvent('parking:tryBuyTicket', plateInput, hours, vehPos.x, vehPos.y, vehPos.z, heading, model)
    TriggerServerEvent('parking:logToDiscord', '[PARKING][Client] Ticket bought for ' .. plateInput .. ' for ' .. hours .. ' hours.')
    ]]--

    if Config.Debug then
        print("[PARKING][DEBUG] Searching for vehicle with plate:", plateInput)
    end

    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local foundVehicle = nil

    local vehicles = GetGamePool('CVehicle')
    for _, veh in ipairs(vehicles) do
        local vehPlate = GetVehicleNumberPlateText(veh):gsub("%s+", "")
        if vehPlate == plateInput:gsub("%s+", "") then
            local vehPos = GetEntityCoords(veh)
            if #(playerPos - vehPos) <= 10.0 then
                foundVehicle = veh
                break
            end
        end
    end

    if not foundVehicle then
        Notify(Locales.not_near_vehicle or "You are not near the vehicle with this plate or the vehicle does not exist!", "error")
        if Config.Debug then
            print("[PARKING][DEBUG] Vehicle not found or not near.")
        end
        return
    end

    local vehPos = GetEntityCoords(foundVehicle)
    local heading = GetEntityHeading(foundVehicle)
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(foundVehicle))

    if Config.Debug then
        print("[PARKING][DEBUG] Sending ticket request to server for plate:", plateInput, "hours:", hours)
    end
    TriggerServerEvent('parking:tryBuyTicket', plateInput, hours, vehPos.x, vehPos.y, vehPos.z, heading, model)
    TriggerServerEvent('parking:logToDiscord', '[PARKING][Client] Ticket bought for ' .. plateInput .. ' for ' .. hours .. ' hours.')
end)

RegisterNetEvent('parking:ticketBoughtNotify')
AddEventHandler('parking:ticketBoughtNotify', function(plate, hours)
    LoadLocale()
    local msg = (Locales.ticket_bought or "You bought a ticket: %s (%d hours)"):format(plate, hours)
    Notify(msg, "success")
end)

local towtruckerDispatch = {
    tickets = {},
    selected = 1,
    show = false
}

RegisterNetEvent('parking:towtruckerWaypoint')
AddEventHandler('parking:towtruckerWaypoint', function(pos)
    SetNewWaypoint(pos.x, pos.y)
    Notify(Locales.waypoint_set or "Waypoint set to vehicle.", "info")
end)

local function IsTowtrucker()
    local playerData = ESX.GetPlayerData()
    return playerData and playerData.job and playerData.job.name == 'towtrucker'
end

local filteredTickets = {}
local parkedSinceTimestamp = {}
local lastJobPlates = {}

local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%02ih %02im %02is", h, m, s)
    elseif m > 0 then
        return string.format("%02im %02is", m, s)
    else
        return string.format("%02is", s)
    end
end

local function shouldIgnore(ticket)
    if ticket.vehicle and ticket.vehicle.model then
        for _, model in ipairs(Config.IgnoreModels or {}) do
            if string.lower(ticket.vehicle.model) == string.lower(model) then
                return true
            end
        end
    end
    local plate = (ticket.plate or ""):gsub("%s+", "")
    for _, ignorePlate in ipairs(Config.IgnorePlates or {}) do
        if plate == ignorePlate then
            return true
        end
    end
    return false
end

local function UpdateTowtruckerDispatchUI()
    filteredTickets = {}
    local now = GetGameTimer()
    local newJobPlates = {}
    if towtruckerDispatch.show and IsTowtrucker() then
        local vehicles = GetGamePool('CVehicle')
        for _, ticket in ipairs(towtruckerDispatch.tickets) do
            if not shouldIgnore(ticket) then
                local foundStopped = false
                for _, veh in ipairs(vehicles) do
                    local vehPlate = GetVehicleNumberPlateText(veh):gsub("%s+", "")
                    if vehPlate == ticket.plate:gsub("%s+", "") and IsVehicleStopped(veh) then
                        foundStopped = true
                        break
                    end
                end
                if foundStopped then
                    table.insert(filteredTickets, ticket)
                    newJobPlates[ticket.plate] = true
                    if not parkedSinceTimestamp[ticket.plate] then
                        parkedSinceTimestamp[ticket.plate] = now
                    end
                end
            end
        end

        for plate, _ in pairs(newJobPlates) do
            if not lastJobPlates[plate] then
                TriggerServerEvent('parking:logToDiscord', '[PARKING][Client] New unpaid parking ticket: ' .. plate)
                Notify(Locales.new_job_desc and Locales.new_job_desc:format(plate) or ("New unpaid parking ticket: " .. plate), "info")
                PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", true)
            end
        end
        lastJobPlates = newJobPlates

        towtruckerDispatch.selected = math.min(math.max(1, towtruckerDispatch.selected), #filteredTickets)
        SetNuiFocus(true, false)
        SetNuiFocusKeepInput(true)
        SendNUIMessage({
            action = "show",
            tickets = filteredTickets,
            selected = towtruckerDispatch.selected
        })
    else
        SendNUIMessage({ action = "hide" })
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        parkedSinceTimestamp = {}
        lastJobPlates = {}
    end
end

RegisterNUICallback('dispatchNavigate', function(data, cb)
    if data.dir == "left" then
        towtruckerDispatch.selected = math.max(1, towtruckerDispatch.selected - 1)
    elseif data.dir == "right" then
        towtruckerDispatch.selected = math.min(#filteredTickets, towtruckerDispatch.selected + 1)
    elseif data.dir == "setSelected" and data.selected then
        towtruckerDispatch.selected = math.min(math.max(1, tonumber(data.selected)), #filteredTickets)
    end
    UpdateTowtruckerDispatchUI()
    cb('ok')
end)

RegisterNUICallback('dispatchWaypoint', function(data, cb)
    local idx = tonumber(data.selected) or towtruckerDispatch.selected
    idx = math.min(math.max(1, idx), #filteredTickets)
    local ticket = filteredTickets[idx]
    if ticket then
        TriggerServerEvent('parking:towtruckerSetWaypoint', ticket.plate)
        TriggerServerEvent('parking:logToDiscord', '[PARKING][Client] Waypoint set for plate: ' .. ticket.plate)
    end
    cb('ok')
end)

RegisterNUICallback('getParkovaneTime', function(data, cb)
    local idx = tonumber(data.selected) or towtruckerDispatch.selected
    idx = math.min(math.max(1, idx), #filteredTickets)
    local ticket = filteredTickets[idx]
    local seconds = 0
    if ticket and parkedSinceTimestamp[ticket.plate] then
        seconds = math.floor((GetGameTimer() - parkedSinceTimestamp[ticket.plate]) / 1000)
    end
    cb(formatTime(seconds))
end)

RegisterCommand('towdispatch', function()
    LoadLocale()
    if not IsTowtrucker() then
        Notify(Locales.not_towtrucker or 'You are not a Towtrucker!', "error")
        return
    end

    towtruckerDispatch.show = not towtruckerDispatch.show

    if towtruckerDispatch.show then
        ESX.TriggerServerCallback('parking:getUnpaidTickets', function(tickets)
            local filtered = {}
            local vehicles = GetGamePool('CVehicle')

            for _, ticket in ipairs(tickets) do
                local ticketPlate = ticket.plate:gsub("%s+", "")
                for _, veh in ipairs(vehicles) do
                    local vehPlate = GetVehicleNumberPlateText(veh):gsub("%s+", "")
                    if vehPlate == ticketPlate and IsVehicleStopped(veh) then
                        local vehCoords = GetEntityCoords(veh)
                        if not IsInFreeZone(vehCoords) then
                            table.insert(filtered, ticket)
                            break
                        end
                    end
                end
            end

            towtruckerDispatch.tickets = filtered
            towtruckerDispatch.selected = 1
            UpdateTowtruckerDispatchUI()
        end)
    else
        UpdateTowtruckerDispatchUI()
    end
end, false)


CreateThread(function()
    while true do
        Wait(5000)
        if towtruckerDispatch.show then
            if IsTowtrucker() then
                ESX.TriggerServerCallback('parking:getUnpaidTickets', function(tickets)
                    local filtered = {}
                    local vehicles = GetGamePool('CVehicle')

                    for _, ticket in ipairs(tickets) do
                        local ticketPlate = ticket.plate:gsub("%s+", "")
                        for _, veh in ipairs(vehicles) do
                            local vehPlate = GetVehicleNumberPlateText(veh):gsub("%s+", "")
                            if vehPlate == ticketPlate and IsVehicleStopped(veh) then
                                local vehCoords = GetEntityCoords(veh)
                                if not IsInFreeZone(vehCoords) then
                                    table.insert(filtered, ticket)
                                    break
                                end
                            end
                        end
                    end

                    towtruckerDispatch.tickets = filtered
                    towtruckerDispatch.selected = math.min(math.max(1, towtruckerDispatch.selected), #filtered)
                    UpdateTowtruckerDispatchUI()
                end)
            else
                towtruckerDispatch.show = false
                UpdateTowtruckerDispatchUI()
            end
        end
    end
end)

RegisterNetEvent('trs_parking:playTowJobSound')
AddEventHandler('trs_parking:playTowJobSound', function()
    PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", true)
end)

RegisterNetEvent('trs_parking:removeTowJob')
AddEventHandler('trs_parking:removeTowJob', function(plate)
    for i, ticket in ipairs(towtruckerDispatch.tickets) do
        if ticket.plate == plate then
            table.remove(towtruckerDispatch.tickets, i)
            break
        end
    end
    UpdateTowtruckerDispatchUI()
    RemoveBlipForPlate(plate)
end)

CreateThread(function()
    while true do
        Wait(1000)
        if IsTowtrucker() then
            ESX.TriggerServerCallback('parking:getUnpaidTickets', function(tickets)
                for _, ticket in ipairs(tickets) do
                    local plate = ticket.plate
                    local vehicles = GetGamePool('CVehicle')

                    for _, veh in ipairs(vehicles) do
                        local vehPlate = GetVehicleNumberPlateText(veh):gsub("%s+", "")
                        if vehPlate == plate:gsub("%s+", "") then
                            local vehCoords = GetEntityCoords(veh)
                            local inFreeZone = IsInFreeZone(vehCoords)

                            if IsVehicleStopped(veh) and not inFreeZone then
                                CreateOrUpdateBlip(plate, veh, false)
                            else
                                RemoveBlipForPlate(plate)
                            end
                        end
                    end
                end
            end)
        end
    end
end)
