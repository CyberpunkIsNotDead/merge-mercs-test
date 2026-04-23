local api = require("lib.api")
local ui = require("lib.ui")

-- UI Colors
local COLORS = {
    bg = { 25, 25, 35, 255 },
    text = { 240, 240, 240, 255 },
    textDim = { 150, 150, 160, 255 },
    accent = { 70, 130, 220, 255 },
    success = { 80, 200, 120, 255 },
    warning = { 220, 160, 50, 255 },
    danger = { 220, 70, 70, 255 },
    dayActive = { 220, 180, 40, 255 },
}

-- Game State
local state = {
    rewardState = nil,
    showResult = false,
    resultMessage = "",
    resultType = "success",
    isLoading = true,
    buttonHover = false,
    claimTime = nil,
}

-- UI Dimensions
local BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H
DAY_INDICATOR_SIZE = 40
DAY_INDICATOR_START_X = 120
DAY_INDICATOR_SPACING = 95

function love.load()
    love.window.setMode(800, 600)
    love.graphics.setFont(love.graphics.newFont(24))
    
    state.fontSmall = love.graphics.newFont(16)
    state.fontLarge = love.graphics.newFont(32)
    state.fontTitle = love.graphics.newFont(28)
    
    BUTTON_X = 300
    BUTTON_Y = 490
    BUTTON_W = 200
    BUTTON_H = 50
    
    loadDailyRewards()
end

function loadDailyRewards()
    local data, err = api.get("/daily-rewards")
    if not data then
        state.isLoading = false
        state.showResult = true
        state.resultMessage = "Failed to load daily rewards: " .. tostring(err)
        state.resultType = "error"
        return
    end
    
    state.rewardState = data
    state.isLoading = false
end

local function getCooldownRemaining()
    if not state.rewardState or not state.rewardState.can_claim then
        return nil
    end
    
    local cooldownUntil = state.rewardState.cooldown_until
    if cooldownUntil and #cooldownUntil > 0 then
        local year = tonumber(cooldownUntil:sub(1, 4))
        local month = tonumber(cooldownUntil:sub(6, 7))
        local day = tonumber(cooldownUntil:sub(9, 10))
        local hour = tonumber(cooldownUntil:sub(12, 13))
        local min = tonumber(cooldownUntil:sub(15, 16))
        local sec = tonumber(cooldownUntil:sub(18, 19))
        
        if year and month and day and hour and min and sec then
            local cooldownEpoch = os.time({year = year, month = month, day = day,
                                           hour = hour, min = min, sec = sec})
            local now = os.time()
            local remaining = cooldownEpoch - now
            
            if remaining > 0 then
                return remaining
            end
        end
    end
    
    if state.claimTime then
        local elapsed = love.timer.getTime() - state.claimTime
        local COOLDOWN_SECONDS = 5 * 60
        local remaining = COOLDOWN_SECONDS - elapsed
        
        if remaining > 0 then
            return remaining
        end
    end
    
    return nil
end

function formatCooldown(seconds)
    return ui.formatCooldown(seconds)
end

function love.update(dt)
    if not state.showResult and not state.isLoading and state.rewardState then
        local remaining = getCooldownRemaining()
        if remaining == 0 or (remaining ~= nil and remaining <= 0) then
            loadDailyRewards()
        end
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then
        if state.showResult then
            state.showResult = false
            loadDailyRewards()
            return
        end
        
        if x >= BUTTON_X and x <= BUTTON_X + BUTTON_W and
           y >= BUTTON_Y and y <= BUTTON_Y + BUTTON_H then
            claimReward()
        end
    end
end

function love.mousemoved(x, y)
    state.mouseX = x
    state.mouseY = y
    
    if not state.showResult and not state.isLoading then
        local inButton = x >= BUTTON_X and x <= BUTTON_X + BUTTON_W and
                         y >= BUTTON_Y and y <= BUTTON_Y + BUTTON_H
        state.buttonHover = inButton
        love.window.setTitle("Daily Rewards - " .. (state.buttonHover and "Press to Claim!" or ""))
    end
end

