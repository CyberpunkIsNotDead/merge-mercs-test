local api = require("lib.api")

-- UI Colors
local COLORS = {
    bg = { 25, 25, 35, 255 },
    text = { 240, 240, 240, 255 },
    textDim = { 150, 150, 160, 255 },
    accent = { 70, 130, 220, 255 },
    success = { 80, 200, 120, 255 },
    warning = { 220, 160, 50, 255 },
    danger = { 220, 70, 70, 255 },
    button = { 60, 110, 180, 255 },
    buttonHover = { 80, 140, 220, 255 },
    buttonDisabled = { 50, 50, 70, 255 },
    dayCompleted = { 60, 160, 90, 255 },
    dayActive = { 220, 180, 40, 255 },
    dayUpcoming = { 50, 50, 70, 255 },
}

-- Game State
local state = {
    user_id = nil,
    token = nil,
    rewardState = nil,
    showResult = false,
    resultMessage = "",
    resultType = "success", -- success, error, cooldown
    resultCoins = 0,
    isLoading = true,
    mouseX = 0,
    mouseY = 0,
    buttonHover = false,
}

-- UI Dimensions
local BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H
DAY_INDICATOR_SIZE = 40

function love.load()
    love.window.setMode(800, 600)
    love.graphics.setFont(love.graphics.newFont(24))
    
    state.fontSmall = love.graphics.newFont(16)
    state.fontLarge = love.graphics.newFont(32)
    state.fontTitle = love.graphics.newFont(28)
    
    BUTTON_X = 300
    BUTTON_Y = 420
    BUTTON_W = 200
    BUTTON_H = 50
    
    loadUser()
end

function loadUser()
    local result, err = api.authGuest()
    if not result then
        state.isLoading = false
        state.showResult = true
        state.resultMessage = "Failed to connect to server: " .. tostring(err)
        state.resultType = "error"
        return
    end
    
    state.user_id = result.user_id
    state.token = result.token
    
    loadDailyRewards()
end

function loadDailyRewards()
    local data, err = api.get("/daily-rewards", state.token)
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

local function checkCooldown()
    -- Server returns cooldown_until timestamp; client just displays current state
    -- No need to poll — server has the authoritative data
end

