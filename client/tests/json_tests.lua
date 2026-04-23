-- JSON Library Tests (busted)
local json = require("lib.json")
local assert = require("busted").assert

describe("JSON Encoding", function()
    it("encodes nil as null", function()
        assert.equal(json.encode(nil), "null")
    end)

    it("encodes number", function()
        assert.equal(json.encode(42), "42")
    end)

    it("encodes boolean true", function()
        assert.equal(json.encode(true), "true")
    end)

    it("encodes boolean false", function()
        assert.equal(json.encode(false), "false")
    end)

    it("encodes string with quotes", function()
        assert.equal(json.encode("hello"), '"hello"')
    end)

    it("escapes backslash in strings", function()
        assert.equal(json.encode("a\\b"), '"a\\\\b"')
    end)

    it("escapes newline in strings", function()
        assert.equal(json.encode("a\nb"), '"a\\nb"')
    end)

    it("encodes empty array", function()
        assert.equal(json.encode({}), "[]")
    end)

    it("encodes simple array", function()
        assert.equal(json.encode({1, 2, 3}), "[1,2,3]")
    end)

    it("encodes string array", function()
        assert.equal(json.encode({"a","b"}), '["a","b"]')
    end)

    it("encodes object", function()
        local obj = {name = "test", value = 42}
        local encoded = json.encode(obj)
        assert.truthy(encoded:find('"name"'))
        assert.truthy(encoded:find('42'))
    end)

    it("encodes nested structure", function()
        local nested = {items = {1, 2}, flag = true}
        local encoded = json.encode(nested)
        assert.truthy(encoded:find('"items"'))
        assert.truthy(encoded:find('[1,2]'))
    end)
end)

describe("JSON Decoding", function()
    it("decodes null", function()
        assert.equal(json.decode("null"), nil)
    end)

    it("decodes number", function()
        assert.equal(json.decode("42"), 42)
    end)

    it("decodes float", function()
        assert.equal(json.decode("3.14"), 3.14)
    end)

    it("decodes negative number", function()
        assert.equal(json.decode("-5"), -5)
    end)

    it("decodes boolean true", function()
        assert.is_true(json.decode("true"))
    end)

    it("decodes boolean false", function()
        assert.is_false(json.decode("false"))
    end)

    it("decodes string", function()
        assert.equal(json.decode('"hello"'), "hello")
    end)

    it("decodes escaped string", function()
        local decoded = json.decode('"line1\\nline2"')
        assert.equal(decoded, "line1\nline2")
    end)

    it("decodes empty object", function()
        local obj = json.decode("{}")
        assert.is_true(type(obj) == "table")
        assert.is_nil(next(obj))
    end)

    it("decodes simple object", function()
        local obj = json.decode('{"name":"test","value":42}')
        assert.equal(obj.name, "test")
        assert.equal(obj.value, 42)
    end)

    it("decodes empty array", function()
        local arr = json.decode("[]")
        assert.is_true(type(arr) == "table")
        assert.equal(#arr, 0)
    end)

    it("decodes number array", function()
        local arr = json.decode("[1,2,3]")
        assert.equal(#arr, 3)
        assert.equal(arr[1], 1)
        assert.equal(arr[2], 2)
        assert.equal(arr[3], 3)
    end)

    it("decodes nested structure", function()
        local data = json.decode('{"items":[1,2],"flag":true}')
        assert.is_true(type(data.items) == "table")
        assert.equal(#data.items, 2)
        assert.is_true(data.flag == true)
    end)

    it("throws on invalid JSON", function()
        assert.has_error(function() json.decode("{invalid}") end)
    end)
end)

describe("JSON Round-trip", function()
    it("encodes and decodes string", function()
        local original = "hello world"
        local encoded = json.encode(original)
        local decoded = json.decode(encoded)
        assert.equal(decoded, original)
    end)

    it("encodes and decodes number", function()
        local original = 12345
        local encoded = json.encode(original)
        local decoded = json.decode(encoded)
        assert.equal(decoded, original)
    end)

    it("encodes and decodes array", function()
        local original = {10, 20, 30}
        local encoded = json.encode(original)
        local decoded = json.decode(encoded)
        assert.same(original, decoded)
    end)
end)
