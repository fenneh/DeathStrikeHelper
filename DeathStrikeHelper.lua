local addonName, DSH = ...
local _, class = UnitClass("player")
local currentSpec = GetSpecialization()

-- Only initialize if player is a Death Knight (spec check moved to OnEnable)
if class ~= "DEATHKNIGHT" then
    return
end

-- Add LSM dependency
DSH = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

-- Register default sounds
LSM:Register("sound", "None", "")
LSM:Register("sound", "Death Strike Ready", [[Sound\Spells\DeathKnightFrostPresence.ogg]])
LSM:Register("sound", "Ready Check", [[Sound\Interface\ReadyCheck.ogg]])
LSM:Register("sound", "Raid Warning", [[Sound\Interface\RaidWarning.ogg]])

-- Variables to store frame references
local mainFrame, icon, ratingText, healedText, overhealText, timingText, cooldownFrame, criticalText

-- Add these constants at the top of the file after the variables
local UP_ARROW = "|cFF00FF00+|r"    -- Green plus
local DOWN_ARROW = "|cFFFF0000-|r"   -- Red minus
local DASH = "|cFFFFFF00=|r"         -- Yellow equals
local DEATH_STRIKE_ID = 49998
local DEATH_STRIKE_HEAL_ID = 45470
local UPDATE_THROTTLE = 0.2  -- 200ms throttle for balanced updates (was 50ms)
local lastUpdate = 0
local lastSoundPlayed = 0
local SOUND_THROTTLE = 2.0  -- Don't play sounds more often than every 2 seconds

-- Add after the addon creation
DSH.defaults = {
    profile = {
        iconSize = 32,
        textSize = 12,
        frameWidth = 150,
        frameHeight = 80,
        backgroundColor = {r = 0, g = 0, b = 0, a = 0.9},
        borderColor = {r = 1, g = 1, b = 1, a = 1},
        font = "Friz Quadrata TT",
        fontShadow = true,
        fontShadowColor = {r = 0, g = 0, b = 0, a = 1},
        fontShadowOffset = {x = 1, y = -1},
        showBorder = true,
        backgroundTexture = "Blizzard Tooltip",
        borderTexture = "Blizzard Tooltip",
        frameLocked = false,
        position = {
            point = "CENTER",
            relativePoint = "CENTER",
            xOfs = 0,
            yOfs = 100,
        },
        textPositions = {
            healing = {
                anchor = "TOPRIGHT",
                relativePoint = "TOPRIGHT",
                xOffset = -10,
                yOffset = -10
            },
            overhealing = {
                anchor = "RIGHT",
                relativePoint = "RIGHT",
                xOffset = -10,
                yOffset = 0
            },
            timing = {
                anchor = "BOTTOMRIGHT",
                relativePoint = "BOTTOMRIGHT",
                xOffset = -10,
                yOffset = 10
            },
            rating = {
                anchor = "TOP",
                relativePoint = "BOTTOM",
                xOffset = 0,
                yOffset = -5
            }
        },
        testMode = false,
        debug = false,
        textVisibility = {
            healing = true,
            overhealing = true,
            timing = true,
            rating = true,
        },
        sound = {
            enabled = true,
            file = "Death Strike Ready",
            conditions = {
                highRpCap = true,  -- Play sound when RP >= 105
                highRp = true,     -- Play sound when RP >= 80
                lowHp = true,      -- Play sound when HP < 50% and RP >= 40
            }
        },
        criticalText = "SLAM IT"  -- Add default text for critical health situations
    }
}

function DSH:OnEnable()
    C_Timer.After(1, function()
        self:CreateMainFrame()
        self:RefreshConfig()  -- Apply saved settings
        
        -- Check if we're in Blood spec
        if GetSpecialization() == 1 then
            self:RegisterEvent("UNIT_POWER_UPDATE")
            self:RegisterEvent("UNIT_HEALTH")
            self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            self:RegisterEvent("PLAYER_TARGET_CHANGED")
            if mainFrame then
                mainFrame:Show()
            end
        else
            if mainFrame then
                mainFrame:Hide()
            end
        end
        
        -- Register for spec changes
        self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    end)
end

function DSH:PLAYER_LOGIN()
    -- Remove duplicate event registrations
    self:CreateMainFrame()
    -- Unregister the login event as we don't need it anymore
    self:UnregisterEvent("PLAYER_LOGIN")
end

function DSH:CreateMainFrame()
    -- Create main frame
    mainFrame = CreateFrame("Frame", "DSHMainFrame", UIParent, "BackdropTemplate")
    
    -- Use saved position or default
    local pos = self.db.profile.position
    mainFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    
    mainFrame:SetSize(150, 80)  -- Adjusted size for new layout
    mainFrame:SetMovable(not self.db.profile.frameLocked)
    mainFrame:EnableMouse(not self.db.profile.frameLocked)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        
        -- Save the position
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        DSH.db.profile.position.point = point
        DSH.db.profile.position.relativePoint = relativePoint
        DSH.db.profile.position.xOfs = xOfs
        DSH.db.profile.position.yOfs = yOfs
    end)
    mainFrame:Show()
    mainFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    mainFrame:SetBackdropColor(0, 0, 0, 0.9)

    -- Create Death Strike icon
    local iconSize = 32
    icon = mainFrame:CreateTexture("DSHIcon", "OVERLAY")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -10)
    icon:SetTexture("Interface\\Icons\\Spell_Deathknight_Butcher2")

    -- Create cooldown frame
    local cooldownParent = CreateFrame("Frame", nil, mainFrame)
    cooldownParent:SetAllPoints(icon)
    cooldownFrame = CreateFrame("Cooldown", nil, cooldownParent, "CooldownFrameTemplate")
    cooldownFrame:SetAllPoints()
    cooldownFrame:SetDrawBling(false)
    cooldownFrame:SetDrawEdge(true)
    cooldownFrame:SetHideCountdownNumbers(false) -- Show the built-in cooldown numbers
    cooldownFrame:SetSwipeColor(1, 1, 1, 0.8) -- Make the swipe more visible

    -- Create critical health text overlay
    criticalText = mainFrame:CreateFontString(nil, "OVERLAY")
    criticalText:SetFont("Fonts\\FRIZQT__.TTF", self.db.profile.textSize, "OUTLINE")
    criticalText:SetPoint("BOTTOM", icon, "TOP", 0, 2)
    criticalText:SetJustifyH("CENTER")
    criticalText:SetTextColor(1, 0, 0, 1) -- Red text
    criticalText:SetText("")
    criticalText:Hide()

    -- Create text lines with proper alignment
    healedText = mainFrame:CreateFontString(nil, "OVERLAY")
    healedText:SetFont("Fonts\\FRIZQT__.TTF", self.db.profile.textSize, "OUTLINE")
    healedText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", iconSize + 20, -10)
    healedText:SetJustifyH("LEFT")

    overhealText = mainFrame:CreateFontString(nil, "OVERLAY")
    overhealText:SetFont("Fonts\\FRIZQT__.TTF", self.db.profile.textSize, "OUTLINE")
    overhealText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", iconSize + 20, -30)
    overhealText:SetJustifyH("LEFT")

    timingText = mainFrame:CreateFontString(nil, "OVERLAY")
    timingText:SetFont("Fonts\\FRIZQT__.TTF", self.db.profile.textSize, "OUTLINE")
    timingText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", iconSize + 20, -50)
    timingText:SetJustifyH("LEFT")

    -- Create star rating text under the icon
    ratingText = mainFrame:CreateFontString(nil, "OVERLAY")
    ratingText:SetFont("Fonts\\FRIZQT__.TTF", self.db.profile.textSize, "OUTLINE")
    ratingText:SetPoint("TOP", icon, "BOTTOM", 0, -5)
    ratingText:SetJustifyH("CENTER")

    -- Initialize text
    healedText:SetText("")
    overhealText:SetText("")
    timingText:SetText("")
    ratingText:SetText("")
