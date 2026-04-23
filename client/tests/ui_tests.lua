-- Tests for client/lib/ui.lua (pure game logic, no LÖVE2D)
local ui = require("lib.ui")

local tests_run = 0
local tests_passed = 0
local tests_failed = 0
local failures = {}

local function assert_equal(actual, expected, msg)
    tests_run = tests_run + 1
    if actual == expected then
        tests_passed = tests_passed + 1
        return true
    else
        tests_failed = tests_failed + 1
        table.insert(failures, (msg or ("Expected: " .. tostring(expected) .. ", got: " .. tostring(actual))))
        print("  FAIL: " .. (msg or ("Expected: " .. tostring(expected) .. ", got: " .. tostring(actual))))
    end
end

local function assert_true(val, msg)
    tests_run = tests_run + 1
    if val then
        tests_passed = tests_passed + 1
        return true
    else
        tests_failed = tests_failed + 1
        table.insert(failures, (msg or "Expected truthy value"))
        print("  FAIL: " .. (msg or "Expected truthy value"))
    end
end

local function assert_false(val, msg)
    tests_run = tests_run + 1
    if not val then
        tests_passed = tests_passed + 1
        return true
    else
        tests_failed = tests_failed + 1
        table.insert(failures, (msg or "Expected falsy value"))
        print("  FAIL: " .. (msg or "Expected falsy value"))
    end
end

local function assert_nil(val, msg)
    tests_run = tests_run + 1
    if val == nil then
        tests_passed = tests_passed + 1
        return true
    else
        tests_failed = tests_failed + 1
        table.insert(failures, (msg or ("Expected nil, got: " .. tostring(val))))
        print("  FAIL: " .. (msg or ("Expected nil, got: " .. tostring(val))))
    end
end

local function assert_type(val, expected_type, msg)
    tests_run = tests_run + 1
    if type(val) == expected_type then
        tests_passed = tests_passed + 1
        return true
    else
        tests_failed = tests_failed + 1
        table.insert(failures, (msg or ("Expected " .. expected_type .. ", got " .. type(val))))
        print("  FAIL: " .. (msg or ("Expected " .. expected_type .. ", got " .. type(val))))
    end
end

local function assert_contains(tbl, val)
    tests_run = tests_run + 1
    for _, v in ipairs(type(tbl) == "table" and tbl or {tbl}) do
        if v == val then
            tests_passed = tests_passed + 1
            return true
        end
    end
    tests_failed = tests_failed + 1
    print("  FAIL: Value " .. tostring(val) .. " not found")
end

print("\n╔═══════════════════════════════════════════╗")
print("║  Daily Rewards — UI Logic Tests          ║")
print("╚═══════════════════════════════════════════╝")

-- getCoinsForDay tests
describe = function(name, fn) print("\n" .. name); fn() end
it = function(name, fn)
    io.write("    " .. name .. "... ")
    local ok, err = pcall(fn)
    if not ok then
        tests_failed = tests_failed + 1
        table.insert(failures, "ERROR: " .. tostring(err))
        print("ERROR: " .. tostring(err))
    end
end

describe("getCoinsForDay", function()
    it("returns 100 for day 1", function() assert_equal(ui.getCoinsForDay(1), 100) end)
    it("returns 200 for day 2", function() assert_equal(ui.getCoinsForDay(2), 200) end)
    it("returns 300 for day 3", function() assert_equal(ui.getCoinsForDay(3), 300) end)
    it("returns 400 for day 4", function() assert_equal(ui.getCoinsForDay(4), 400) end)
    it("returns 500 for day 5", function() assert_equal(ui.getCoinsForDay(5), 500) end)
    it("returns 600 for day 6", function() assert_equal(ui.getCoinsForDay(6), 600) end)
    it("returns 1000 for day 7", function() assert_equal(ui.getCoinsForDay(7), 1000) end)
    it("returns nil for day 0", function() assert_nil(ui.getCoinsForDay(0)) end)
    it("returns nil for day 8", function() assert_nil(ui.getCoinsForDay(8)) end)
    it("returns nil for negative day", function() assert_nil(ui.getCoinsForDay(-1)) end)
    it("returns nil for non-number input", function() assert_nil(ui.getCoinsForDay("abc")) end)
end)

