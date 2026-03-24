--[[
    Draw & Guess Utility v9 | Place ID: 3281073759
    - Kata asli dari gameEnd param[2]
    - Dictionary matching berdasarkan pola hint
    - Auto Guess blast semua kata sesuai panjang hint
    - Auto-learn: kata baru dari gameEnd disimpan ke GitHub Gist
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local LocalPlayer       = Players.LocalPlayer
local PlayerGui         = LocalPlayer:WaitForChild("PlayerGui")

-- ANTI-AFK (Infinite Yield method - karakter & kamera tidak bergerak)
LocalPlayer.Idled:Connect(function()
    game:GetService("VirtualUser"):Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    task.wait(1)
    game:GetService("VirtualUser"):Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
end)

-- KONFIGURASI GITHUB GIST
local GITHUB_TOKEN = "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"
local GIST_ID      = "72a9ee3b4eae8b659b6d9e12ebfe3e2e"
local GIST_FILE    = "DrawGuess_Words.txt"
local WORDS_FILE   = "DrawGuess_Words.txt"

local wordSet       = {}
local WORDLIST      = {}
local pendingWords  = {}
local wordsByLength = {}  -- index per panjang kata untuk matchHint

-- HTTP helper
local function httpRequest(method, url, headers, body)
    local reqFunc = request or (syn and syn.request) or http_request or (http and http.request)
    if not reqFunc then return nil end
    local ok, res = pcall(reqFunc, {
        Url = url, Method = method, Headers = headers, Body = body
    })
    if ok then return res end
    return nil
end

-- Muat kata dari string
local function loadWordsFromString(str)
    local count = 0
    for line in (str .. "\n"):gmatch("([^\n]*)\n") do
        local w = line:lower():match("^%s*(.-)%s*$")
        if w and w ~= "" and not wordSet[w] then
            WORDLIST[#WORDLIST+1] = w
            wordSet[w] = true
            count = count + 1
        end
    end
    return count
end

-- Rebuild length index
local function rebuildLengthIndex()
    wordsByLength = {}
    for _, word in ipairs(WORDLIST) do
        local len = #word
        if not wordsByLength[len] then wordsByLength[len] = {} end
        wordsByLength[len][#wordsByLength[len]+1] = word
    end
end

-- Tambah kata baru ke WORDLIST + file cache
local function addWordToList(word)
    if not word or word == "" then return false end
    local w = word:lower():match("^%s*(.-)%s*$")
    if w == "" or wordSet[w] then return false end
    WORDLIST[#WORDLIST+1] = w
    wordSet[w] = true
    pendingWords[#pendingWords+1] = w
    local len = #w
    if not wordsByLength[len] then wordsByLength[len] = {} end
    wordsByLength[len][#wordsByLength[len]+1] = w
    pcall(function()
        local existing = ""
        local ok, c = pcall(readfile, WORDS_FILE)
        if ok and c and #c > 0 then
            existing = c
            -- Pastikan ada newline di akhir agar kata tidak tergabung
            if existing:sub(-1) ~= "\n" then
                existing = existing .. "\n"
            end
        end
        writefile(WORDS_FILE, existing .. w .. "\n")
    end)
    return true
end

-- Upload ke GitHub Gist — hanya append kata baru
local function uploadToGist()
    if #pendingWords == 0 then return end
    local toUpload = pendingWords
    pendingWords = {}
    task.spawn(function()
        -- Step 1: GET konten Gist saat ini
        local res = httpRequest("GET",
            "https://api.github.com/gists/" .. GIST_ID,
            {
                ["Authorization"] = "token " .. GITHUB_TOKEN,
                ["Accept"]        = "application/vnd.github.v3+json",
            },
            nil
        )

        -- PENTING: Jika GET gagal, batalkan upload
        -- Jangan kirim PATCH dengan existing="" karena akan hapus semua kata
        if not res or res.StatusCode ~= 200 then
            for _, w in ipairs(toUpload) do
                pendingWords[#pendingWords+1] = w
            end
            return
        end

        local existing = ""
        local raw = res.Body or ""
        local cm = raw:match('"' .. GIST_FILE .. '".-"content":"(.-[^\\])"')
        if cm then
            existing = cm:gsub("\\n","\n"):gsub('\\"','"'):gsub("\\\\","\\")
            if existing:sub(-1) ~= "\n" then existing = existing .. "\n" end
        else
            -- Tidak bisa parse content — batalkan, jangan overwrite
            for _, w in ipairs(toUpload) do
                pendingWords[#pendingWords+1] = w
            end
            return
        end

        -- Step 2: PATCH dengan existing + kata baru
        local newContent = existing .. table.concat(toUpload, "\n") .. "\n"
        local escaped = newContent:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n")
        local body = '{"files":{"' .. GIST_FILE .. '":{"content":"' .. escaped .. '"}}}'
        local res2 = httpRequest("PATCH",
            "https://api.github.com/gists/" .. GIST_ID,
            {
                ["Authorization"] = "token " .. GITHUB_TOKEN,
                ["Content-Type"]  = "application/json",
                ["Accept"]        = "application/vnd.github.v3+json",
            },
            body
        )
        if not (res2 and (res2.StatusCode == 200 or res2.StatusCode == 201)) then
            for _, w in ipairs(toUpload) do
                pendingWords[#pendingWords+1] = w
            end
        end
    end)
end

-- Load wordlist saat startup
-- Step 1: baca cache lokal dulu (cepat)
-- Step 2: sync Gist di background (satu arah: Gist -> cache)
local wordlistReady = false
local function loadLearnedWords()
    local ok, c = pcall(readfile, WORDS_FILE)
    if ok and c and #c > 0 then loadWordsFromString(c) end
    rebuildLengthIndex()

    task.spawn(function()
        local reqFunc = request or (syn and syn.request) or http_request or (http and http.request)
        if not reqFunc then wordlistReady = true; return end

        local ok2, res = pcall(reqFunc, {
            Url     = "https://api.github.com/gists/" .. GIST_ID,
            Method  = "GET",
            Headers = {
                ["Authorization"] = "token " .. GITHUB_TOKEN,
                ["Accept"]        = "application/vnd.github.v3+json",
            },
        })

        if ok2 and res and res.StatusCode == 200 then
            local raw = res.Body or ""
            local cm = raw:match('"DrawGuess_Words.txt".-"content":"(.-[^\\])"')
            if not cm then
                cm = raw:match('"content"%s*:%s*"(.-[^\\])"')
            end
            if cm then
                local decoded = cm:gsub("\\n","\n"):gsub('\\"','"'):gsub("\\\\","\\")
                local added = 0
                for line in (decoded .. "\n"):gmatch("([^\n]*)\n") do
                    local w = line:lower():match("^%s*(.-)%s*$")
                    if w ~= "" and not wordSet[w] then
                        WORDLIST[#WORDLIST+1] = w
                        wordSet[w] = true
                        local len = #w
                        if not wordsByLength[len] then wordsByLength[len] = {} end
                        wordsByLength[len][#wordsByLength[len]+1] = w
                        added = added + 1
                    end
                end
                if added > 0 then
                    local ls = {}
                    for _, w in ipairs(WORDLIST) do ls[#ls+1] = w end
                    pcall(writefile, WORDS_FILE, table.concat(ls,"\n"))
                end
            end
        end
        wordlistReady = true
    end)
end

task.spawn(loadLearnedWords)

-- DICTIONARY MATCHER
local byte = string.byte
local function matchHint(hint)
    if not hint or hint == "" then return nil end
    local pattern = hint:lower():gsub("%s+", " "):match("^%s*(.-)%s*$")
    local hintLen = #pattern
    local allUnderscore = not pattern:find("[^_ ]")
    local pool = wordsByLength[hintLen]
    if not pool then return nil, {} end
    local candidates = {}
    if allUnderscore then
        for i = 1, #pool do candidates[i] = pool[i] end
    else
        for _, word in ipairs(pool) do
            local match = true
            for i = 1, hintLen do
                local hb = byte(pattern, i)
                if hb ~= 95 and hb ~= 32 then
                    if hb ~= byte(word, i) then match = false; break end
                end
            end
            if match then candidates[#candidates+1] = word end
        end
    end
    return candidates[1], candidates
end

-- REMOTES
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local R = {}
for _, name in ipairs({
    "gameStart","gameEnd","word","guess","sendGuess",
    "systemChat","isChoosing","turn",
    "draw","wayPoint","drawTools","erase","undoRedo","choosingWords"
}) do
    local rem = Remotes:FindFirstChild(name)
    if rem then R[name] = rem end
end

-- ═══════════════════════════════════════════════
--  AUTO DRAW TEKS
--  Format: draw(Vector(X, Y, rotasi), panjang)
--  Canvas: X ~ -40..+40, Y ~ 22..52
-- ═══════════════════════════════════════════════

-- Font bitmap: setiap huruf = kumpulan stroke
-- Setiap stroke = urutan titik {x, y}
-- x: 0..4, y: 0(bawah)..8(atas) — Y positif ke atas sesuai canvas game
-- Lebar huruf = 4 unit, tinggi = 8 unit
local FONT = {
    -- y=0=atas y=8=bawah x=0=kiri x=4=kanan
    A = {
        {{0,8},{2,0},{4,8}},
        {{1,4},{3,4}}
    },
    B = {
        {{0,0},{0,8}},
        {{0,0},{3,0},{4,1},{4,3},{3,4},{0,4}},
        {{0,4},{3,4},{4,5},{4,7},{3,8},{0,8}}
    },
    C = {
        {{4,1},{3,0},{1,0},{0,1},{0,7},{1,8},{3,8},{4,7}}
    },
    D = {
        {{0,0},{0,8}},
        {{0,0},{2,0},{4,2},{4,6},{2,8},{0,8}}
    },
    E = {
        {{0,0},{0,8}},
        {{0,0},{4,0}},
        {{0,4},{3,4}},
        {{0,8},{4,8}}
    },
    F = {
        {{0,0},{0,8}},
        {{0,0},{4,0}},
        {{0,4},{3,4}}
    },
    G = {
        {{4,1},{3,0},{1,0},{0,1},{0,7},{1,8},{3,8},{4,7},{4,4},{2,4}}
    },
    H = {
        {{0,0},{0,8}},
        {{4,0},{4,8}},
        {{0,4},{4,4}}
    },
    I = {
        {{1,0},{3,0}},
        {{2,0},{2,8}},
        {{1,8},{3,8}}
    },
    J = {
        {{2,0},{4,0}},
        {{3,0},{3,7},{2,8},{1,8},{0,7}}
    },
    K = {
        {{0,0},{0,8}},
        {{0,4},{4,0}},
        {{0,4},{4,8}}
    },
    L = {
        {{0,0},{0,8},{4,8}}
    },
    M = {
        {{0,8},{0,0},{2,4},{4,0},{4,8}}
    },
    N = {
        {{0,8},{0,0},{4,8},{4,0}}
    },
    O = {
        {{1,0},{3,0},{4,2},{4,6},{3,8},{1,8},{0,6},{0,2},{1,0}}
    },
    P = {
        {{0,0},{0,8}},
        {{0,0},{3,0},{4,1},{4,3},{3,4},{0,4}}
    },
    Q = {
        {{1,0},{3,0},{4,2},{4,6},{3,8},{1,8},{0,6},{0,2},{1,0}},
        {{3,6},{4,8}}
    },
    R = {
        {{0,0},{0,8}},
        {{0,0},{3,0},{4,1},{4,3},{3,4},{0,4}},
        {{2,4},{4,8}}
    },
    S = {
        {{4,1},{3,0},{1,0},{0,1},{0,3},{1,4},{3,4},{4,5},{4,7},{3,8},{1,8},{0,7}}
    },
    T = {
        {{0,0},{4,0}},
        {{2,0},{2,8}}
    },
    U = {
        {{0,0},{0,7},{1,8},{3,8},{4,7},{4,0}}
    },
    V = {
        {{0,0},{2,8},{4,0}}
    },
    W = {
        {{0,0},{1,8},{2,4},{3,8},{4,0}}
    },
    X = {
        {{0,0},{4,8}},
        {{4,0},{0,8}}
    },
    Y = {
        {{0,0},{2,4},{4,0}},
        {{2,4},{2,8}}
    },
    Z = {
        {{0,0},{4,0},{0,8},{4,8}}
    },
    [" "] = {},
}

-- Local renderer: duplikasi persis fungsi render game
-- Dari source: CFrame.new(X, Y, canvas.Z + canvas.SizeZ + pixelLayer)
--              * CFrame.Angles(0, 0, rotation)
-- Part size = Vector3.new(length, pixelSize, partThickness)
-- Cari canvas dengan nama spesifik atau Z sekitar -147
local canvasRef = nil
local function getCanvas()
    if canvasRef and canvasRef.Parent then return canvasRef end
    -- Strategi 1: cari Part bernama "canvas" atau "Canvas"
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Part") then
            local name = obj.Name:lower()
            if name == "canvas" or name:find("canvas") then
                canvasRef = obj
                return canvasRef
            end
        end
    end
    -- Strategi 2: cari Part dengan Z sekitar -130 sampai -160 (area canvas)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Part") and obj.Size.X > 5 and obj.Size.Y > 5 then
            local z = obj.Position.Z
            if z < -100 and z > -200 then
                canvasRef = obj
                return canvasRef
            end
        end
    end
    return nil
end

local cachedSurfaceZ = nil
local function getSurfaceZ()
    -- Prioritas 1: ambil dari Part yang sudah ada di canvasPixels
    local canvasPixels = workspace:FindFirstChild("canvasPixels")
    if canvasPixels then
        for _, part in ipairs(canvasPixels:GetChildren()) do
            if part:IsA("Part") then
                cachedSurfaceZ = part.Position.Z
                return cachedSurfaceZ
            end
        end
    end
    -- Prioritas 2: hitung dari canvas
    local canvas = getCanvas()
    if canvas then
        local z = canvas.Position.Z + canvas.Size.Z + 1.4
        return z
    end
    -- Prioritas 3: cache sebelumnya
    if cachedSurfaceZ then return cachedSurfaceZ end
    -- Fallback mutlak
    return -146.3
end

local function renderLocalStroke(posX, posY, rotation, length, pixelSize, color, surfZ)
    if length <= 0 then return end

    local surfaceZ = getSurfaceZ()
    local partThickness = 0.1

    local ok = pcall(function()
        local p1 = Instance.new("Part")
        p1.CFrame = CFrame.new(posX, posY, surfaceZ) * CFrame.Angles(0, 0, rotation)
        p1.Size = Vector3.new(length, pixelSize, partThickness)
        p1.Anchored = true
        p1.CanCollide = false
        p1.Color = color
        p1.Material = Enum.Material.SmoothPlastic
        p1.CastShadow = false
        p1.Parent = workspace.canvasPixels

        -- Cylinder ujung stroke
        local p2 = Instance.new("Part")
        p2.Shape = Enum.PartType.Cylinder
        p2.CFrame = p1.CFrame * CFrame.new(-length/2, 0, 0) * CFrame.Angles(0, math.pi/2, 0)
        p2.Size = Vector3.new(partThickness, pixelSize, pixelSize)
        p2.Anchored = true
        p2.CanCollide = false
        p2.Color = color
        p2.Material = Enum.Material.SmoothPlastic
        p2.CastShadow = false
        p2.Parent = workspace.canvasPixels
    end)
end

-- Fungsi untuk menggambar teks di canvas
local function autoDraw(text, startX, startY, letterScale, color, pixLayer)
    if not R.draw or not R.wayPoint then
        return
    end
    if not R.drawTools then
        return
    end

    text = text:upper()
    local letterW = 5 * letterScale  -- lebar huruf (4) + spasi (1)
    local spacing = letterScale * 0.5 -- spasi tambahan antar huruf
    local curX = startX

    task.spawn(function()
        -- Set layer dulu jika ditentukan
        if pixLayer ~= nil then
            R.drawTools:FireServer(pixLayer)
            task.wait(0.02)
        end
        -- Set brush size dan warna
        R.drawTools:FireServer(1.4, color or drawColor)
        task.wait(0.03)

        local function makeVec(x, y, z)
            local ok, v = pcall(vector.create, x, y, z)
            if ok and v then return v end
            return Vector3.new(x, y, z)
        end

        -- Cache surfaceZ sekali di awal
        local surfaceZ = getSurfaceZ()

        -- Gambar huruf
        for ci = 1, #text do
            local ch = text:sub(ci, ci)
            local strokes = FONT[ch]
            if strokes then
                for si, stroke in ipairs(strokes) do
                    if #stroke >= 1 then
                        local p0 = stroke[1]
                        local wx = curX + p0[1] * letterScale
                        local wy = startY - p0[2] * letterScale
                        -- Titik pertama: pen down di posisi awal (len=0)
                        pcall(function()
                            R.draw:FireServer(makeVec(wx, wy, 0), 0)
                        end)
                        task.wait(0.02)

                        local prevX, prevY = wx, wy
                        for pi = 2, #stroke do
                            local p = stroke[pi]
                            local nx = curX + p[1] * letterScale
                            local ny = startY - p[2] * letterScale
                            local dx = nx - prevX
                            local dy = ny - prevY
                            local len = math.sqrt(dx*dx + dy*dy)
                            local angle = math.atan2(dy, dx)
                            -- POSISI = MIDPOINT antara prevPoint dan nextPoint
                            local mx = (prevX + nx) / 2
                            local my = (prevY + ny) / 2
                            pcall(function()
                                R.draw:FireServer(makeVec(mx, my, angle), len)
                            end)
                            renderLocalStroke(mx, my, angle, len, 1.4,
                                color or Color3.fromRGB(0,0,0), surfaceZ)
                            task.wait(0.02)
                            prevX, prevY = nx, ny
                        end
                        R.wayPoint:FireServer()
                        task.wait(0.03)
                    end
                end
            end
            curX = curX + letterW + spacing
        end
    end)
end

-- GAME STATE
local State = {
    currentDrawer  = nil,
    confirmedWord  = nil,
    currentHint    = nil,
    matchedWord    = nil,
    allCandidates  = {},
    candidateIndex = 1,
    isMyTurn       = false,
    hasGuessed     = false,
    gameActive     = false,
}
local autoGuessEnabled  = false
local autoDrawEnabled   = false
local autoDrawDone      = false
local autoPickWord      = false
local drawColor         = Color3.fromRGB(0, 0, 0)   -- warna huruf
local shadowColor       = Color3.fromRGB(0, 0, 0)   -- warna shadow
local allUnderscoreDone = false
local sentWords         = {}

-- KIRIM TEBAKAN
local function sendGuessWord(word)
    if not word or word == "" then return false end
    R.sendGuess:FireServer(word)
    return true
end

local function sendNew(word)
    local w = word:lower()
    if sentWords[w] then return false end
    sentWords[w] = true
    return sendGuessWord(word)
end

-- AUTO GUESS LOOP
local autoGuessThread = nil
local function stopAutoGuessLoop()
    if autoGuessThread then
        pcall(function() task.cancel(autoGuessThread) end)
        autoGuessThread = nil
    end
end

local function startAutoGuessLoop()
    stopAutoGuessLoop()
    if not autoGuessEnabled then return end
    if State.isMyTurn or State.hasGuessed or not State.gameActive then return end
    if #State.allCandidates == 0 then return end

    local hint = State.currentHint or ""
    local isAllUnderscore = not hint:find("[^_ ]")

    if isAllUnderscore then
        allUnderscoreDone = false
        autoGuessThread = task.spawn(function()
            local batch = 0
            for _, word in ipairs(State.allCandidates) do
                if not State.gameActive or State.hasGuessed
                   or State.isMyTurn or allUnderscoreDone then break end
                sendNew(word)
                batch = batch + 1
                if batch % 15 == 0 then
                    task.wait(0)
                end
            end
            allUnderscoreDone = true
        end)
    else
        autoGuessThread = task.spawn(function()
            for _, word in ipairs(State.allCandidates) do
                if not State.gameActive or State.hasGuessed or State.isMyTurn then break end
                sendNew(word)
            end
        end)
    end
end

-- REMOTE LISTENERS

if R.gameEnd then
    R.gameEnd.OnClientEvent:Connect(function(scoreTable, word, tick, dur)
        stopAutoGuessLoop()
        if type(word) == "string" and word ~= "" then
            State.confirmedWord = word
            local added = addWordToList(word)
            if added then task.delay(1, uploadToGist) end
        end
        State.gameActive     = false
        State.isMyTurn       = false
        State.hasGuessed     = false
        State.currentHint    = nil
        State.matchedWord    = nil
        State.allCandidates  = {}
        State.candidateIndex = 1
        sentWords            = {}
    end)
end

if R.gameStart then
    R.gameStart.OnClientEvent:Connect(function(drawer, tick, dur, hint)
        State.gameActive     = true
        State.hasGuessed     = false
        State.currentHint    = nil
        State.matchedWord    = nil
        State.allCandidates  = {}
        State.candidateIndex = 1
        allUnderscoreDone    = false
        sentWords            = {}
        autoDrawDone         = false

        if drawer then
            State.currentDrawer = drawer
            State.isMyTurn      = (drawer == LocalPlayer)
        end

        -- Auto draw dihandle di word.OnClientEvent saat isMyTurn=true
     
        if type(hint) == "string" and hint ~= "" then
            State.currentHint = hint
            local best, candidates = matchHint(hint)
            State.matchedWord   = best
            State.allCandidates = candidates or {}
        end

        if autoGuessEnabled and not State.isMyTurn then
            if wordlistReady then
                startAutoGuessLoop()
            else
                task.spawn(function()
                    local waited = 0
                    while not wordlistReady and waited < 5 do
                        task.wait(0.05)
                        waited = waited + 0.05
                    end
                    if State.gameActive and not State.hasGuessed
                       and not State.isMyTurn and autoGuessEnabled then
                        local h = State.currentHint or ""
                        local best, candidates = matchHint(h)
                        State.matchedWord   = best
                        State.allCandidates = candidates or {}
                        startAutoGuessLoop()
                    end
                end)
            end
        end
    end)
end

if R.word then
    R.word.OnClientEvent:Connect(function(hint)
        if type(hint) ~= "string" or hint == "" then return end

        if State.isMyTurn then
            -- Saat giliran menggambar, word event membawa kata asli
            -- (bukan underscore) — ini saat yang tepat untuk auto draw
            local word = hint:gsub("_","")  -- bersihkan jika masih ada underscore
            if word ~= "" and not hint:find("_") then
                -- Kata asli diterima
                if autoDrawEnabled and not autoDrawDone then
                    autoDrawDone = true
                    task.delay(1, function()
                        local w = hint:upper()
                        -- Canvas width aman: ~75 unit (-37.5 sampai +37.5)
                        -- letterW per huruf = 5 * scale, total = n*5*scale - scale
                        -- maxScale = 75 / (5*n - 1)
                        local clr = drawColor
                        -- Cek apakah ada spasi (kata lebih dari satu suku kata)
                        if w:find(" ") then
                            -- Pecah jadi kata-kata
                            local parts = {}
                            for part in (w .. " "):gmatch("([^ ]*) ") do
                                if part ~= "" then parts[#parts+1] = part end
                            end
                            -- Tentukan jumlah baris: 1 kata = 1 baris, 2 = 2 baris, 3+ = 3 baris (maks)
                            local numLines = math.min(#parts, 3)
                            -- Bagi kata ke baris seimbang
                            -- Distribusi: bagikan kata merata, sisa ke baris atas
                            local lines = {}
                            local perLine = math.floor(#parts / numLines)
                            local extra   = #parts - perLine * numLines
                            local idx = 1
                            for li = 1, numLines do
                                local count = perLine + (li <= extra and 1 or 0)
                                lines[li] = table.concat(parts, " ", idx, idx + count - 1)
                                idx = idx + count
                            end
                            -- Scale berdasarkan baris terpanjang
                            local longest = 0
                            for _, ln in ipairs(lines) do
                                if #ln > longest then longest = #ln end
                            end
                            local canvasW = 72
                            local maxScale = canvasW / (5.5 * longest - 0.5)
                            local letterScale = math.min(1.8, math.max(0.6, maxScale))
                            local letterW = 5.5 * letterScale
                            local lineH = 8 * letterScale
                            local gap = letterScale * 2.5
                            local totalH = numLines * lineH + (numLines - 1) * gap
                            -- Gambar tiap baris dari atas ke bawah
                            -- Y canvas: besar = atas, kecil = bawah
                            local delay = 0
                            for li, ln in ipairs(lines) do
                                local lw = #ln * letterW - letterScale * 0.5
                                local sy = 35 + totalH/2 - (li-1) * (lineH + gap) - lineH
                                local lx = -lw / 2
                                local d  = delay
                                task.delay(d, function()
                                    local shadowOffset = letterScale * 0.35
                                    autoDraw(ln, lx + shadowOffset, sy - shadowOffset, letterScale, shadowColor, 0.0)
                                    task.wait(#ln * 0.08)
                                    autoDraw(ln, lx, sy, letterScale, clr, 0.1)
                                end)
                                delay = delay + #ln * 0.12 + 0.3
                            end
                        else
                            -- Satu baris normal
                            local n = #w
                            local canvasW = 72
                            local maxScale = canvasW / (5.5 * n - 0.5)
                            local letterScale = math.min(1.8, math.max(0.6, maxScale))
                            local letterW = 5.5 * letterScale
                            local totalW = n * letterW - letterScale * 0.5
                            local startX = -totalW / 2
                            local startY = 35 - (8 * letterScale / 2)
                            local shadowOffset = letterScale * 0.35
                            -- Shadow di Layer 1, huruf asli di Layer 2
                            autoDraw(w, startX + shadowOffset, startY - shadowOffset, letterScale, shadowColor, 0.0)
                            task.wait(#w * 0.08)
                            autoDraw(w, startX, startY, letterScale, clr, 0.1)
                        end
                    end)
                end
            else
            end
            return
        end

        -- Saat menebak
        State.currentHint = hint
        local best, candidates = matchHint(hint)
        State.matchedWord    = best
        State.allCandidates  = candidates or {}
        State.candidateIndex = 1

        if not autoGuessEnabled or State.hasGuessed
           or not State.gameActive then return end

        allUnderscoreDone = true
        stopAutoGuessLoop()

        if #State.allCandidates == 0 then return end

        autoGuessThread = task.spawn(function()
            for _, word in ipairs(State.allCandidates) do
                if not State.gameActive or State.hasGuessed or State.isMyTurn then break end
                sendNew(word)
            end
        end)
    end)
end

if R.guess then
    R.guess.OnClientEvent:Connect(function(player)
        if player == LocalPlayer then
            State.hasGuessed = true
            stopAutoGuessLoop()
        end
    end)
end

if R.isChoosing then
    R.isChoosing.OnClientEvent:Connect(function(player)
        stopAutoGuessLoop()
        State.gameActive = false
        State.currentHint = nil
        if player then
            State.currentDrawer = player
            State.isMyTurn = (player == LocalPlayer)
        end
    end)
end

-- choosingWords: diterima saat giliran memilih kata
-- Server mengirim data kata, client merespons dengan index (1-3)
if R.choosingWords then
    R.choosingWords.OnClientEvent:Connect(function(p)
        if autoPickWord and State.isMyTurn then
            -- Pilih index random 1-3 (3 pilihan kata normal)
            task.delay(0.3, function()
                local idx = math.random(1, 3)
                pcall(function() R.choosingWords:FireServer(idx) end)
            end)
        end
    end)
end

if R.turn then
    R.turn.OnClientEvent:Connect(function() end)
end

if R.systemChat then
    R.systemChat.OnClientEvent:Connect(function() end)
end

-- GUI
local function mkCorner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end
local function mkStroke(p, col, thick)
    local s = Instance.new("UIStroke")
    s.Color = col; s.Thickness = thick or 1; s.Parent = p
end
local function mkGrad(p, c0, c1, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(c0, c1)
    g.Rotation = rot or 90; g.Parent = p
end
local function setGrad(p, c0, c1, rot)
    for _, c in ipairs(p:GetChildren()) do
        if c:IsA("UIGradient") then c:Destroy() end
    end
    mkGrad(p, c0, c1, rot)
end
local function mkLabel(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Size        = props.size or UDim2.new(1,0,1,0)
    l.Position    = props.pos  or UDim2.new(0,0,0,0)
    l.Text        = props.text or ""
    l.TextColor3  = props.col  or Color3.new(1,1,1)
    l.TextSize    = props.ts   or 13
    l.Font        = props.font or Enum.Font.GothamBold
    l.TextXAlignment = props.align or Enum.TextXAlignment.Left
    l.TextWrapped = true
    l.ZIndex      = props.z or 1
    l.Parent      = parent
    return l
end


-- ── ORPH HUB UI (Eclipse) ──────────────────


-- ═══════════════════════════════════════════
--  ORPH HUB UI
-- ═══════════════════════════════════════════

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()
local ViewportSize = workspace.CurrentCamera.ViewportSize

local CFG = {
    MainColor = Color3.fromRGB(14, 14, 14),
    SecondaryColor = Color3.fromRGB(26, 26, 26),
    AccentColor = Color3.fromRGB(80, 180, 255),
    TextColor = Color3.fromRGB(200, 200, 200),
    TextDark = Color3.fromRGB(120, 120, 120),
    StrokeColor = Color3.fromRGB(40, 40, 40),
    Font = Enum.Font.Code,
    BaseSize = Vector2.new(600, 450)
}

local Library = {
    Flags = {},
    Connections = {},
    Unloaded = false
}

local function Create(class, props, children)
    local inst = Instance.new(class)
    for i, v in pairs(props or {}) do
        inst[i] = v
    end
    for _, child in pairs(children or {}) do
        child.Parent = inst
    end
    return inst
end

local function Tween(obj, props, time, style, dir)
    TweenService:Create(obj, TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

local function GetTextSize(text, size, font)
    return game:GetService("TextService"):GetTextSize(text, size, font, Vector2.new(10000, 10000))
end

local ScreenGui = Create("ScreenGui", {
    Name = "OrphHub",
    Parent = PlayerGui,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    ResetOnSpawn = false,
    IgnoreGuiInset = true
})

local UIScale = Create("UIScale", {Parent = ScreenGui})

local function UpdateScale()
    local vp = workspace.CurrentCamera.ViewportSize
    local widthRatio = (vp.X - 40) / CFG.BaseSize.X
    local scale = math.min(widthRatio, 0.55)
    UIScale.Scale = math.max(scale, 0.4)
end

workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateScale)
UpdateScale()

local NotificationContainer = Create("Frame", {
    Parent = ScreenGui,
    Position = UDim2.new(1, -20, 0, 20),
    AnchorPoint = Vector2.new(1, 0),
    Size = UDim2.new(0, 300, 1, 0),
    BackgroundTransparency = 1,
    ZIndex = 100
})
local UIListNotif = Create("UIListLayout", {
    Parent = NotificationContainer,
    Padding = UDim.new(0, 5),
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    VerticalAlignment = Enum.VerticalAlignment.Top
})

function Library:Notify(msg, type)
    local color = (type == "success" and Color3.fromRGB(100, 255, 100)) or 
                  (type == "warning" and Color3.fromRGB(255, 100, 100)) or 
                  CFG.AccentColor

    local Frame = Create("Frame", {
        Parent = NotificationContainer,
        Size = UDim2.new(0, 0, 0, 30),
        BackgroundColor3 = CFG.MainColor,
        BorderSizePixel = 0,
        ClipsDescendants = true
    }, {
        Create("UIStroke", {Color = CFG.AccentColor, Thickness = 1, Transparency = 0.5}),
        Create("Frame", {
            Size = UDim2.new(0, 2, 1, 0),
            BackgroundColor3 = color
        }),
        Create("TextLabel", {
            Text = msg,
            TextColor3 = CFG.TextColor,
            Font = CFG.Font,
            TextSize = 12,
            Size = UDim2.new(1, -10, 1, 0),
            Position = UDim2.new(0, 10, 0, 0),
            BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left
        })
    })

    Tween(Frame, {Size = UDim2.new(0, 250, 0, 35)}, 0.5, Enum.EasingStyle.Back)
    
    task.delay(3, function()
        Tween(Frame, {Size = UDim2.new(0, 250, 0, 0), BackgroundTransparency = 1}, 0.5)
        task.wait(0.5)
        Frame:Destroy()
    end)
end

local TooltipLabel = Create("TextLabel", {
    Parent = ScreenGui,
    Size = UDim2.new(0, 0, 0, 20),
    BackgroundColor3 = CFG.SecondaryColor,
    TextColor3 = CFG.TextColor,
    TextSize = 11,
    Font = CFG.Font,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 200
}, {
    Create("UIPadding", {PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5)}),
    Create("UIStroke", {Color = CFG.StrokeColor})
})

local function AddTooltip(obj, text)
    obj.MouseEnter:Connect(function()
        TooltipLabel.Text = text
        TooltipLabel.Size = UDim2.fromOffset(GetTextSize(text, 11, CFG.Font).X + 12, 20)
        TooltipLabel.Visible = true
    end)
    obj.MouseLeave:Connect(function()
        TooltipLabel.Visible = false
    end)
end

RunService.RenderStepped:Connect(function()
    if TooltipLabel.Visible then
        local m = UserInputService:GetMouseLocation()
        TooltipLabel.Position = UDim2.fromOffset(m.X + 15, m.Y + 15)
    end
end)

local MainFrame = Create("Frame", {
    Name = "MainFrame",
    Parent = ScreenGui,
    Size = UDim2.fromOffset(CFG.BaseSize.X, CFG.BaseSize.Y),
    Position = UDim2.new(0.5, -300, 0.5, -225),
    BackgroundColor3 = CFG.MainColor,
    BorderSizePixel = 0
}, {
    Create("UIStroke", {Color = CFG.StrokeColor}),
    Create("UICorner", {CornerRadius = UDim.new(0, 3)})
})

local Dragging, DragInput, DragStart, StartPos = false, nil, nil, nil

MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        Dragging = true
        DragStart = input.Position
        StartPos = MainFrame.Position
        
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                Dragging = false
            end
        end)
    end
end)

MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        DragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == DragInput and Dragging then
        local delta = input.Position - DragStart
        Tween(MainFrame, {Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + delta.X, StartPos.Y.Scale, StartPos.Y.Offset + delta.Y)}, 0.05)
    end
end)

local TopBar = Create("Frame", {
    Parent = MainFrame,
    Size = UDim2.new(1, 0, 0, 30),
    BackgroundColor3 = CFG.MainColor,
    BorderSizePixel = 0
}, {
    Create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = CFG.StrokeColor
    })
})

local TitleLabel = Create("TextLabel", {
    Parent = TopBar,
    Text = "Orph Hub | Guess the Drawing!",
    TextColor3 = CFG.TextDark,
    TextSize = 13,
    Font = CFG.Font,
    BackgroundTransparency = 1,
    Size = UDim2.new(0, 200, 1, 0),
    Position = UDim2.new(0, 10, 0, 0),
    TextXAlignment = Enum.TextXAlignment.Left,
    RichText = true
})



local ContentContainer = Create("Frame", {
    Parent = MainFrame,
    Size = UDim2.new(1, 0, 1, -30),
    Position = UDim2.new(0, 0, 0, 30),
    BackgroundTransparency = 1
})

local Sidebar = Create("Frame", {
    Parent = ContentContainer,
    Size = UDim2.new(0, 60, 1, 0),
    BackgroundColor3 = Color3.fromRGB(17, 17, 17),
    BorderSizePixel = 0,
  Position = UDim2.new(0, 0, 0, 0)
}, {
    Create("Frame", {Size = UDim2.new(0, 1, 0, 0), Position = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BackgroundColor3 = CFG.StrokeColor}),
    Create("UIListLayout", {Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Top}),
    Create("UIPadding", {PaddingTop = UDim.new(0, 8)})
})

local PagesContainer = Create("Frame", {
    Parent = ContentContainer,
    Size = UDim2.new(1, -60, 1, 0),
    Position = UDim2.new(0, 60, 0, 0),
    BackgroundTransparency = 1
})

local Tabs = {}
local CurrentTab = nil

function Library:Tab(name, icon)
    local TabButton = Create("TextButton", {
        Parent = Sidebar,
        Size = UDim2.new(0, 40, 0, 40),
        BackgroundColor3 = CFG.MainColor,
        Text = "",
        TextSize = 20,
        TextColor3 = CFG.TextDark,
        Font = CFG.Font,
        AutoButtonColor = false
    }, {
        Create("ImageLabel", {
            Name = "Icon",
            Size = UDim2.new(0.65, 0, 0.65, 0),
            Position = UDim2.new(0.175, 0, 0.175, 0),
            BackgroundTransparency = 1,
            Image = "rbxassetid://" .. icon,
            ImageColor3 = Color3.new(1,1,1),
            ScaleType = Enum.ScaleType.Fit
        }),
        Create("UICorner", {CornerRadius = UDim.new(0, 6)})
    })

    local PageFrame = Create("ScrollingFrame", {
        Parent = PagesContainer,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible = false,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = CFG.AccentColor,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y
    }, {
        Create("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8)}),
        Create("UIGridLayout", {
            CellSize = UDim2.new(0.48, 0, 0, 0),
            CellPadding = UDim2.new(0.02, 0, 0, 10),
            FillDirectionMaxCells = 2
        })
    })

    PageFrame:ClearAllChildren()
    local Padding = Create("UIPadding", {Parent = PageFrame, PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8)})
    
    local LeftCol = Create("Frame", {Parent = PageFrame, Size = UDim2.new(0.48, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, {
        Create("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
    })
    local RightCol = Create("Frame", {Parent = PageFrame, Size = UDim2.new(0.48, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.new(0.52, 0, 0, 0), BackgroundTransparency = 1}, {
        Create("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder})
    })

    TabButton.MouseButton1Click:Connect(function()
        for _, t in pairs(Tabs) do
            Tween(t.Btn, {TextColor3 = CFG.TextDark, BackgroundColor3 = CFG.MainColor}, 0.2)
            local ic = t.Btn:FindFirstChild("Icon")
            if ic then ic.ImageColor3 = Color3.new(1,1,1) end
            t.Page.Visible = false
        end
        Tween(TabButton, {TextColor3 = CFG.AccentColor, BackgroundColor3 = CFG.SecondaryColor}, 0.2)
        local ic2 = TabButton:FindFirstChild("Icon")
        if ic2 then ic2.ImageColor3 = CFG.AccentColor end
        PageFrame.Visible = true
        CurrentTab = PageFrame
    end)

    table.insert(Tabs, {Btn = TabButton, Page = PageFrame})

    if #Tabs == 1 then
        Tween(TabButton, {TextColor3 = CFG.AccentColor, BackgroundColor3 = CFG.SecondaryColor}, 0.2)
        PageFrame.Visible = true
    end

    local GroupFunctions = {}
    local LeftSide = true

    function GroupFunctions:Group(title)
        local ParentCol = LeftSide and LeftCol or RightCol
        LeftSide = not LeftSide

        local GroupFrame = Create("Frame", {
            Parent = ParentCol,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Color3.fromRGB(17, 17, 17),
            BorderSizePixel = 0
        }, {
            Create("UIStroke", {Color = CFG.StrokeColor}),
            Create("UICorner", {CornerRadius = UDim.new(0, 2)})
        })

        Create("Frame", {
            Parent = GroupFrame,
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundColor3 = CFG.SecondaryColor,
            BorderSizePixel = 0
        }, {
            Create("UICorner", {CornerRadius = UDim.new(0, 2)}),
            Create("Frame", {
                Size = UDim2.new(1, 0, 0, 5),
                Position = UDim2.new(0, 0, 1, -5),
                BackgroundColor3 = CFG.SecondaryColor,
                BorderSizePixel = 0
            }),
            Create("TextLabel", {
                Text = title,
                Size = UDim2.new(1, -20, 1, 0),
                Position = UDim2.new(0, 8, 0, 0),
                BackgroundTransparency = 1,
                TextColor3 = CFG.TextColor,
                Font = Enum.Font.GothamBold,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left
            }),
            Create("Frame", {
                Size = UDim2.new(0, 4, 0, 4),
                Position = UDim2.new(1, -10, 0.5, -2),
                BackgroundColor3 = CFG.AccentColor,
                BorderSizePixel = 0
            }, {Create("UICorner", {CornerRadius = UDim.new(1, 0)})})
        })

        local Content = Create("Frame", {
            Parent = GroupFrame,
            Size = UDim2.new(1, 0, 0, 0),
            Position = UDim2.new(0, 0, 0, 25),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1
        }, {
            Create("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}),
            Create("UIPadding", {PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)})
        })

        local ItemFuncs = {}
        local ColorPickerCount = 0
        local PICKER_W, PICKER_H = 180, 170
        local OpenPickers = {}
        local PickerLayoutConn

        local function ReflowOpenPickers()
            if #OpenPickers == 0 then return end

            table.sort(OpenPickers, function(a, b)
                return a.Order < b.Order
            end)

            local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
            local uiSize = MainFrame.AbsoluteSize
            local uiAbsX = (MainFrame.Position.X.Scale * viewport.X) + MainFrame.Position.X.Offset
            local uiAbsY = (MainFrame.Position.Y.Scale * viewport.Y) + MainFrame.Position.Y.Offset

            -- Prioritas kiri; jika UI digeser terlalu kiri, pindah ke samping kanan UI
            local leftAbsX = uiAbsX - PICKER_W - 8
            local canLeft = leftAbsX >= 8
            local xLocal = canLeft and (-PICKER_W - 8) or (uiSize.X + 8)

            -- Hitung stack sebagai satu blok supaya tidak saling tabrakan saat clamp
            local stackGap = 8
            local stackTotal = (#OpenPickers * PICKER_H) + ((#OpenPickers - 1) * stackGap)
            local startAbsY = uiAbsY + 34
            startAbsY = math.clamp(startAbsY, 8, math.max(8, viewport.Y - 8 - stackTotal))

            for idx, pickerMeta in ipairs(OpenPickers) do
                local yAbs = startAbsY + ((idx - 1) * (PICKER_H + stackGap))
                pickerMeta.Frame.Position = UDim2.fromOffset(xLocal, yAbs - uiAbsY)
            end
        end

        local function EnsurePickerLayoutLoop()
            if PickerLayoutConn or #OpenPickers == 0 then return end
            PickerLayoutConn = RunService.RenderStepped:Connect(function()
                if #OpenPickers == 0 then
                    if PickerLayoutConn then
                        PickerLayoutConn:Disconnect()
                        PickerLayoutConn = nil
                    end
                    return
                end
                ReflowOpenPickers()
            end)
        end

        local function RemoveOpenPicker(pickerFrame)
            for i = #OpenPickers, 1, -1 do
                if OpenPickers[i].Frame == pickerFrame then
                    table.remove(OpenPickers, i)
                    break
                end
            end
            ReflowOpenPickers()
            if #OpenPickers == 0 and PickerLayoutConn then
                PickerLayoutConn:Disconnect()
                PickerLayoutConn = nil
            end
        end

        function ItemFuncs:Toggle(cfg)
            local Enabled = false
            local Frame = Create("TextButton", {
                Parent = Content,
                Size = UDim2.new(1, 0, 0, 18),
                BackgroundTransparency = 1,
                Text = ""
            })

            local Box = Create("Frame", {
                Parent = Frame,
                Size = UDim2.new(0, 12, 0, 12),
                Position = UDim2.new(0, 0, 0.5, -6),
                BackgroundColor3 = CFG.SecondaryColor,
                BorderSizePixel = 0
            }, {Create("UIStroke", {Color = CFG.StrokeColor})})

            local Check = Create("Frame", {
                Parent = Box,
                Size = UDim2.new(1, -4, 1, -4),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = CFG.AccentColor,
                BackgroundTransparency = 1
            })

            local Label = Create("TextLabel", {
                Parent = Frame,
                Text = cfg.Name,
                TextColor3 = CFG.TextDark,
                TextSize = 11,
                Font = CFG.Font,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 18, 0, 0),
                Size = UDim2.new(1, -18, 1, 0),
                TextXAlignment = Enum.TextXAlignment.Left
            })

            if cfg.Risky then Label.TextColor3 = Color3.fromRGB(200, 80, 80) end
            if cfg.Tooltip then AddTooltip(Frame, cfg.Tooltip) end

            local function Update()
                Enabled = not Enabled
                Tween(Check, {BackgroundTransparency = Enabled and 0 or 1}, 0.1)
                Tween(Label, {TextColor3 = Enabled and CFG.TextColor or (cfg.Risky and Color3.fromRGB(200, 80, 80) or CFG.TextDark)}, 0.1)
                if cfg.Callback then cfg.Callback(Enabled) end
            end

            Frame.MouseButton1Click:Connect(Update)
            return {Set = function(v) if v ~= Enabled then Update() end end}
        end

        function ItemFuncs:Slider(cfg)
            local Value = cfg.Default or cfg.Min
            local DraggingSlider = false

            local Frame = Create("Frame", {
                Parent = Content,
                Size = UDim2.new(1, 0, 0, 32),
                BackgroundTransparency = 1
            })

            local Label = Create("TextLabel", {
                Parent = Frame,
                Text = cfg.Name,
                TextColor3 = CFG.TextDark,
                TextSize = 11,
                Font = CFG.Font,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 15),
                TextXAlignment = Enum.TextXAlignment.Left
            })

            local ValueLabel = Create("TextLabel", {
                Parent = Frame,
                Text = Value .. (cfg.Unit or ""),
                TextColor3 = CFG.TextDark,
                TextSize = 11,
                Font = CFG.Font,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 15),
                TextXAlignment = Enum.TextXAlignment.Right
            })

            local SliderBG = Create("Frame", {
                Parent = Frame,
                Size = UDim2.new(1, 0, 0, 6),
                Position = UDim2.new(0, 0, 0, 20),
                BackgroundColor3 = CFG.SecondaryColor,
                BorderSizePixel = 0
            }, {
                Create("UIStroke", {Color = CFG.StrokeColor}),
                Create("UICorner", {CornerRadius = UDim.new(1, 0)})
            })

            local Fill = Create("Frame", {
                Parent = SliderBG,
                Size = UDim2.new(0, 0, 1, 0),
                BackgroundColor3 = CFG.AccentColor
            }, {Create("UICorner", {CornerRadius = UDim.new(1, 0)})})

            local function Update(input)
                local SizeX = SliderBG.AbsoluteSize.X
                local PosX = SliderBG.AbsolutePosition.X
                local InputX = input.Position.X
                
                local Percent = math.clamp((InputX - PosX) / SizeX, 0, 1)
                Value = math.floor(cfg.Min + (cfg.Max - cfg.Min) * Percent)
                
                Fill.Size = UDim2.new(Percent, 0, 1, 0)
                ValueLabel.Text = Value .. (cfg.Unit or "")
                if cfg.Callback then cfg.Callback(Value) end
            end

            Frame.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    DraggingSlider = true
                    Update(input)
                end
            end)
            
            UserInputService.InputChanged:Connect(function(input)
                if DraggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    Update(input)
                end
            end)

            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    DraggingSlider = false
                end
            end)

            local percent = (Value - cfg.Min) / (cfg.Max - cfg.Min)
            Fill.Size = UDim2.new(percent, 0, 1, 0)
            if cfg.Tooltip then AddTooltip(Frame, cfg.Tooltip) end
        end

        function ItemFuncs:Dropdown(cfg)
            local Expanded = false
            local Current = cfg.Default or cfg.Options[1]

            local Frame = Create("Frame", {
                Parent = Content,
                Size = UDim2.new(1, 0, 0, 36),
                BackgroundTransparency = 1,
                ZIndex = 20
            })

            Create("TextLabel", {
                Parent = Frame,
                Text = cfg.Name,
                TextColor3 = CFG.TextDark,
                TextSize = 11,
                Font = CFG.Font,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 15),
                TextXAlignment = Enum.TextXAlignment.Left
            })

            local MainBox = Create("TextButton", {
                Parent = Frame,
                Size = UDim2.new(1, 0, 0, 20),
                Position = UDim2.new(0, 0, 0, 16),
                BackgroundColor3 = CFG.SecondaryColor,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false
            }, {
                Create("UIStroke", {Color = CFG.StrokeColor}),
                Create("UICorner", {CornerRadius = UDim.new(0, 3)}),
                Create("TextLabel", {
                    Name = "Val",
                    Text = Current,
                    Size = UDim2.new(1, -20, 1, 0),
                    Position = UDim2.new(0, 5, 0, 0),
                    BackgroundTransparency = 1,
                    TextColor3 = CFG.TextColor,
                    TextSize = 11,
                    Font = CFG.Font,
                    TextXAlignment = Enum.TextXAlignment.Left
                }),
                Create("TextLabel", {
                    Text = "▼",
                    Size = UDim2.new(0, 20, 1, 0),
                    Position = UDim2.new(1, -20, 0, 0),
                    BackgroundTransparency = 1,
                    TextColor3 = CFG.TextDark,
                    TextSize = 10
                })
            })

            local ListFrame = Create("ScrollingFrame", {
                Parent = MainBox,
                Size = UDim2.new(1, 0, 0, 0),
                Position = UDim2.new(0, 0, 1, 2),
                BackgroundColor3 = CFG.SecondaryColor,
                BorderSizePixel = 0,
                Visible = false,
                ZIndex = 50,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 2
            }, {
                Create("UIStroke", {Color = CFG.StrokeColor}),
                Create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}),
                Create("UICorner", {CornerRadius = UDim.new(0, 3)})
            })

            for _, opt in pairs(cfg.Options) do
                local Btn = Create("TextButton", {
                    Parent = ListFrame,
                    Size = UDim2.new(1, 0, 0, 20),
                    BackgroundTransparency = 1,
                    Text = opt,
                    TextColor3 = (opt == Current) and CFG.AccentColor or CFG.TextDark,
                    TextSize = 11,
                    Font = CFG.Font
                })
                Btn.MouseButton1Click:Connect(function()
                    Current = opt
                    MainBox.Val.Text = opt
                    if cfg.Callback then cfg.Callback(opt) end
                    Expanded = false
                    Tween(ListFrame, {Size = UDim2.new(1, 0, 0, 0)}, 0.1)
                    task.wait(0.1)
                    ListFrame.Visible = false
                end)
            end

            MainBox.MouseButton1Click:Connect(function()
                Expanded = not Expanded
                if Expanded then
                    ListFrame.Visible = true
                    Tween(ListFrame, {Size = UDim2.new(1, 0, 0, math.min(#cfg.Options * 20, 100))}, 0.1)
                else
                    Tween(ListFrame, {Size = UDim2.new(1, 0, 0, 0)}, 0.1)
                    task.wait(0.1)
                    ListFrame.Visible = false
                end
            end)
            if cfg.Tooltip then AddTooltip(Frame, cfg.Tooltip) end
        end

        function ItemFuncs:ColorPicker(cfg)
            local Color = cfg.Default or Color3.fromRGB(255, 255, 255)
            local Opened = false
            ColorPickerCount = ColorPickerCount + 1
            local PickerOrder = ColorPickerCount
            
            local Frame = Create("Frame", {
                Parent = Content,
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
                ZIndex = 15
            })
            
            Create("TextLabel", {
                Parent = Frame,
                Text = cfg.Name,
                TextColor3 = CFG.TextDark,
                TextSize = 11,
                Font = CFG.Font,
                BackgroundTransparency = 1,
                Size = UDim2.new(0.6, 0, 1, 0),
                TextXAlignment = Enum.TextXAlignment.Left
            })

            local Preview = Create("TextButton", {
                Parent = Frame,
                Size = UDim2.new(0, 30, 0, 14),
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                BackgroundColor3 = Color,
                Text = "",
                AutoButtonColor = false
            }, {
                Create("UIStroke", {Color = CFG.StrokeColor}),
                Create("UICorner", {CornerRadius = UDim.new(0, 3)})
            })

            local PickerFrame = Create("Frame", {
                Parent = MainFrame,
                Size = UDim2.new(0, 180, 0, 0),
                Position = UDim2.new(0, 0, 0, 0),
                ZIndex = 200,
                AnchorPoint = Vector2.new(0, 0),
                BackgroundColor3 = CFG.MainColor,
                BorderSizePixel = 0,
                ClipsDescendants = true,
                Visible = false
            }, {
                Create("UIStroke", {Color = CFG.StrokeColor}),
                Create("UICorner", {CornerRadius = UDim.new(0, 3)})
            })

            local SatValPanel = Create("TextButton", {
                Parent = PickerFrame,
                Size = UDim2.new(1, -20, 0, 100),
                Position = UDim2.new(0, 10, 0, 10),
                BackgroundColor3 = Color3.fromHSV(0, 1, 1),
                Text = "",
                AutoButtonColor = false
            }, {
                Create("ImageLabel", {
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Image = "rbxassetid://4801885019"
                }),
                Create("ImageLabel", {
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Image = "rbxassetid://4801885019",
                    ImageColor3 = Color3.new(0,0,0),
                    Rotation = 90
                })
            })

            local Cursor = Create("Frame", {
                Parent = SatValPanel,
                Size = UDim2.new(0, 4, 0, 4),
                BackgroundColor3 = Color3.new(1,1,1),
                AnchorPoint = Vector2.new(0.5, 0.5)
            }, {Create("UICorner", {CornerRadius = UDim.new(1, 0)})})

            local HueSlider = Create("TextButton", {
                Parent = PickerFrame,
                Size = UDim2.new(1, -20, 0, 10),
                Position = UDim2.new(0, 10, 0, 120),
                Text = "",
                AutoButtonColor = false
            }, {
                Create("UIGradient", {
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromHSV(0,1,1)),
                        ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17,1,1)),
                        ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33,1,1)),
                        ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5,1,1)),
                        ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67,1,1)),
                        ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83,1,1)),
                        ColorSequenceKeypoint.new(1, Color3.fromHSV(1,1,1))
                    })
                }),
                Create("UICorner", {CornerRadius = UDim.new(0, 2)})
            })

            local H, S, V = Color3.toHSV(Color)
            local DraggingHSV, DraggingHue = false, false

            local function UpdateColor()
                Color = Color3.fromHSV(H, S, V)
                Preview.BackgroundColor3 = Color
                SatValPanel.BackgroundColor3 = Color3.fromHSV(H, 1, 1)
                Cursor.Position = UDim2.new(S, 0, 1 - V, 0)
                if cfg.Callback then cfg.Callback(Color) end
            end
            UpdateColor()

            SatValPanel.InputBegan:Connect(function(inp) 
                if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then 
                    DraggingHSV = true 
                end 
            end)
            HueSlider.InputBegan:Connect(function(inp) 
                if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then 
                    DraggingHue = true 
                end 
            end)
            
            UserInputService.InputEnded:Connect(function(inp) 
                if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then 
                    DraggingHSV = false; DraggingHue = false 
                end 
            end)

            UserInputService.InputChanged:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
                    if DraggingHSV then
                        local size = SatValPanel.AbsoluteSize
                        local pos = SatValPanel.AbsolutePosition
                        local x = math.clamp((inp.Position.X - pos.X) / size.X, 0, 1)
                        local y = math.clamp((inp.Position.Y - pos.Y) / size.Y, 0, 1)
                        S = x
                        V = 1 - y
                        UpdateColor()
                    elseif DraggingHue then
                        local size = HueSlider.AbsoluteSize
                        local pos = HueSlider.AbsolutePosition
                        local x = math.clamp((inp.Position.X - pos.X) / size.X, 0, 1)
                        H = x
                        UpdateColor()
                    end
                end
            end)

            Preview.MouseButton1Click:Connect(function()
                Opened = not Opened
                if Opened then
                    PickerFrame.Visible = true
                    for _, v in ipairs(PickerFrame:GetDescendants()) do
                        pcall(function() v.ZIndex = 200 end)
                    end
                    Tween(PickerFrame, {Size = UDim2.new(0, PICKER_W, 0, PICKER_H)}, 0.2)
                    table.insert(OpenPickers, {Frame = PickerFrame, Order = PickerOrder})
                    ReflowOpenPickers()
                    EnsurePickerLayoutLoop()
                else
                    RemoveOpenPicker(PickerFrame)
                    Tween(PickerFrame, {Size = UDim2.new(0, PICKER_W, 0, 0)}, 0.2)
                    task.delay(0.2, function()
                        if not Opened then
                            PickerFrame.Visible = false
                        end
                    end)
                end
            end)
            if cfg.Tooltip then AddTooltip(Frame, cfg.Tooltip) end
        end

        function ItemFuncs:Textbox(cfg)
            local Frame = Create("Frame", {
                Parent = Content,
                Size = UDim2.new(1, 0, 0, 35),
                BackgroundTransparency = 1
            })
            
            Create("TextLabel", {
                Parent = Frame,
                Text = cfg.Name,
                TextColor3 = CFG.TextDark,
                TextSize = 11,
                Font = CFG.Font,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 15),
                TextXAlignment = Enum.TextXAlignment.Left
            })

            local Box = Create("TextBox", {
                Parent = Frame,
                Size = UDim2.new(1, 0, 0, 20),
                Position = UDim2.new(0, 0, 0, 15),
                BackgroundColor3 = CFG.SecondaryColor,
                TextColor3 = CFG.TextColor,
                PlaceholderText = cfg.Placeholder or "...",
                Text = "",
                Font = CFG.Font,
                TextSize = 11,
                BorderSizePixel = 0
            }, {
                Create("UIStroke", {Color = CFG.StrokeColor}),
                Create("UICorner", {CornerRadius = UDim.new(0, 3)}),
                Create("UIPadding", {PaddingLeft = UDim.new(0, 5)})
            })

            Box.FocusLost:Connect(function()
                if cfg.Callback then cfg.Callback(Box.Text) end
            end)
            if cfg.Tooltip then AddTooltip(Frame, cfg.Tooltip) end
        end

        function ItemFuncs:Keybind(cfg)
            local Key = cfg.Default or Enum.KeyCode.Insert
            local Waiting = false

            local Frame = Create("Frame", {
                Parent = Content,
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1
            })

            Create("TextLabel", {
                Parent = Frame,
                Text = cfg.Name,
                TextColor3 = CFG.TextDark,
                TextSize = 11,
                Font = CFG.Font,
                BackgroundTransparency = 1,
                Size = UDim2.new(0.6, 0, 1, 0),
                TextXAlignment = Enum.TextXAlignment.Left
            })

            local Btn = Create("TextButton", {
                Parent = Frame,
                Size = UDim2.new(0, 60, 1, 0),
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                BackgroundColor3 = CFG.SecondaryColor,
                Text = Key.Name,
                TextColor3 = CFG.TextDark,
                TextSize = 10,
                Font = CFG.Font
            }, {
                Create("UIStroke", {Color = CFG.StrokeColor}),
                Create("UICorner", {CornerRadius = UDim.new(0, 3)})
            })

            Btn.MouseButton1Click:Connect(function()
                Waiting = true
                Btn.Text = "..."
                Btn.TextColor3 = CFG.AccentColor
            end)

            UserInputService.InputBegan:Connect(function(inp)
                if Waiting and inp.UserInputType == Enum.UserInputType.Keyboard then
                    Waiting = false
                    Key = inp.KeyCode
                    Btn.Text = Key.Name
                    Btn.TextColor3 = CFG.TextDark
                    if cfg.Callback then cfg.Callback(Key) end
                end
            end)
            if cfg.Tooltip then AddTooltip(Frame, cfg.Tooltip) end
        end

        function ItemFuncs:Button(cfg)
            local Btn = Create("TextButton", {
                Parent = Content,
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundColor3 = CFG.SecondaryColor,
                Text = cfg.Name,
                TextColor3 = CFG.TextDark,
                Font = Enum.Font.GothamBold,
                TextSize = 10
            }, {
                Create("UIStroke", {Color = CFG.StrokeColor}),
                Create("UICorner", {CornerRadius = UDim.new(0, 3)})
            })

            if cfg.Variant == "Primary" then
                Btn.BackgroundColor3 = CFG.AccentColor
                Btn.TextColor3 = Color3.new(0,0,0)
            elseif cfg.Variant == "Danger" then
                Btn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
                Btn.TextColor3 = Color3.new(0,0,0)
            end

            Btn.MouseButton1Click:Connect(function()
                if cfg.Callback then cfg.Callback() end
            end)
            if cfg.Tooltip then AddTooltip(Btn, cfg.Tooltip) end
        end

        return ItemFuncs
    end
    return GroupFunctions
end


-- ── INIT TABS ───────────────────────────────
local TabMain  = Library:Tab("Main",  111795921099960)
local TabMisc  = Library:Tab("Misc",  75608340919404)
local TabAbout = Library:Tab("About", 132274905878799)

-- Title animasi Orph Hub
TitleLabel.RichText = true
task.spawn(function()
    local list = {
        "","O","Or","Orp","Orph","Orph ","Orph H","Orph Hu","Orph Hub",
        "Orph Hub |","Orph Hub | G","Orph Hub | Gu","Orph Hub | Gue",
        "Orph Hub | Guess","Orph Hub | Guess the",
        "Orph Hub | Guess the Draw","Orph Hub | Guess the Drawing!",
    }
    while TitleLabel.Parent do
        for _, t in ipairs(list) do
            TitleLabel.Text = t:gsub("Hub", '<font color="#50b4ff">Hub</font>')
            task.wait(0.09)
        end
        task.wait(2)
        for i = #list,1,-1 do
            TitleLabel.Text = list[i]:gsub("Hub",'<font color="#50b4ff">Hub</font>')
            task.wait(0.06)
        end
        task.wait(0.5)
    end
end)

-- Mobile toggle (Orph Hub logo)
local Visible2 = true
local MobileToggle = Create("ImageButton", {
    Parent = ScreenGui,
    Size = UDim2.new(0,44,0,44),
    Position = UDim2.new(0.5,0,0,10),
    AnchorPoint = Vector2.new(0.5,0),
    BackgroundColor3 = CFG.MainColor,
    Image = "rbxassetid://124532527991032",
    ImageColor3 = Color3.new(1,1,1),
    ScaleType = Enum.ScaleType.Fit,
    AutoButtonColor = false, ZIndex = 10
}, {
    Create("UICorner",{CornerRadius=UDim.new(1,0)}),
    Create("UIStroke",{Color=CFG.AccentColor,Thickness=2})
})
-- Drag MobileToggle
local mtDragging, mtDragInput, mtDragStart, mtStartPos = false, nil, nil, nil

MobileToggle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        mtDragging = true
        mtDragStart = input.Position
        mtStartPos = MobileToggle.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                mtDragging = false
            end
        end)
    end