function love.update(dt)
    -- Check cooldown periodically
    if not state.showResult and not state.isLoading and state.rewardState then
        checkCooldown()
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
    
    local result, err = api.post("/daily-rewards/claim", {}, state.token)
    
    if not result then
        state.showResult = true
        state.resultMessage = "Connection error: " .. tostring(err)
        state.resultType = "error"
        return
    end
    
    if result.success and result.coins_awarded then
        state.rewardState.total_coins = result.total_coins or state.rewardState.total_coins
        state.rewardState.current_day = result.current_day + 1
        
        state.showResult = true
        state.resultType = "success"
        
        local dayText = result.current_day and ("Day " .. result.current_day) or ""
        if result.reset_occurred then
            dayText = dayText .. " (Series Reset!)"
        end
        
        state.resultMessage = string.format(
            "You received %d coins!\n%s",
            result.coins_awarded,
            dayText
        )
    else
        -- Error response from server
        state.showResult = true
        state.resultType = result.error == "COOLDOWN_ACTIVE" and "cooldown" or "error"
        
        if result.retry_after_seconds then
            local minutes = math.ceil(result.retry_after_seconds / 60)
            state.resultMessage = string.format(
                "Come back in %d minute(s)",
                minutes
            )
        else
            state.resultMessage = tostring(result.message or "Failed to claim reward")
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
    -- Background
    love.graphics.clear(COLORS.bg[1]/255, COLORS.bg[2]/255, COLORS.bg[3]/255)
    
    if state.isLoading then
        drawLoading()
        return
    end
    
    drawTitle()
    drawDayIndicators()
    drawRewardInfo()
    drawClaimButton()
    drawStatusText()
    
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
    local startX = 180
    local startY = 120
    local spacing = 60
    
    for i = 1, 7 do
        local x = startX + (i - 1) * spacing
        local y = startY
        
        -- Determine day state
        local color = COLORS.dayUpcoming
        if state.rewardState then
            if i < state.rewardState.current_day then
                color = COLORS.dayCompleted
            elseif i == state.rewardState.current_day then
                color = COLORS.dayActive
            end
            
            if state.rewardState.reset_needed and i <= state.rewardState.current_day then
                -- Highlight reset indicator
                love.graphics.setColor(1, 0.5, 0)
                love.graphics.printf("RESET", x - 20, y + DAY_INDICATOR_SIZE + 5, 80, "center")
            end
        end
        
        -- Draw day box
        love.graphics.setColor(color[1]/255, color[2]/255, color[3]/255)
        love.graphics.rectangle("fill", x - DAY_INDICATOR_SIZE/2, y - DAY_INDICATOR_SIZE/2, 
                                DAY_INDICATOR_SIZE, DAY_INDICATOR_SIZE, 8, 8)
        
        -- Draw day number
        love.graphics.setColor(COLORS.text[1]/255, COLORS.text[2]/255, COLORS.text[3]/255)
        love.graphics.printf(tostring(i), x, y - 6, DAY_INDICATOR_SIZE, "center")
        
        -- Draw coins for this day
        local coins = getCoinsForDay(i)
        if coins then
            love.graphics.setColor(COLORS.textDim[1]/255, COLORS.textDim[2]/255, COLORS.textDim[3]/255)
            love.graphics.setFont(state.fontSmall)
            love.graphics.printf("+" .. tostring(coins), x, y + DAY_INDICATOR_SIZE/2 + 5, 
                                 DAY_INDICATOR_SIZE, "center")
            love.graphics.setFont(state.fontTitle)
        end
    end
end

function getCoinsForDay(day)
    local schedule = {100, 200, 300, 400, 500, 600, 700}
    if day >= 1 and day <= 7 then
        return schedule[day]
    end
    return nil
end

function drawRewardInfo()
    local y = 230
    
    -- Total coins
    love.graphics.setColor(COLORS.textDim[1]/255, COLORS.textDim[2]/255, COLORS.textDim[3]/255)
    love.graphics.setFont(state.fontSmall)
    love.graphics.print("TOTAL COINS", 40, y)
    
    love.graphics.setColor(COLORS.success[1]/255, COLORS.success[2]/255, COLORS.success[3]/255)
    love.graphics.setFont(state.fontLarge)
    if state.rewardState then
        love.graphics.print(tostring(state.rewardState.total_coins or 0), 40, y + 25)
    end
    
    -- Coins to win
    love.graphics.setColor(COLORS.textDim[1]/255, COLORS.textDim[2]/255, COLORS.textDim[3]/255)
    love.graphics.setFont(state.fontSmall)
    local infoY = y + 80
    love.graphics.print("NEXT REWARD", 40, infoY)
    
    if state.rewardState then
        love.graphics.setColor(COLORS.accent[1]/255, COLORS.accent[2]/255, COLORS.accent[3]/255)
        love.graphics.setFont(state.fontLarge)
        local coinsToWin = state.rewardState.coins_to_win or 0
        love.graphics.print(tostring(coinsToWin), 40, infoY + 25)
    end
    
    -- Current day label
    if state.rewardState then
        love.graphics.setColor(COLORS.textDim[1]/255, COLORS.textDim[2]/255, COLORS.textDim[3]/255)
        love.graphics.setFont(state.fontSmall)
        local dayLabelY = y + 80
        love.graphics.print("CURRENT DAY", 400, dayLabelY - 10)
        
        love.graphics.setColor(COLORS.dayActive[1]/255, COLORS.dayActive[2]/255, COLORS.dayActive[3]/255)
        love.graphics.setFont(state.fontLarge)
        love.graphics.print("Day " .. tostring(state.rewardState.current_day), 400, dayLabelY + 15)
    end
