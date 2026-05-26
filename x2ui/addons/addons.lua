EventHandler = {}
EventHandler.__index = EventHandler

function EventHandler:new()
  local instance = {
    listeners = {}
  }
  setmetatable(instance, EventHandler)
  return instance
end

function EventHandler:on(event, callback)
  if not self.listeners[event] then
    self.listeners[event] = {}
  end
  table.insert(self.listeners[event], callback)
end

function EventHandler:emit(event, ...)
  if not self.listeners[event] then
    return
  end
  for _, callback in ipairs(self.listeners[event]) do
    callback(...)
  end
end

function EventHandler:clear()
  self.listeners = {}
end

API_STORE = {
  settingPages = {},
  addons = {},
  ev = EventHandler:new()
}

function sanitizeAddonId(addonId)
  local sanitized = addonId:gsub("[^%w_]", "_")
  if sanitized:match("^[%d]") then
    sanitized = "_" .. sanitized
  end
  return sanitized
end

function SaveAddonSettings()
  local settings = {}
  for _, addon in ipairs(API_STORE.addons) do
    settings[sanitizeAddonId(addon.id)] = addon.settings
  end
  ADDON_API.File:Write("addon_settings", settings)
end

function resetApiStore()
  API_STORE = {
    settingPages = {},
    addons = {},
    ev = EventHandler:new()
  }
  X2DialogManager:DeleteByOwnerWindow("aacApi")
  apiEmptyWnd = CreateEmptyWindow("aacApi", "UIParent")
  apiEmptyWnd:Show(true)
  EventHandler:clear()
end

function ADDON_API.addSettingPage(name, pageFunc)
  table.insert(API_STORE.settingPages, {
    titleText = "ArcheAge Classic",
    buttonText = name,
    resetKind = nil,
    visibleRestartTip = false,
    func = pageFunc
  })
end

function ADDON_API.CreateOptionSubFrame(parent, subFrameIndex)
  return CreateOptionSubFrame(parent, subFrameIndex)
end

function runAddon(filePath, api, baseDir)
  local directory = filePath:match("(.*)/[^/]*$")
  package.path = package.path .. ";" .. directory .. "/?.lua"
  local addonFunc, err = loadfile(filePath)
  if not addonFunc then
    error("Failed to load addon: " .. err)
  end
  setfenv(addonFunc, ADDON_API.env)
  local status, result = pcall(addonFunc)
  if not status then
    error("Error running addon: " .. result)
  end
  return result
end

function isLuaFile(filename)
  return filename:sub(-4) == ".lua"
end

function loadAddonNames(filePath)
  local addonNames = {}
  local file, err = io.open(filePath, "r")
  if not file then
    apiEmptyWnd:Show(false)
    return {}
  end
  for line in file:lines() do
    table.insert(addonNames, line)
  end
  file:close()
  return addonNames
end

function InitAddons()
  local UCCPath = X2Ucc:GetUccUserDirectoryPath()
  local dbgPath = string.sub(UCCPath, 1, string.len(UCCPath) - 4)
  local baseDir = string.format("%s/Addon", dbgPath)
  if API_STORE.addons ~= nil then
    for k, v in pairs(API_STORE.addons) do
      if v.OnUnload ~= nil then
        local status, err = pcall(v.OnUnload)
        if not status then
          ADDON_API.Log:Err("Failed to load " .. v.id .. " -- " .. err)
        end
      end
    end
  end
  apiEmptyWnd:Show(false)
  apiEmptyWnd:ClearChildren()
  apiEmptyWnd:Show(true)
  resetApiStore()
  ADDON_API.env = CreateAddonSandbox(baseDir, ADDON_API)
  local addonNames = loadAddonNames(baseDir .. "/addons.txt")
  if #addonNames == 0 then
    return
  end
  API_STORE.addons = {}
  for _, file in ipairs(addonNames) do
    local filePath = baseDir .. "/" .. file .. "/main.lua"
    local status, err = pcall(runAddon, filePath, ADDON_API, baseDir)
    if not status then
      X2Chat:DispatchChatMessage(CMF_SYSTEM, "Error loading addon " .. file .. ": " .. err)
    else
      err.id = file
      table.insert(API_STORE.addons, err)
    end
  end
  local settings = ADDON_API.File:Read("addon_settings")
  if settings == nil then
    settings = {}
    for _, addon in ipairs(API_STORE.addons) do
      settings[sanitizeAddonId(addon.id)] = {enabled = true}
    end
  end
  for _, addon in ipairs(API_STORE.addons) do
    if settings[sanitizeAddonId(addon.id)] == nil then
      settings[sanitizeAddonId(addon.id)] = {enabled = true}
    end
    addon.settings = settings[sanitizeAddonId(addon.id)]
  end
  API_STORE.settings = settings
  ADDON_API.File:Write("addon_settings", settings)
  addonsList:UpdateAddonList()
end

function LoadAddons()
  local addons = API_STORE.addons
  for _, addon in ipairs(addons) do
    if addon.settings.enabled == true and addon.OnLoad ~= nil then
      local status, err = pcall(addon.OnLoad)
      if status then
        addon.status = "LOADED"
      else
        addon.status = "ERROR"
        addon.error = err
        ADDON_API.Log:Err("Failed to load " .. addon.id .. " -- " .. err)
      end
    end
  end
end

apiEmptyWnd = CreateEmptyWindow("aacApi", "UIParent")
apiEmptyWnd:RegisterEvent("CHAT_MESSAGE")
apiEmptyWnd:RegisterEvent("TEAM_MEMBERS_CHANGED")
apiEmptyWnd:RegisterEvent("UI_RELOADED")
apiEmptyWnd:RegisterEvent("UPDATE_PING_INFO")
apiEmptyWnd:SetHandler("OnEvent", function(this, event, ...)
  API_STORE.ev:emit(event, ...)
end)

function apiEmptyWnd:OnUpdate(dt)
  if API_STORE.ev ~= nil then
    API_STORE.ev:emit("UPDATE", dt)
  end
  for i = #ADDON_API.timers, 1, -1 do
    local timer = ADDON_API.timers[i]
    if timer.when <= ADDON_API.Time:GetUiMsec() then
      table.remove(ADDON_API.timers, i)
      timer.callback(timer.arg)
    end
  end
end

apiEmptyWnd:SetHandler("OnUpdate", apiEmptyWnd.OnUpdate)
AddonPatchWnd(apiEmptyWnd)
ADDON_API.rootWindow = apiEmptyWnd
apiEmptyWnd:AddAnchor("TOPLEFT", "UIParent", 0, 0)
apiEmptyWnd:Show(true)

local function OnUiReloaded()
  InitAddons()
  LoadAddons()
end

if X2Player:GetUIScreenState() == 6 then
  ADDON_API:DoIn(5000, OnUiReloaded)
end