end)

MobileToggle.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch then
        mtDragInput = input
    end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
    if input == mtDragInput and mtDragging then
        local delta = input.Position - mtDragStart
        MobileToggle.Position = UDim2.new(
            mtStartPos.X.Scale,
            mtStartPos.X.Offset + delta.X,
            mtStartPos.Y.Scale,
            mtStartPos.Y.Offset + delta.Y
        )
    end
end)

MobileToggle.MouseButton1Click:Connect(function()
    Visible2 = not Visible2
    MainFrame.Visible = Visible2
end)

-- ── PROFILE PICTURE (pojok kiri bawah UI) ───
local profileFrame = Create("Frame", {
    Parent = MainFrame,
    Size = UDim2.new(0, 36, 0, 36),
    Position = UDim2.new(0, 8, 1, -44),
    BackgroundColor3 = CFG.SecondaryColor,
    BorderSizePixel = 0,
    ZIndex = 10
}, {
    Create("UICorner", {CornerRadius = UDim.new(1, 0)}),
    Create("UIStroke", {Color = CFG.AccentColor, Thickness = 1.5})
})

local profileImg = Create("ImageLabel", {
    Parent = profileFrame,
    Size = UDim2.new(1, -4, 1, -4),
    Position = UDim2.new(0, 2, 0, 2),
    BackgroundTransparency = 1,
    ZIndex = 11
}, {
    Create("UICorner", {CornerRadius = UDim.new(1, 0)})
})