end

-- Add near the top of the file, after creating the DSH addon:
SLASH_DEATHSTRIKEHELPER1 = "/dsh"
SlashCmdList["DEATHSTRIKEHELPER"] = function(msg)
    if msg == "test" then
        DSH:TestFeedback()
    elseif msg == "reset" then
        maxHealingSeen = 0
        print("Death Strike Helper: Reset max healing seen")
    elseif msg == "config" then
        LibStub("AceConfigDialog-3.0"):Open("DeathStrikeHelper")
    elseif msg == "sound" then
        LibStub("AceConfigDialog-3.0"):SelectGroup("DeathStrikeHelper", "sound")
        LibStub("AceConfigDialog-3.0"):Open("DeathStrikeHelper")
    elseif msg == "debug" then
        DSH.db.profile.debug = not DSH.db.profile.debug
        print("Death Strike Helper: Debug mode " .. (DSH.db.profile.debug and "enabled" or "disabled"))
    elseif msg == "status" then
        local runicPower = UnitPower("player", Enum.PowerType.RunicPower)
        local healthPercent = UnitHealth("player") / UnitHealthMax("player") * 100
        local shouldCast, message = DSH:ShouldDeathStrike()
        print(string.format("Death Strike Helper Status:"))
        print(string.format("  Health: %.1f%%", healthPercent))
        print(string.format("  Runic Power: %d", runicPower))
        print(string.format("  Should Cast: %s", shouldCast and "Yes" or "No"))
        print(string.format("  Message: %s", message or "None"))
        print(string.format("  Low HP Condition: %s", (healthPercent < 50 and runicPower >= 40) and "Met" or "Not Met"))
    else
        print("Death Strike Helper commands:")
        print("  /dsh test - Test the feedback display")
        print("  /dsh reset - Reset max healing seen")
        print("  /dsh config - Open configuration window")
        print("  /dsh sound - Open sound configuration")
        print("  /dsh debug - Toggle debug mode")
        print("  /dsh status - Show current status")
    end
end

