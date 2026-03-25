with open("DrawGuess_Utility.lua", "r") as f:
    content = f.read()

bad_def = """        local function revertPendingWords()
            revertPendingWords()
        end"""

good_def = """        local function revertPendingWords()
            for _, w in ipairs(toUpload) do
                pendingWords[#pendingWords+1] = w
            end
        end"""

content = content.replace(bad_def, good_def)

with open("DrawGuess_Utility.lua", "w") as f:
    f.write(content)
