-- Mail: recipient names. The players you mailed come first, newest first;
-- then ClassicAPI's known names: your other characters, group, guild,
-- friends and whispers. Doc headings are ClassicAPI's docs/API.md.
if not CLASSIC_API_VERSION then
    error("Mail needs ClassicAPI.", 0)
end

local _, M = ...
MailDB = MailDB or {} -- restored first: LoadSavedVariablesFirst

local SHOWN, RECENT = 5, 10
-- "## AutoComplete": not Online, since offline players get mail too.
local KNOWN = Enum.AutoCompleteEntryFlag.AccountCharacter + Enum.AutoCompleteEntryFlag.InGroup
    + Enum.AutoCompleteEntryFlag.InGuild + Enum.AutoCompleteEntryFlag.Friend
    + Enum.AutoCompleteEntryFlag.InteractedWith

local box = SendMailNameEditBox
local matches, choice, typed = {}, nil, 0

function M.Print(text) DEFAULT_CHAT_FRAME:AddMessage("|cffff9e38Mail:|r " .. text) end

-- Saved per realm and faction: { recent = { name, ... }, last = { [character] = name } }.
-- Nothing is saved until you mail someone.
local NONE = { recent = {}, last = {} }
local function Key() return GetRealmName() .. "|" .. UnitFactionGroup("player") end
local function Saved() return MailDB[Key()] or NONE end

function M.Last() return Saved().last[UnitName("player")] end

-- GAP: C_AutoComplete's RecentPlayer bit should cover the players you mailed.
-- Until then the last ten are kept here, newest first.
function M.Mailed(name)
    local key = Key()
    MailDB[key] = MailDB[key] or { recent = {}, last = {} } -- vanillaforge-ignore: D2 (once per realm)
    local realm = MailDB[key]
    for i, known in ipairs(realm.recent) do
        if known == name then table.remove(realm.recent, i); break end
    end
    table.insert(realm.recent, 1, name)
    realm.recent[RECENT + 1] = nil
    realm.last[UnitName("player")] = name
end

-- The list under the name box ------------------------------------------------

local list = CreateFrame("Frame", nil, box)
list:SetFrameStrata("DIALOG")
list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -10, 3)
list:SetWidth(140)
list:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 } })
list:SetBackdropColor(0, 0, 0, 0.9)
list:Hide()
local hint = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
hint:SetPoint("BOTTOMLEFT", 15, 9)
hint:SetText("Tab: next name")

local function Complete()
    box:SetText(matches[choice])
    box:HighlightText(typed, -1)
    for i, button in ipairs(list) do
        if i == choice then button:LockHighlight() else button:UnlockHighlight() end
    end
end

local function Take()
    list:Hide()
    box:HighlightText(0, 0)
end

for i = 1, SHOWN do
    local button = CreateFrame("Button", nil, list)
    button:SetHeight(14)
    button:SetPoint("TOPLEFT", 5, -8 - (i - 1) * 14)
    button:SetPoint("RIGHT", -5, 0)
    button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    button.label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    button.label:SetPoint("LEFT", 10, 0)
    button:SetScript("OnClick", function() choice = i; Complete(); Take() end)
    list[i] = button
end

local function Listed(name)
    for _, match in ipairs(matches) do if match == name then return true end end
end

local function Suggest()
    local text = box:GetText()
    typed = #text
    table.wipe(matches)
    local upper = string.upper(text)
    for _, name in ipairs(Saved().recent) do
        if #matches == SHOWN then break end
        if string.find(string.upper(name), upper, 1, true) == 1 then matches[#matches + 1] = name end
    end
    for _, entry in ipairs(C_AutoComplete.GetAutoCompleteResults(text, SHOWN, 0, true, KNOWN, 0)) do
        if #matches == SHOWN then break end
        if not Listed(entry.name) then matches[#matches + 1] = entry.name end
    end
    if typed == 0 or #matches == 0 or (#matches == 1 and matches[1] == text) then return list:Hide() end
    for i, button in ipairs(list) do
        button.label:SetText(matches[i])
        if matches[i] then button:Show() else button:Hide() end
    end
    list:SetHeight(#matches * 14 + 30)
    list:Show()
    choice = 1
    Complete()
end

local function Cycle(by)
    choice = (choice - 1 + by) % #matches + 1
    Complete()
end

-- The box's own scripts run when the list is closed (FrameXML MailFrame.xml).
local function OrElse(script, f)
    local original = box:GetScript(script)
    box:SetScript(script, function() if list:IsShown() then f() else original() end end)
end
OrElse("OnTabPressed", function() Cycle(IsShiftKeyDown() and -1 or 1) end)
OrElse("OnEnterPressed", Take)
OrElse("OnEscapePressed", function() list:Hide() end)
box:SetScript("OnChar", Suggest) -- replaces the client's friends-then-guild guess
box:HookScript("OnEditFocusLost", function() list:Hide() end)
-- "jyskedollars" becomes "Jyskedollars".
box:HookScript("OnTextChanged", function()
    local text = box:GetText()
    local name = string.upper(string.sub(text, 1, 1)) .. string.lower(string.sub(text, 2))
    if name ~= text then box:SetText(name) end
end)
