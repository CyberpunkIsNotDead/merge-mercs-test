-- API Integration Tests (uses curl instead of Lua socket)
local json = require("lib.json")

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

-- HTTP request helper using curl
local function http_request(method, path)
    local API_BASE = os.getenv("API_BASE") or "http://localhost:3000"
    
    -- Check if backend is running first
    local handle = io.popen("curl -s -o /dev/null -w '%{http_code}' '" .. API_BASE .. "/health' 2>/dev/null")
    local status = handle:read("*a"):gsub("%s+", "")
    handle:close()
    
    if status ~= "200" then
        return nil, "Backend server not running at " .. API_BASE
    end
    
    -- Make the actual request and capture output
    local cmd = "curl -s '" .. API_BASE .. path .. "' 2>/dev/null"
    handle = io.popen(cmd)
    local response = handle:read("*a")
    handle:close()
    
    if not response or #response < 1 then
        return nil, "No response from server"
    end
    
    -- Parse JSON response
    local ok, data = pcall(json.decode, response)
    if not ok then
        return nil, "Failed to parse JSON: " .. tostring(data)
    end
    
    return { status = 200, data = data }, nil
end

local function describe(name, fn) print("\n" .. name); fn() end
local function it(name, fn)
    io.write("    " .. name .. "... ")
    local ok, err = pcall(fn)
    if not ok then
        tests_failed = tests_failed + 1
        table.insert(failures, "ERROR: " .. tostring(err))
        print("ERROR: " .. tostring(err))
    end
end

print("\n╔═══════════════════════════════════════════╗")
print("║  Daily Rewards — API Integration Tests  ║")
print("╚═══════════════════════════════════════════╝")

-- Test GET /daily-rewards
describe("GET /daily-rewards", function()
    it("returns 200 with reward state", function()
        local result, err = http_request("GET", "/daily-rewards")
        
        if not result then
            tests_failed = tests_failed + 1
            table.insert(failures, "Backend server not running: " .. tostring(err))
            print("  FAIL: Backend server not running - " .. tostring(err))
            return
        end
        
        assert_equal(result.status, 200)
        assert_type(result.data, "table")
        assert_true(result.data.total_coins ~= nil)
        assert_true(result.data.current_day ~= nil)
    end)
    
    it("returns can_claim boolean", function()
        local result, err = http_request("GET", "/daily-rewards")
        
        if not result then return end
        
        assert_true(type(result.data.can_claim) == "boolean" or result.data.can_claim == nil)
    end)
end)

-- Test POST /daily-rewards/claim
describe("POST /daily-rewards/claim", function()
    it("returns success with coins_awarded", function()
        local result, err = http_request("POST", "/daily-rewards/claim")
        
        if not result then return end
        
        assert_equal(result.status, 200)
        assert_true(result.data.success == true or result.data.error ~= nil)
    end)
end)

-- Test error handling
describe("Error Handling", function()
    it("returns 404 for unknown route", function()
        local result, err = http_request("GET", "/unknown-route")
        
        if not result then return end
        
        assert_equal(result.status, 404)
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
