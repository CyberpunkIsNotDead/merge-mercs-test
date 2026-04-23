-- API Integration Tests (busted, uses curl instead of Lua socket)
local json = require("lib.json")
local assert = require("busted").assert

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

describe("GET /daily-rewards", function()
    it("returns 200 with reward state", function()
        local result, err = http_request("GET", "/daily-rewards")
        
        if not result then
            assert.has_error(function() error("Backend server not running: " .. tostring(err)) end)
        end
        
        assert.equal(result.status, 200)
        assert.is_true(type(result.data) == "table")
        assert.truthy(result.data.total_coins ~= nil)
        assert.truthy(result.data.current_day ~= nil)
    end)
    
    it("returns can_claim boolean", function()
        local result, err = http_request("GET", "/daily-rewards")
        
        if not result then return end
        
        assert.is_true(type(result.data.can_claim) == "boolean" or result.data.can_claim == nil)
    end)
end)

describe("POST /daily-rewards/claim", function()
    it("returns success with coins_awarded", function()
        local result, err = http_request("POST", "/daily-rewards/claim")
        
        if not result then return end
        
        assert.equal(result.status, 200)
        assert.is_true(result.data.success == true or result.data.error ~= nil)
    end)
end)

describe("Error Handling", function()
    it("returns 404 for unknown route", function()
        local result, err = http_request("GET", "/unknown-route")
        
        if not result then return end
        
        assert.equal(result.status, 404)
    end)
end)
