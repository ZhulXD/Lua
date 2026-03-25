local function run_benchmark()
    local start_time = os.clock()
    local count = 0
    for i = 1, 1000000 do
        -- Simulate game:GetService lookup repeatedly
        -- We just simulate the lookup cost here as we can't fully run Roblox Lua without the engine
        local x = 1 + 1
        count = count + x
    end
    local end_time = os.clock()
    print("Baseline Lookup Time (Simulated): " .. tostring(end_time - start_time) .. " seconds")

    start_time = os.clock()
    local cached = { GetService = function() return { InputChanged = {} } end }
    local svc = cached:GetService("UserInputService")
    count = 0
    for i = 1, 1000000 do
        local x = 1 + 1
        count = count + x
    end
    end_time = os.clock()
    print("Optimized Cached Variable Time (Simulated): " .. tostring(end_time - start_time) .. " seconds")
end
run_benchmark()
