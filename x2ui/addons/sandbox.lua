CUIC_RAID_COMMAND_MESSAGE = 9002
CUIC_COMBAT_TEXT_FRAME = 9003
CUIC_TARGET_OF_TARGET_FRAME = 9004
CUIC_WATCH_TARGET_FRAME = 9005
CUIC_RAID_MANAGER = 9006
CUIC_COMMUNITY_WINDOW = 9007
CUIC_ENCHANT_WINDOW = 9008
CUIC_ADVENTURE_GUIDE = 9009
CUIC_RESIDENT_GLOBAL_TRADE = 9010
local blockedEvents = {
  HOUSE_TAX_INFO = true,
  UNIT_ENTERED_SIGHT = true,
  UNIT_LEAVED_SIGHT = true
}
local sanitizedEvents = {COMBAT_MSG = true}
local blockedCombatMsgTypes = {
  SPELL_AURA_APPLIED = true,
  SPELL_AURA_REMOVED = true,
  SPELL_CAST_START = true,
  SPELL_CAST_SUCCESS = true,
  ENVIRONMENT_DAMAGE = true
}
local blockedSkills = {10082}
local blockedBuffs = {
  599,
  600,
  601,
  5278,
  5279,
  5280,
  8224,
  8225,
  7743
}

local function checkIfCalledFromAddon()
  for level = 1, 10 do
    local info = debug.getinfo(level, "S")
    if not info then
      break
    end
    local source = string.lower(string.gsub(info.source or "", "\\", "/"))
    if string.find(source, "/documents/", 1, true) and string.find(source, "/addon/", 1, true) then
      return true
    end
  end
  return false
end

local patchedWindows = setmetatable({}, {__mode = "k"})

function AddonPatchWnd(wnd)
  if type(wnd) ~= "table" and type(wnd) ~= "userdata" then
    return wnd
  end
  if patchedWindows[wnd] then
    return wnd
  end
  patchedWindows[wnd] = true
  
  local function deepPatchChildren(root)
    local queue = {root}
    local seen = {
      [root] = true
    }
    while 0 < #queue do
      local current = table.remove(queue, 1)
      if type(current) == "table" or type(current) == "userdata" then
        if not patchedWindows[current] then
          pcall(AddonPatchWnd, current)
        end
        if type(current) == "table" then
          local idx = 1
          while true do
            local child = current[idx]
            if child == nil then
              break
            end
            if (type(child) == "table" or type(child) == "userdata") and not seen[child] then
              seen[child] = true
              table.insert(queue, child)
            end
            idx = idx + 1
          end
          for k, child in pairs(current) do
            if (type(child) == "table" or type(child) == "userdata") and not seen[child] then
              seen[child] = true
              table.insert(queue, child)
            end
          end
        end
      end
    end
  end
  
  local rawRegister = wnd.RegisterEvent
  local rawSetHandler = wnd.SetHandler
  local rawOnClick = wnd.OnClick
  local rawSetTarget = wnd.SetTarget
  local rawCreateWidget = wnd.CreateWidget
  local rawCreateChild = wnd.CreateChildWidget
  if type(rawRegister) == "function" then
    function wnd:RegisterEvent(eventName, callback)
      if blockedEvents[eventName] then
        ADDON_API.Log:Info("|cFFC13D36[Addon API] Event: '" .. eventName .. "' is not allowed to be registered.")
        
        return
      end
      return rawRegister(self, eventName, callback)
    end
  end
  if type(rawSetHandler) == "function" then
    function wnd:SetHandler(eventName, handler)
      if eventName == "OnEvent" and type(handler) == "function" then
        local function wrapped(self, event, ...)
          if blockedEvents[event] then
            ADDON_API.Log:Info("|cFFC13D36[Addon API] Event: '" .. event .. "' is not allowed to be handled.")
            
            return
          end
          if sanitizedEvents[event] then
            local args = {
              ...
            }
            if event == "COMBAT_MSG" then
              local combatMsgType = args[2]
              if blockedCombatMsgTypes[combatMsgType] then
                return
              end
              if combatMsgType == "SPELL_AURA_REMOVED" or combatMsgType == "SPELL_AURA_APPLIED" then
                for i, blockedBuff in ipairs(blockedBuffs) do
                  if args[5] == blockedBuff then
                    return
                  end
                end
              end
              if combatMsgType == "SPELL_CAST_START" or combatMsgType == "SPELL_CAST_SUCCESS" then
                for i, blockedSkill in ipairs(blockedSkills) do
                  if args[5] == blockedSkill then
                    return
                  end
                end
              end
            end
          end
          return handler(self, event, ...)
        end
        
        return rawSetHandler(self, eventName, wrapped)
      end
      return rawSetHandler(self, eventName, handler)
    end
  end
  if type(rawOnClick) == "function" then
    function wnd:OnClick(arg)
      if checkIfCalledFromAddon() then
        return
      end
      return rawOnClick(self, arg)
    end
  end
  if type(rawSetTarget) == "function" then
    function wnd:SetTarget(arg)
      if checkIfCalledFromAddon() then
        return
      end
      return rawSetTarget(self, arg)
    end
  end
  
  local function patchChild(child)
    if not child then
      return child
    end
    return AddonPatchWnd(child)
  end
  
  if type(rawCreateWidget) == "function" then
    function wnd:CreateWidget(...)
      local child = rawCreateWidget(self, ...)
      
      child = patchChild(child)
      deepPatchChildren(child)
      return child
    end
  end
  if type(rawCreateChild) == "function" then
    function wnd:CreateChildWidget(...)
      local child = rawCreateChild(self, ...)
      
      child = patchChild(child)
      deepPatchChildren(child)
      return child
    end
  end
  deepPatchChildren(wnd)
  return wnd
