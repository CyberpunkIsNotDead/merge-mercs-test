-- Game logic for Daily Rewards client (pure functions, no LÖVE2D dependencies)
local UI = {}

-- Reward schedule: coins awarded per day in the series
UI.REWARD_SCHEDULE = {100, 200, 300, 400, 500, 600, 1000}

-- Get coins for a given day (1-7)
function UI.getCoinsForDay(day)
    if type(day) ~= "number" or day < 1 or day > 7 then
        return nil
    end
    return UI.REWARD_SCHEDULE[day]
end

-- Format cooldown seconds to human-readable string
function UI.formatCooldown(seconds)
    if not seconds or seconds <= 0 then
        return "0s"
    end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    
    if mins > 0 and secs > 0 then
        return string.format("%dm%ds", mins, secs)
    elseif mins > 0 then
        return string.format("%dm", mins)
    else
        return string.format("%ds", secs)
    end
end

-- Build success message from claim API response
function UI.buildSuccessMessage(result)
    if not result or not result.coins_awarded then
        return "Unknown error"
    end
    
    local dayText = result.current_day and ("Day " .. result.current_day) or ""
    if result.reset_occurred then
        dayText = dayText .. " (Series Reset!)"
    end
    
    return string.format(
        "You received %d coins!\n%s",
        result.coins_awarded,
        dayText
    )
end

-- Build error message from claim API response
function UI.buildErrorMessage(result)
    if not result then
        return "Connection error"
    end
    
    if result.error == "COOLDOWN_ACTIVE" and result.retry_after_seconds then
        local minutes = math.ceil(result.retry_after_seconds / 60)
        return string.format("Come back in %d minute(s)", minutes)
    end
    
    return tostring(result.message or "Failed to claim reward")
end

-- Determine popup type from API response
function UI.getPopupType(result)
    if not result then
        return "error"
    end
    
    if result.success and result.coins_awarded then
        return "success"
    end
    
    if result.error == "COOLDOWN_ACTIVE" then
        return "cooldown"
    end
    
    return "error"
end

-- Get button color based on hover state
function UI.getButtonColor(isHover)
    local COLORS = {
        normal = {60, 110, 180},
        hover = {80, 140, 220}
    }
    
    if isHover then
        return COLORS.hover
    end
    return COLORS.normal
end

-- Get day indicator color based on state
function UI.getDayColor(dayIndex, currentDay, resetNeeded)
    local COLORS = {
        completed = {60, 160, 90},
        active = {220, 180, 40},
        upcoming = {50, 50, 70}
    }
    
    if resetNeeded and dayIndex <= currentDay then
        return {255, 128, 0} -- orange for reset days
    end
    
    if dayIndex < currentDay then
        return COLORS.completed
    elseif dayIndex == currentDay then
        return COLORS.active
    end
    
    return COLORS.upcoming
end

-- Get popup border color based on result type
function UI.getPopupBorderColor(resultType)
    local COLORS = {
        success = {80, 200, 120},
        cooldown = {220, 160, 50},
        error = {220, 70, 70}
    }
    
    return COLORS[resultType] or COLORS.error
end

-- Get popup title based on result type
function UI.getPopupTitle(resultType)
    local TITLES = {
        success = "SUCCESS!",
        cooldown = "COOLDOWN",
        error = "ERROR"
    }
    
    return TITLES[resultType] or TITLES.error
end

-- Check if click is within button bounds
function UI.isClickInButton(x, y)
    local BUTTON_X = 300
    local BUTTON_Y = 490
    local BUTTON_W = 200
    local BUTTON_H = 50
    
    return x >= BUTTON_X and x <= BUTTON_X + BUTTON_W and
           y >= BUTTON_Y and y <= BUTTON_Y + BUTTON_H
end

-- Get day text for display
function UI.getDayText(day)
    if not day then
        return ""
    end
    return "Day " .. tostring(day)
end

return UI