function claimReward()
    if not state.rewardState then return end
    
    state.claimTime = love.timer.getTime()
    
    local result, err = api.post("/daily-rewards/claim", {})
    
    if not result then
        state.showResult = true
        state.resultMessage = "Connection error: " .. tostring(err)
        state.resultType = "error"
        return
    end
    
    if result.success and result.coins_awarded then
        state.rewardState.total_coins = result.total_coins
        state.rewardState.current_day = result.current_day
        
        state.showResult = true
        state.resultMessage = ui.buildSuccessMessage(result)
    else
        state.showResult = true
        state.resultType = ui.getPopupType(result)
        
        if result.error == "COOLDOWN_ACTIVE" and result.retry_after_seconds then
            local minutes = math.ceil(result.retry_after_seconds / 60)
            state.resultMessage = string.format(
                "Come back in %d minute(s)",
                minutes
            )
        else
            state.resultMessage = ui.buildErrorMessage(result)
        end
    end
end

function love.keypressed(key)
    if key == "escape" and state.showResult then
        state.showResult = false
        loadDailyRewards()
    elseif key == "return" and not state.isLoading then
        claimReward()
    end
end

-- Drawing functions
function love.draw()
    love.graphics.clear(COLORS.bg[1]/255, COLORS.bg[2]/255, COLORS.bg[3]/255)
    
    if state.isLoading then
        drawLoading()
        return
    end
    
    drawTitle()
    drawDayIndicators()
    drawRewardInfo()
    drawClaimButton()
    
    if state.showResult then
        drawResultPopup()
    end
end

function drawLoading()
    love.graphics.setColor(COLORS.text[1]/255, COLORS.text[2]/255, COLORS.text[3]/255)
    love.graphics.print("Connecting to server...", 280, 280)
end

function drawTitle()
    love.graphics.setColor(COLORS.accent[1]/255, COLORS.accent[2]/255, COLORS.accent[3]/255)
    love.graphics.setFont(state.fontTitle)
    love.graphics.print("DAILY REWARDS", 250, 40)
end

function drawDayIndicators()
    local startY = 120
    
    for i = 1, 7 do
        local x = DAY_INDICATOR_START_X + (i - 1) * DAY_INDICATOR_SPACING
        local y = startY
        
        -- Determine day state color using UI module
        local currentDay = state.rewardState and state.rewardState.current_day or 1
        local resetNeeded = state.rewardState and state.rewardState.reset_needed or false
        local color = ui.getDayColor(i, currentDay, resetNeeded)
        
        if state.rewardState and state.rewardState.reset_needed and i <= state.rewardState.current_day then
            love.graphics.setColor(1, 0.5, 0)
            love.graphics.printf("RESET", x - 20, y + DAY_INDICATOR_SIZE + 5, 80, "center")
        end
        
        -- Draw day box
        love.graphics.setColor(color[1]/255, color[2]/255, color[3]/255)
        love.graphics.rectangle("fill", x - DAY_INDICATOR_SIZE/2, y - DAY_INDICATOR_SIZE/2, 
                                DAY_INDICATOR_SIZE, DAY_INDICATOR_SIZE, 8, 8)
        
        -- Draw day number centered in box (no wrapping)
        love.graphics.setColor(COLORS.text[1]/255, COLORS.text[2]/255, COLORS.text[3]/255)
        local dayText = tostring(i)
        love.graphics.printf(dayText, x - DAY_INDICATOR_SIZE/2, y - 6, DAY_INDICATOR_SPACING, "center")
        
        -- Draw coins below the box (no wrapping)
        local coins = ui.getCoinsForDay(i)
        if coins then
            local coinsText = "+" .. tostring(coins)
            
            love.graphics.setFont(state.fontSmall)
            love.graphics.setColor(COLORS.textDim[1]/255, COLORS.textDim[2]/255, COLORS.textDim[3]/255)
            love.graphics.printf(coinsText, x - DAY_INDICATOR_SIZE/2, y + DAY_INDICATOR_SIZE/2 + 5, DAY_INDICATOR_SPACING, "center")
            
            -- Reset font
            love.graphics.setFont(state.fontTitle)
        end
    end
end

