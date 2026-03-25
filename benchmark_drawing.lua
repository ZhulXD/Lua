local function run_benchmark()
    local FONT = {
        ["A"] = {
            {{0,0}, {1,2}, {2,0}, {1,2}, {2,0}, {1,2}, {2,0}, {1,2}, {2,0}},
            {{0.5,1}, {1.5,1}, {0.5,1}, {1.5,1}, {0.5,1}, {1.5,1}, {0.5,1}, {1.5,1}}
        }
    }

    local strokes = FONT["A"]
    local curX, startY, letterScale = 0, 0, 1

    local simulated_time = 0
    local task = {}
    task.wait = function(t)
        simulated_time = simulated_time + (t or 0.016) -- assume wait() is 0.016
    end

    -- ORIGINAL
    for _, stroke in ipairs(strokes) do
        local wx, wy = stroke[1][1], stroke[1][2]
        task.wait(0.02)
        local prevX, prevY = wx, wy
        for pi = 2, #stroke do
            local nx = curX + stroke[pi][1]
            local ny = startY - stroke[pi][2]
            task.wait(0.02)
        end
        task.wait(0.03)
    end
    print("Baseline simulated time (Original): " .. tostring(simulated_time))

    -- OPTIMIZED
    simulated_time = 0
    for _, stroke in ipairs(strokes) do
        local wx, wy = stroke[1][1], stroke[1][2]
        task.wait()
        local prevX, prevY = wx, wy
        for pi = 2, #stroke do
            local nx = curX + stroke[pi][1]
            local ny = startY - stroke[pi][2]
            if pi % 4 == 0 then
                task.wait()
            end
        end
        task.wait(0.015)
    end
    print("Optimized simulated time: " .. tostring(simulated_time))
end
run_benchmark()
