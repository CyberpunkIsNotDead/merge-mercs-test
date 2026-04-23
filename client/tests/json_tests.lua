-- Simple Lua test runner (no external dependencies)
local json = require("lib.json")

local tests_run = 0
local tests_passed = 0
local tests_failed = 0
local failures = {}

local function assert_equal(actual, expected, msg)
    tests_run = tests_run + 1
    if actual == expected or (type(actual) == "table" and type(expected) == "table" and _deep_equal(actual, expected)) then
        tests_passed = tests_passed + 1
        return true
    else
        tests_failed = tests_failed + 1
        local fail_msg = msg or ("Expected: " .. tostring(expected) .. ", got: " .. tostring(actual))
        table.insert(failures, fail_msg)
        print("  FAIL: " .. fail_msg)
        return false
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
        return false
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
        return false
    end
end

local function assert_error(fn, msg)
    tests_run = tests_run + 1
    local ok, err = pcall(fn)
    if not ok then
        tests_passed = tests_passed + 1
        return true
    else
        tests_failed = tests_failed + 1
        table.insert(failures, (msg or "Expected error but none thrown"))
        print("  FAIL: " .. (msg or "Expected error but none thrown"))
        return false
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
    print("  FAIL: Value " .. tostring(val) .. " not found in table")
    return false
end

local function assert_type(val, expected_type, msg)
    tests_run = tests_run + 1
    if type(val) == expected_type then
        tests_passed = tests_passed + 1
        return true
    else
        tests_failed = tests_failed + 1
        table.insert(failures, (msg or ("Expected type " .. expected_type .. ", got " .. type(val))))
        print("  FAIL: " .. (msg or ("Expected type " .. expected_type .. ", got " .. type(val))))
        return false
    end
end

local function assert_nil(val, msg)
    tests_run = tests_run + 1
    if val == nil then
        tests_passed = tests_passed + 1
        return true
    else
        tests_failed = tests_failed + 1
        table.insert(failures, (msg or ("Expected nil, got " .. tostring(val))))
        print("  FAIL: " .. (msg or ("Expected nil, got " .. tostring(val))))
        return false
    end
end

local function describe(name, fn)
    print("\n" .. name)
    fn()
end

local function it(name, fn)
    io.write("    " .. name .. "... ")
    local ok, err = pcall(fn)
    if not ok then
        tests_failed = tests_failed + 1
        print("ERROR: " .. tostring(err))
    end
end

-- Deep equality for tables
local function _deep_equal(t1, t2)
    if #t1 ~= #t2 then return false end
    for i = 1, #t1 do
        local v1, v2 = t1[i], t2[i]
        if type(v1) ~= type(v2) or v1 ~= v2 then
            if type(v1) == "table" and type(v2) == "table" then
                if not _deep_equal(v1, v2) then return false end
            else
                return false
            end
        end
    end
    return true
end

-- Run tests
print("╔═══════════════════════════════════════════╗")
print("║  Daily Rewards — Lua Client Tests       ║")
print("╚═══════════════════════════════════════════╝")

describe("JSON Encoding", function()
    it("encodes nil as null", function() assert_equal(json.encode(nil), "null") end)
    it("encodes number", function() assert_equal(json.encode(42), "42") end)
    it("encodes boolean true", function() assert_equal(json.encode(true), "true") end)
    it("encodes boolean false", function() assert_equal(json.encode(false), "false") end)
    it("encodes string with quotes", function() assert_equal(json.encode("hello"), '"hello"') end)
    it("escapes backslash in strings", function() assert_equal(json.encode("a\\b"), '"a\\\\b"') end)
    it("escapes newline in strings", function() assert_equal(json.encode("a\nb"), '"a\\nb"') end)
    it("encodes empty array", function() assert_equal(json.encode({}), "[]") end)
    it("encodes simple array", function() assert_equal(json.encode({1, 2, 3}), "[1,2,3]") end)
    it("encodes string array", function() assert_equal(json.encode({"a","b"}), '["a","b"]') end)
    it("encodes object", function() 
        local obj = {name = "test", value = 42}
        local encoded = json.encode(obj)
        assert_true(encoded:find('"name"') and encoded:find('42'))
    end)
    it("encodes nested structure", function()
        local nested = {items = {1, 2}, flag = true}
        local encoded = json.encode(nested)
        assert_true(encoded:find('"items"') and encoded:find('[1,2]'))
    end)
end)

describe("JSON Decoding", function()
    it("decodes null", function() assert_nil(json.decode("null")) end)
    it("decodes number", function() assert_equal(json.decode("42"), 42) end)
    it("decodes float", function() assert_equal(json.decode("3.14"), 3.14) end)
    it("decodes negative number", function() assert_equal(json.decode("-5"), -5) end)
    it("decodes boolean true", function() assert_true(json.decode("true")) end)
    it("decodes boolean false", function() assert_false(json.decode("false")) end)
    it("decodes string", function() assert_equal(json.decode('"hello"'), "hello") end)
    it("decodes escaped string", function() 
        local decoded = json.decode('"line1\\nline2"')
        assert_equal(decoded, "line1\nline2")
    end)
    it("decodes empty object", function() 
        local obj = json.decode("{}")
        assert_true(type(obj) == "table" and next(obj) == nil)
    end)
    it("decodes simple object", function()
        local obj = json.decode('{"name":"test","value":42}')
        assert_equal(obj.name, "test")
        assert_equal(obj.value, 42)
    end)
    it("decodes empty array", function() 
        local arr = json.decode("[]")
        assert_true(type(arr) == "table" and #arr == 0)
    end)
    it("decodes number array", function()
        local arr = json.decode("[1,2,3]")
        assert_equal(#arr, 3)
        assert_equal(arr[1], 1)
        assert_equal(arr[2], 2)
        assert_equal(arr[3], 3)
    end)
    it("decodes nested structure", function()
        local data = json.decode('{"items":[1,2],"flag":true}')
        assert_true(type(data.items) == "table")
        assert_equal(#data.items, 2)
        assert_true(data.flag == true)
    end)
    it("throws on invalid JSON", function() 
        assert_error(function() json.decode("{invalid}") end)
    end)
end)

describe("JSON Round-trip", function()
    it("encodes and decodes string", function()
        local original = "hello world"
        local encoded = json.encode(original)
        local decoded = json.decode(encoded)
        assert_equal(decoded, original)
    end)
    it("encodes and decodes number", function()
        local original = 12345
        local encoded = json.encode(original)
        local decoded = json.decode(encoded)
        assert_equal(decoded, original)
    end)
    it("encodes and decodes array", function()
        local original = {10, 20, 30}
        local encoded = json.encode(original)
        local decoded = json.decode(encoded)
        assert_true(_deep_equal(original, decoded))
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
