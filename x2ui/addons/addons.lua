local function logApiCallbackError(context, err)
  local message = context .. " -- " .. tostring(err)
  if ADDON_API ~= nil and ADDON_API.Log ~= nil and type(ADDON_API.Log.Err) == "function" then
    ADDON_API.Log:Err(message)
  elseif X2Chat ~= nil then
    X2Chat:DispatchChatMessage(CMF_NOTICE, message)
  end
end

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
  if type(callback) ~= "function" then
    return
  end
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
    local status, err = pcall(callback, ...)
    if not status then
      logApiCallbackError("Addon event callback failed for " .. tostring(event), err)
    end
  end
end

function EventHandler:clear()
  self.listeners = {}
end

API_STORE = {
  settingPages = {},
  addons = {},
  knownUnitIds = {},
  ev = EventHandler:new()
}

local function trimString(value)
  return string.gsub(value, "^%s*(.-)%s*$", "%1")
end

local function addPackagePath(path)
  if path == nil or string.find(package.path, path, 1, true) then
    return
  end
  package.path = package.path .. ";" .. path
end

function sanitizeAddonId(addonId)
  local sanitized = addonId:gsub("[^%w_]", "_")
  if sanitized:match("^[%d]") then
    sanitized = "_" .. sanitized
  end
  return sanitized
end

local function dispatchApiEvent(this, event, ...)
  if API_STORE.ev ~= nil then
    API_STORE.ev:emit(event, ...)
  end
end

local function updateApiWindow(this, dt)
  if API_STORE.ev ~= nil then
    API_STORE.ev:emit("UPDATE", dt)
  end
  for i = #ADDON_API.timers, 1, -1 do
    local timer = ADDON_API.timers[i]
    if timer.when <= ADDON_API.Time:GetUiMsec() then
      table.remove(ADDON_API.timers, i)
      if type(timer.callback) == "function" then
        local status, err = pcall(timer.callback, unpack(timer.args, 1, timer.args.n))
        if not status then
          logApiCallbackError("Addon timer callback failed", err)
        end
      end
    end
  end
end

local function createApiWindow()
  local wnd = CreateEmptyWindow("aacApi", "UIParent")
  wnd:RegisterEvent("CHAT_MESSAGE")
  wnd:RegisterEvent("TEAM_MEMBERS_CHANGED")
  wnd:RegisterEvent("UI_RELOADED")
  wnd:RegisterEvent("UPDATE_PING_INFO")
  wnd:SetHandler("OnEvent", dispatchApiEvent)
  wnd:SetHandler("OnUpdate", updateApiWindow)
  AddonPatchWnd(wnd)
  ADDON_API.rootWindow = wnd
  wnd:AddAnchor("TOPLEFT", "UIParent", 0, 0)
  wnd:Show(true)
  return wnd
end

function SaveAddonSettings()
  local settings = API_STORE.settings or {}
  for _, addon in ipairs(API_STORE.addons or {}) do
    if addon.id ~= nil then
      settings[sanitizeAddonId(addon.id)] = addon.settings or {}
    end
  end
  API_STORE.settings = settings
  ADDON_API.File:Write("addon_settings", settings)
end

function resetApiStore()
  API_STORE = {
    settingPages = {},
    addons = {},
    knownUnitIds = {},
    ev = EventHandler:new()
  }
  ADDON_API.timers = {}
  if ADDON_API.profiler ~= nil then
    ADDON_API.profiler.totalWindows = 0
    ADDON_API.profiler.windowCounts = {}
  end
  X2DialogManager:DeleteByOwnerWindow("aacApi")
  apiEmptyWnd = createApiWindow()
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

function runAddon(filePath, api, baseDir, env)
  local directory = filePath:match("(.*)/[^/]*$")
  addPackagePath(directory .. "/?.lua")
  local addonFunc, err = loadfile(filePath)
  if not addonFunc then
    error("Failed to load addon: " .. err)
  end
  setfenv(addonFunc, env or ADDON_API.env)
  local status, result = pcall(addonFunc)
  if not status then
    error("Error running addon: " .. result)
  end
  if type(result) ~= "table" then
    error("Addon main.lua must return a table")
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
    local addonName = trimString(line)
    if addonName ~= "" and string.sub(addonName, 1, 1) ~= "#" and string.sub(addonName, 1, 2) ~= "--" then
      table.insert(addonNames, addonName)
    end
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
          ADDON_API.Log:Err("Failed to unload " .. v.id .. " -- " .. err)
        end
      end
    end
  end
  if apiEmptyWnd ~= nil then
    apiEmptyWnd:Show(false)
    apiEmptyWnd:ClearChildren()
  end
  resetApiStore()
  ADDON_API.env = CreateAddonSandbox(baseDir, ADDON_API)
  local settings = ADDON_API.File:Read("addon_settings")
  if settings == nil then
    settings = {}
  end
  API_STORE.settings = settings
  local addonNames = loadAddonNames(baseDir .. "/addons.txt")
  if #addonNames == 0 then
    return
  end
  API_STORE.addons = {}
  for _, file in ipairs(addonNames) do
    local settingsId = sanitizeAddonId(file)
    if settings[settingsId] == nil then
      settings[settingsId] = {enabled = true}
    end
    local addonEnv = CreateAddonEnvironment(baseDir, ADDON_API, ADDON_API.env)
    local filePath = baseDir .. "/" .. file .. "/main.lua"
    local status, addon = pcall(runAddon, filePath, ADDON_API, baseDir, addonEnv)
    if not status then
      X2Chat:DispatchChatMessage(CMF_SYSTEM, "Error loading addon " .. file .. ": " .. addon)
    else
      addon.id = file
      addon.settings = settings[settingsId]
      table.insert(API_STORE.addons, addon)
    end
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

apiEmptyWnd = createApiWindow()

local function OnUiReloaded()
  InitAddons()
  LoadAddons()
end

if X2Player:GetUIScreenState() == 6 then
  ADDON_API:DoIn(5000, OnUiReloaded)
end