-- Username label di sebelah kanan foto profil
local profileName = Create("TextLabel", {
    Parent = MainFrame,
    Size = UDim2.new(0, 120, 0, 36),
    Position = UDim2.new(0, 50, 1, -44),
    BackgroundTransparency = 1,
    Text = LocalPlayer.Name,
    TextColor3 = CFG.TextDark,
    TextSize = 10,
    Font = CFG.Font,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 10
})

-- Load thumbnail async
task.spawn(function()
    local ok, id = pcall(function()
        return game:GetService("Players"):GetUserThumbnailAsync(
            LocalPlayer.UserId,
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size48x48
        )
    end)
    if ok then profileImg.Image = id end
end)

-- ── MAIN TAB ────────────────────────────────
local InfoGroup = TabMain:Group("Info")
local CtrlGroup = TabMain:Group("Control")

-- Info rows injected via task.defer
local HintLbl, MatchLbl, ConfirmedLbl, StatusLbl

local function mkInfoRow(parent, tag, tagCol)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,18); row.BackgroundTransparency = 1; row.Parent = parent
    local tl = Instance.new("TextLabel")
    tl.Size = UDim2.new(0.4,0,1,0); tl.BackgroundTransparency = 1
    tl.Text = tag; tl.TextColor3 = tagCol or CFG.TextDark
    tl.TextSize = 11; tl.Font = CFG.Font
    tl.TextXAlignment = Enum.TextXAlignment.Left; tl.Parent = row
    local vl = Instance.new("TextLabel")
    vl.Size = UDim2.new(0.6,0,1,0); vl.Position = UDim2.new(0.4,0,0,0)
    vl.BackgroundTransparency = 1; vl.Text = "—"
    vl.TextColor3 = CFG.TextColor; vl.TextSize = 11; vl.Font = CFG.Font
    vl.TextXAlignment = Enum.TextXAlignment.Left; vl.Parent = row
    return vl