end

local rawGetContent = ADDON.GetContent
local wrappedAddon = setmetatable({}, {
  __index = function(_, k)
    if k == "GetContent" then
      return function(_, ...)
        local wnd = rawGetContent(ADDON, ...)
        return AddonPatchWnd(wnd)
      end
    end
    local v = ADDON[k]
    if type(v) == "function" then
      return function(_, ...)
        return v(ADDON, ...)
      end
    end
    return v
  end
})
if not table.pack then
  function table.pack(...)
    return {
      n = select("#", ...),
      
      ...
    }
  end
end
if not table.unpack then
  table.unpack = unpack
end

local function PatchFactory(lib)
  if type(lib) ~= "table" then
    return lib
  end
  local proxy = {}
  local fnCache = {}
  setmetatable(proxy, {
    __index = function(_, k)
      local v = lib[k]
      if type(v) ~= "function" then
        return v
      end
      if fnCache[k] then
        return fnCache[k]
      end
      
      local function wrapped(...)
        local n = select("#", ...)
        if n == 0 then
          local results = table.pack(v())
          for i = 1, results.n do
            if type(results[i]) == "table" or type(results[i]) == "userdata" then
              results[i] = AddonPatchWnd(results[i])
            end
          end
          return table.unpack(results, 1, results.n)
        end
        local args = table.pack(...)
        if args[1] == proxy then
          args[1] = lib
        end
        local results = table.pack(v(table.unpack(args, 1, args.n)))
        for i = 1, results.n do
          if type(results[i]) == "table" or type(results[i]) == "userdata" then
            results[i] = AddonPatchWnd(results[i])
          end
        end
        return table.unpack(results, 1, results.n)
      end
      
      fnCache[k] = wrapped
      return wrapped
    end,
    __newindex = function(_, k, v)
      lib[k] = v
    end,
    __pairs = function()
      return pairs(lib)
    end,
    __len = function()
      return #lib
    end
  })
  return proxy
end

local PW_CTRL = PatchFactory(W_CTRL)
local PW_ICON = PatchFactory(W_ICON)
local PW_UNIT = PatchFactory(W_UNIT)
local PW_ETC = PatchFactory(W_ETC)
local PW_BAR = PatchFactory(W_BAR)
local PW_MONEY = PatchFactory(W_MONEY)
local PW_BTN = PatchFactory(W_BTN)

local function patchedCreateItemIconButton(...)
  local button = CreateItemIconButton(...)
  return AddonPatchWnd(button)
end

