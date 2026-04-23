-- Tests for client/lib/ui.lua (pure game logic, no LÖVE2D)
local ui = require("lib.ui")
local assert = require("busted").assert

describe("getCoinsForDay", function()
    it("returns correct coins for each day 1-7", function()
        local schedule = {100, 200, 300, 400, 500, 600, 1000}
        for i = 1, 7 do
            assert.equal(schedule[i], ui.getCoinsForDay(i))
        end
    end)

    it("returns nil for invalid days", function()
        assert.is_nil(ui.getCoinsForDay(0))
        assert.is_nil(ui.getCoinsForDay(8))
        assert.is_nil(ui.getCoinsForDay(-1))
        assert.is_nil(ui.getCoinsForDay("abc"))
    end)
end)

describe("formatCooldown", function()
    it("formats zero/negative/nil as 0s", function()
        assert.equal("0s", ui.formatCooldown(0))
        assert.equal("0s", ui.formatCooldown(-5))
        assert.equal("0s", ui.formatCooldown(nil))
    end)

    it("formats seconds correctly", function()
        assert.equal("30s", ui.formatCooldown(30))
        assert.equal("59s", ui.formatCooldown(59))
    end)

    it("formats minutes correctly", function()
        assert.equal("1m", ui.formatCooldown(60))
        assert.equal("2m", ui.formatCooldown(120))
    end)

    it("formats minutes and seconds correctly", function()
        assert.equal("5m30s", ui.formatCooldown(330))
    end)
end)

describe("buildSuccessMessage", function()
    it("builds message with coins and day", function()
        local msg = ui.buildSuccessMessage({coins_awarded = 100, current_day = 1})
        assert.truthy(msg:find("100"))
        assert.truthy(msg:find("Day 1"))
    end)

    it("includes reset text when reset_occurred", function()
        local msg = ui.buildSuccessMessage({coins_awarded = 100, current_day = 1, reset_occurred = true})
        assert.truthy(msg:find("Series Reset"))
    end)

    it("handles nil or missing coins_awarded", function()
        assert.equal("Unknown error", ui.buildSuccessMessage(nil))
        assert.equal("Unknown error", ui.buildSuccessMessage({current_day = 1}))
    end)
end)

describe("buildErrorMessage", function()
    it("returns cooldown message with retry_after_seconds", function()
        local msg = ui.buildErrorMessage({error = "COOLDOWN_ACTIVE", retry_after_seconds = 300})
        assert.truthy(msg:find("Come back in"))
        assert.truthy(msg:find("5 minute"))
    end)

    it("handles nil result", function()
        assert.equal("Connection error", ui.buildErrorMessage(nil))
    end)

    it("uses message field for other errors", function()
        local msg = ui.buildErrorMessage({message = "Something went wrong"})
        assert.truthy(msg:find("Something went wrong"))
    end)

    it("returns default for unknown error", function()
        local msg = ui.buildErrorMessage({error = "UNKNOWN_ERROR"})
        assert.equal("Failed to claim reward", msg)
    end)
end)

describe("getPopupType", function()
    it("returns success for successful claim", function()
        assert.equal("success", ui.getPopupType({success = true, coins_awarded = 100}))
    end)

    it("returns cooldown for COOLDOWN_ACTIVE error", function()
        assert.equal("cooldown", ui.getPopupType({error = "COOLDOWN_ACTIVE"}))
    end)

    it("returns error for other cases", function()
        assert.equal("error", ui.getPopupType({error = "UNKNOWN_ERROR"}))
        assert.equal("error", ui.getPopupType(nil))
    end)
end)

describe("getButtonColor", function()
    it("returns normal color when not hovering", function()
        local color = ui.getButtonColor(false)
        assert.same({60, 110, 180}, color)
    end)

    it("returns hover color when hovering", function()
        local color = ui.getButtonColor(true)
        assert.same({80, 140, 220}, color)
    end)
end)

describe("getDayColor", function()
    it("returns completed for past days", function()
        local color = ui.getDayColor(1, 3, false)
        assert.same({60, 160, 90}, color)
    end)

    it("returns active for current day", function()
        local color = ui.getDayColor(3, 3, false)
        assert.same({220, 180, 40}, color)
    end)

    it("returns upcoming for future days", function()
        local color = ui.getDayColor(5, 3, false)
        assert.same({50, 50, 70}, color)
    end)

    it("returns orange for reset day when reset_needed", function()
        local color = ui.getDayColor(2, 3, true)
        assert.same({255, 128, 0}, color)
    end)
end)

describe("getPopupBorderColor", function()
    it("returns correct colors for each type", function()
        local success_color = ui.getPopupBorderColor("success")
        assert.same({80, 200, 120}, success_color)

        local cooldown_color = ui.getPopupBorderColor("cooldown")
        assert.same({220, 160, 50}, cooldown_color)

        local error_color = ui.getPopupBorderColor("unknown")
        assert.same({220, 70, 70}, error_color)
    end)
end)

describe("getPopupTitle", function()
    it("returns correct titles for each type", function()
        assert.equal("SUCCESS!", ui.getPopupTitle("success"))
        assert.equal("COOLDOWN", ui.getPopupTitle("cooldown"))
        assert.equal("ERROR", ui.getPopupTitle("unknown"))
    end)
end)

describe("isClickInButton", function()
    it("detects clicks within button bounds", function()
        assert.is_true(ui.isClickInButton(400, 515))
        assert.is_true(ui.isClickInButton(300, 490)) -- top-left corner
        assert.is_true(ui.isClickInButton(500, 540)) -- bottom-right corner
    end)

    it("rejects clicks outside button bounds", function()
        assert.is_false(ui.isClickInButton(400, 489))   -- above
        assert.is_false(ui.isClickInButton(400, 541))   -- below
        assert.is_false(ui.isClickInButton(299, 515))   -- left
        assert.is_false(ui.isClickInButton(501, 515))   -- right
    end)
end)

describe("getDayText", function()
    it("returns formatted day text", function()
        assert.equal("Day 1", ui.getDayText(1))
        assert.equal("Day 7", ui.getDayText(7))
        assert.equal("", ui.getDayText(nil))
    end)
end)