end

task.defer(function()
    -- Cari Content frame milik InfoGroup (frame pertama dengan UIListLayout+UIPadding)
    for _, v in ipairs(ScreenGui:GetDescendants()) do
        if v:IsA("Frame") and v.AutomaticSize == Enum.AutomaticSize.Y
           and v:FindFirstChildOfClass("UIListLayout")
           and v:FindFirstChildOfClass("UIPadding")
           and not HintLbl then
            HintLbl      = mkInfoRow(v, "hint",   CFG.AccentColor)
            MatchLbl     = mkInfoRow(v, "match",  Color3.fromRGB(80,220,130))
            ConfirmedLbl = mkInfoRow(v, "answer", Color3.fromRGB(160,100,255))
            local sl = Instance.new("TextLabel")
            sl.Size = UDim2.new(1,0,0,14); sl.BackgroundTransparency = 1
            sl.Text = "○ menunggu  ·  0 kata"; sl.TextColor3 = CFG.TextDark
            sl.TextSize = 9; sl.Font = CFG.Font
            sl.TextXAlignment = Enum.TextXAlignment.Left; sl.Parent = v
            StatusLbl = sl
            break
        end
    end
end)

local function setStatus(msg, col)
    if StatusLbl then StatusLbl.Text = msg; StatusLbl.TextColor3 = col or CFG.TextDark end
