-- DrawGuess_Utility.test.lua
-- Unit tests for DrawGuess_Utility core logic

-- 1. Mocking Roblox Globals
_G.TESTING = true

-- Lua 5.1 compatibility
if not unpack then unpack = table.unpack end

local function noop() end

local mock_local_player = {
    Name = "TestPlayer",
    UserId = 1,
    Idled = { Connect = noop },
    WaitForChild = function(self, name) return self end,
    GetMouse = function()
        return {
            Target = { Name = "" },
            Hit = { Position = { X = 0, Y = 0, Z = 0 } },
        }
    end,
}

game = {
    GetService = function(_, serviceName)
        if serviceName == "HttpService" then
            return {
                JSONDecode = function(_, str) return {} end,
                JSONEncode = function(_, obj) return "{}" end,
            }
        elseif serviceName == "Players" then
            return {
                LocalPlayer = mock_local_player,
                GetPlayerByUserId = function() return nil end,
            }
        elseif serviceName == "RunService" then
            return {
                RenderStepped = { Connect = noop },
                Heartbeat = { Connect = noop },
                BindToRenderStep = noop,
            }
        elseif serviceName == "UserInputService" then
            return {
                InputBegan = { Connect = noop },
                InputEnded = { Connect = noop },
                InputChanged = { Connect = noop },
                GetMouseLocation = function() return Vector2.new() end,
            }
        elseif serviceName == "TweenService" then
            return {
                Create = function() return { Play = noop } end,
            }
        end
        return {
            Idled = { Connect = noop },
            OnClientEvent = { Connect = noop },
            WaitForChild = function(self, name) return self end,
            FindFirstChild = function(self, name) return self end,
            FindFirstChildOfClass = function() return nil end,
            GetDescendants = function() return {} end,
            GetChildren = function() return {} end,
            Heartbeat = { Connect = noop },
            BindToRenderStep = noop,
            SetCoreGuiEnabled = noop,
            GetPropertyChangedSignal = function() return { Connect = noop } end,
            DisplayBubble = noop,
            RenderStepped = { Connect = noop },
            InputBegan = { Connect = noop },
            InputEnded = { Connect = noop },
            InputChanged = { Connect = noop },
            ClearAllChildren = noop,
            Create = function() return { Play = noop } end,
        }
    end,
    Players = {
        LocalPlayer = mock_local_player,
    }
}

-- Handle game.Players access
setmetatable(game, {
    __index = function(t, k)
        if k == "Players" then return t.Players end
        return nil
    end
})

workspace = {
    CurrentCamera = {
        CFrame = {},
        ViewportSize = { X = 1920, Y = 1080 },
        GetPropertyChangedSignal = function() return { Connect = noop } end,
    },
    GetDescendants = function() return {} end,
    FindFirstChild = function() return nil end,
    GetServerTimeNow = function() return 0 end,
    GetPartsInPart = function() return {} end,
    canvas = { Position = {Z=0}, Size = {Z=0} },
}

task = {
    spawn = function(f)
        -- Don't run spawned tasks that cause infinite loops
    end,
    wait = noop,
    delay = function(d, f) end, -- Don't run delayed tasks
    cancel = noop,
    defer = function(f) end,
}

Enum = {
    Font = { GothamBold = 1, Code = 2 },
    TextXAlignment = { Left = 1, Right = 2 },
    HorizontalAlignment = { Right = 1, Center = 2 },
    VerticalAlignment = { Top = 1 },
    ZIndexBehavior = { Sibling = 1 },
    EasingStyle = { Quad = 1, Back = 2, Quint = 3 },
    EasingDirection = { Out = 1, In = 2 },
    AutomaticSize = { Y = 1 },
    Material = { SmoothPlastic = 1 },
    PartType = { Cylinder = 1 },
    RenderPriority = { Camera = { Value = 1 } },
    UserInputType = { MouseButton1 = 1, Touch = 2, MouseMovement = 3, MouseWheel = 4, Keyboard = 5 },
    UserInputState = { End = 1, Change = 2 },
    KeyCode = { Slash = 1, Insert = 2 },
    ThumbnailType = { HeadShot = 1 },
    ThumbnailSize = { Size48x48 = 1, Size420x420 = 2 },
    RaycastFilterType = { Include = 1 },
    HumanoidRigType = { R15 = 1 },
    SizeConstraint = { RelativeYY = 1 },
    TextTruncate = { AtEnd = 1 },
    CoreGuiType = { Chat = 1 },
    SortOrder = { LayoutOrder = 1 },
    FillDirection = { Vertical = 1 },
    ScaleType = { Fit = 1 },
}