function CreateAddonSandbox(baseDir, api)
  local sandbox_loaded = {}
  api.baseDir = baseDir
  local sandboxEnv = {
    api = api,
    print = print,
    string = string,
    table = table,
    math = math,
    pairs = pairs,
    ipairs = ipairs,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    pcall = pcall,
    xpcall = xpcall,
    unpack = unpack,
    baseDir = baseDir,
    getmetatable = getmetatable,
    ADDON = wrappedAddon,
    BUTTON_BASIC = BUTTON_BASIC,
    BUTTON_CONTENTS = BUTTON_CONTENTS,
    CURSOR_PATH = CURSOR_PATH,
    FONT_COLOR = FONT_COLOR,
    FONT_SIZE = FONT_SIZE,
    TEXTURE_PATH = TEXTURE_PATH,
    F_SLOT = F_SLOT,
    F_UNIT = F_UNIT,
    SLOT_STYLE = SLOT_STYLE,
    STATUSBAR_STYLE = STATUSBAR_STYLE,
    COMBAT_TEXT_COLOR = COMBAT_TEXT_COLOR,
    ConvertColor = ConvertColor,
    ApplyTextColor = ApplyTextColor,
    ApplyButtonSkin = ApplyButtonSkin,
    X2Util = X2Util,
    X2Hotkey = X2Hotkey,
    X2NameTag = X2NameTag,
    X2Player = X2Player,
    CreateItemIconButton = patchedCreateItemIconButton,
    petFrame = AddonPatchWnd(petFrame),
    combatTextLocale = combatTextLocale,
    ParseCombatMessage = ParseCombatMessage,
    GetTextureInfo = GetTextureInfo,
    UIC = {
      DEV_WINDOW = UIC_DEV_WINDOW,
      ABILITY_CHANGE = UIC_ABILITY_CHANGE,
      CHARACTER_INFO = UIC_CHARACTER_INFO,
      AUTH_MSG_WND = UIC_AUTH_MSG_WND,
      BUBBLE_ACTION_BAR = UIC_BUBBLE_ACTION_BAR,
      BAG = UIC_BAG,
      DEATH_AND_RESURRECTION_WND = UIC_DEATH_AND_RESURRECTION_WND,
      OPTION_FRAME = UIC_OPTION_FRAME,
      SYSTEM_CONFIG_FRAME = UIC_SYSTEM_CONFIG_FRAME,
      GAME_EXIT_FRAME = UIC_GAME_EXIT_FRAME,
      SLAVE_EQUIPMENT = UIC_SLAVE_EQUIPMENT,
      PLAYER_UNITFRAME = UIC_PLAYER_UNITFRAME,
      TARGET_UNITFRAME = UIC_TARGET_UNITFRAME,
      RAID_COMMAND_MESSAGE = CUIC_RAID_COMMAND_MESSAGE,
      COMBAT_TEXT_FRAME = CUIC_COMBAT_TEXT_FRAME,
      TARGET_OF_TARGET_FRAME = CUIC_TARGET_OF_TARGET_FRAME,
      WATCH_TARGET_FRAME = CUIC_WATCH_TARGET_FRAME,
      RAID_MANAGER = CUIC_RAID_MANAGER,
      COMMUNITY_WINDOW = CUIC_COMMUNITY_WINDOW,
      ENCHANT_WINDOW = CUIC_ENCHANT_WINDOW
    },
    ALIGN = {
      LEFT = ALIGN_LEFT,
      RIGHT = ALIGN_RIGHT,
      CENTER = ALIGN_CENTER,
      TOP = ALIGN_TOP,
      BOTTOM = ALIGN_BOTTOM,
      BOTTOM_RIGHT = ALIGN_BOTTOM_RIGHT,
      BOTTOM_LEFT = ALIGN_BOTTOM_LEFT,
      TOP_LEFT = ALIGN_TOP_LEFT,
      TOP_RIGHT = ALIGN_TOP_RIGHT
    },
    W_CTRL = PW_CTRL,
    W_ICON = PW_ICON,
    W_UNIT = PW_UNIT,
    W_ETC = PW_ETC,
    W_BAR = PW_BAR,
    W_MONEY = PW_MONEY,
    W_BTN = PW_BTN,
    EQUIP_SLOT = {
      HEAD = ES_HEAD,
      NECK = ES_NECK,
      CHEST = ES_CHEST,
      WAIST = ES_WAIST,
      LEGS = ES_LEGS,
      HANDS = ES_HANDS,
      FEET = ES_FEET,
      ARMS = ES_ARMS,
      BACK = ES_BACK,
      EAR_1 = ES_EAR_1,
      EAR_2 = ES_EAR_2,
      FINGER_1 = ES_FINGER_1,
      FINGER_2 = ES_FINGER_2,
      UNDERSHIRT = ES_UNDERSHIRT,
      UNDERPANTS = ES_UNDERPANTS,
      MAINHAND = ES_MAINHAND,
      OFFHAND = ES_OFFHAND,
      RANGED = ES_RANGED,
      MUSICAL = ES_MUSICAL,
      BACKPACK = ES_BACKPACK,
      COSPLAY = ES_COSPLAY
    },
    CHAT_MESSAGE_FILTERS = {
      CHANNEL_INFO = CMF_CHANNEL_INFO,
      WHISPER = CMF_WHISPER,
      SYSTEM = CMF_SYSTEM,
      NOTICE = CMF_NOTICE,
      SAY = CMF_SAY,
      PARTY = CMF_PARTY,
      RAID = CMF_RAID,
      RAID_COMMAND = CMF_RAID_COMMAND,
      EXPEDITION = CMF_EXPEDITION,
      FAMILY = CMF_FAMILY,
      FACTION = CMF_FACTION,
      ZONE = CMF_ZONE,
      TRADE = CMF_TRADE,
      FIND_PARTY = CMF_FIND_PARTY,
      TRIAL = CMF_TRIAL,
      RACE = CMF_RACE,
      MSG_QUEST = CMF_MSG_QUEST,
      ETC_GROUP = CMF_ETC_GROUP,
      LOOT_METHOD_CHANGED = CMF_LOOT_METHOD_CHANGED,
      ADDED_ITEM_SELF = CMF_ADDED_ITEM_SELF,
      ADDED_ITEM_TEAM = CMF_ADDED_ITEM_TEAM,
      SELF_SKILL_INFO = CMF_SELF_SKILL_INFO,
      SELF_STATUS_INFO = CMF_SELF_STATUS_INFO,
      SELF_MONEY_CHANGED = CMF_SELF_MONEY_CHANGED,
      SELF_HONOR_POINT_CHANGED = CMF_SELF_HONOR_POINT_CHANGED,
      SELF_LIVING_POINT_CHANGED = CMF_SELF_LIVING_POINT_CHANGED,
      SELF_CONTRIBUTION_POINT_CHANGED = CMF_SELF_CONTRIBUTION_POINT_CHANGED,
      SELF_LEADERSHIP_POINT_CHANGED = CMF_SELF_LEADERSHIP_POINT_CHANGED,
      TRADE_STORE_MSG = CMF_TRADE_STORE_MSG,
      HERO_SEASON_UPDATED = CMF_HERO_SEASON_UPDATED,
      WEB_CAST_INFO = CMF_WEB_CAST_INFO,
      DOMINION_AND_SIEGE_INFO = CMF_DOMINION_AND_SIEGE_INFO,
      COMMUNITY = CMF_COMMUNITY,
      BLOCK_INFO = CMF_BLOCK_INFO,
      FRIEND_INFO = CMF_FRIEND_INFO,
      FAMILY_INFO = CMF_FAMILY_INFO,
      COMBAT_MELEE_DAMAGE = CMF_COMBAT_MELEE_DAMAGE,
      COMBAT_MELEE_MISSED = CMF_COMBAT_MELEE_MISSED,
      COMBAT_SPELL_DAMAGE = CMF_COMBAT_SPELL_DAMAGE,
      COMBAT_SPELL_MISSED = CMF_COMBAT_SPELL_MISSED,
      COMBAT_SPELL_HEALED = CMF_COMBAT_SPELL_HEALED,
      COMBAT_SPELL_ENERGIZE = CMF_COMBAT_SPELL_ENERGIZE,
      COMBAT_SPELL_CAST = CMF_COMBAT_SPELL_CAST,
      COMBAT_SPELL_AURA = CMF_COMBAT_SPELL_AURA,
      COMBAT_ENVIRONMENTAL_DMANAGE = CMF_COMBAT_ENVIRONMENTAL_DMANAGE,
      COMBAT_SRC_GROUP = CMF_COMBAT_SRC_GROUP,
      COMBAT_DST_GROUP = CMF_COMBAT_DST_GROUP
    },
    UI_EVENTS = {
      CHAT_MESSAGE = "CHAT_MESSAGE",
      LOOT_DICE = "LOOT_DICE",
      LOOTING_RULE_METHOD_CHANGED = "LOOTING_RULE_METHOD_CHANGED",
      LOOTING_RULE_MASTER_CHANGED = "LOOTING_RULE_MASTER_CHANGED",
      LOOTING_RULE_GRADE_CHANGED = "LOOTING_RULE_GRADE_CHANGED",
      APPELLATION_GAINED = "APPELLATION_GAINED",
      LOOTING_RULE_BOP_CHANGED = "LOOTING_RULE_BOP_CHANGED",
      TOGGLE_WALK = "TOGGLE_WALK",
      TOGGLE_FOLLOW = "TOGGLE_FOLLOW",
      CHAT_JOINED_CHANNEL = "CHAT_JOINED_CHANNEL",
      CHAT_LEAVED_CHANNEL = "CHAT_LEAVED_CHANNEL",
      NOTICE_MESSAGE = "NOTICE_MESSAGE",
      CHAT_FAILED = "CHAT_FAILED",
      REQUIRE_ITEM_TO_CHAT = "REQUIRE_ITEM_TO_CHAT",
      REQUIRE_DELAY_TO_CHAT = "REQUIRE_DELAY_TO_CHAT",
      CHAT_MSG_QUEST = "CHAT_MSG_QUEST",
      CHAT_MSG_DOODAD = "CHAT_MSG_DOODAD",
      EXPIRED_ITEM = "EXPIRED_ITEM",
      ADDED_ITEM = "ADDED_ITEM",
      REMOVED_ITEM = "REMOVED_ITEM",
      CRAFT_FAILED = "CRAFT_FAILED",
      GLIDER_MOVED_INTO_BAG = "GLIDER_MOVED_INTO_BAG",
      ITEM_ACQUISITION_BY_LOOT = "ITEM_ACQUISITION_BY_LOOT",
      MONEY_ACQUISITION_BY_LOOT = "MONEY_ACQUISITION_BY_LOOT",
      SKILL_LEARNED = "SKILL_LEARNED",
      MATE_SKILL_LEARNED = "MATE_SKILL_LEARNED",
      SKILL_CHANGED = "SKILL_CHANGED",
      SKILLS_RESET = "SKILLS_RESET",
      ABILITY_CHANGED = "ABILITY_CHANGED",
      PREMIUM_LABORPOWER_CHANGED = "PREMIUM_LABORPOWER_CHANGED",
      LABORPOWER_CHANGED = "LABORPOWER_CHANGED",
      ACTABILITY_EXPERT_CHANGED = "ACTABILITY_EXPERT_CHANGED",
      ACTABILITY_EXPERT_GRADE_CHANGED = "ACTABILITY_EXPERT_GRADE_CHANGED",
      DOODAD_PHASE_MSG = "DOODAD_PHASE_MSG",
      HOUSE_FARM_MSG = "HOUSE_FARM_MSG",
      UCC_IMPRINT_SUCCEEDED = "UCC_IMPRINT_SUCCEEDED",
      BUILD_AREA_MSG = "BUILD_AREA_MSG",
      PLAYER_MONEY = "PLAYER_MONEY",
      PLAYER_HONOR_POINT = "PLAYER_HONOR_POINT",
      PLAYER_LIVING_POINT = "PLAYER_LIVING_POINT",
      PLAYER_CONTRIBUTION_POINT = "PLAYER_CONTRIBUTION_POINT",
      PLAYER_LEADERSHIP_POINT = "PLAYER_LEADERSHIP_POINT",
      PLAYER_AA_POINT = "PLAYER_AA_POINT",
      GRADE_ENCHANT_RESULT = "GRADE_ENCHANT_RESULT",
      ITEM_SOCKETING_RESULT = "ITEM_SOCKETING_RESULT",
      ITEM_ENCHANT_MAGICAL_RESULT = "ITEM_ENCHANT_MAGICAL_RESULT",
      ITEM_SMELTING_RESULT = "ITEM_SMELTING_RESULT",
      GRADE_ENCHANT_BROADCAST = "GRADE_ENCHANT_BROADCAST",
      NOTIFY_WEB_TRANSFER_STATE = "NOTIFY_WEB_TRANSFER_STATE",
      DOMINION = "DOMINION",
      COMMUNITY_ERROR = "COMMUNITY_ERROR",
      BLOCKED_USER_LIST = "BLOCKED_USER_LIST",
      FRIENDLIST = "FRIENDLIST",
      FAMILY_ERROR = "FAMILY_ERROR",
      FAMILY_MEMBER_ADDED = "FAMILY_MEMBER_ADDED",
      FAMILY_MEMBER_LEFT = "FAMILY_MEMBER_LEFT",
      FAMILY_MEMBER_KICKED = "FAMILY_MEMBER_KICKED",
      FAMILY_MEMBER = "FAMILY_MEMBER",
      FAMILY_OWNER_CHANGED = "FAMILY_OWNER_CHANGED",
      FAMILY_REMOVED = "FAMILY_REMOVED",
      FACTION_RELATION_PROPOSED = "FACTION_RELATION_PROPOSED",
      FACTION_RELATION_ACCEPTED = "FACTION_RELATION_ACCEPTED",
      FACTION_RELATION_DECLINED = "FACTION_RELATION_DECLINED",
      FACTION_RELATION_CANCELLED = "FACTION_RELATION_CANCELLED",
      FACTION_RELATION_EXPIRED = "FACTION_RELATION_EXPIRED",
      EXPEDITION_EXP = "EXPEDITION_EXP",
      FAMILY_EXP_ADD = "FAMILY_EXP_ADD",
      FAMILY_NAME_CHANGED = "FAMILY_NAME_CHANGED",
      RESIDENT_SERVICE_POINT_CHANGED = "RESIDENT_SERVICE_POINT_CHANGED",
      CHAT_DICE_VALUE = "CHAT_DICE_VALUE",
      CRIME_REPORTED = "CRIME_REPORTED",
      TOWER_DEF_MSG = "TOWER_DEF_MSG",
      SAVE_SCREEN_SHOT = "SAVE_SCREEN_SHOT",
      TRIAL_MESSAGE = "TRIAL_MESSAGE",
      AUCTION_BIDDEN = "AUCTION_BIDDEN",
      AUCTION_BOUGHT_BY_SOMEONE = "AUCTION_BOUGHT_BY_SOMEONE",
      SELL_SPECIALTY = "SELL_SPECIALTY",
      SHOW_SEXTANT_POS = "SHOW_SEXTANT_POS",
      EXP_CHANGED = "EXP_CHANGED",
      ABILITY_EXP_CHANGED = "ABILITY_EXP_CHANGED",
      ACQUAINTANCE_LOGIN = "ACQUAINTANCE_LOGIN",
      HPW_ZONE_STATE_CHANGE = "HPW_ZONE_STATE_CHANGE",
      SHOW_ACCUMULATE_HONOR_POINT_DURING_HPW = "SHOW_ACCUMULATE_HONOR_POINT_DURING_HPW",
      ITEM_EQUIP_RESULT = "ITEM_EQUIP_RESULT",
      INSTANT_GAME_KILL = "INSTANT_GAME_KILL",
      INSTANT_GAME_UNEARNED_WIN_REMAIN_TIME = "INSTANT_GAME_UNEARNED_WIN_REMAIN_TIME",
      CHAT_MSG_ALARM = "CHAT_MSG_ALARM",
      HOUSE_CANCEL_SELL_SUCCESS = "HOUSE_CANCEL_SELL_SUCCESS",
      HOUSE_CANCEL_SELL_FAIL = "HOUSE_CANCEL_SELL_FAIL",
      HOUSE_SET_SELL_SUCCESS = "HOUSE_SET_SELL_SUCCESS",
      HOUSE_SET_SELL_FAIL = "HOUSE_SET_SELL_FAIL",
      HOUSE_BUY_SUCCESS = "HOUSE_BUY_SUCCESS",
      HOUSE_BUY_FAIL = "HOUSE_BUY_FAIL",
      HOUSE_SALE_SUCCESS = "HOUSE_SALE_SUCCESS",
      BOT_SUSPECT_REPORTED = "BOT_SUSPECT_REPORTED",
      NATION_INDEPENDENCE = "NATION_INDEPENDENCE",
      NATION_TAXRATE = "NATION_TAXRATE",
      SECOND_PASSWORD_CREATION_COMPLETED = "SECOND_PASSWORD_CREATION_COMPLETED",
      SECOND_PASSWORD_CHANGE_COMPLETED = "SECOND_PASSWORD_CHANGE_COMPLETED",
      SECOND_PASSWORD_CLEAR_COMPLETED = "SECOND_PASSWORD_CLEAR_COMPLETED",
      SECOND_PASSWORD_CHECK_COMPLETED = "SECOND_PASSWORD_CHECK_COMPLETED",
      SECOND_PASSWORD_CHECK_OVER_FAILED = "SECOND_PASSWORD_CHECK_OVER_FAILED",
      SECOND_PASSWORD_ACCOUNT_LOCKED = "SECOND_PASSWORD_ACCOUNT_LOCKED",
      ITEM_LOOK_CONVERTED = "ITEM_LOOK_CONVERTED",
      AUDIENCE_JOINED = "AUDIENCE_JOINED",
      AUDIENCE_LEFT = "AUDIENCE_LEFT",
      ACTABILITY_EXPERT_EXPANDED = "ACTABILITY_EXPERT_EXPANDED",
      INVALID_NAME_POLICY = "INVALID_NAME_POLICY",
      HERO_SEASON_UPDATED = "HERO_SEASON_UPDATED",
      LOOT_PACK_ITEM_BROADCAST = "LOOT_PACK_ITEM_BROADCAST",
      DICE_BID_RULE_CHANGED = "DICE_BID_RULE_CHANGED",
      BADWORD_USER_REPORED_RESPONE_MSG = "BADWORD_USER_REPORED_RESPONE_MSG",
      HEIR_SKILL_LEARN = "HEIR_SKILL_LEARN",
      HEIR_SKILL_RESET = "HEIR_SKILL_RESET",
      TEAM_MEMBERS_CHANGED = "TEAM_MEMBERS_CHANGED",
      UI_RELOADED = "UI_RELOADED",
      UPDATE_PING_INFO = "UPDATE_PING_INFO",
      MOUSE_DOWN = "MOUSE_DOWN",
      LEFT_LOADING = "LEFT_LOADING",
      HERO_SCORE_UPDATED = "HERO_SCORE_UPDATED",
      START_HERO_ELECTION_PERIOD = "START_HERO_ELECTION_PERIOD",
      UPDATE_HERO_ELECTION_CONDITION = "UPDATE_HERO_ELECTION_CONDITION",
      END_HERO_ELECTION_PERIOD = "END_HERO_ELECTION_PERIOD",
      NATION_INVITE = "NATION_INVITE",
      NATION_KICK = "NATION_KICK",
      PLAYER_JURY_POINT = "PLAYER_JURY_POINT",
      JURY_WAITING_NUMBER = "JURY_WAITING_NUMBER",
      CHAT_EMOTION = "CHAT_EMOTION",
      IME_STATUS_CHANGED = "IME_STATUS_CHANGED",
      OPEN_COMMON_FARM_INFO = "OPEN_COMMON_FARM_INFO",
      INTERACTION_END = "INTERACTION_END",
      WEB_BROWSER_ESC_EVENT = "WEB_BROWSER_ESC_EVENT",
      BLOCKED_USER_UPDATE = "BLOCKED_USER_UPDATE",
      UNIT_COMBAT_STATE_CHANGED = "UNIT_COMBAT_STATE_CHANGED",
      ENTERED_WORLD = "ENTERED_WORLD",
      TARGET_OVER = "TARGET_OVER",
      RELOAD_COSMETIC_WINDOW = "RELOAD_COSMETIC_WINDOW",
      DEMO_MODE = "DEMO_MODE",
      DEMO_CHAR_RESET = "DEMO_CHAR_RESET",
      AGGRO_METER_UPDATED = "AGGRO_METER_UPDATED",
      AGGRO_METER_CLEARED = "AGGRO_METER_CLEARED",
      DYNAMIC_ACTION_BAR_SHOW = "DYNAMIC_ACTION_BAR_SHOW",
      DYNAMIC_ACTION_BAR_HIDE = "DYNAMIC_ACTION_BAR_HIDE",
      DYNAMIC_ACTION_EXECUTE = "DYNAMIC_ACTION_EXECUTE",
      UPDATE_BINDINGS = "UPDATE_BINDINGS",
      GOODS_MAIL_INBOX_UPDATE = "GOODS_MAIL_INBOX_UPDATE",
      UNIT_NPC_EQUIPMENT_CHANGED = "UNIT_NPC_EQUIPMENT_CHANGED",
      UPDATE_INGAME_SHOP = "UPDATE_INGAME_SHOP",
      PLAYER_BM_POINT = "PLAYER_BM_POINT",
      INTERACTION_START = "INTERACTION_START",
      INTERACTION_LIST = "INTERACTION_LIST",
      DRAW_DOODAD_SIGN_TAG = "DRAW_DOODAD_SIGN_TAG",
      DRAW_DOODAD_TOOLTIP = "DRAW_DOODAD_TOOLTIP",
      SIM_DOODAD_MSG = "SIM_DOODAD_MSG",
      BAG_UPDATE = "BAG_UPDATE",
      BAG_EXPANDED = "BAG_EXPANDED",
      CHANGED_AUTO_USE_AAPOINT = "CHANGED_AUTO_USE_AAPOINT",
      BANK_UPDATE = "BANK_UPDATE",
      BANK_EXPANDED = "BANK_EXPANDED",
      PLAYER_BANK_MONEY = "PLAYER_BANK_MONEY",
      PLAYER_BANK_AA_POINT = "PLAYER_BANK_AA_POINT",
      COFFER_UPDATE = "COFFER_UPDATE",
      CREATE_CHARACTER_FAILED = "CREATE_CHARACTER_FAILED",
      FADE_INOUT_DONE = "FADE_INOUT_DONE",
      OPEN_WORLD_QUEUE = "OPEN_WORLD_QUEUE",
      REFRESH_WORLD_QUEUE = "REFRESH_WORLD_QUEUE",
      SHOW_CHARACTER_CREATE_WINDOW = "SHOW_CHARACTER_CREATE_WINDOW",
      SHOW_CHARACTER_CUSTOMIZE_WINDOW = "SHOW_CHARACTER_CUSTOMIZE_WINDOW",
      SHOW_CHARACTER_ABILITY_WINDOW = "SHOW_CHARACTER_ABILITY_WINDOW",
      USE_ALL_ASSETS = "USE_ALL_ASSETS",
      ENTERED_LOGIN = "ENTERED_LOGIN",
      LEFT_LOGIN = "LEFT_LOGIN",
      LOOT_BAG_CLOSE = "LOOT_BAG_CLOSE",
      MAIL_INBOX_UPDATE = "MAIL_INBOX_UPDATE",
      MAIL_SENTBOX_UPDATE = "MAIL_SENTBOX_UPDATE",
      MAIL_RETURNED = "MAIL_RETURNED",
      MAIL_SENT_SUCCESS = "MAIL_SENT_SUCCESS",
      MAIL_INBOX_ITEM_TAKEN = "MAIL_INBOX_ITEM_TAKEN",
      MAIL_INBOX_MONEY_TAKEN = "MAIL_INBOX_MONEY_TAKEN",
      MAIL_INBOX_ATTACHMENT_TAKEN_ALL = "MAIL_INBOX_ATTACHMENT_TAKEN_ALL",
      MAIL_INBOX_TAX_PAID = "MAIL_INBOX_TAX_PAID",
      MAIL_WRITE_ITEM_UPDATE = "MAIL_WRITE_ITEM_UPDATE",
      UPDATE_OPTION_BINDINGS = "UPDATE_OPTION_BINDINGS",
      OPEN_CONFIG = "OPEN_CONFIG",
      LEAVING_WORLD_STARTED = "LEAVING_WORLD_STARTED",
      LEAVING_WORLD_CANCELED = "LEAVING_WORLD_CANCELED",
      SAVE_PORTAL = "SAVE_PORTAL",
      DELETE_PORTAL = "DELETE_PORTAL",
      RENAME_PORTAL = "RENAME_PORTAL",
      QUEST_LEFT_TIME_UPDATED = "QUEST_LEFT_TIME_UPDATED",
      FOLDER_STATE_CHANGED = "FOLDER_STATE_CHANGED",
      END_QUEST_CHAT_BUBBLE = "END_QUEST_CHAT_BUBBLE",
      QUEST_HIDDEN_READY = "QUEST_HIDDEN_READY",
      QUEST_HIDDEN_COMPLETE = "QUEST_HIDDEN_COMPLETE",
      QUEST_ERROR_INFO = "QUEST_ERROR_INFO",
      QUEST_TASK_READY = "QUEST_TASK_READY",
      TEAM_MEMBER_DISCONNECTED = "TEAM_MEMBER_DISCONNECTED",
      SET_OVERHEAD_MARK = "SET_OVERHEAD_MARK",
      TEAM_ROLE_CHANGED = "TEAM_ROLE_CHANGED",
      TEAM_HEALTH_CHANGED = "TEAM_HEALTH_CHANGED",
      TEAM_MANA_CHANGED = "TEAM_MANA_CHANGED",
      TOGGLE_RAID_FRAME_PARTY = "TOGGLE_RAID_FRAME_PARTY",
      TOGGLE_PARTY_FRAME = "TOGGLE_PARTY_FRAME",
      RAID_FRAME_SIMPLE_VIEW = "RAID_FRAME_SIMPLE_VIEW",
      UPDATE_DURABILITY_STATUS = "UPDATE_DURABILITY_STATUS",
      UNIT_EQUIPMENT_CHANGED = "UNIT_EQUIPMENT_CHANGED",
      NPC_INTERACTION_END = "NPC_INTERACTION_END",
      OPEN_EMBLEM_IMPRINT_UI = "OPEN_EMBLEM_IMPRINT_UI",
      DIVE_START = "DIVE_START",
      DIVE_END = "DIVE_END",
      SPELLCAST_START = "SPELLCAST_START",
      SPELLCAST_STOP = "SPELLCAST_STOP",
      SPELLCAST_SUCCEEDED = "SPELLCAST_SUCCEEDED",
      TARGET_CHANGED = "TARGET_CHANGED",
      TARGET_TO_TARGET_CHANGED = "TARGET_TO_TARGET_CHANGED",
      BAD_USER_LIST_UPDATE = "BAD_USER_LIST_UPDATE",
      SET_UI_MESSAGE = "SET_UI_MESSAGE"
    }
  }
  setmetatable(sandboxEnv, {__metatable = "locked"})
  
  function sandboxEnv.require(name)
    if name == "api" then
      return ADDON_API
    end
    if type(name) ~= "string" then
      error("Invalid require path: " .. tostring(name))
    end
    if string.find(name, "..", 1, true) or string.find(name, ":", 1, true) or string.sub(name, 1, 1) == "/" then
      error("Invalid require path: " .. tostring(name))
    end
    if not sandbox_loaded[name] then
      local file, err = loadfile(baseDir .. "/" .. name .. ".lua")
      if not file then
        error("Error loading file " .. err)
      end
      local module_env = setmetatable({}, {__index = sandboxEnv})
      setfenv(file, module_env)
      local result = file()
      if result == nil then
        result = true
      end
      sandbox_loaded[name] = result
    end
    return sandbox_loaded[name]
  end
  
  return sandboxEnv
end