end

-- Control toggles
CtrlGroup:Toggle({Name = "Auto Guess", Callback = function(v)
    autoGuessEnabled = v
    if v and State.gameActive and not State.isMyTurn then startAutoGuessLoop()
    elseif not v then stopAutoGuessLoop() end
end})
CtrlGroup:Toggle({Name = "Auto Draw",      Callback = function(v) autoDrawEnabled = v end})
CtrlGroup:Toggle({Name = "Auto Pick Word", Callback = function(v) autoPickWord    = v end})

local ColorGroup = TabMain:Group("Draw Colors")
ColorGroup:ColorPicker({Name = "Warna Huruf", Default = Color3.fromRGB(0, 0, 0), Callback = function(c)
    drawColor = c
end})
ColorGroup:ColorPicker({Name = "Warna Shadow", Default = Color3.fromRGB(0, 0, 0), Callback = function(c)
    shadowColor = c
end})

-- ── MISC TAB ────────────────────────────────
local MiscGroup = TabMisc:Group("Settings")
MiscGroup:Toggle({Name = "Anti-AFK", Callback = function(v) end})

-- ── ABOUT TAB ───────────────────────────────
local AboutGroup = TabAbout:Group("Orph Hub")
AboutGroup:Button({Name = "Draw & Guess Utility"})
AboutGroup:Button({Name = "Auto Guess + Draw + Pick"})
AboutGroup:Button({Name = "Wordlist: GitHub Gist Sync"})
AboutGroup:Button({Name = "Place ID: 3281073759"})

