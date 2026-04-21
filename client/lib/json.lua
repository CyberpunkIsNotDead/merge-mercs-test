-- Minimal pure-Lua JSON library (no external dependencies)
-- Supports: strings, numbers, booleans, null, arrays, objects

local json = {}

json._VERSION = "1.0"

function json.encode(obj)
    local t = type(obj)
    
    if obj == nil then
        return "null"
    elseif t == "number" or t == "boolean" then
        return tostring(obj)
    elseif t == "string" then
        return '"' .. obj:gsub("\\", "\\\\")
                       :gsub('"', '\\"')
                       :gsub("\n", "\\n")
                       :gsub("\r", "\\r")
                       :gsub("\t", "\\t")
                       :gsub("\b", "\\b")
                       :gsub("\f", "\\f") .. '"'
    elseif t == "table" then
        local is_array = true
        local max_key = 0
        for k, _ in pairs(obj) do
            if type(k) ~= "number" or math.floor(k) ~= k or k < 1 then
                is_array = false; break
            end
            if k > max_key then max_key = k end
        end
        
        local parts = {}
        if is_array and max_key == #obj then
            for i = 1, max_key do table.insert(parts, json.encode(obj[i])) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(obj) do
                table.insert(parts, json.encode(tostring(k)) .. ":" .. json.encode(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        error("Cannot encode type: " .. t)
    end
end

function json.decode(str)
    local pos = 1
    local len = #str
    
    -- Forward declarations (Lua doesn't support forward references for locals)
    local skipWs, peek, consume, decodeValue, decodeObject, decodeArray
    local decodeString, decodeBoolean, decodeNull, decodeNumber
    
    skipWs = function()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else break end
        end
    end
    
    peek = function() skipWs(); return str:sub(pos, pos) end
    
    consume = function(ch)
        if str:sub(pos, pos) ~= ch then
            error("Expected '" .. ch .. "' at position " .. pos .. ", got '" .. str:sub(pos, math.min(pos+20, len)) .. "'")
        end
        pos = pos + 1
    end
    
    decodeValue = function()
        skipWs()
        local c = peek()
        
        if c == "{" then return decodeObject()
        elseif c == "[" then return decodeArray()
        elseif c == '"' then return decodeString()
        elseif c == "t" or c == "f" then return decodeBoolean()
        elseif c == "n" then return decodeNull()
        elseif c == "-" or (c >= "0" and c <= "9") then return decodeNumber()
        else error("Unexpected character at position " .. pos) end
    end
    
    decodeObject = function()
        consume("{")
        local obj = {}
        
        skipWs()
        if peek() == "}" then pos = pos + 1; return obj end
        
        while true do
            local key = decodeString()
            consume(":")
            obj[key] = decodeValue()
            
            skipWs()
            local c = str:sub(pos, pos)
            if c == "," then pos = pos + 1
            elseif c == "}" then pos = pos + 1; break
            else error("Expected ',' or '}' at position " .. pos) end
        end
        
        return obj
    end
    
    decodeArray = function()
        consume("[")
        local arr = {}
        local idx = 1
        
        skipWs()
        if peek() == "]" then pos = pos + 1; return arr end
        
        while true do
            arr[idx] = decodeValue(); idx = idx + 1
            
            skipWs()
            local c = str:sub(pos, pos)
            if c == "," then pos = pos + 1
            elseif c == "]" then pos = pos + 1; break
            else error("Expected ',' or ']' at position " .. pos) end
        end
        
        return arr
    end
    
    decodeString = function()
        consume('"')
        local parts = {}
        
        while true do
            local c = str:sub(pos, pos)
            
            if c == '"' then pos = pos + 1; break
            elseif c == "\\" then
                pos = pos + 1
                local esc = str:sub(pos, pos)
                
                -- Inline escape map for performance (Lua 5.2+)
                local escapes = {['"']='"',['\\']='\\', ['/']='/', ['b']="\b", ['f']="\f", ['n']="\n", ['r']="\r", ['t']="\t"}
                if escapes[esc] then table.insert(parts, escapes[esc]); pos = pos + 1
                else error("Unknown escape: \\" .. esc) end
                
            elseif c == "" then
                error("Unterminated string at position " .. (pos - 1))
            else
                table.insert(parts, c); pos = pos + 1
            end
        end
        
        return table.concat(parts)
    end
    
    decodeBoolean = function()
        if str:sub(pos, pos+3) == "true" then pos = pos + 4; return true
        elseif str:sub(pos, pos+4) == "false" then pos = pos + 5; return false
        else error("Invalid boolean at position " .. pos) end
    end
    
    decodeNull = function()
        if str:sub(pos, pos+3) == "null" then pos = pos + 4; return nil
        else error("Invalid null at position " .. pos) end
    end
    
    decodeNumber = function()
        local start_pos = pos
        if str:sub(pos, pos) == "-" then pos = pos + 1 end
        
        while pos <= len do
            local c = str:sub(pos, pos)
            if (c >= "0" and c <= "9") or c == "." or c == "e" or c == "E" or c == "+" then
                pos = pos + 1
            else break end
        end
        
        return tonumber(str:sub(start_pos, pos - 1))
    end
    
    -- Entry point
    local result = decodeValue()
    
    -- Skip trailing whitespace and verify we consumed everything
    skipWs()
    if pos < len then
        error("Unexpected data after JSON at position " .. pos)
    end
    
    return result
end

return json
