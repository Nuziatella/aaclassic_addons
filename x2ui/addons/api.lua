local DISALLOWED_UNIT_TYPES = {"housing"}
local DISALLOWED_TARGETING_UNITS = {
  "watchtarget",
  "targettarget",
  "target"
}

local function isValidPath(path)
  return not path:find("%.%.")
end

local function getAddonNameFromPath(path)
  return path:match("/Addon/([^/]+)/")
end

local function logAddonStats()
  local memoryUsage = UIParent:GetVirtualMemoryStats().usage
  local logString = "[ADDONS] High memory usage detected, logging Addon statistics. \n"
  logString = logString .. "Current memory usage: " .. memoryUsage .. " MB\n"
  logString = logString .. "Total windows created by addons: " .. ADDON_API.profiler.totalWindows .. "\n"
  local sortedAddons = {}
  for addonId, count in pairs(ADDON_API.profiler.windowCounts) do
    table.insert(sortedAddons, {addonId = addonId, count = count})
  end
  table.sort(sortedAddons, function(a, b)
    return a.count > b.count
  end)
  for i = 1, math.min(5, #sortedAddons) do
    logString = logString .. " - " .. sortedAddons[i].addonId .. ": " .. sortedAddons[i].count .. "\n"
  end
  UIParent:Warning(logString)
end

local function trackAddonWindowCreation(addonId)
  if addonId == nil then
    return
  end
  ADDON_API.profiler.totalWindows = ADDON_API.profiler.totalWindows + 1
  ADDON_API.profiler.windowCounts[addonId] = (ADDON_API.profiler.windowCounts[addonId] or 0) + 1
  local vmemStats = UIParent:GetVirtualMemoryStats()
  if vmemStats ~= nil and vmemStats.usage > 2800 then
    logAddonStats()
  end
end

local function getChatTimestamp()
  local timestamp = ""
  if X2Option:GetOptionItemValueByName("ShowChatTimestamps") > 0 then
    local timestampObj = X2Time:TimeToDate(X2Time:GetLocalTime())
    timestamp = string.format("%02d:%02d:%02d", timestampObj.hour, timestampObj.minute, timestampObj.second)
    timestamp = "|cFF8F8F8F" .. "[" .. timestamp .. "]|r "
  end
  return timestamp
end

local function serializeTable(val, name, skipnewlines, depth)
  skipnewlines = skipnewlines or false
  depth = depth or 0
  local tmp = string.rep(" ", depth)
  if name then
    tmp = tmp .. name .. " = "
  end
  if type(val) == "table" then
    local isArray = 0 < #val
    tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")
    for k, v in pairs(val) do
      if isArray then
        tmp = tmp .. serializeTable(v, nil, skipnewlines, depth + 4) .. "," .. (not skipnewlines and "\n" or "")
      else
        tmp = tmp .. serializeTable(v, k, skipnewlines, depth + 4) .. "," .. (not skipnewlines and "\n" or "")
      end
    end
    tmp = tmp .. string.rep(" ", depth) .. "}"
  elseif type(val) == "number" then
    tmp = tmp .. tostring(val)
  elseif type(val) == "string" then
    tmp = tmp .. string.format("%q", val)
  elseif type(val) == "boolean" then
    tmp = tmp .. (val and "true" or "false")
  elseif val == nil then
    tmp = tmp .. "nil"
  else
    tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
  end
  return tmp
end

local function deserializeTable(str)
  local env = setmetatable({}, nil)
  local func, loadErr = loadstring("return " .. str)
  if not func then
    return nil
  end
  setfenv(func, env)
  local success, result = pcall(func)
  if not success then
    error("Failed to deserialize string: " .. result)
  end
  return result
end

local function inCombat()
  return X2Unit:UnitCombatState("player")
end

local function isAllowedUnitTypeById(unitId)
  local unitInfo = X2Unit:GetUnitInfoById(unitId)
  if unitInfo == nil then
    return false
  end
  return not DISALLOWED_UNIT_TYPES[unitInfo.type]
end

local function isAllowedUnitType(unit)
  local unitId = X2Unit:GetUnitId(unit)
  return isAllowedUnitTypeById(unitId)
end

ADDON_API = {
  File = {},
  Unit = {},
  Team = {},
  Log = {},
  Interface = {},
  Cursor = {},
  Input = {},
  Time = {},
  Player = {},
  Bag = {},
  Ability = {},
  Item = {},
  Skill = {},
  Store = {},
  Bank = {},
  Equipment = {},
  SiegeWeapon = {},
  ItemEnchant = {},
  Map = {},
  Quest = {},
  Zone = {},
  Craft = {},
  Option = {},
  Chat = {},
  baseDir = "",
  rootWindow = {},
  timers = {},
  serialize = serializeTable,
  profiler = {
    totalWindows = 0,
    windowCounts = {}
  }
}

function ADDON_API.Log:Info(message)
  if type(message) == "table" then
    local text = serializeTable(message)
    local timestamp = getChatTimestamp()
    X2Chat:DispatchChatMessage(CMF_SYSTEM, timestamp .. text)
  else
    local timestamp = getChatTimestamp()
    X2Chat:DispatchChatMessage(CMF_SYSTEM, timestamp .. "" .. message)
  end
end

function ADDON_API.Log:Err(message)
  local timestamp = getChatTimestamp()
  X2Chat:DispatchChatMessage(CMF_NOTICE, timestamp .. "" .. message)
end

function ADDON_API.Log:WriteEventParameters(event, ...)
  local params = {
    ...
  }
  local timestamp = getChatTimestamp()
  X2Chat:DispatchChatMessage(CMF_SYSTEM, timestamp .. "Event: " .. event)
  for i, param in ipairs(params) do
    if type(param) == "table" then
      X2Chat:DispatchChatMessage(CMF_SYSTEM, timestamp .. "Parameter " .. i .. ": " .. serializeTable(param))
    else
      X2Chat:DispatchChatMessage(CMF_SYSTEM, timestamp .. "Parameter " .. i .. ": " .. tostring(param))
    end
  end
end

function ADDON_API.File:Write(path, tbl)
  if not isValidPath(path) then
    error("Invalid file path")
  end
  local fullPath = ADDON_API.baseDir .. "/" .. path
  local file = io.open(fullPath, "w")
  if not file then
    error("Could not open file for writing: " .. fullPath)
  end
  local content = serializeTable(tbl)
  file:write(content)
  file:close()
end

function ADDON_API.File:Read(path)
  if not isValidPath(path) then
    error("Invalid file path")
  end
  local fullPath = ADDON_API.baseDir .. "/" .. path
  local file = io.open(fullPath, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return deserializeTable(content)
end

function ADDON_API.GetSettings(addonId)
  for _, addon in ipairs(API_STORE.addons) do
    if addon.id == sanitizeAddonId(addonId) then
      return addon.settings
    end
  end
  return {}
end

function ADDON_API.SaveSettings()
  SaveAddonSettings()
end

function ADDON_API.Interface:CreateWindow(id, title, x, y, tabs)
  trackAddonWindowCreation(getAddonNameFromPath(debug.getinfo(2, "Sn").source))
  local frame = CreateWindow(id, "UIParent", tabs)
  frame:SetExtent(x or 680, y or 615)
  frame:SetTitle(title)
  AddonPatchWnd(frame)
  return frame
end

function ADDON_API.Interface:CreateEmptyWindow(id)
  trackAddonWindowCreation(getAddonNameFromPath(debug.getinfo(2, "Sn").source))
  local frame = CreateEmptyWindow(id, "UIParent")
  AddonPatchWnd(frame)
  return frame
end

function ADDON_API.Interface:CreateWidget(type, id, parent)
  local widget = UIParent:CreateWidget(type, id, parent)
  AddonPatchWnd(widget)
  return widget
end

function ADDON_API.Interface:CreateStatusBar(name, parent, type)
  local widget = W_BAR.CreateStatusBar(name, parent, type)
  AddonPatchWnd(widget)
  return widget
end

function ADDON_API.Interface:CreateComboBox(window)
  local widget = W_CTRL.CreateComboBox(window)
  AddonPatchWnd(widget)
  return widget
end

function ADDON_API.Interface:ApplyButtonSkin(btn, skin)
  return ApplyButtonSkin(btn, skin)
end

function ADDON_API.Interface:SetTooltipOnPos(text, target, posX, posY)
  SetTooltipOnPos(text, target, posX, posY)
end

function ADDON_API.Interface:Free(wnd)
  if wnd ~= nil then
    wnd:Show(false)
    wnd:ReleaseHandler("OnEvent")
    wnd:ReleaseHandler("OnClick")
    wnd:ReleaseHandler("OnShow")
    wnd:ReleaseHandler("OnHide")
    wnd:ReleaseHandler("OnUpdate")
    wnd:ReleaseHandler("OnEnter")
    wnd:ReleaseHandler("OnLeave")
    wnd:ReleaseHandler("OnKeyUp")
    wnd:ReleaseHandler("OnKeyDown")
    wnd:ReleaseHandler("OnWheelUp")
    wnd:ReleaseHandler("OnWheelDown")
    wnd:ReleaseHandler("OnDragStart")
    wnd:ReleaseHandler("OnDragReceive")
    wnd:ReleaseHandler("OnDragEnd")
  end
  wnd = nil
  return wnd
end

function ADDON_API.Interface:GetScreenWidth()
  return UIParent:GetScreenWidth()
end

function ADDON_API.Interface:GetScreenHeight()
  return UIParent:GetScreenHeight()
end

function ADDON_API.Interface:GetUIScale()
  return UIParent:GetUIScale()
end

function ADDON_API.Unit:GetUnitNameById(id)
  return X2Unit:GetUnitNameById(id)
end

function ADDON_API.Unit:GetUnitInfoById(id)
  if not isAllowedUnitTypeById(id) then
    return nil
  end
  return X2Unit:GetUnitInfoById(id)
end

function ADDON_API.Unit:UnitName(unit)
  return X2Unit:UnitName(unit)
end

function ADDON_API.Unit:GetUnitScreenPosition(unit)
  return X2Unit:GetUnitScreenPosition(unit)
end

function ADDON_API.Unit:UnitDistance(unit)
  return X2Unit:UnitDistance(unit)
end

function ADDON_API.Unit:GetUnitId(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:GetUnitId(unit)
end

function ADDON_API.Unit:UnitBuffCount(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:UnitBuffCount(unit)
end

function ADDON_API.Unit:UnitBuff(unit, index)
  if not isAllowedUnitType(unit) then
    return {}
  end
  return X2Unit:UnitBuff(unit, index)
end

function ADDON_API.Unit:UnitWorldPosition(unit)
  local id = X2Unit:GetUnitId(unit)
  return X2Unit:GetUnitWorldPosition(id)
end

function ADDON_API.Unit:UnitDeBuffCount(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:UnitDeBuffCount(unit)
end

function ADDON_API.Unit:UnitDeBuff(unit, index)
  if not isAllowedUnitType(unit) then
    return {}
  end
  return X2Unit:UnitDeBuff(unit, index)
end

function ADDON_API.Unit:UnitHealth(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:UnitHealth(unit)
end

function ADDON_API.Unit:UnitMaxHealth(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:UnitMaxHealth(unit)
end

function ADDON_API.Unit:UnitMana(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:UnitMana(unit)
end

function ADDON_API.Unit:UnitMaxMana(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:UnitMaxMana(unit)
end

function ADDON_API.Unit:UnitInfo(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:UnitInfo(unit)
end

function ADDON_API.Unit:UnitModifierInfo(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:UnitModifierInfo(unit)
end

function ADDON_API.Unit:UnitClass(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:UnitClass(unit)
end

function ADDON_API.Unit:UnitGearScore(unit)
  if not isAllowedUnitType(unit) then
    return nil
  end
  return X2Unit:UnitGearScore(unit)
end

function ADDON_API.Unit:UnitTeamAuthority(unit)
  return X2Unit:UnitTeamAuthority(unit)
end

function ADDON_API.Unit:UnitIsTeamMember(unit)
  return X2Unit:UnitIsTeamMember(unit)
end

function ADDON_API.Unit:UnitIsForceAttack(unit)
  return X2Unit:UnitIsForceAttack(unit)
end

function ADDON_API.Unit:GetFactionName(unit)
  return X2Unit:GetFactionName(unit)
end

function ADDON_API.Unit:GetUnitScreenNameTagOffset(unit)
  local id = X2Unit:GetUnitId(unit)
  return X2Unit:GetUnitScreenNameTagOffset(id)
end

function ADDON_API.Unit:GetHighAbilityRscInfo()
  return X2Unit:GetHighAbilityRscInfo()
end

function ADDON_API.Unit:UnitIsOffline(unit)
  return X2Unit:UnitIsOffline(unit)
end

function ADDON_API.Unit:GetOverHeadMarkerUnitId(markerIndex)
  if 12 < markerIndex or markerIndex < 1 then
    error("api.Unit:GetOverHeadMarkerUnitId: markerIndex must be between 1 and 12")
  end
  return X2Unit:GetOverHeadMarkerUnitId(markerIndex)
end

function ADDON_API.Unit:GetCurrentZoneGroup()
  return X2Unit:GetCurrentZoneGroup()
end

function ADDON_API.Unit:TargetUnit(unit)
  for _, disallowed in ipairs(DISALLOWED_TARGETING_UNITS) do
    if unit == disallowed then
      return
    end
  end
  return X2Unit:TargetUnit(unit)
end

function ADDON_API.Team:InviteToTeam(name, party)
  return X2Team:InviteToTeam(name, party)
end

function ADDON_API.Team:SetRole(role)
  return X2Team:SetRole(role)
end

function ADDON_API.Team:IsPartyTeam()
  return X2Team:IsPartyTeam()
end

function ADDON_API.Team:IsPartyRaid()
  return X2Team:IsPartyRaid()
end

function ADDON_API.Team:GetMemberIndexByName(playerName)
  return X2Team:GetMemberIndexByName(playerName)
end

function ADDON_API.Team:GetTeamDistributorName()
  return X2Team:GetTeamDistributorName()
end

function ADDON_API.Team:GetTeamPlayerIndex()
  return X2Team:GetTeamPlayerIndex()
end

function ADDON_API.Team:GetRole(memberIndex)
  return X2Team:GetRole(memberIndex)
end

function ADDON_API.Team:MakeTeamOwner(target)
  return X2Team:MakeTeamOwner(target)
end

function ADDON_API.Team:MoveTeamMember(fromIndex, toIndex)
  return X2Team:MoveTeamMember(fromIndex, toIndex)
end

function ADDON_API.Bag:EquipBagItem(bagSlot, isAux)
  if inCombat() then
    return
  end
  return X2Bag:EquipBagItem(bagSlot, isAux)
end

function ADDON_API.Bag:GetBagItemInfo(bagType, index)
  return X2Bag:GetBagItemInfo(bagType, index)
end

function ADDON_API.Bag:CountItems()
  return X2Bag:CountItems()
end

function ADDON_API.Bag:Capacity()
  return X2Bag:Capacity()
end

function ADDON_API.Bag:CountBagItemByItemType(type)
  return X2Bag:CountBagItemByItemType(type)
end

function ADDON_API.Bag:GetCurrency()
  return X2Bag:GetCurrency()
end

function ADDON_API.Cursor:ClearCursor()
  return X2Cursor:ClearCursor()
end

function ADDON_API.Cursor:SetCursorImage(image, x, y)
  return X2Cursor:SetCursorImage(image, x, y)
end

function ADDON_API.Cursor:GetCursorPickedBagItemIndex()
  return X2Cursor:GetCursorPickedBagItemIndex()
end

function ADDON_API.Cursor:GetCursorPickedBagItemAmount()
  return X2Cursor:GetCursorPickedBagItemAmount()
end

function ADDON_API.Cursor:GetCursorInfo()
  return X2Cursor:GetCursorInfo()
end

function ADDON_API.Time:GetUiMsec()
  return X2Time:GetUiMsec()
end

function ADDON_API.Time:GetLocalTime()
  return X2Time:GetLocalTime()
end

function ADDON_API.Time:PeriodTimeToDate(localTime, period)
  return X2Time:PeriodTimeToDate(localTime, period)
end

function ADDON_API.Time:TimeToDate(epochTimestamp)
  return X2Time:TimeToDate(epochTimestamp)
end

function ADDON_API.Time:GetGameTime()
  return X2Time:GetGameTime()
end

function ADDON_API.Quest:IsCompleted(questTypeId)
  return X2Quest:IsCompleted(questTypeId)
end

function ADDON_API.Quest:GetActiveQuestTitle(questTypeId)
  return X2Quest:GetActiveQuestTitle(questTypeId)
end

function ADDON_API.Quest:GetQuestContextMainTitle(questTypeId)
  return X2Quest:GetQuestContextMainTitle(questTypeId)
end

function ADDON_API.Quest:GetQuestContextBody(questTypeId)
  return X2Quest:GetQuestContextBody(questTypeId)
end

function ADDON_API.Input:IsShiftKeyDown()
  return X2Input:IsShiftKeyDown()
end

function ADDON_API.Input:IsControlKeyDown()
  return X2Input:IsControlKeyDown()
end

function ADDON_API.Input:IsAltKeyDown()
  return X2Input:IsAltKeyDown()
end

function ADDON_API.Input:GetMousePos()
  return X2Input:GetMousePos()
end

function ADDON_API.Player:ChangeAppellation(type)
  if inCombat() then
    return nil
  end
  return X2Player:ChangeAppellation(type)
end

function ADDON_API.Player:GetShowingAppellation()
  return X2Player:GetShowingAppellation()
end

function ADDON_API.Player:GetGamePoints()
  return X2Player:GetGamePoints()
end

function ADDON_API.Player:GetCrimeInfo()
  return X2Player:GetCrimeInfo()
end

function ADDON_API.On(event, callback)
  API_STORE.ev:on(event, callback)
end

function ADDON_API:DoIn(msec, callback, ...)
  local now = self.Time:GetUiMsec()
  table.insert(self.timers, {
    when = now + msec,
    callback = callback,
    arg = arg
  })
end

function ADDON_API:Emit(event, ...)
  API_STORE.ev:emit(event, ...)
end

function ADDON_API.Ability:GetBuffTooltip(buffId, itemLevel)
  return X2Ability:GetBuffTooltip(buffId, itemLevel or 1)
end

function ADDON_API.Ability:GetAbilityFromView(index)
  return X2Ability:GetAbilityFromView(index)
end

function ADDON_API.Ability:IsActiveAbility(ability)
  return X2Ability:IsActiveAbility(ability)
end

function ADDON_API.Ability:GetSkillsetNameById(skillsetId)
  return X2Ability:GetAbilityStr(skillsetId)
end

function ADDON_API.Ability:GetUnitClassName(unit)
  local unitId = X2Unit:GetUnitId(unit)
  local unitInfo = X2Unit:GetUnitInfoById(unitId)
  if unitInfo ~= nil and unitInfo.class then
    return F_UNIT.GetPlayerJobName(unitInfo.class["1"], unitInfo.class["2"], unitInfo.class["3"])
  end
  return nil
end

function ADDON_API.Ability:GetClassNameFromSkillsetIds(skillset1, skillset2, skillset3)
  return F_UNIT.GetPlayerJobName(skillset1, skillset2, skillset3)
end

function ADDON_API.Item:GetItemInfoByType(itemId)
  return X2Item:GetItemInfoByType(itemId)
end

function ADDON_API.Skill:GetSkillTooltip(skillId)
  return X2Skill:GetSkillTooltip(skillId, 0, SIK_DESCRIPTION)
end

function ADDON_API.Store:GetSellerShareRatio()
  return X2Store:GetSellerShareRatio()
end

function ADDON_API.Store:GetSpecialtyRatio()
  return X2Store:GetSpecialtyRatio()
end

function ADDON_API.Store:GetProductionZoneGroups()
  return X2Store:GetProductionZoneGroups()
end

function ADDON_API.Store:GetSellableZoneGroups(startZoneId)
  return X2Store:GetSellableZoneGroups(startZoneId)
end

function ADDON_API.Store:GetSpecialtyRatioBetween(startZoneId, finishZoneId)
  return X2Store:GetSpecialtyRatioBetween(startZoneId, finishZoneId)
end

function ADDON_API.Bank:CountItems()
  return X2Bank:CountItems()
end

function ADDON_API.Bank:Capacity()
  return X2Bank:Capacity()
end

function ADDON_API.Bank:GetCurrency()
  return X2Bank:GetCurrency()
end

function ADDON_API.Bank:GetLinkText(inventorySlotId)
  return X2Bank:GetLinkText(inventorySlotId)
end

function ADDON_API.Equipment:GetEquippedItemTooltipInfo(slotIdx)
  return X2Equipment:GetEquippedItemTooltipInfo(slotIdx)
end

function ADDON_API.Equipment:GetEquippedItemTooltipText(unit, slotIdx)
  return X2Equipment:GetEquippedItemTooltipText("player", slotIdx)
end

function ADDON_API.Equipment:GetEquippedSkillsetLunagems(unit)
  local skillsetLunagemIds = {}
  local targetEquipmentSlots = {ES_WAIST, ES_ARMS}
  for _, slotIdx in ipairs(targetEquipmentSlots) do
    local itemInfo = X2Equipment:GetEquippedItemTooltipText(unit, slotIdx)
    if itemInfo ~= nil and itemInfo.socketInfo ~= nil then
      for _, lunagemId in ipairs(itemInfo.socketInfo.socketItem) do
        local lunagemInfo = X2Item:GetItemInfoByType(lunagemId)
        if string.find(lunagemInfo.name, " Ancient ") or string.find(lunagemInfo.name, " Eternal ") then
          table.insert(skillsetLunagemIds, lunagemId)
        end
      end
    end
  end
  return skillsetLunagemIds
end

function ADDON_API.SiegeWeapon:GetSiegeWeaponSpeed()
  return X2SiegeWeapon:GetSiegeWeaponSpeed()
end

function ADDON_API.SiegeWeapon:GetSiegeWeaponTurnSpeed()
  return X2SiegeWeapon:GetSiegeWeaponTurnSpeed()
end

function ADDON_API.ItemEnchant:GetRatioInfos()
  return X2ItemEchant:GetRatioInfos()
end

function ADDON_API.ItemEnchant:GetEnchantItemInfo()
  return X2ItemEnchant:GetEnchantItemInfo()
end

function ADDON_API.ItemEnchant:GetSupportItemInfo()
  return X2ItemEnchant:GetSupportItemInfo()
end

function ADDON_API.ItemEnchant:GetTargetItemInfo()
  return X2ItemEchant:GetTargetItemInfo()
end

function ADDON_API.Map:ToggleMapWithPortal(portal_zone_id, x, y, z)
  worldmap:ToggleMapWithPortal(portal_zone_id, x, y, z)
end

function ADDON_API.Map:GetPlayerSextants()
  return worldmap:GetPlayerSextants()
end

function ADDON_API.Zone:GetZoneStateInfoByZoneId(zoneId)
  return X2Map:GetZoneStateInfoByZoneId(zoneId)
end

function ADDON_API.Craft:GetCraftBaseInfo(craftId)
  return X2Craft:GetCraftBaseInfo(craftId)
end

function ADDON_API.Craft:GetCraftMaterialInfo(craftId)
  return X2Craft:GetCraftMaterialInfo(craftId, 0)
end

function ADDON_API.Craft:GetCraftProductInfo(craftId)
  return X2Craft:GetCraftProductInfo(craftId)
end

function ADDON_API.Craft:GetCraftTypeByItemType(itemType)
  return X2Craft:GetCraftTypeByItemType(itemType)
end

function ADDON_API.Craft:GetCraftTypesByName(actAbilityGroupType, actAbilityCategoryType, keyword)
  return X2Craft:GetCraftTypesByName(actAbilityGroupType, actAbilityCategoryType, keyword)
end

function ADDON_API.Option:GetOnlyUseMyPortalSetting()
  return GetOptionItemValue(OPTION_ITEM_USE_ONLY_MY_PORTAL)
end

function ADDON_API.Option:SetOnlyUseMyPortalSetting(value)
  if value ~= 0 and value ~= 1 then
    value = value and 1 or 0
  end
  return SetOptionItemValue(OPTION_ITEM_USE_ONLY_MY_PORTAL, value)
end

function ADDON_API.Option:GetCustomCloneModelCountSetting()
  return GetOptionItemValue(OPTION_ITEM_CUSTOM_MAX_CLONE_MODEL)
end

function ADDON_API.Option:SetCustomCloneModelCountSetting(value)
  if value < 1 then
    value = 1
  elseif 5 < value then
    value = 5
  end
  return SetOptionItemValue(OPTION_ITEM_CUSTOM_MAX_CLONE_MODEL, value)
end

function ADDON_API.Option:GetCustomCloneModeSetting()
  return GetOptionItemValue(OPTION_ITEM_CUSTOM_CLONE_MODE)
end

function ADDON_API.Option:SetCustomCloneModeSetting(value)
  if value ~= 0 and value ~= 1 then
    value = value and 1 or 0
  end
  return SetOptionItemValue(OPTION_ITEM_CUSTOM_CLONE_MODE, value)
end

function ADDON_API.Chat:DispatchChatMessage(chatMessageFilter, message)
  X2Chat:DispatchChatMessage(chatMessageFilter, message)
end

function ADDON_API.Chat:ExpressEmotion(emotion)
  X2Chat:ExpressEmotion(emotion)
end