-- Dummy refs
local AutoBtn = Instance.new("TextButton"); AutoBtn.Parent = Instance.new("Folder")
local DrawBtn = AutoBtn; local PickBtn = AutoBtn
local GuessRow = Instance.new("Frame"); GuessRow.Parent = Instance.new("Folder")
local DrawRow = GuessRow; local divider = Instance.new("Frame")
divider.Parent = Instance.new("Folder")
local panelVisible = true

-- ── HEARTBEAT ───────────────────────────────
local prevHint, prevMatch, prevConf, prevWC = nil, nil, nil, 0
RunService.Heartbeat:Connect(function()
    if not HintLbl then return end
    local hint  = State.currentHint or "—"
    local match = State.matchedWord
        and (State.matchedWord .. "  (" .. #State.allCandidates .. ")")
        or "—"
    local conf   = State.confirmedWord or "—"
    local wcount = #WORDLIST
    if hint == prevHint and match == prevMatch and conf == prevConf
       and wcount == prevWC then return end
    prevHint = hint; prevMatch = match; prevConf = conf; prevWC = wcount
    HintLbl.Text = hint; MatchLbl.Text = match; ConfirmedLbl.Text = conf
    local wc = tostring(wcount) .. " kata"
    if State.matchedWord then
        MatchLbl.TextColor3 = Color3.fromRGB(100,255,160)
        setStatus("● " .. State.matchedWord .. "  ·  " .. #State.allCandidates .. " kandidat  ·  " .. wc, Color3.fromRGB(80,200,120))
    elseif State.gameActive then
        MatchLbl.TextColor3 = Color3.fromRGB(220,80,80)
        setStatus("● ronde aktif  ·  " .. wc, CFG.AccentColor)
    else
        setStatus("○ menunggu  ·  " .. wc, CFG.TextDark)
    end
end)
