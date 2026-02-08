-- SkyridingFrameHider
-- Hide any frame while skyriding, flying, or mounted
-- Configure via /sfh commands

local addonName, addon = ...

---------------------------------------------------------------------------
-- Upvalue caching (local lookups are faster than global table lookups)
---------------------------------------------------------------------------
local IsMounted = IsMounted
local IsFlying = IsFlying
local type = type
local pairs = pairs
local issecretvalue = issecretvalue

-- Cached API references (resolved once during init, avoids repeated nil-checks)
local GetGlidingInfo  -- C_PlayerInfo.GetGlidingInfo
local GetPlayerAura   -- C_UnitAuras.GetPlayerAuraBySpellID

-- Constants
local SKYRIDING_SPELL_ID = 410137
local TICKER_INTERVAL = 0.25 -- seconds between checks while mounted

-- Default settings
local defaults = {
	frameNames = {},
	mode = "skyriding", -- "skyriding" | "flying" | "mounted"
}

-- Runtime state
local db                       -- Cached reference to SkyridingFrameHiderDB
local trackedFrames = {}       -- Resolved frame references
local numTrackedFrames = 0     -- Cached count for fast early-exit checks
local frameStates = {}         -- Original alpha/mouse state before hiding
local updateTicker             -- Ticker for frequent updates while mounted
local lastShouldHide = false   -- Track state changes to avoid redundant work
local initialized = false

-- Color helpers for chat output
local function PrintMsg(msg)
	print("|cFF33AAFF[SFH]|r " .. msg)
end

local function PrintError(msg)
	print("|cFFFF3333[SFH]|r " .. msg)
end

local function PrintSuccess(msg)
	print("|cFF33FF33[SFH]|r " .. msg)
end

-- Initialize saved variables with defaults
local function InitializeDB()
	if not SkyridingFrameHiderDB then
		SkyridingFrameHiderDB = {}
	end

	for k, v in pairs(defaults) do
		if SkyridingFrameHiderDB[k] == nil then
			if type(v) == "table" then
				SkyridingFrameHiderDB[k] = {}
			else
				SkyridingFrameHiderDB[k] = v
			end
		end
	end

	-- Cache reference to avoid global lookup in hot path
	db = SkyridingFrameHiderDB

	-- Cache API availability once (these never change at runtime)
	if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
		GetGlidingInfo = C_PlayerInfo.GetGlidingInfo
	end
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		GetPlayerAura = C_UnitAuras.GetPlayerAuraBySpellID
	end
end

---------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------

local function ShouldHideFrames()
	if not IsMounted() then
		return false
	end

	local mode = db.mode

	-- Mode: mounted -- hide whenever mounted
	if mode == "mounted" then
		return true
	end

	local flying = IsFlying()

	-- Mode: flying -- hide on all flying (includes skyriding)
	if mode == "flying" then
		return flying
	end

	-- Mode: skyriding (default) -- only hide while skyriding
	if flying then
		if GetGlidingInfo then
			local _, canGlide = GetGlidingInfo()
			if canGlide then
				return true
			end
		end

		if GetPlayerAura then
			if GetPlayerAura(SKYRIDING_SPELL_ID) then
				return true
			end
		end
	end

	return false
end

---------------------------------------------------------------------------
-- Frame management
---------------------------------------------------------------------------

local function DiscoverFrames()
	local newFrames = {}
	local count = 0

	for i = 1, #db.frameNames do
		local targetFrame = _G[db.frameNames[i]]
		if targetFrame then
			count = count + 1
			newFrames[count] = targetFrame
		end
	end

	trackedFrames = newFrames
	numTrackedFrames = count
end

local function HideTrackedFrames()
	for i = 1, numTrackedFrames do
		local targetFrame = trackedFrames[i]
		if targetFrame.SetAlpha and targetFrame.GetAlpha then
			-- Store the original state if not already stored
			if not frameStates[targetFrame] then
				local currentAlpha = targetFrame:GetAlpha()
				-- Guard against secret values; skip this frame only (not all frames)
				if not (issecretvalue and issecretvalue(currentAlpha)) then
					frameStates[targetFrame] = {
						alpha = currentAlpha,
						mouseEnabled = targetFrame.IsMouseEnabled and targetFrame:IsMouseEnabled() or nil,
					}
				end
			end
			-- Make invisible (only if we successfully saved state)
			local state = frameStates[targetFrame]
			if state then
				targetFrame:SetAlpha(0)
				if state.mouseEnabled and targetFrame.EnableMouse then
					targetFrame:EnableMouse(false)
				end
			end
		end
	end
end

local function RestoreTrackedFrames()
	for i = 1, numTrackedFrames do
		local targetFrame = trackedFrames[i]
		local state = frameStates[targetFrame]
		if state then
			if targetFrame.SetAlpha and state.alpha then
				targetFrame:SetAlpha(state.alpha)
			end
			if targetFrame.EnableMouse and state.mouseEnabled ~= nil then
				targetFrame:EnableMouse(state.mouseEnabled)
			end
			frameStates[targetFrame] = nil
		end
	end
end

local function CheckAndUpdateFrameVisibility()
	-- Early exit if nothing is tracked
	if numTrackedFrames == 0 then
		return
	end

	local shouldHide = ShouldHideFrames()

	if shouldHide ~= lastShouldHide then
		lastShouldHide = shouldHide

		if shouldHide then
			HideTrackedFrames()
		else
			RestoreTrackedFrames()
		end
	end
end

