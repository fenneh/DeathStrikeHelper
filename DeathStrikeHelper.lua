local addonName, DSH = ...
DSH = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0")

-- Variables to store frame references
local mainFrame, icon, ratingText, healedText, overhealText, timingText, cooldownFrame

-- Add these constants at the top of the file after the variables
local UP_ARROW = "|cFF00FF00+|r"    -- Green plus
local DOWN_ARROW = "|cFFFF0000-|r"   -- Red minus
local DASH = "|cFFFFFF00=|r"         -- Yellow equals
local DEATH_STRIKE_ID = 49998
local DEATH_STRIKE_HEAL_ID = 45470
local UPDATE_THROTTLE = 0.1  -- 100ms throttle
local lastUpdate = 0

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
        textVisibility = {
            healing = true,
            overhealing = true,
            timing = true,
            rating = true,
        },
    }
}

function DSH:OnEnable()
    C_Timer.After(1, function()
        self:CreateMainFrame()
        self:RefreshConfig()  -- Apply saved settings
        self:RegisterEvent("UNIT_POWER_UPDATE")
        self:RegisterEvent("UNIT_HEALTH")
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
    end)
end

function DSH:PLAYER_LOGIN()
    self:CreateMainFrame()
    self:RegisterEvent("UNIT_POWER_UPDATE")
    self:RegisterEvent("UNIT_HEALTH")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
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
    else
        print("Death Strike Helper commands:")
        print("  /dsh test - Test the feedback display")
        print("  /dsh reset - Reset max healing seen")
        print("  /dsh config - Open configuration window")
    end
end

-- Function to update the display
function DSH:UpdateDisplay()
    local now = GetTime()
    if now - lastUpdate < UPDATE_THROTTLE then return end
    lastUpdate = now
    
    local shouldCast, message = self:ShouldDeathStrike()
    
    -- Update icon saturation
    if shouldCast then
        icon:SetDesaturated(false)
    else
        icon:SetDesaturated(true)
    end
    
    -- Update wait message if on cooldown
    if message:match("Wait") then
        local timeLeft = tonumber(message:match("(%d+%.?%d*)s"))
        if timeLeft then
            cooldownFrame:SetCooldown(GetTime() - (5 - timeLeft), 5)
        end
        ratingText:SetText("")
        healedText:SetText("")
        overhealText:SetText("")
        timingText:SetText("")
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
        cooldownFrame:SetCooldown(GetTime(), 5)
        damageTakenSince = 0
        
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
        if self.db.profile.textVisibility.overhealing and overkill > 0 then
            overhealText:SetText("|cFFFF0000" .. FormatLargeNumber(overkill) .. "|r")
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
    
    -- Don't recommend Death Strike if used in last 5 seconds
    if timeSinceLastDS < 5 then
        -- Use milliseconds if under 1 second remaining
        if remainingTime < 1 then
            return false, string.format("%.1f", remainingTime)  -- Show one decimal place for sub-1 second
        else
            return false, string.format("%.1f", remainingTime)  -- Show one decimal place for >1 second
        end
    end
    
    -- Rule 1: Cast Death Strike when above 80 runic power
    if runicPower >= 80 then
        return true, "High RP"
    end
    
    -- Rule 2: Cast Death Strike when below 50% health and above 40 runic power
    if healthPercent < 50 and runicPower >= 40 then
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
    self:UpdateDisplay()
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
    
    -- Add stars based on healing efficiency
    if efficiency > 0.8 then
        stars = stars + 2
    elseif efficiency > 0.6 then
        stars = stars + 1
    end
    
    -- Add stars based on timing
    if runicPower > 110 then
        -- No additional stars for wasting resources
    elseif runicPower >= 80 or (healthPercent < 50 and runicPower >= 40) then
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
    
    -- Make sure everything is visible
    healedText:Show()
    overhealText:Show()
    timingText:Show()
    ratingText:Show()
    mainFrame:Show()
    
    -- Reset after 5 seconds
    C_Timer.After(5, function()
        healedText:SetText("")
        overhealText:SetText("")
        timingText:SetText("")
        ratingText:SetText("")
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
                    textPositions = {
                        type = "group",
                        name = "Text Positions",
                        order = 6,
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
                        order = 7,
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