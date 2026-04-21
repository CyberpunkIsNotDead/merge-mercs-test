local socket = require("socket")
local json = require("cjson")

local API_BASE = "http://localhost:3000"

local function parseResponse(response)
    local bodyStart = response:find("\r\n\r\n") or response:find("\n\n")
    if not bodyStart then
        return nil, "Invalid response format"
    end
    
    local body = response:sub(bodyStart + 4):gsub("^%s*(.-)%s*$", "%1")
    
    if body == "" then
        return {}
    end
    
    local ok, data = pcall(json.decode, body)
    if not ok then
        return nil, "Failed to parse JSON: " .. tostring(data)
    end
    
    return data, nil
end

local function request(method, path, headers, body)
    local host, portStr = API_BASE:gsub("http://", ""):gsub("https://", "")
    local colonPos = host:find(":")
    
    if not colonPos then
        host = host
        portStr = "80"
    else
        host = host:sub(1, colonPos - 1)
        portStr = host:sub(colonPos + 1)
        host = host:sub(1, colonPos - 1)
    end
    
    local sock = socket.tcp()
    sock:settimeout(10)
    
    local ok, err = sock:connect(host, tonumber(portStr))
    if not ok then
        return nil, "Connection failed: " .. tostring(err)
    end
    
    local requestLine = method .. " " .. path .. " HTTP/1.1\r\n"
    requestLine = requestLine .. "Host: " .. host .. "\r\n"
    requestLine = requestLine .. "Connection: close\r\n"
    
    headers = headers or {}
    for key, value in pairs(headers) do
        requestLine = requestLine .. key .. ": " .. value .. "\r\n"
    end
    
    if body then
        local bodyStr = type(body) == "string" and body or json.encode(body)
        requestLine = requestLine .. "Content-Length: " .. #bodyStr .. "\r\n"
        requestLine = requestLine .. "Content-Type: application/json\r\n"
        
        sock:send(requestLine .. "\r\n" .. bodyStr)
    else
        requestLine = requestLine .. "\r\n"
        sock:send(requestLine)
    end
    
    local response, status = sock:receive("*l")
    if not response then
        sock:close()
        return nil, "No response received"
    end
    
    local lines = {}
    while true do
        local line
        line, status = sock:receive("*l")
        if not line or (line == "" and #lines > 0) then
            break
        end
        table.insert(lines, line)
    end
    
    sock:close()
    
    local statusCode = tonumber(response:match("(%d%d%d)"))
    if not statusCode then
        return nil, "Invalid response status: " .. tostring(statusCode)
    end
    
    local bodyText = ""
    for _, line in ipairs(lines) do
        if #line > 0 then
            bodyText = bodyText .. (bodyText ~= "" and "\n" or "") .. line
        end
    end
    
    local ok, data = pcall(json.decode, bodyText)
    if not ok then
        return nil, "Failed to parse JSON response: " .. tostring(data)
    end
    
    return { status = statusCode, data = data }, nil
end

local function get(path, token)
    local headers = {}
    if token then
        headers["Authorization"] = "Bearer " .. token
    end
    
    local result, err = request("GET", path, headers)
    if not result then
        return nil, err
    end
    
    return result.data, nil
end

local function post(path, body, token)
    local headers = {
        ["Content-Type"] = "application/json"
    }
    if token then
        headers["Authorization"] = "Bearer " .. token
    end
    
    local result, err = request("POST", path, headers, body)
    if not result then
        return nil, err
    end
    
    return result.data, nil
end

local function authGuest()
    return post("/auth/guest", {})
end

return {
    get = get,
    post = post,
    authGuest = authGuest,
    API_BASE = API_BASE
}