Color3 = {
    new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0, ToHSV = function() return 0, 0, 0 end } end,
    fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255, ToHSV = function() return 0, 0, 0 end } end,
    fromHSV = function(h, s, v) return { h = h, s = s, v = v, ToHSV = function() return h, s, v end } end,
    toHSV = function(c) return 0, 0, 0 end,
}

Vector2 = {
    new = function(x, y) return { X = x or 0, Y = y or 0, magnitude = 0 } end,
    zero = { X = 0, Y = 0 },
}

Vector3 = {
    new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0, magnitude = 0 } end,
    zero = { X = 0, Y = 0, Z = 0 },
}

CFrame = {
    new = function() return { PointToObjectSpace = function() return Vector3.new() end } end,
    Angles = function() return {} end,
    fromEulerAnglesXYZ = function() return {} end,
    fromMatrix = function() return {} end,
}

Instance = {
    new = function(className)
        return {
            Name = className,
            Parent = nil,
            InputBegan = { Connect = noop },
            InputEnded = { Connect = noop },
            InputChanged = { Connect = noop },
            MouseButton1Click = { Connect = noop },
            MouseEnter = { Connect = noop },
            MouseLeave = { Connect = noop },
            Activated = { Connect = noop },
            GetPropertyChangedSignal = function() return { Connect = noop } end,
            FindFirstChild = function(self, name) return nil end,
            FindFirstChildOfClass = function() return nil end,
            GetChildren = function() return {} end,
            GetDescendants = function() return {} end,
            ClearAllChildren = noop,
            Destroy = noop,
            CFrame = CFrame.new(),
            Size = Vector3.new(),
            Position = Vector3.new(),
            BackgroundColor3 = Color3.new(),
            TextColor3 = Color3.new(),
            AbsoluteSize = Vector2.new(),
            AbsolutePosition = Vector2.new(),
            Visible = true,
        }
    end
}

UDim = {
    new = function(s, o) return { Scale = s, Offset = o } end,
}

UDim2 = {
    new = function(sx, ox, sy, oy) return { X = { Scale = sx, Offset = ox }, Y = { Scale = sy, Offset = oy } } end,
    fromOffset = function(o, p) return { X = { Scale = 0, Offset = o }, Y = { Scale = 0, Offset = p } } end,
    fromScale = function(s, t) return { X = { Scale = s, Offset = 0 }, Y = { Scale = t, Offset = 0 } } end,
}

ColorSequence = {
    new = function() return {} end,
}

ColorSequenceKeypoint = {
    new = function() return {} end,
}

NumberSequence = {
    new = function() return {} end,
}

NumberSequenceKeypoint = {
    new = function() return {} end,
}

TweenInfo = {
    new = function() return {} end,
}

OverlapParams = {
    new = function() return {} end,
}

utf8 = {
    char = function() return "" end,
}

function readfile() return "" end
function writefile() end
function pcall(f, ...)
    local args = {...}
    local status, res = xpcall(function() return f(unpack(args)) end, function(err) return err end)
    return status, res
end
function ypcall(f, ...) return pcall(f, ...) end
function tick() return 0 end
function wait() end
function getgenv() return {} end

-- 2. Load the utility script
local chunk, err = loadfile("DrawGuess_Utility.lua")
if not chunk then
    print("FAILED TO LOAD DrawGuess_Utility.lua: " .. tostring(err))
    os.exit(1)
end

local Utility = chunk()

-- 3. Test Runner Helper
local tests_passed = 0
local tests_failed = 0

