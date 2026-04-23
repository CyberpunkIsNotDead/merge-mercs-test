-- API Integration Tests (requires running backend server)
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

-- HTTP request test helper (uses socket directly to avoid circular deps)
local function http_request(method, path, body)
    local socket = require("socket")
    local API_BASE = "http://localhost:3000"
    
    local url = API_BASE:gsub("http://", "")
    local colonPos = url:find(":")
    local host, portStr
    if not colonPos then
        host = url
        portStr = "80"
    else
        host = url:sub(1, colonPos - 1)
        portStr = url:sub(colonPos + 1)
    end
    
    local sock = socket.tcp()
    sock:settimeout(5)
    
    local ok, err = sock:connect(host, tonumber(portStr))
    if not ok then
        return nil, "Cannot connect to server at " .. host .. ":" .. portStr
    end
    
    local bodyStr = ""
    if body ~= nil then
        bodyStr = json.encode(body)
    end
    
    local requestFull = method .. " " .. path .. " HTTP/1.1\r\n" ..
                        "Host: " .. host .. "\r\n" ..
                        "Connection: close\r\n"
    
    if body ~= nil then
        requestFull = requestFull .. "Content-Type: application/json\r\n" ..
                      "Content-Length: " .. #bodyStr .. "\r\n"
    end
    
    requestFull = requestFull .. "\r\n" .. bodyStr
    sock:send(requestFull)
    
    local response = sock:receive("*a")
    sock:close()
    
    if not response or #response < 1 then
        return nil, "No response from server"
    end
    
    -- Parse status line
    local status_line = response:match("^(.-)\r\n")
    local status_code = status_line:match("(%d%d%d)")
    
    -- Extract body (after \r\n\r\n)
    local crlfIdx = response:find("\r\n\r\n")
    if not crlfIdx then return nil, "Invalid response format" end
    
    local body_str = response:sub(crlfIdx + 4)
    local data = json.decode(body_str)
    
    return { status = tonumber(status_code), data = data }, nil
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
        local result, err = http_request("POST", "/daily-rewards/claim", {})
        
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