describe("formatCooldown", function()
    it("formats 0 as 0s", function() assert_equal(ui.formatCooldown(0), "0s") end)
    it("formats negative as 0s", function() assert_equal(ui.formatCooldown(-5), "0s") end)
    it("formats nil as 0s", function() assert_equal(ui.formatCooldown(nil), "0s") end)
    it("formats 30s correctly", function() assert_equal(ui.formatCooldown(30), "30s") end)
    it("formats 59s correctly", function() assert_equal(ui.formatCooldown(59), "59s") end)
    it("formats 60s as 1m", function() assert_equal(ui.formatCooldown(60), "1m") end)
    it("formats 120s as 2m", function() assert_equal(ui.formatCooldown(120), "2m") end)
    it("formats 5m30s correctly", function() assert_equal(ui.formatCooldown(330), "5m30s") end)
    it("formats 3661s as 1h1m1s (shows 61m1s)", function() 
        local result = ui.formatCooldown(3661)
        assert_true(result:find("61m"))
    end)
end)

describe("buildSuccessMessage", function()
    it("builds message for day 1 claim", function()
        local msg = ui.buildSuccessMessage({coins_awarded = 100, current_day = 1})
        assert_true(msg:find("100"))
        assert_true(msg:find("Day 1"))
    end)
    it("builds message for day 7 claim", function()
        local msg = ui.buildSuccessMessage({coins_awarded = 1000, current_day = 7})
        assert_true(msg:find("1000"))
        assert_true(msg:find("Day 7"))
    end)
    it("includes reset text when reset_occurred", function()
        local msg = ui.buildSuccessMessage({coins_awarded = 100, current_day = 1, reset_occurred = true})
        assert_true(msg:find("Series Reset"))
    end)
    it("handles nil result", function() 
        assert_equal(ui.buildSuccessMessage(nil), "Unknown error")
    end)
    it("handles missing coins_awarded", function()
        local msg = ui.buildSuccessMessage({current_day = 1})
        assert_equal(msg, "Unknown error")
    end)
end)

describe("buildErrorMessage", function()
    it("returns cooldown message with retry_after_seconds", function()
        local msg = ui.buildErrorMessage({error = "COOLDOWN_ACTIVE", retry_after_seconds = 300})
        assert_true(msg:find("Come back in"))
        assert_true(msg:find("5 minute"))
    end)
    it("returns cooldown message for 90 seconds (rounds up to 2m)", function()
        local msg = ui.buildErrorMessage({error = "COOLDOWN_ACTIVE", retry_after_seconds = 90})
        assert_true(msg:find("2 minute"))
    end)
    it("handles nil result", function() 
        assert_equal(ui.buildErrorMessage(nil), "Connection error")
    end)
    it("uses message field for other errors", function()
        local msg = ui.buildErrorMessage({message = "Something went wrong"})
        assert_true(msg:find("Something went wrong"))
    end)
    it("returns default for unknown error", function()
        local msg = ui.buildErrorMessage({error = "UNKNOWN_ERROR"})
        assert_equal(msg, "Failed to claim reward")
    end)
end)

describe("getPopupType", function()
    it("returns success for successful claim", function()
        local result = {success = true, coins_awarded = 100}
        assert_equal(ui.getPopupType(result), "success")
    end)
    it("returns cooldown for COOLDOWN_ACTIVE error", function()
        local result = {error = "COOLDOWN_ACTIVE"}
        assert_equal(ui.getPopupType(result), "cooldown")
    end)
    it("returns error for other errors", function()
        local result = {error = "UNKNOWN_ERROR"}
        assert_equal(ui.getPopupType(result), "error")
    end)
    it("returns error for nil result", function()
        assert_equal(ui.getPopupType(nil), "error")
    end)
end)