-- Function to update the display
function DSH:UpdateDisplay()
    local now = GetTime()
    if now - lastUpdate < UPDATE_THROTTLE then return end
    lastUpdate = now
    
    local shouldCast, message = self:ShouldDeathStrike()
    local runicPower = UnitPower("player", Enum.PowerType.RunicPower)
    local healthPercent = UnitHealth("player") / UnitHealthMax("player") * 100
    local inCombat = UnitAffectingCombat("player")
    
    -- Debug output
    if self.db.profile.debug then
        print(string.format("DSH Update: HP: %.1f%%, RP: %d, Should Cast: %s, Message: %s", 
            healthPercent, runicPower, tostring(shouldCast), message))
    end
    
    -- Hide critical text by default
    if criticalText then
        criticalText:Hide()
    end
    
    -- Special case: Always show ready when RP > 105, regardless of cooldown
    if runicPower >= 105 then
        icon:SetDesaturated(false)
        if cooldownFrame then
            cooldownFrame:Clear()
        end
        
        -- Play sound for high RP cap condition if enabled
        if self.db.profile.sound.conditions.highRpCap then
            self:PlayDeathStrikeSound()
            if self.db.profile.debug and inCombat then
                print("DSH: Playing sound for High RP Cap condition")
            end
        end
        
        return
    end
    
    -- Update icon saturation and critical text
    if shouldCast then
        icon:SetDesaturated(false)
        
        -- Show critical text for Critical HP condition
        if message == "Critical HP" and criticalText then
            criticalText:SetText(self.db.profile.criticalText)
            criticalText:Show()
        end
        
        -- Play appropriate sound based on the condition that was met
        if message == "High RP" and self.db.profile.sound.conditions.highRp then
            self:PlayDeathStrikeSound()
            if self.db.profile.debug and inCombat then
                print("DSH: Playing sound for High RP condition")
            end
        elseif message == "Low HP" and self.db.profile.sound.conditions.lowHp then
            self:PlayDeathStrikeSound()
            if self.db.profile.debug and inCombat then
                print("DSH: Playing sound for Low HP condition")
            end
        elseif message == "Critical HP" and self.db.profile.sound.conditions.lowHp then
            self:PlayDeathStrikeSound()
            if self.db.profile.debug and inCombat then
                print("DSH: Playing sound for Critical HP condition")
            end
        end
    else
        icon:SetDesaturated(true)
    end
    
    -- Update wait message if on cooldown
    if message and message:match("Wait") then
        local timeLeft = tonumber(message:match("(%d+%.?%d*)s"))
        if timeLeft then
            -- Always maintain the cooldown animation for the entire duration
            if cooldownFrame then
                -- Only set the cooldown if it's not already running
                -- This prevents the animation from resetting on every update
                local start = lastDeathStrikeTime
                local duration = 5
                
                -- Check if we need to set the cooldown (first time or after it's been cleared)
                if not cooldownFrame.start or now - cooldownFrame.start > duration then
                    cooldownFrame:SetCooldown(start, duration)
                    cooldownFrame:SetHideCountdownNumbers(false) -- Show the built-in cooldown numbers
                    cooldownFrame.start = start
                end
                
                -- Show the built-in cooldown text while keeping the swipe animation
                cooldownFrame:SetHideCountdownNumbers(false)
            end
            
            -- Remove our custom cooldown text display
            if criticalText then
                criticalText:SetText("")
                criticalText:Hide()
            end
            
            -- Clear the timing text since we're showing the time on the icon now
            if timingText then
                timingText:SetText("")
            end
        end
        
        -- Clear other text elements during cooldown
        if ratingText then ratingText:SetText("") end
        if healedText then healedText:SetText("") end
        if overhealText then overhealText:SetText("") end
        return
    end
end

-- Modify the feedback function to use the new text lines
function DSH:ShowDeathStrikeFeedback(amount, stars, reasons)
    ratingText:SetText(self:GetStarsText(stars))
    healedText:SetText("|cFF00FF00Healed: " .. FormatLargeNumber(amount) .. "|r")
    timingText:SetText(reasons[2] or "") -- Timing reason
    
    icon:SetDesaturated(false)
    C_Timer.After(5, function()
        self:UpdateDisplay() -- Reset to normal state after 5 seconds
    end)
end

-- Track last Death Strike and damage taken
local lastDeathStrikeTime = 0
local damageTakenSince = 0
local lastHealAmount = 0
local maxHealingSeen = 0  -- We'll use this to calibrate our star rating

function DSH:COMBAT_LOG_EVENT_UNFILTERED()
    -- Get only essential info first
    local _, subevent, _, sourceGUID = CombatLogGetCurrentEventInfo()
    
    -- Early exit if not player's action
    if sourceGUID ~= UnitGUID("player") then return end
    
    -- Early exit if not Death Strike related
    if subevent ~= "SPELL_CAST_SUCCESS" and subevent ~= "SPELL_HEAL" then return end
    
    -- Only now get the full combat log info since we know we need it
    local _, _, _, _, _, _, _, _, _, _, _, spellId, _, _, amount, overkill = CombatLogGetCurrentEventInfo()
    
    if spellId == DEATH_STRIKE_ID and subevent == "SPELL_CAST_SUCCESS" then 
        lastDeathStrikeTime = GetTime()
        
        -- Set the cooldown animation
        if cooldownFrame then
            cooldownFrame:SetCooldown(lastDeathStrikeTime, 5)
            cooldownFrame:SetHideCountdownNumbers(false) -- Show the built-in cooldown numbers
            cooldownFrame.start = lastDeathStrikeTime
        end
        
        if self.db.profile.debug then
            print("DSH: Death Strike cast at " .. GetTime())
        end
        
        damageTakenSince = 0
        
        -- Update the display immediately after casting
        self:UpdateDisplay()
        
        -- Schedule more frequent updates during the last second of cooldown
        self:ScheduleFrequentUpdates()
        
    elseif spellId == DEATH_STRIKE_HEAL_ID and subevent == "SPELL_HEAL" then 
        overkill = overkill or 0
        local effectiveHealing = amount - overkill
        
        local runicPower = UnitPower("player", Enum.PowerType.RunicPower)
        local timingIndicator = ""
        
        if runicPower > 110 then
            timingIndicator = "|cFFFF0000-|r"
        else
            if runicPower >= 80 or (UnitHealth("player") / UnitHealthMax("player") * 100 < 50 and runicPower >= 40) then
                timingIndicator = "|cFF00FF00+|r"
            else
                timingIndicator = "|cFFFF0000-|r"
            end
        end
        
        local stars = self:RateDeathStrike(effectiveHealing, overkill)
        
        if self.db.profile.textVisibility.healing then
            healedText:SetText("|cFF00FF00" .. FormatLargeNumber(effectiveHealing) .. "|r")
            healedText:Show()
        end
        if self.db.profile.textVisibility.overhealing then
            -- Always update overhealing text when visible, even if 0
            if overkill > 0 then
                overhealText:SetText("|cFFFF0000" .. FormatLargeNumber(overkill) .. "|r")
            else
                overhealText:SetText("")
            end
            overhealText:Show()
        end
        if self.db.profile.textVisibility.timing then
            timingText:SetText(timingIndicator)
            timingText:Show()
        end
        if self.db.profile.textVisibility.rating then
            ratingText:SetText(self:GetStarsText(stars))
            ratingText:Show()
        end
        
        mainFrame:Show()
    end
end

-- Add this new function to schedule frequent updates during the last second of cooldown
function DSH:ScheduleFrequentUpdates()
    -- Schedule an update at 4 seconds (1 second before cooldown ends)
    C_Timer.After(4, function()
        -- Start rapid updates for the last second
        local updateCount = 0
        local function RapidUpdate()
            updateCount = updateCount + 1
            self:UpdateDisplay()
            
            -- Continue rapid updates for about 1.2 seconds (6 updates at 200ms intervals)
            if updateCount < 10 then
                C_Timer.After(0.1, RapidUpdate)
            end
        end
        
        -- Start the rapid update chain
        RapidUpdate()
    end)
end

-- Helper function to format large numbers
function FormatLargeNumber(number)
    if number >= 1000000 then
        return string.format("%.1fM", number/1000000)
    elseif number >= 1000 then
        return string.format("%.1fK", number/1000)
    else
        return number
    end
end

function DSH:ShouldDeathStrike()
    local runicPower = UnitPower("player", Enum.PowerType.RunicPower)
    local healthPercent = UnitHealth("player") / UnitHealthMax("player") * 100
    local timeSinceLastDS = GetTime() - lastDeathStrikeTime
    local remainingTime = 5 - timeSinceLastDS
    
    -- Critical health check - override cooldown if health is very low
    if healthPercent < 30 and runicPower >= 40 and timeSinceLastDS >= 1 then
        if self.db.profile.debug then
            print(string.format("Death Strike Helper: Critical HP condition met - HP: %.1f%%, RP: %d (Cooldown override)", 
                healthPercent, runicPower))
        end
        return true, "Critical HP"
    end
    
    -- Don't recommend Death Strike if used in last 5 seconds
    if timeSinceLastDS < 5 then
        -- Format the remaining time with millisecond precision when below 1 second
        local waitMsg
        if remainingTime < 1 then
            -- Use 0.1 precision for sub-second values
            waitMsg = string.format("Wait %.1fs", remainingTime)
        else
            -- Use regular precision for values >= 1 second
            waitMsg = string.format("Wait %.1fs", remainingTime)
        end
        return false, waitMsg
    end
    
    -- Rule 0 (Highest Priority): Cast Death Strike when above 105 runic power
    if runicPower >= 105 then
        return true, "High RP (Cap)"
    end
    
    -- Rule 1: Cast Death Strike when above 80 runic power
    if runicPower >= 80 then
        return true, "High RP"
    end
    
    -- Rule 2: Cast Death Strike when below 50% health and above 40 runic power
    if healthPercent < 50 and runicPower >= 40 then
        -- Add debug output to help diagnose issues
        if self.db.profile.debug then
            print(string.format("Death Strike Helper: Low HP condition met - HP: %.1f%%, RP: %d", healthPercent, runicPower))
        end
        return true, "Low HP"
    end
    
    return false, runicPower .. " RP"
end

function DSH:UNIT_POWER_UPDATE(event, unit, powerType)
    if unit ~= "player" then return end
    self:UpdateDisplay()
end

function DSH:UNIT_HEALTH(event, unit)
    if unit ~= "player" then return end
    
    -- Check specifically for the Low HP condition
    local healthPercent = UnitHealth("player") / UnitHealthMax("player") * 100
    local runicPower = UnitPower("player", Enum.PowerType.RunicPower)
    
    -- Debug output for health changes
    if self.db.profile.debug then
        print(string.format("DSH Health Update: HP: %.1f%%, RP: %d", healthPercent, runicPower))
    end
    
    -- If we meet the Low HP condition, update the display immediately
    if healthPercent < 50 and runicPower >= 40 then
        if self.db.profile.debug then
            print("DSH: Low HP condition met, updating display")
        end
        self:UpdateDisplay()
    else
        self:UpdateDisplay()
    end
end

DSH.PLAYER_TARGET_CHANGED = DSH.UpdateDisplay

function DSH:RateDeathStrike(healAmount, overhealing)
    local stars = 1  -- Start with 1 star minimum
    
    -- Calculate healing efficiency
    local totalHealing = healAmount + overhealing
    local efficiency = healAmount / totalHealing
    
    -- Get current conditions
    local runicPower = UnitPower("player", Enum.PowerType.RunicPower)
    local healthPercent = UnitHealth("player") / UnitHealthMax("player") * 100
    
    -- Special case: If RP was above 105, automatic 5 stars
    if runicPower >= 105 then
        return 5
    end
    
    -- Add stars based on healing efficiency
    if efficiency > 0.8 then
        stars = stars + 2
    elseif efficiency > 0.6 then
        stars = stars + 1
    end
    
    -- Add stars based on timing
    if runicPower >= 80 or (healthPercent < 50 and runicPower >= 40) then
        stars = stars + 2
    elseif runicPower >= 40 then
        stars = stars + 1
    end
    
    -- Clamp stars between 1 and 5
    return math.min(5, math.max(1, stars))
end

function DSH:GetStarsText(stars)
    local colors = {
        "|cFFFF0000",  -- 1 star - Red
        "|cFFFF8000",  -- 2 stars - Orange
        "|cFFFFFF00",  -- 3 stars - Yellow
        "|cFF80FF00",  -- 4 stars - Light Green
        "|cFF00FF00"   -- 5 stars - Green
    }
    
    return colors[stars] .. stars .. "*|r"
end

-- Debug function to test the feedback
function DSH:TestFeedback()
    -- Calculate star rating for test
    local stars = 3  -- Example rating
    
    -- Update display elements with test values
    healedText:SetText("|cFF00FF00" .. FormatLargeNumber(50000) .. "|r")
    overhealText:SetText("|cFFFF0000" .. FormatLargeNumber(5000) .. "|r")
    timingText:SetText("|cFF00FF00+|r")  -- Example timing indicator
    ratingText:SetText(self:GetStarsText(stars))
    
    -- Show critical text for testing
    if criticalText then
        criticalText:SetText(self.db.profile.criticalText)
        criticalText:Show()
    end
    
    -- Make sure everything is visible
    healedText:Show()
    overhealText:Show()
    timingText:Show()
    ratingText:Show()
    mainFrame:Show()
    
    -- Play test sound if enabled
    if self.db.profile.sound.enabled and self.db.profile.sound.file ~= "None" then
        self:PlayDeathStrikeSound(true)
    end
    
    -- Reset after 5 seconds
    C_Timer.After(5, function()
        healedText:SetText("")
        overhealText:SetText("")
        timingText:SetText("")
        ratingText:SetText("")
        if criticalText then
            criticalText:Hide()
        end
    end)
end

function DSH:OnInitialize()
    -- Initialize the database with our defaults
    self.db = LibStub("AceDB-3.0"):New("DeathStrikeHelperDB", self.defaults, true)
    
    -- Register callback for profile changes
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
    
    self:SetupOptions()
end

function DSH:SetupOptions()
    local options = {
        name = "Death Strike Helper",
        handler = DSH,
        type = "group",
        args = {
            display = {
                type = "group",
                name = "Display",
                order = 1,
                args = {
                    iconSize = {
                        type = "range",
                        name = "Icon Size",
                        desc = "Size of the Death Strike icon",
                        min = 16,
                        max = 64,
                        step = 1,
                        get = function() return self.db.profile.iconSize end,
                        set = function(_, value)
                            self.db.profile.iconSize = value
                            self:UpdateLayout()
                        end,
                        order = 1,
                    },
                    textSize = {
                        type = "range",
                        name = "Text Size",
                        desc = "Size of the text elements",
                        min = 8,
                        max = 24,
                        step = 1,
                        get = function() return self.db.profile.textSize end,
                        set = function(_, value)
                            self.db.profile.textSize = value
                            self:UpdateLayout()
                        end,
                        order = 2,
                    },
                    frameWidth = {
                        type = "range",
                        name = "Frame Width",
                        desc = "Width of the main frame",
                        min = 100,
                        max = 300,
                        step = 10,
                        get = function() return self.db.profile.frameWidth end,
                        set = function(_, value)
                            self.db.profile.frameWidth = value
                            self:UpdateLayout()
                        end,
                        order = 3,
                    },
                    frameHeight = {
                        type = "range",
                        name = "Frame Height",
                        desc = "Height of the main frame",
                        min = 50,
                        max = 200,
                        step = 10,
                        get = function() return self.db.profile.frameHeight end,
                        set = function(_, value)
                            self.db.profile.frameHeight = value
                            self:UpdateLayout()
                        end,
                        order = 4,
                    },
                    frameLocked = {
                        type = "toggle",
                        name = "Lock Frame",
                        desc = "Lock the frame position",
                        get = function() return self.db.profile.frameLocked end,
                        set = function(_, value)
                            self.db.profile.frameLocked = value
                            self:UpdateFrameLock()
                        end,
                        order = 5,
                    },
                    criticalText = {
                        type = "input",
                        name = "Critical Health Text",
                        desc = "Text to display over the icon during critical health situations",
                        get = function() return self.db.profile.criticalText end,
                        set = function(_, value)
                            self.db.profile.criticalText = value
                        end,
                        order = 6,
                    },
                    textPositions = {
                        type = "group",
                        name = "Text Positions",
                        order = 7,
                        args = {
                            healing = {
                                type = "group",
                                name = "Healing Text",
                                inline = true,
                                order = 1,
                                args = {
                                    anchor = {
                                        type = "select",
                                        name = "Anchor Point",
                                        values = {
                                            ["TOPLEFT"] = "Top Left",
                                            ["TOP"] = "Top",
                                            ["TOPRIGHT"] = "Top Right",
                                            ["LEFT"] = "Left",
                                            ["CENTER"] = "Center",
                                            ["RIGHT"] = "Right",
                                            ["BOTTOMLEFT"] = "Bottom Left",
                                            ["BOTTOM"] = "Bottom",
                                            ["BOTTOMRIGHT"] = "Bottom Right",
                                        },
                                        get = function() return self.db.profile.textPositions.healing.anchor end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.healing.anchor = value
                                            self:UpdateLayout()
                                        end,
                                        order = 1,
                                    },
                                    xOffset = {
                                        type = "range",
                                        name = "X Offset",
                                        min = -100,
                                        max = 100,
                                        step = 1,
                                        get = function() return self.db.profile.textPositions.healing.xOffset end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.healing.xOffset = value
                                            self:UpdateLayout()
                                        end,
                                        order = 2,
                                    },
                                    yOffset = {
                                        type = "range",
                                        name = "Y Offset",
                                        min = -100,
                                        max = 100,
                                        step = 1,
                                        get = function() return self.db.profile.textPositions.healing.yOffset end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.healing.yOffset = value
                                            self:UpdateLayout()
                                        end,
                                        order = 3,
                                    },
                                },
                            },
                            overhealing = {
                                type = "group",
                                name = "Overhealing Text",
                                inline = true,
                                order = 2,
                                args = {
                                    anchor = {
                                        type = "select",
                                        name = "Anchor Point",
                                        values = {
                                            ["TOPLEFT"] = "Top Left",
                                            ["TOP"] = "Top",
                                            ["TOPRIGHT"] = "Top Right",
                                            ["LEFT"] = "Left",
                                            ["CENTER"] = "Center",
                                            ["RIGHT"] = "Right",
                                            ["BOTTOMLEFT"] = "Bottom Left",
                                            ["BOTTOM"] = "Bottom",
                                            ["BOTTOMRIGHT"] = "Bottom Right",
                                        },
                                        get = function() return self.db.profile.textPositions.overhealing.anchor end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.overhealing.anchor = value
                                            self:UpdateLayout()
                                        end,
                                        order = 1,
                                    },
                                    xOffset = {
                                        type = "range",
                                        name = "X Offset",
                                        min = -100,
                                        max = 100,
                                        step = 1,
                                        get = function() return self.db.profile.textPositions.overhealing.xOffset end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.overhealing.xOffset = value
                                            self:UpdateLayout()
                                        end,
                                        order = 2,
                                    },
                                    yOffset = {
                                        type = "range",
                                        name = "Y Offset",
                                        min = -100,
                                        max = 100,
                                        step = 1,
                                        get = function() return self.db.profile.textPositions.overhealing.yOffset end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.overhealing.yOffset = value
                                            self:UpdateLayout()
                                        end,
                                        order = 3,
                                    },
                                },
                            },
                            timing = {
                                type = "group",
                                name = "Timing Text",
                                inline = true,
                                order = 3,
                                args = {
                                    anchor = {
                                        type = "select",
                                        name = "Anchor Point",
                                        values = {
                                            ["TOPLEFT"] = "Top Left",
                                            ["TOP"] = "Top",
                                            ["TOPRIGHT"] = "Top Right",
                                            ["LEFT"] = "Left",
                                            ["CENTER"] = "Center",
                                            ["RIGHT"] = "Right",
                                            ["BOTTOMLEFT"] = "Bottom Left",
                                            ["BOTTOM"] = "Bottom",
                                            ["BOTTOMRIGHT"] = "Bottom Right",
                                        },
                                        get = function() return self.db.profile.textPositions.timing.anchor end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.timing.anchor = value
                                            self:UpdateLayout()
                                        end,
                                        order = 1,
                                    },
                                    xOffset = {
                                        type = "range",
                                        name = "X Offset",
                                        min = -100,
                                        max = 100,
                                        step = 1,
                                        get = function() return self.db.profile.textPositions.timing.xOffset end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.timing.xOffset = value
                                            self:UpdateLayout()
                                        end,
                                        order = 2,
                                    },
                                    yOffset = {
                                        type = "range",
                                        name = "Y Offset",
                                        min = -100,
                                        max = 100,
                                        step = 1,
                                        get = function() return self.db.profile.textPositions.timing.yOffset end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.timing.yOffset = value
                                            self:UpdateLayout()
                                        end,
                                        order = 3,
                                    },
                                },
                            },
                            rating = {
                                type = "group",
                                name = "Rating Text",
                                inline = true,
                                order = 4,
                                args = {
                                    anchor = {
                                        type = "select",
                                        name = "Anchor Point",
                                        values = {
                                            ["TOPLEFT"] = "Top Left",
                                            ["TOP"] = "Top",
                                            ["TOPRIGHT"] = "Top Right",
                                            ["LEFT"] = "Left",
                                            ["CENTER"] = "Center",
                                            ["RIGHT"] = "Right",
                                            ["BOTTOMLEFT"] = "Bottom Left",
                                            ["BOTTOM"] = "Bottom",
                                            ["BOTTOMRIGHT"] = "Bottom Right",
                                        },
                                        get = function() return self.db.profile.textPositions.rating.anchor end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.rating.anchor = value
                                            self:UpdateLayout()
                                        end,
                                        order = 1,
                                    },
                                    xOffset = {
                                        type = "range",
                                        name = "X Offset",
                                        min = -100,
                                        max = 100,
                                        step = 1,
                                        get = function() return self.db.profile.textPositions.rating.xOffset end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.rating.xOffset = value
                                            self:UpdateLayout()
                                        end,
                                        order = 2,
                                    },
                                    yOffset = {
                                        type = "range",
                                        name = "Y Offset",
                                        min = -100,
                                        max = 100,
                                        step = 1,
                                        get = function() return self.db.profile.textPositions.rating.yOffset end,
                                        set = function(_, value)
                                            self.db.profile.textPositions.rating.yOffset = value
                                            self:UpdateLayout()
                                        end,
                                        order = 3,
                                    },
                                },
                            },
                        },
                    },
                    testMode = {
                        type = "toggle",
                        name = "Test Mode",
                        desc = "Show test values to help with text positioning",
                        get = function() return self.db.profile.testMode end,
                        set = function(_, value)
                            self.db.profile.testMode = value
                            if value then
                                self:ShowTestValues()
                            else
                                self:HideTestValues()
                            end
                        end,
                        order = 0,  -- Put it at the top of display options
                    },
                    textVisibility = {
                        type = "group",
                        name = "Text Visibility",
                        order = 8,
                        inline = true,
                        args = {
                            healing = {
                                type = "toggle",
                                name = "Show Healing",
                                desc = "Toggle visibility of healing amount",
                                get = function() return self.db.profile.textVisibility.healing end,
                                set = function(_, value)
                                    self.db.profile.textVisibility.healing = value
                                    self:UpdateLayout()
                                end,
                                order = 1,
                            },
                            overhealing = {
                                type = "toggle",
                                name = "Show Overhealing",
                                desc = "Toggle visibility of overhealing amount",
                                get = function() return self.db.profile.textVisibility.overhealing end,
                                set = function(_, value)
                                    self.db.profile.textVisibility.overhealing = value
                                    self:UpdateLayout()
                                end,
                                order = 2,
                            },
                            timing = {
                                type = "toggle",
                                name = "Show Timing",
                                desc = "Toggle visibility of timing indicator",
                                get = function() return self.db.profile.textVisibility.timing end,
                                set = function(_, value)
                                    self.db.profile.textVisibility.timing = value
                                    self:UpdateLayout()
                                end,
                                order = 3,
                            },
                            rating = {
                                type = "toggle",
                                name = "Show Rating",
                                desc = "Toggle visibility of star rating",
                                get = function() return self.db.profile.textVisibility.rating end,
                                set = function(_, value)
                                    self.db.profile.textVisibility.rating = value
                                    self:UpdateLayout()
                                end,
                                order = 4,
                            },
                        },
                    },
                },
            },
            background = {
                type = "group",
                name = "Background",
                order = 2,
                args = {
                    backgroundColor = {
                        type = "color",
                        name = "Background Color",
                        desc = "Color of the background",
                        hasAlpha = true,
                        get = function()
                            local c = self.db.profile.backgroundColor
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            self.db.profile.backgroundColor.r = r
                            self.db.profile.backgroundColor.g = g
                            self.db.profile.backgroundColor.b = b
                            self.db.profile.backgroundColor.a = a
                            self:UpdateLayout()
                        end,
                        order = 1,
                    },
                    backgroundTexture = {
                        type = "select",
                        name = "Background Texture",
                        desc = "Texture used for the background",
                        values = {
                            ["Blizzard Tooltip"] = "Blizzard Tooltip",
                            ["Solid"] = "Solid",
                            ["Transparent"] = "Transparent",
                        },
                        get = function() return self.db.profile.backgroundTexture end,
                        set = function(_, value)
                            self.db.profile.backgroundTexture = value
                            self:UpdateLayout()
                        end,
                        order = 2,
                    },
                },
            },
            border = {
                type = "group",
                name = "Border",
                order = 3,
                args = {
                    showBorder = {
                        type = "toggle",
                        name = "Show Border",
                        desc = "Toggle the frame border",
                        get = function() return self.db.profile.showBorder end,
                        set = function(_, value)
                            self.db.profile.showBorder = value
                            self:UpdateLayout()
                        end,
                        order = 1,
                    },
                    borderColor = {
                        type = "color",
                        name = "Border Color",
                        desc = "Color of the border",
                        hasAlpha = true,
                        get = function()
                            local c = self.db.profile.borderColor
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            self.db.profile.borderColor.r = r
                            self.db.profile.borderColor.g = g
                            self.db.profile.borderColor.b = b
                            self.db.profile.borderColor.a = a
                            self:UpdateLayout()
                        end,
                        order = 2,
                    },
                    borderTexture = {
                        type = "select",
                        name = "Border Texture",
                        desc = "Texture used for the border",
                        values = {
                            ["Blizzard Tooltip"] = "Blizzard Tooltip",
                            ["Thin"] = "Thin",
                            ["None"] = "None",
                        },
                        get = function() return self.db.profile.borderTexture end,
                        set = function(_, value)
                            self.db.profile.borderTexture = value
                            self:UpdateLayout()
                        end,
                        order = 3,
                    },
                },
            },
            font = {
                type = "group",
                name = "Font",
                order = 4,
                args = {
                    font = {
                        type = "select",
                        name = "Font",
                        desc = "Font used for text",
                        values = {
                            ["Friz Quadrata TT"] = "Friz Quadrata TT",
                            ["Arial Narrow"] = "Arial Narrow",
                            ["Skurri"] = "Skurri",
                            ["Morpheus"] = "Morpheus",
                        },
                        get = function() return self.db.profile.font end,
                        set = function(_, value)
                            self.db.profile.font = value
                            self:UpdateLayout()
                        end,
                        order = 1,
                    },
                    fontShadow = {
                        type = "toggle",
                        name = "Font Shadow",
                        desc = "Toggle text shadow",
                        get = function() return self.db.profile.fontShadow end,
                        set = function(_, value)
                            self.db.profile.fontShadow = value
                            self:UpdateLayout()
                        end,
                        order = 2,
                    },
                    fontShadowColor = {
                        type = "color",
                        name = "Shadow Color",
                        desc = "Color of the font shadow",
                        hasAlpha = true,
                        get = function()
                            local c = self.db.profile.fontShadowColor
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            self.db.profile.fontShadowColor.r = r
                            self.db.profile.fontShadowColor.g = g
                            self.db.profile.fontShadowColor.b = b
                            self.db.profile.fontShadowColor.a = a
                            self:UpdateLayout()
                        end,
                        order = 3,
                    },
                },
            },
            sound = {
                type = "group",
                name = "Sound",
                order = 5,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable Sounds",
                        desc = "Play sounds when Death Strike conditions are met",
                        get = function() return self.db.profile.sound.enabled end,
                        set = function(_, value)
                            self.db.profile.sound.enabled = value
                        end,
                        order = 1,
                    },
                    soundFile = {
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Sound",
                        desc = "Sound to play when Death Strike conditions are met",
                        values = function() return LSM:HashTable("sound") end,
                        get = function() return self.db.profile.sound.file end,
                        set = function(_, value)
                            self.db.profile.sound.file = value
                            -- Play the sound for preview
                            if value ~= "None" then
                                self:PlayDeathStrikeSound(true) -- Force play for preview
                            end
                        end,
                        order = 2,
                        disabled = function() return not self.db.profile.sound.enabled end,
                    },
                    conditionsHeader = {
                        type = "header",
                        name = "Sound Conditions",
                        order = 3,
                    },
                    highRpCap = {
                        type = "toggle",
                        name = "High Runic Power (Cap)",
                        desc = "Play sound when Runic Power is at or above 105",
                        get = function() return self.db.profile.sound.conditions.highRpCap end,
                        set = function(_, value)
                            self.db.profile.sound.conditions.highRpCap = value
                        end,
                        order = 4,
                        disabled = function() return not self.db.profile.sound.enabled end,
                    },
                    highRp = {
                        type = "toggle",
                        name = "High Runic Power",
                        desc = "Play sound when Runic Power is at or above 80",
                        get = function() return self.db.profile.sound.conditions.highRp end,
                        set = function(_, value)
                            self.db.profile.sound.conditions.highRp = value
                        end,
                        order = 5,
                        disabled = function() return not self.db.profile.sound.enabled end,
                    },
                    lowHp = {
                        type = "toggle",
                        name = "Low Health",
                        desc = "Play sound when Health is below 50% and Runic Power is at or above 40",
                        get = function() return self.db.profile.sound.conditions.lowHp end,
                        set = function(_, value)
                            self.db.profile.sound.conditions.lowHp = value
                        end,
                        order = 6,
                        disabled = function() return not self.db.profile.sound.enabled end,
                    },
                    testSound = {
                        type = "execute",
                        name = "Test Sound",
                        desc = "Play the selected sound to test selection",
                        func = function()
                            if self.db.profile.sound.file ~= "None" then
                                self:PlayDeathStrikeSound(true) -- Force play for test
                            end
                        end,
                        order = 7,
                        disabled = function() return not self.db.profile.sound.enabled or self.db.profile.sound.file == "None" end,
                    },
                },
            },
            advanced = {
                type = "group",
                name = "Advanced",
                order = 6,
                args = {
                    debug = {
                        type = "toggle",
                        name = "Debug Mode",
                        desc = "Enable debug output to help diagnose issues",
                        get = function() return self.db.profile.debug end,
                        set = function(_, value)
                            self.db.profile.debug = value
                        end,
                        order = 1,
                    },
                },
            },
        },
    }
    
    LibStub("AceConfig-3.0"):RegisterOptionsTable("DeathStrikeHelper", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DeathStrikeHelper", "Death Strike Helper")
end

function DSH:UpdateLayout()
    if not mainFrame then return end
    
    -- Update frame size
    mainFrame:SetSize(self.db.profile.frameWidth, self.db.profile.frameHeight)
    
    -- Update background
    local bgFile = self.db.profile.backgroundTexture == "Solid" and "Interface\\Buttons\\WHITE8X8"
        or self.db.profile.backgroundTexture == "Transparent" and ""
        or "Interface\\Tooltips\\UI-Tooltip-Background"
    
    local edgeFile = self.db.profile.borderTexture == "None" and ""
        or self.db.profile.borderTexture == "Thin" and "Interface\\Buttons\\WHITE8X8"
        or "Interface\\Tooltips\\UI-Tooltip-Border"
    
    mainFrame:SetBackdrop({
        bgFile = bgFile,
        edgeFile = self.db.profile.showBorder and edgeFile or "",
        tile = true,
        tileSize = 16,
        edgeSize = self.db.profile.borderTexture == "Thin" and 1 or 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    
    -- Update colors
    local bg = self.db.profile.backgroundColor
    local border = self.db.profile.borderColor
    mainFrame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
    mainFrame:SetBackdropBorderColor(border.r, border.g, border.b, border.a)
    
    -- Update icon size
    icon:SetSize(self.db.profile.iconSize, self.db.profile.iconSize)
    
    -- Update text properties
    local function UpdateTextElement(element)
        if not element then return end
        
        -- Map font names to actual font paths
        local fontPaths = {
            ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
            ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
            ["Skurri"] = "Fonts\\SKURRI.TTF",
            ["Morpheus"] = "Fonts\\MORPHEUS.TTF"
        }
        
        -- Get the correct font path
        local fontPath = fontPaths[self.db.profile.font] or "Fonts\\FRIZQT__.TTF"
        
        -- Apply font settings
        element:SetFont(fontPath, self.db.profile.textSize, "OUTLINE")
        
        -- Apply shadow settings
        if self.db.profile.fontShadow then
            local c = self.db.profile.fontShadowColor
            element:SetShadowColor(c.r, c.g, c.b, c.a)
            element:SetShadowOffset(self.db.profile.fontShadowOffset.x, self.db.profile.fontShadowOffset.y)
        else
            element:SetShadowColor(0, 0, 0, 0)
        end
    end
    
    UpdateTextElement(healedText)
    UpdateTextElement(overhealText)
    UpdateTextElement(timingText)
    UpdateTextElement(ratingText)
    UpdateTextElement(criticalText)
    
    -- Update positions and visibility
    local function UpdateTextPosition(element, settings, visible)
        if not element then return end
        element:ClearAllPoints()
        
        -- Set text alignment based on anchor point
        if settings.anchor:find("RIGHT") then
            element:SetJustifyH("RIGHT")
        elseif settings.anchor:find("LEFT") then
            element:SetJustifyH("LEFT")
        else
            element:SetJustifyH("CENTER")
        end
        
        -- Use the configured position settings
        element:SetPoint(settings.anchor, icon, settings.relativePoint or settings.anchor, settings.xOffset, settings.yOffset)
        
        if visible then
            element:Show()
        else
            element:Hide()
        end
    end

    UpdateTextPosition(healedText, self.db.profile.textPositions.healing, self.db.profile.textVisibility.healing)
    UpdateTextPosition(overhealText, self.db.profile.textPositions.overhealing, self.db.profile.textVisibility.overhealing)
    UpdateTextPosition(timingText, self.db.profile.textPositions.timing, self.db.profile.textVisibility.timing)
    UpdateTextPosition(ratingText, self.db.profile.textPositions.rating, self.db.profile.textVisibility.rating)
    
    -- Special handling for critical text - always center it on the icon
    if criticalText then
        criticalText:ClearAllPoints()
        criticalText:SetPoint("CENTER", icon, "CENTER", 0, 0)
        criticalText:SetJustifyH("CENTER")
    end

    -- After updating all positions, check if we should show test values
    if self.db.profile.testMode then
        self:ShowTestValues()
    end
end

function DSH:UpdateFrameLock()
    if mainFrame then
        mainFrame:EnableMouse(not self.db.profile.frameLocked)
        mainFrame:SetMovable(not self.db.profile.frameLocked)
    end
end

function DSH:RefreshConfig()
    self:UpdateLayout()
    self:UpdateFrameLock()
end

function DSH:ShowTestValues()
    if self.db.profile.textVisibility.healing then
        healedText:SetText("|cFF00FF00" .. FormatLargeNumber(1234567) .. "|r")
        healedText:Show()
    end
    if self.db.profile.textVisibility.overhealing then
        overhealText:SetText("|cFFFF0000" .. FormatLargeNumber(234567) .. "|r")
        overhealText:Show()
    end
    if self.db.profile.textVisibility.timing then
        timingText:SetText("|cFF00FF00+|r")
        timingText:Show()
    end
    if self.db.profile.textVisibility.rating then
        ratingText:SetText(self:GetStarsText(5))
        ratingText:Show()
    end
    mainFrame:Show()
end

function DSH:HideTestValues()
    -- Only hide text if the elements exist and have fonts set
    if healedText and healedText:GetFont() then
        healedText:SetText("")
    end
    if overhealText and overhealText:GetFont() then
        overhealText:SetText("")
    end
    if timingText and timingText:GetFont() then
        timingText:SetText("")
    end
    if ratingText and ratingText:GetFont() then
        ratingText:SetText("")
    end
end

-- Add this new function to handle spec changes
function DSH:PLAYER_SPECIALIZATION_CHANGED(event, unit)
    if unit ~= "player" then return end
    
    if GetSpecialization() == 1 then  -- Blood spec
        self:RegisterEvent("UNIT_POWER_UPDATE")
        self:RegisterEvent("UNIT_HEALTH")
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        if mainFrame then
            mainFrame:Show()
        end
    else  -- Not Blood spec
        self:UnregisterEvent("UNIT_POWER_UPDATE")
        self:UnregisterEvent("UNIT_HEALTH")
        self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:UnregisterEvent("PLAYER_TARGET_CHANGED")
        if mainFrame then
            mainFrame:Hide()
        end
    end
end

-- Add this function after the GetStarsText function
function DSH:PlayDeathStrikeSound(force)
    -- Don't play sounds if disabled
    if not self.db.profile.sound.enabled then return end
    
    -- Don't play sounds if the selected sound is "None"
    if self.db.profile.sound.file == "None" then return end
    
    -- Don't play sounds when not in combat, unless forced (for testing)
    if not force and not UnitAffectingCombat("player") then
        if self.db.profile.debug then
            print("DSH: Sound suppressed - not in combat")
        end
        return
    end
    
    -- Don't play sounds too frequently unless forced
    local now = GetTime()
    if not force and now - lastSoundPlayed < SOUND_THROTTLE then return end
    
    -- Get the sound file path from LSM
    local soundFile = LSM:Fetch("sound", self.db.profile.sound.file)
    if not soundFile or soundFile == "" then return end
    
    -- Play the sound
    PlaySoundFile(soundFile, "Master")
    
    lastSoundPlayed = now
end