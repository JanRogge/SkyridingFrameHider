-- SkyridingFrameHider
-- Hide any frame while skyriding, flying, or mounted
-- Configure via /sfh commands

local addonName, addon = ...

-- Default settings
local defaults = {
	frameNames = {},
	mode = "skyriding", -- "skyriding" | "flying" | "mounted"
}

-- Runtime state
local trackedFrames = {}   -- Resolved frame references
local frameStates = {}     -- Original alpha/mouse state before hiding
local updateTicker         -- Ticker for frequent updates while mounted
local lastShouldHide = false -- Track state changes
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
end

---------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------

local function ShouldHideFrames()
	local db = SkyridingFrameHiderDB
	local mounted = IsMounted("player")
	local flying = IsFlying("player")

	if not mounted then
		return false
	end

	-- Mode: mounted -- hide whenever mounted
	if db.mode == "mounted" then
		return true
	end

	-- Mode: flying -- hide on all flying (includes skyriding)
	if db.mode == "flying" and flying then
		return true
	end

	-- Mode: skyriding (default) -- only hide while skyriding
	if flying then
		-- Method 1: Check GetGlidingInfo
		if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
			local isGliding, canGlide = C_PlayerInfo.GetGlidingInfo()
			if canGlide then
				return true
			end
		end

		-- Method 2: Check for Skyriding buff (spell ID 410137)
		if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
			local buffName = C_UnitAuras.GetPlayerAuraBySpellID(410137)
			if buffName then
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
	local db = SkyridingFrameHiderDB
	trackedFrames = {}

	for _, frameName in ipairs(db.frameNames) do
		local targetFrame = _G[frameName]
		if targetFrame then
			table.insert(trackedFrames, targetFrame)
		end
	end
end

local function HideTrackedFrames()
	for _, targetFrame in ipairs(trackedFrames) do
		if targetFrame and targetFrame.SetAlpha and targetFrame.GetAlpha then
			-- Store the original state if not already stored
			if not frameStates[targetFrame] then
				local currentAlpha = targetFrame:GetAlpha()
				-- Skip taint-protected values
				if issecretvalue and issecretvalue(currentAlpha) then
					return
				end
				frameStates[targetFrame] = {
					alpha = currentAlpha,
					mouseEnabled = targetFrame.EnableMouse and targetFrame:IsMouseEnabled() or nil,
				}
			end
			-- Make invisible
			targetFrame:SetAlpha(0)
			-- Disable mouse interaction to prevent invisible clicks
			if targetFrame.EnableMouse and frameStates[targetFrame].mouseEnabled then
				targetFrame:EnableMouse(false)
			end
		end
	end
end

local function RestoreTrackedFrames()
	for _, targetFrame in ipairs(trackedFrames) do
		if targetFrame and targetFrame.SetAlpha and frameStates[targetFrame] then
			local state = frameStates[targetFrame]
			if state.alpha then
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
	local mounted = IsMounted("player")

	if mounted and not updateTicker then
		updateTicker = C_Timer.NewTicker(0.15, CheckAndUpdateFrameVisibility)
	elseif not mounted and updateTicker then
		updateTicker:Cancel()
		updateTicker = nil
		-- Final check to restore frames
		CheckAndUpdateFrameVisibility()
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function HandleSlashCommand(msg)
	local args = {}
	for word in msg:gmatch("%S+") do
		table.insert(args, word)
	end

	local cmd = args[1] and args[1]:lower() or ""
	local param = args[2] or ""

	-- /sfh add <framename>
	if cmd == "add" then
		local frameName = strtrim(param)
		if frameName == "" then
			PrintMsg("Usage: /sfh add <framename>")
			return
		end

		local targetFrame = _G[frameName]
		if not targetFrame then
			PrintError("Frame not found: " .. frameName)
			PrintMsg("Make sure the frame exists and the name is correct.")
			return
		end

		-- Check if already tracked
		for _, name in ipairs(SkyridingFrameHiderDB.frameNames) do
			if name == frameName then
				PrintMsg("Frame already tracked: " .. frameName)
				return
			end
		end

		table.insert(SkyridingFrameHiderDB.frameNames, frameName)
		DiscoverFrames()
		PrintSuccess("Added frame: " .. frameName)
		return
	end

	-- /sfh remove <framename>
	if cmd == "remove" then
		local frameName = strtrim(param)
		if frameName == "" then
			PrintMsg("Usage: /sfh remove <framename>")
			return
		end

		for i, name in ipairs(SkyridingFrameHiderDB.frameNames) do
			if name == frameName then
				-- Restore the frame if it is currently hidden
				local targetFrame = _G[frameName]
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

				table.remove(SkyridingFrameHiderDB.frameNames, i)
				DiscoverFrames()
				PrintSuccess("Removed frame: " .. frameName)
				return
			end
		end

		PrintError("Frame not in tracked list: " .. frameName)
		return
	end

	-- /sfh list
	if cmd == "list" then
		PrintMsg("Tracked frames:")
		if #SkyridingFrameHiderDB.frameNames == 0 then
			print("  (none)")
		else
			for i, name in ipairs(SkyridingFrameHiderDB.frameNames) do
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
			PrintMsg("Current mode: |cFFFFFF00" .. SkyridingFrameHiderDB.mode .. "|r")
			PrintMsg("Available modes: skyriding, flying, mounted")
			return
		end

		if mode == "skyriding" or mode == "flying" or mode == "mounted" then
			-- Restore frames before changing mode
			RestoreTrackedFrames()
			lastShouldHide = false

			SkyridingFrameHiderDB.mode = mode
			PrintSuccess("Mode set to: " .. mode)

			-- Re-check with new mode
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

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		InitializeDB()

	elseif event == "PLAYER_LOGIN" then
		-- Check API availability
		if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then
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

	else
		-- Runtime events (UNIT_AURA, PLAYER_MOUNT_DISPLAY_CHANGED, PLAYER_ENTERING_WORLD)
		if initialized then
			UpdateTicker()
			CheckAndUpdateFrameVisibility()
		end
	end
end)