end

function drawClaimButton()
    local color = state.buttonHover and COLORS.buttonHover or COLORS.button
    
    if not state.rewardState or not state.rewardState.can_claim then
        color = COLORS.buttonDisabled
        state.buttonHover = false
    end
    
    love.graphics.setColor(color[1]/255, color[2]/255, color[3]/255)
    love.graphics.rectangle("fill", BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H, 10, 10)
    
    -- Button border
    if state.rewardState and state.rewardState.can_claim then
        love.graphics.setColor(COLORS.accent[1]/255, COLORS.accent[2]/255, COLORS.accent[3]/255)
        love.graphics.rectangle("line", BUTTON_X, BUTTON_Y, BUTTON_W, BUTTON_H, 10, 10)
    end
    
    -- Button text
    love.graphics.setColor(COLORS.text[1]/255, COLORS.text[2]/255, COLORS.text[3]/255)
    love.graphics.setFont(state.fontSmall)
    local buttonText = "CLAIM REWARD"
    if state.rewardState and not state.rewardState.can_claim then
        buttonText = "COMING SOON"
    end
    love.graphics.print(buttonText, BUTTON_X + BUTTON_W/2 - 60, BUTTON_Y + BUTTON_H/2 - 8)
end

function drawStatusText()
    if not state.rewardState or state.showResult then return end
    
    local y = BUTTON_Y + BUTTON_H + 30
    love.graphics.setColor(COLORS.textDim[1]/255, COLORS.textDim[2]/255, COLORS.textDim[3]/255)
    love.graphics.setFont(state.fontSmall)
    
    if state.rewardState.can_claim then
        love.graphics.setColor(COLORS.success[1]/255, COLORS.success[2]/255, COLORS.success[3]/255)
        love.graphics.print("Click the button to claim your daily reward!", 400, y)
    elseif state.rewardState.cooldown_until then
        -- Calculate remaining time (simplified)
        local cooldownText = "Cooldown active - check back soon"
        if state.rewardState.reset_needed then
            love.graphics.setColor(COLORS.warning[1]/255, COLORS.warning[2]/255, COLORS.warning[3]/255)
            love.graphics.print("Series reset! Claim to start over.", 400, y)
        else
            love.graphics.setColor(COLORS.warning[1]/255, COLORS.warning[2]/255, COLORS.warning[3]/255)
            love.graphics.print(cooldownText, 400, y)
        end
    end
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
    
    -- Popup border
    local borderColor = state.resultType == "success" and COLORS.success or 
                        state.resultType == "cooldown" and COLORS.warning or COLORS.danger
    
    love.graphics.setColor(borderColor[1]/255, borderColor[2]/255, borderColor[3]/255)
    love.graphics.rectangle("line", popupX, popupY, popupW, popupH, 15, 15)
    
    -- Title
    love.graphics.setColor(COLORS.text[1]/255, COLORS.text[2]/255, COLORS.text[3]/255)
    love.graphics.setFont(state.fontTitle)
    
    local titleText = state.resultType == "success" and "SUCCESS!" or 
                      state.resultType == "cooldown" and "COOLDOWN" or "ERROR"
    love.graphics.print(titleText, popupX + 100, popupY + 25)
    
    -- Message (multi-line support)
    love.graphics.setColor(COLORS.text[1]/255, COLORS.text[2]/255, COLORS.text[3]/255)
    love.graphics.setFont(state.fontSmall)
    
    local lines = {}
    for line in state.resultMessage:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    for i, line in ipairs(lines) do
        love.graphics.print(line, popupX + 20, popupY + 70 + (i - 1) * 25)
    end
    
    -- Hint to close
    love.graphics.setColor(COLORS.textDim[1]/255, COLORS.textDim[2]/255, COLORS.textDim[3]/255)
    love.graphics.print("(click or press Enter)", popupX + 40, popupY + popupH - 30)
end
