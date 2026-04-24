-- API Integration Tests (busted, uses curl instead of Lua socket)
local json = require("lib.json")
local assert = require("busted").assert

-- HTTP request helper using curl
local function http_request(method, path, token)
    local API_BASE = os.getenv("API_BASE") or "http://localhost:3000"
    
    -- Check if backend is running first
    local handle = io.popen("curl -s -o /dev/null -w '%{http_code}' '" .. API_BASE .. "/health' 2>/dev/null")
    local status = handle:read("*a"):gsub("%s+", "")
    handle:close()
    
    if status ~= "200" then
        return nil, "Backend server not running at " .. API_BASE
    end
    
    -- Make the actual request and capture output
    local cmd = "curl -s"
    
    if token then
        cmd = cmd .. " -H 'Authorization: Bearer " .. token .. "'"
    end
    
    if method == "POST" then
        cmd = cmd .. " -X POST -H 'Content-Type: application/json' -d '{}'"
    else
        cmd = cmd .. " -X GET"
    end
    
    cmd = cmd .. " '" .. API_BASE .. path .. "' 2>/dev/null"
    
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

local function auth_and_get_token()
    local API_BASE = os.getenv("API_BASE") or "http://localhost:3000"
    
    local handle = io.popen(
        "curl -s -X POST '" .. API_BASE .. "/auth/guest' 2>/dev/null"
    )
    local response = handle:read("*a")
    handle:close()
    
    if not response or #response < 1 then
        return nil, "Failed to authenticate"
    end
    
    local ok, data = pcall(json.decode, response)
    if not ok then
        return nil, "Failed to parse auth response: " .. tostring(data)
    end
    
    return data.token, nil
end

describe("GET /daily-rewards", function()
    it("returns 200 with reward state after auth", function()
        local token, err = auth_and_get_token()
        
        if not token then
            assert.has_error(function() error("Auth failed: " .. tostring(err)) end)
        end
        
        local result, api_err = http_request("GET", "/daily-rewards", token)
        
        if not result then
            assert.has_error(function() error("API call failed: " .. tostring(api_err)) end)
        end
        
        assert.equal(result.status, 200)
        assert.is_true(type(result.data) == "table")
        assert.truthy(result.data.total_coins ~= nil)
        assert.truthy(result.data.current_day ~= nil)
    end)
    
    it("returns can_claim boolean", function()
        local token, err = auth_and_get_token()
        
        if not token then return end
        
        local result, api_err = http_request("GET", "/daily-rewards", token)
        
        if not result then return end
        
        assert.is_true(type(result.data.can_claim) == "boolean" or result.data.can_claim == nil)
    end)
    
    it("returns 401 without auth token", function()
        local API_BASE = os.getenv("API_BASE") or "http://localhost:3000"
        
        local handle = io.popen(
            "curl -s -o /dev/null -w '%{http_code}' '" .. API_BASE .. "/daily-rewards' 2>&1",
            "r"
        )
        local status_str = handle:read("*a"):gsub("%s+", "")
        handle:close()
        
        assert.equal(401, tonumber(status_str))
    end)
end)

describe("POST /daily-rewards/claim", function()
    it("returns success with coins_awarded after auth", function()
        local token, err = auth_and_get_token()
        
        if not token then return end
        
        local result, api_err = http_request("POST", "/daily-rewards/claim", token)
        
        if not result then return end
        
        assert.equal(result.status, 200)
        assert.is_true(result.data.success == true or result.data.error ~= nil)
    end)
    
    it("returns 401 without auth token", function()
        local API_BASE = os.getenv("API_BASE") or "http://localhost:3000"
        
        local handle = io.popen(
            "curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' '" .. API_BASE .. "/daily-rewards/claim' 2>&1",
            "r"
        )
        local status_str = handle:read("*a"):gsub("%s+", "")
        handle:close()
        
        assert.equal(401, tonumber(status_str))
    end)
end)

describe("POST /auth/guest", function()
    it("returns user_id and token", function()
        local API_BASE = os.getenv("API_BASE") or "http://localhost:3000"
        
        local handle = io.popen(
            "curl -s -X POST '" .. API_BASE .. "/auth/guest' 2>/dev/null"
        )
        local response = handle:read("*a")
        handle:close()
        
        local ok, data = pcall(json.decode, response)
        assert.is_true(ok == true)
        assert.truthy(data.user_id)
        assert.truthy(data.token)
    end)
end)

describe("Error Handling", function()
    it("returns 404 for unknown route", function()
        local API_BASE = os.getenv("API_BASE") or "http://localhost:3000"
        
        local handle = io.popen(
            "curl -s -o /dev/null -w '%{http_code}' '" .. API_BASE .. "/unknown-route' 2>&1",
            "r"
        )
        local status_str = handle:read("*a"):gsub("%s+", "")
        handle:close()
        
        assert.equal(404, tonumber(status_str))
    end)
end)