describe("getButtonColor", function()
    it("returns normal color when not hovering", function()
        local color = ui.getButtonColor(false)
        assert_contains(color, 60)
        assert_contains(color, 110)
        assert_contains(color, 180)
    end)
    it("returns hover color when hovering", function()
        local color = ui.getButtonColor(true)
        assert_contains(color, 80)
        assert_contains(color, 140)
        assert_contains(color, 220)
    end)
end)

describe("getDayColor", function()
    it("returns completed for past days", function()
        local color = ui.getDayColor(1, 3, false)
        assert_contains(color, 60)
        assert_contains(color, 160)
        assert_contains(color, 90)
    end)
    it("returns active for current day", function()
        local color = ui.getDayColor(3, 3, false)
        assert_contains(color, 220)
        assert_contains(color, 180)
        assert_contains(color, 40)
    end)
    it("returns upcoming for future days", function()
        local color = ui.getDayColor(5, 3, false)
        assert_contains(color, 50)
        assert_contains(color, 50)
        assert_contains(color, 70)
    end)
    it("returns orange for reset day when reset_needed", function()
        local color = ui.getDayColor(2, 3, true)
        assert_contains(color, 255)
        assert_contains(color, 128)
        assert_contains(color, 0)
    end)
end)

describe("getPopupBorderColor", function()
    it("returns success color", function()
        local color = ui.getPopupBorderColor("success")
        assert_contains(color, 80)
        assert_contains(color, 200)
        assert_contains(color, 120)
    end)
    it("returns cooldown color", function()
        local color = ui.getPopupBorderColor("cooldown")
        assert_contains(color, 220)
        assert_contains(color, 160)
        assert_contains(color, 50)
    end)
    it("returns error color for unknown type", function()
        local color = ui.getPopupBorderColor("unknown")
        assert_contains(color, 220)
        assert_contains(color, 70)
        assert_contains(color, 70)
    end)
end)

describe("getPopupTitle", function()
    it("returns SUCCESS!", function() assert_equal(ui.getPopupTitle("success"), "SUCCESS!") end)
    it("returns COOLDOWN", function() assert_equal(ui.getPopupTitle("cooldown"), "COOLDOWN") end)
    it("returns ERROR for unknown type", function() assert_equal(ui.getPopupTitle("unknown"), "ERROR") end)
end)

describe("isClickInButton", function()
    it("detects click in button center", function() 
        assert_true(ui.isClickInButton(400, 515))
    end)
    it("rejects click above button", function() 
        assert_false(ui.isClickInButton(400, 489))
    end)
    it("rejects click below button", function() 
        assert_false(ui.isClickInButton(400, 541))
    end)
    it("rejects click left of button", function() 
        assert_false(ui.isClickInButton(299, 515))
    end)
    it("rejects click right of button", function() 
        assert_false(ui.isClickInButton(501, 515))
    end)
    it("accepts click on top-left corner", function() 
        assert_true(ui.isClickInButton(300, 490))
    end)
    it("accepts click on bottom-right corner", function() 
        assert_true(ui.isClickInButton(500, 540))
    end)
end)

describe("getDayText", function()
    it("returns Day 1 for day 1", function() assert_equal(ui.getDayText(1), "Day 1") end)
    it("returns Day 7 for day 7", function() assert_equal(ui.getDayText(7), "Day 7") end)
    it("returns empty string for nil", function() assert_equal(ui.getDayText(nil), "") end)
end)

print("\n" .. string.rep("─", 45))
print("Results: " .. tests_passed .. "/" .. tests_run .. " passed")
if tests_failed > 0 then
    print("FAILURES (" .. tests_failed .. "):")
    for _, f in ipairs(failures) do
        print("  • " .. f)
    end
end

os.exit(tests_failed == 0 and 0 or 1)