function drawRewardInfo()
    local leftX = 40
    local labelY = 260
    
    -- Total coins section (left side)
    love.graphics.setColor(COLORS.textDim[1]/255, COLORS.textDim[2]/255, COLORS.textDim[3]/255)
    love.graphics.setFont(state.fontSmall)
    love.graphics.print("TOTAL COINS", leftX, labelY)
    
    -- Value: print directly without wrapping
    love.graphics.setColor(COLORS.success[1]/255, COLORS.success[2]/255, COLORS.success[3]/255)
    love.graphics.setFont(state.fontLarge)
    if state.rewardState then
        local coinsText = tostring(state.rewardState.total_coins or 0)
        love.graphics.print(coinsText, leftX, labelY + 25)
    end
    
    -- Current day section (below total coins)
    local dayInfoY = labelY + 85
    if state.rewardState then
        love.graphics.setColor(COLORS.textDim[1]/255, COLORS.textDim[2]/255, COLORS.textDim[3]/255)
        love.graphics.setFont(state.fontSmall)
        love.graphics.print("CURRENT DAY", leftX, dayInfoY)
        
        local dayText = "Day " .. tostring(state.rewardState.current_day)
        love.graphics.setColor(COLORS.dayActive[1]/255, COLORS.dayActive[2]/255, COLORS.dayActive[3]/255)
        love.graphics.setFont(state.fontLarge)
        love.graphics.print(dayText, leftX, dayInfoY + 25)
    end
end

function drawClaimButton()
    local color = ui.getButtonColor(state.buttonHover)
    
    love.graphics.setColor(color[1]/255, color[2]/255, color[3]/255)
    love.graphics.rectangle("fill", BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H, 10, 10)
    
    -- Button border (always visible when we have state)
    if state.rewardState then
        love.graphics.setColor(COLORS.accent[1]/255, COLORS.accent[2]/255, COLORS.accent[3]/255)
        love.graphics.rectangle("line", BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H, 10, 10)
    end
    
    -- Button text (always the same - no state changes)
    love.graphics.setColor(COLORS.text[1]/255, COLORS.text[2]/255, COLORS.text[3]/255)
    love.graphics.setFont(state.fontSmall)
    love.graphics.print("CLAIM REWARD", BUTTON_X + BUTTON_W/2 - 60, BUTTON_Y + BUTTON_H/2 - 8)
end

function drawResultPopup()
    -- Overlay
    love.graphics.setColor(0, 0, 0, 150/255)
    love.graphics.rectangle("fill", 0, 0, 800, 600)
    
    -- Popup background
    local popupX, popupY = 250, 200
    local popupW, popupH = 300, 180
    
    love.graphics.setColor(COLORS.bg[1]/255 + 0.1, COLORS.bg[2]/255 + 0.1, COLORS.bg[3]/255 + 0.1)
    love.graphics.rectangle("fill", popupX, popupY, popupW, popupH, 15, 15)
    
    -- Popup border using UI module
    local borderColor = ui.getPopupBorderColor(state.resultType)
    love.graphics.setColor(borderColor[1]/255, borderColor[2]/255, borderColor[3]/255)
    love.graphics.rectangle("line", popupX, popupY, popupW, popupH, 15, 15)
    
    -- Title using UI module
    local titleText = ui.getPopupTitle(state.resultType)
    love.graphics.setColor(COLORS.text[1]/255, COLORS.text[2]/255, COLORS.text[3]/255)
    love.graphics.setFont(state.fontTitle)
    love.graphics.print(titleText, popupX + 100, popupY + 25)
    
    -- Message using printf for proper word wrapping
    love.graphics.setColor(COLORS.text[1]/255, COLORS.text[2]/255, COLORS.text[3]/255)
    love.graphics.setFont(state.fontSmall)
    
    local messageX = popupX + 30
    local messageY = popupY + 70
    local messageW = popupW - 60
    
    -- Use printf which handles word wrapping correctly at space boundaries
    love.graphics.printf(state.resultMessage, messageX, messageY, messageW)
    
    -- Hint to close
    love.graphics.setColor(COLORS.textDim[1]/255, COLORS.textDim[2]/255, COLORS.textDim[3]/255)
    love.graphics.print("(click or press Enter)", popupX + 40, popupY + popupH - 30)
end