-- Start/stop ticker based on mount state for efficiency
local function UpdateTicker()
	local mounted = IsMounted()

	if mounted and not updateTicker then
		updateTicker = C_Timer.NewTicker(TICKER_INTERVAL, CheckAndUpdateFrameVisibility)
	elseif not mounted and updateTicker then
		updateTicker:Cancel()
		updateTicker = nil
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function HandleSlashCommand(msg)
	local cmd, param = strsplit(" ", msg, 2)
	cmd = cmd and cmd:lower() or ""
	param = param and strtrim(param) or ""

	-- /sfh add <framename>
	if cmd == "add" then
		if param == "" then
			PrintMsg("Usage: /sfh add <framename>")
			return
		end

		local targetFrame = _G[param]
		if not targetFrame then
			PrintError("Frame not found: " .. param)
			PrintMsg("Make sure the frame exists and the name is correct.")
			return
		end

		-- Check if already tracked
		for i = 1, #db.frameNames do
			if db.frameNames[i] == param then
				PrintMsg("Frame already tracked: " .. param)
				return
			end
		end

		db.frameNames[#db.frameNames + 1] = param
		DiscoverFrames()

		-- If currently hiding, also hide the newly added frame immediately
		if lastShouldHide then
			HideTrackedFrames()
		end

		PrintSuccess("Added frame: " .. param)
		return
	end

	-- /sfh remove <framename>
	if cmd == "remove" then
		if param == "" then
			PrintMsg("Usage: /sfh remove <framename>")
			return
		end

		for i = 1, #db.frameNames do
			if db.frameNames[i] == param then
				-- Restore the frame if it is currently hidden
				local targetFrame = _G[param]
				if targetFrame and frameStates[targetFrame] then
					local state = frameStates[targetFrame]
					if state.alpha then
						targetFrame:SetAlpha(state.alpha)
					end
					if targetFrame.EnableMouse and state.mouseEnabled ~= nil then
						targetFrame:EnableMouse(state.mouseEnabled)
					end
					frameStates[targetFrame] = nil
				end

				table.remove(db.frameNames, i)
				DiscoverFrames()
				PrintSuccess("Removed frame: " .. param)
				return
			end
		end

		PrintError("Frame not in tracked list: " .. param)
		return
	end

	-- /sfh list
	if cmd == "list" then
		PrintMsg("Tracked frames:")
		if #db.frameNames == 0 then
			print("  (none)")
		else
			for i = 1, #db.frameNames do
				local name = db.frameNames[i]
				local exists = _G[name] and "|cFF33FF33[found]|r" or "|cFFFF3333[not found]|r"
				print("  " .. i .. ". " .. name .. " " .. exists)
			end
		end
		return
	end

	-- /sfh mode [skyriding|flying|mounted]
	if cmd == "mode" then
		local mode = param:lower()
		if mode == "" then
			PrintMsg("Current mode: |cFFFFFF00" .. db.mode .. "|r")
			PrintMsg("Available modes: skyriding, flying, mounted")
			return
		end

		if mode == "skyriding" or mode == "flying" or mode == "mounted" then
			-- Restore frames before changing mode
			RestoreTrackedFrames()
			lastShouldHide = false

			db.mode = mode
			PrintSuccess("Mode set to: " .. mode)

			-- Re-check with new mode and update ticker
			UpdateTicker()
			CheckAndUpdateFrameVisibility()
			return
		end

		PrintError("Invalid mode: " .. param)
		PrintMsg("Available modes: skyriding, flying, mounted")
		return
	end

	-- /sfh (no args or unknown) -- help
	PrintMsg("SkyridingFrameHider commands:")
	print("  |cFFFFFF00/sfh add <framename>|r - Add a frame to hide")
	print("  |cFFFFFF00/sfh remove <framename>|r - Remove a frame")
	print("  |cFFFFFF00/sfh list|r - List tracked frames")
	print("  |cFFFFFF00/sfh mode [skyriding|flying|mounted]|r - Set hide mode")
	print("  Modes:")
	print("    |cFFFFFF00skyriding|r - Only hide while skyriding (default)")
	print("    |cFFFFFF00flying|r - Hide while flying (skyriding + regular)")
	print("    |cFFFFFF00mounted|r - Hide whenever mounted")
end

SLASH_SKYRIDINGFRAMEHIDER1 = "/sfh"
SLASH_SKYRIDINGFRAMEHIDER2 = "/skyridingframehider"
SlashCmdList["SKYRIDINGFRAMEHIDER"] = HandleSlashCommand

---------------------------------------------------------------------------
-- Event handling & initialization
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			InitializeDB()
		end
		return
	end

	if event == "PLAYER_LOGIN" then
		-- Check API availability
		if not GetGlidingInfo then
			PrintError("Requires WoW 10.0.5 or newer for skyriding detection.")
		end

		-- Discover frames and start tracking
		DiscoverFrames()
		initialized = true

		-- Register runtime events
		self:RegisterUnitEvent("UNIT_AURA", "player")
		self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")

		-- Initial check
		UpdateTicker()
		CheckAndUpdateFrameVisibility()

		PrintMsg("Loaded. Type |cFFFFFF00/sfh|r for commands.")
		return
	end

	-- Runtime events
	if not initialized then
		return
	end

	-- UNIT_AURA: only run the lightweight visibility check, skip ticker management.
	-- This event fires very frequently during combat; avoid the redundant IsMounted()
	-- call in UpdateTicker(). The ticker already handles periodic detection.
	if event == "UNIT_AURA" then
		if updateTicker then
			-- Only check when already mounted (ticker is running)
			CheckAndUpdateFrameVisibility()
		end
		return
	end

	-- PLAYER_MOUNT_DISPLAY_CHANGED / PLAYER_ENTERING_WORLD:
	-- Infrequent events that may change mount state; manage ticker accordingly
	UpdateTicker()
	CheckAndUpdateFrameVisibility()
end)