local function assert_eq(actual, expected, name)
    if actual == expected then
        print("  [PASS] " .. name)
        tests_passed = tests_passed + 1
    else
        print("  [FAIL] " .. name .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
        tests_failed = tests_failed + 1
    end
end

local function assert_not_nil(val, name)
    if val ~= nil then
        print("  [PASS] " .. name)
        tests_passed = tests_passed + 1
    else
        print("  [FAIL] " .. name .. ": expected non-nil value")
        tests_failed = tests_failed + 1
    end
end

-- 4. UNIT TESTS

print("Running loadWordsFromString tests...")
-- Clear existing data via internal references
for k in pairs(Utility.wordSet) do Utility.wordSet[k] = nil end
for i = #Utility.WORDLIST, 1, -1 do table.remove(Utility.WORDLIST, i) end
Utility.setWordsByLength({})

local count = Utility.loadWordsFromString("Apple\nBanana\nApple\n  Cherry  ")
assert_eq(count, 3, "Correct count of unique words")
assert_eq(#Utility.WORDLIST, 3, "WORDLIST size matches")
assert_eq(Utility.WORDLIST[1], "apple", "Lowercase normalization 1")
assert_eq(Utility.WORDLIST[2], "banana", "Lowercase normalization 2")
assert_eq(Utility.WORDLIST[3], "cherry", "Trimming whitespace and lowercase")

print("\nRunning rebuildLengthIndex tests...")
Utility.rebuildLengthIndex()
local wordsByLength = Utility.getWordsByLength()
assert_not_nil(wordsByLength[5], "Length 5 group exists")
if wordsByLength[5] then
    assert_eq(#wordsByLength[5], 1, "One word of length 5 (apple)")
end
assert_not_nil(wordsByLength[6], "Length 6 group exists")
if wordsByLength[6] then
    assert_eq(wordsByLength[6][1], "banana", "banana is length 6")
    assert_eq(wordsByLength[6][2], "cherry", "cherry is length 6")
end

print("\nRunning addWordToList tests...")
local added = Utility.addWordToList("Dragon")
assert_eq(added, true, "New word added")
assert_eq(Utility.wordSet["dragon"], true, "Word present in set")
if wordsByLength[6] then
    assert_eq(#wordsByLength[6], 3, "Length index updated")
end
added = Utility.addWordToList("apple")
assert_eq(added, false, "Duplicate word not added")

print("\nRunning matchHint tests...")
-- Setup wordlist for matching
for k in pairs(Utility.wordSet) do Utility.wordSet[k] = nil end
for i = #Utility.WORDLIST, 1, -1 do table.remove(Utility.WORDLIST, i) end
Utility.setWordsByLength({})

Utility.addWordToList("apple")
Utility.addWordToList("banana")
Utility.addWordToList("cherry")
Utility.addWordToList("dragon")
Utility.addWordToList("grape")
Utility.rebuildLengthIndex()

local best, candidates = Utility.matchHint("_____")
assert_not_nil(candidates, "Candidates table returned for _____")
if candidates then
    assert_eq(#candidates, 2, "All underscore match length 5 (apple, grape)")
end

best, candidates = Utility.matchHint("a____")
assert_not_nil(candidates, "Candidates table returned for a____")
if candidates then
    assert_eq(#candidates, 1, "Pattern match 'apple'")
    assert_eq(candidates[1], "apple", "Correct candidate")
end

best, candidates = Utility.matchHint("_r____")
assert_not_nil(candidates, "Candidates table returned for _r____")
if candidates then
    assert_eq(candidates[1], "dragon", "Pattern match 'dragon'")
end

best, candidates = Utility.matchHint("banana")
assert_eq(best, "banana", "Exact match")

best, candidates = Utility.matchHint("unknown")
assert_eq(best, nil, "No match found for unknown")
if candidates then
    assert_eq(#candidates, 0, "Empty candidates list for unknown")
end

print("\n--- TEST SUMMARY ---")
print("Passed: " .. tests_passed)
print("Failed: " .. tests_failed)

if tests_failed > 0 then
    os.exit(1)
else
    os.exit(0)
end
