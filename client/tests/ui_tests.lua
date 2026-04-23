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
    it("returns correct coins for each day 1-7", function()
        local schedule = {100, 200, 300, 400, 500, 600, 1000}
        for i = 1, 7 do
            assert_equal(schedule[i], ui.getCoinsForDay(i))
        end
    end)

    it("returns nil for invalid days", function()
        assert_nil(ui.getCoinsForDay(0))
        assert_nil(ui.getCoinsForDay(8))
        assert_nil(ui.getCoinsForDay(-1))
        assert_nil(ui.getCoinsForDay("abc"))
    end)
end)

describe("formatCooldown", function()
    it("formats zero/negative/nil as 0s", function()
        assert_equal("0s", ui.formatCooldown(0))
        assert_equal("0s", ui.formatCooldown(-5))
        assert_equal("0s", ui.formatCooldown(nil))
    end)

    it("formats seconds correctly", function()
        assert_equal("30s", ui.formatCooldown(30))
        assert_equal("59s", ui.formatCooldown(59))
    end)

    it("formats minutes correctly", function()
        assert_equal("1m", ui.formatCooldown(60))
        assert_equal("2m", ui.formatCooldown(120))
    end)

    it("formats minutes and seconds correctly", function()
        assert_equal("5m30s", ui.formatCooldown(330))
    end)
end)

describe("buildSuccessMessage", function()
    it("builds message with coins and day", function()
        local msg = ui.buildSuccessMessage({coins_awarded = 100, current_day = 1})
        assert_true(msg:find("100"))
        assert_true(msg:find("Day 1"))
    end)

    it("includes reset text when reset_occurred", function()
        local msg = ui.buildSuccessMessage({coins_awarded = 100, current_day = 1, reset_occurred = true})
        assert_true(msg:find("Series Reset"))
    end)

    it("handles nil or missing coins_awarded", function()
        assert_equal("Unknown error", ui.buildSuccessMessage(nil))
        assert_equal("Unknown error", ui.buildSuccessMessage({current_day = 1}))
    end)
end)

describe("buildErrorMessage", function()
    it("returns cooldown message with retry_after_seconds", function()
        local msg = ui.buildErrorMessage({error = "COOLDOWN_ACTIVE", retry_after_seconds = 300})
        assert_true(msg:find("Come back in"))
        assert_true(msg:find("5 minute"))
    end)

    it("handles nil result", function()
        assert_equal("Connection error", ui.buildErrorMessage(nil))
    end)

    it("uses message field for other errors", function()
        local msg = ui.buildErrorMessage({message = "Something went wrong"})
        assert_true(msg:find("Something went wrong"))
    end)

    it("returns default for unknown error", function()
        local msg = ui.buildErrorMessage({error = "UNKNOWN_ERROR"})
        assert_equal("Failed to claim reward", msg)
    end)
end)

describe("getPopupType", function()
    it("returns success for successful claim", function()
        assert_equal("success", ui.getPopupType({success = true, coins_awarded = 100}))
    end)

    it("returns cooldown for COOLDOWN_ACTIVE error", function()
        assert_equal("cooldown", ui.getPopupType({error = "COOLDOWN_ACTIVE"}))
    end)

    it("returns error for other cases", function()
        assert_equal("error", ui.getPopupType({error = "UNKNOWN_ERROR"}))
        assert_equal("error", ui.getPopupType(nil))
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
    it("returns correct colors for each type", function()
        local success_color = ui.getPopupBorderColor("success")
        assert_contains(success_color, 80)
        assert_contains(success_color, 200)
        assert_contains(success_color, 120)

        local cooldown_color = ui.getPopupBorderColor("cooldown")
        assert_contains(cooldown_color, 220)
        assert_contains(cooldown_color, 160)
        assert_contains(cooldown_color, 50)

        local error_color = ui.getPopupBorderColor("unknown")
        assert_contains(error_color, 220)
        assert_contains(error_color, 70)
        assert_contains(error_color, 70)
    end)
end)

describe("getPopupTitle", function()
    it("returns correct titles for each type", function()
        assert_equal("SUCCESS!", ui.getPopupTitle("success"))
        assert_equal("COOLDOWN", ui.getPopupTitle("cooldown"))
        assert_equal("ERROR", ui.getPopupTitle("unknown"))
    end)
end)

describe("isClickInButton", function()
    it("detects clicks within button bounds", function()
        assert_true(ui.isClickInButton(400, 515))
        assert_true(ui.isClickInButton(300, 490)) -- top-left corner
        assert_true(ui.isClickInButton(500, 540)) -- bottom-right corner
    end)

    it("rejects clicks outside button bounds", function()
        assert_false(ui.isClickInButton(400, 489))   -- above
        assert_false(ui.isClickInButton(400, 541))   -- below
        assert_false(ui.isClickInButton(299, 515))   -- left
        assert_false(ui.isClickInButton(501, 515))   -- right
    end)
end)

describe("getDayText", function()
    it("returns formatted day text", function()
        assert_equal("Day 1", ui.getDayText(1))
        assert_equal("Day 7", ui.getDayText(7))
        assert_equal("", ui.getDayText(nil))
    end)
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
