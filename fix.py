with open("DrawGuess_Utility.lua", "r") as f:
    content = f.read()

# Add the helper function
old_start = """local function uploadToGist()
    if #pendingWords == 0 then return end
    if not GIST_ID or GIST_ID == "" then return end
    local toUpload = pendingWords
    pendingWords = {}
    task.spawn(function()"""

new_start = """local function uploadToGist()
    if #pendingWords == 0 then return end
    if not GIST_ID or GIST_ID == "" then return end
    local toUpload = pendingWords
    pendingWords = {}
    task.spawn(function()
        local function revertPendingWords()
            for _, w in ipairs(toUpload) do
                pendingWords[#pendingWords+1] = w
            end
        end"""

content = content.replace(old_start, new_start)

loop = """            for _, w in ipairs(toUpload) do
                pendingWords[#pendingWords+1] = w
            end"""

content = content.replace(loop, "            revertPendingWords()")

with open("DrawGuess_Utility.lua", "w") as f:
    f.write(content)
