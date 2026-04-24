local socket = require("socket")
local json = require("lib.json")

local API_BASE = "http://localhost:3000"

-- Parse HTTP response into {status, data} or throws on error
local function parseResponse(raw)
    local crlfIdx = raw:find("\r\n\r\n")
    if not crlfIdx then error("No HTTP headers/body separator found in response") end
    
    local headerSection = raw:sub(1, crlfIdx - 1)
    local body = raw:sub(crlfIdx + 4):gsub("^%s*(.-)%s*$", "%1")
    
    -- Extract status code from first line "HTTP/1.1 200 OK"
    local statusCode = tonumber(headerSection:match("(%d%d%d)"))
    if not statusCode then error("Invalid HTTP status line: " .. headerSection) end
    
    -- Parse JSON body
    local data = nil
    if body and #body > 0 then
        local ok, decoded = pcall(json.decode, body)
        if not ok then error("Failed to parse JSON response: " .. tostring(decoded)) end
        data = decoded
    end
    
    return { status = statusCode, data = data }
end

-- Make an HTTP request. Returns (resultTable, nil) on success or (nil, errorMessage) on failure.
local function request(method, path, headers, bodyTable)
    -- Parse API_BASE into host and port
    local url = API_BASE:gsub("http://", ""):gsub("https://", "")
    local colonPos = url:find(":")
    
    local host, portStr
    if not colonPos then
        host = url
        portStr = "80"
    else
        host = url:sub(1, colonPos - 1)
        portStr = url:sub(colonPos + 1)
    end
    
    -- Connect with retries (handles brief unavailability or slow start)
    local sock = socket.tcp()
    sock:settimeout(30)
    
    local connected = false
    for attempt = 1, 5 do
        local ok, err = sock:connect(host, tonumber(portStr))
        if ok then connected = true; break end
        if attempt < 5 then socket.sleep(0.5) end
    end
    
    if not connected then
        return nil, "Failed to connect to " .. host .. ":" .. portStr .. " — is the server running?"
    end
    
    -- Encode body as JSON string
    local bodyStr = ""
    local contentType = nil
    if bodyTable ~= nil and type(bodyTable) == "table" then
        contentType = "application/json"
        bodyStr = json.encode(bodyTable)
    elseif bodyTable ~= nil and type(bodyTable) == "string" then
        bodyStr = bodyTable
    end
    
    -- Build HTTP request line + headers
    local reqLines = { method .. " " .. path .. " HTTP/1.1" }
    table.insert(reqLines, "Host: " .. host)
    table.insert(reqLines, "Connection: close")
    
    if contentType then
        table.insert(reqLines, "Content-Type: " .. contentType)
        table.insert(reqLines, "Content-Length: " .. #bodyStr)
    end
    
    if headers then
        for key, value in pairs(headers) do
            table.insert(reqLines, key .. ": " .. value)
        end
    end
    
    -- Send request (header + body separated by \r\n\r\n)
    local requestFull = table.concat(reqLines, "\r\n") .. "\r\n\r\n" .. bodyStr
    sock:send(requestFull)
    
    -- Receive full response into a single string
    local rawResponse = sock:receive("*a")
    sock:close()
    
    if not rawResponse or #rawResponse < 1 then
        return nil, "No data received from server"
    end
    
    -- Parse the HTTP response (status line + headers + body)
    local ok, resultOrErr = pcall(parseResponse, rawResponse)
    if not ok then
        return nil, tostring(resultOrErr)
    end
    
    local result = resultOrErr
    
    -- If server returned error status (4xx, 5xx), still try to extract data from body
    if result.status >= 400 and result.data then
        return { status = result.status, data = result.data }, nil
    end
    
    return { status = result.status, data = result.data or {} }, nil
end

local function get(path, token)
    local headers = {}
    if token then
        headers["Authorization"] = "Bearer " .. token
    end
    
    local result, err = request("GET", path, headers)
    if not result then return nil, err end
    
    -- Handle error responses from server (409 cooldown, 401 unauthorized, etc.)
    if type(result.data) == "table" and result.data.error then
        return nil, result.data.error .. ": " .. tostring(result.data.message or "")
    end
    
    return result.data, nil
end

local function post(path, bodyTable, token)
    local headers = { ["Content-Type"] = "application/json" }
    if token then
        headers["Authorization"] = "Bearer " .. token
    end
    
    local result, err = request("POST", path, headers, bodyTable or {})
    if not result then return nil, err end
    
    -- Handle error responses from server
    if type(result.data) == "table" and result.data.error then
        return nil, result.data.error .. ": " .. tostring(result.data.message or "")
    end
    
    return result.data, nil
end

local function authGuest()
    return post("/auth/guest", {})
end

return {
    get = get,
    post = post,
    authGuest = authGuest
}
