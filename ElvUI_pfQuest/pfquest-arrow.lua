local function ExtendPfQuestConfig()
    for _, entry in pairs(pfQuest_defconfig) do
        if entry.config == "arrowscale" then
            return true
        end
    end

    local insertPos = nil
    for id, data in pairs(pfQuest_defconfig) do
        if data.config and data.config == "arrow" then
            insertPos = id
            break
        end
    end

    if insertPos == nil then
        return  -- shouldn't happen but don't insert the setting at a random place either
    end

    table.insert(pfQuest_defconfig, insertPos + 1,
    {
        text = "Arrow Scale",
        default = "1.0",
        type = "text",
        config = "arrowscale",
    })

    if not pfQuest_config["arrowscale"] then
        pfQuest_config["arrowscale"] = "1.0"
    end
end

local configExtenderFrame = CreateFrame("Frame")
configExtenderFrame:RegisterEvent("VARIABLES_LOADED")
configExtenderFrame:SetScript("OnEvent", function()
    ExtendPfQuestConfig()
end)

function ResizeArrow()
    local scale = tonumber(pfQuest_config["arrowscale"]) or 1
    scale = max(0.5, min(3.0, scale))
    scale = floor(scale * 10 + 0.5) / 10
    pfQuest_config["arrowscale"] = tostring(scale)
    pfQuest.route.arrow:SetScale(pfQuest_config["arrowscale"])
end
