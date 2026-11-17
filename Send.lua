-- Mail: send many items. The client mails one item per letter, so the items
-- wait in a queue, by their item GUID, and go out one letter each. Functions
-- named here are the client's (FrameXML MailFrame.lua) unless a doc heading
-- of ClassicAPI's docs/API.md is given.
local _, M = ...
if not M.Print then return end -- no ClassicAPI: Names.lua said so

local SLOTS, PER_ROW = 21, 7
local queue = {} -- item GUIDs, in the order they were attached
local sending -- the letter going out: to, subject, body, money, cod, total, sent, waiting
local picked -- the GUID PickupContainerItem last took from a bag
local events = CreateFrame("Frame")
local slots = {}

local function Where(guid) return C_Item.GetItemLocation(guid) end -- "### C_Item.GetItemLocation(itemGUID)"

local function Find(guid)
    for i, queued in ipairs(queue) do if queued == guid then return i end end
end

-- "### C_Item.LockItem(itemLocation)": a waiting item looks locked in every
-- bag addon. Only a look; a server update for the item clears it.
local function Lock()
    for _, guid in ipairs(queue) do
        local at = Where(guid)
        if at and not C_Item.IsLocked(at) then C_Item.LockItem(at) end
    end
end

local function Unlock(guid)
    local at = Where(guid)
    if at then C_Item.UnlockItem(at) end
end

-- The slots and the letter -----------------------------------------------------

local letter = { StationeryBackgroundLeft, StationeryBackgroundRight, (select(3, SendMailScrollFrame:GetRegions())) }
local rows

-- One row of slots per seven items and one free slot, three rows at most; the
-- letter gives up the room. Laid out again only when the row count changes.
local function Layout()
    local wanted = math.min(3, math.floor(#queue / PER_ROW) + 1)
    if wanted == rows then return end
    rows = wanted
    for i, slot in ipairs(slots) do slot:SetShown(i <= rows * PER_ROW) end
    local height = 257 - rows * 41
    SendMailScrollFrame:SetHeight(height)
    SendMailScrollChildFrame:SetHeight(height)
    for i, texture in ipairs(letter) do
        texture:SetHeight(height)
        texture:SetTexCoord(0, i == 3 and 0.484375 or 1, 0, height / 256)
    end
    SendMailHorizontalBarLeft:ClearAllPoints()
    SendMailHorizontalBarLeft:SetPoint("BOTTOMLEFT", SendMailFrame, "BOTTOMLEFT", 15, 146 + rows * 41)
end

local function Draw()
    for i, slot in ipairs(slots) do
        local at = queue[i] and Where(queue[i])
        if at then slot.icon:SetTexture(C_Item.GetItemIcon(at)) end
        slot.icon:SetShown(at ~= nil)
        local count = at and C_Item.GetStackCount(at) or 0
        slot.count:SetText(count > 1 and count or "")
    end
    Layout()
    SendMailFrame_Update()
end

local function Listen()
    if #queue > 0 then events:RegisterEvent("BAG_UPDATE_DELAYED") else events:UnregisterEvent("BAG_UPDATE_DELAYED") end
end

-- Attaching --------------------------------------------------------------------

-- Soulbound, conjured and quest items cannot be mailed: "### C_Item.IsBound(itemLocation)",
-- "### C_Item.GetItemData(itemLocation)" (isConjured, bindType 4 = quest).
-- The client's own slot is touched only when a letter goes out.
local function Mailable(at)
    local data = C_Item.GetItemData(at)
    return not C_Item.IsBound(at) and not (data and (data.isConjured or data.bindType == 4))
end

local function Detach(guid)
    local i = Find(guid)
    if not i then return end
    table.remove(queue, i)
    Unlock(guid)
    Listen()
    Draw()
end

local function Attach(guid)
    if sending or not guid or Find(guid) then return end
    if #queue == SLOTS then return M.Print("All " .. SLOTS .. " slots are full.") end
    local at = Where(guid)
    if not at then return end
    if not Mailable(at) then return M.Print(C_Item.GetItemLink(at) .. " cannot be mailed.") end
    queue[#queue + 1] = guid
    Lock()
    Listen()
    Draw()
end

-- GAP: GetCursorInfo should give the bag item's GUID. Until then the last bag
-- pick-up is kept, and the cursor's item ID confirms it is still that item.
hooksecurefunc("PickupContainerItem", function(bag, slot)
    if MailFrame:IsVisible() then picked = C_Item.GetItemGUID({ bagID = bag, slotIndex = slot }) end
end)
local function CursorItem()
    local kind, id = GetCursorInfo()
    local at = kind == "item" and picked and Where(picked)
    if at and C_Item.GetItemID(at) == id then return picked end
end

local function AttachCursor()
    local guid = CursorItem()
    ClearCursor()
    Attach(guid)
end

-- A right-click on a bag item at the mailbox attaches it, or takes it off.
-- The client's own right-click (OctoWoW ContainerFrame.lua:616) would swap it
-- into its one mail slot; the stock bags and Bagnon both click through here.
local BagClick = ContainerFrameItemButton_OnClick
function ContainerFrameItemButton_OnClick(button, ignoreModifiers)
    if button ~= "RightButton" or not MailFrame:IsVisible() or IsModifierKeyDown() then -- "### IsModifierKeyDown()"
        return BagClick(button, ignoreModifiers)
    end
    local guid = C_Item.GetItemGUID({ bagID = this:GetParent():GetID(), slotIndex = this:GetID() })
    if Find(guid) then return Detach(guid) end
    if not SendMailFrame:IsVisible() then MailFrameTab_OnClick(2) end
    Attach(guid)
end

-- An item dropped on the letter is attached too, not put in the client's slot.
SendMailScrollChildFrame:SetScript("OnMouseUp", function()
    SendMailBodyEditBox:SetFocus()
    if CursorHasItem() then AttachCursor() end
end)

local function SlotClick()
    local guid = queue[this:GetID()]
    if CursorHasItem() then
        AttachCursor()
    elseif guid then
        Detach(guid)
        local at = Where(guid)
        if arg1 ~= "RightButton" and at then PickupContainerItem(at.bagID, at.slotIndex) end
    end
end

for i = 1, SLOTS do
    local slot = CreateFrame("Button", nil, SendMailFrame)
    slot:SetID(i)
    slot:SetWidth(37)
    slot:SetHeight(37)
    slot:SetPoint("BOTTOMLEFT", SendMailFrame, "BOTTOMLEFT", 24 + (i - 1) % PER_ROW * 42,
        150 + math.floor((i - 1) / PER_ROW) * 41)
    local back = slot:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\Buttons\\UI-Slot-Background")
    back:SetWidth(39)
    back:SetHeight(39)
    back:SetPoint("TOPLEFT", -1, 1)
    back:SetTexCoord(0, 0.640625, 0, 0.640625)
    slot.icon = slot:CreateTexture(nil, "BORDER")
    slot.icon:SetAllPoints(slot)
    slot.icon:Hide()
    slot.count = slot:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
    slot.count:SetPoint("BOTTOMRIGHT", -5, 2)
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:RegisterForDrag("LeftButton")
    slot:SetScript("OnClick", SlotClick)
    slot:SetScript("OnDragStart", SlotClick)
    slot:SetScript("OnReceiveDrag", SlotClick)
    slot:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        local at = queue[i] and Where(queue[i])
        if at then GameTooltip:SetBagItem(at.bagID, at.slotIndex) else GameTooltip:SetText(ATTACHMENT_TEXT, 1, 1, 1) end
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slots[i] = slot
end
Layout()

-- The client's one slot stays, empty and out of reach: its button holds the
-- money boxes (FrameXML MailFrame.xml, SendMailPackageButton).
SendMailPackageButton:Disable()
SendMailPackageButton:SetScript("OnReceiveDrag", nil)
SendMailPackageButton:SetScript("OnDragStart", nil)
local slotBack = SendMailPackageButton:GetRegions()
slotBack:Hide()
SendMailPackageButtonCount:Hide()

-- The page while items wait: the postage of every letter, C.O.D. allowed.
local Update = SendMailFrame_Update
function SendMailFrame_Update()
    if #queue == 0 and not sending then return Update() end
    MoneyFrame_Update("SendMailCostMoneyFrame", GetSendMailPrice() * math.max(1, #queue))
    SendMailCODButton:Enable()
    SendMailCODButtonText:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    if SendMailCODButton:GetChecked() and #queue > 1 then SendMailMoneyText:SetText("C.O.D. each mail:") end
    SendMailFrame_CanSend()
end
hooksecurefunc("SendMailRadioButton_OnClick", function() if #queue > 0 then SendMailFrame_Update() end end)

-- Send needs a name, a subject or an item, and the money for all of it.
hooksecurefunc("SendMailFrame_CanSend", function()
    local money = MoneyInputFrame_GetCopper(SendMailMoney)
    local cod = SendMailCODButton:GetChecked()
    local cost = GetSendMailPrice() * math.max(1, #queue) + (cod and 0 or money)
    local ok = not sending and SendMailNameEditBox:GetText() ~= ""
        and (SendMailSubjectEditBox:GetText() ~= "" or #queue > 0)
        and not (cod and money > MAX_COD_AMOUNT * COPPER_PER_GOLD) and cost <= GetMoney()
    if ok then SendMailMailButton:Enable() else SendMailMailButton:Disable() end
end)

-- Sending ----------------------------------------------------------------------

local function Stop(why)
    if not sending then return end
    if GetSendMailItem() then -- the item of the letter that failed goes back to its bag
        ClearCursor()
        ClickSendMailItemButton()
        ClearCursor()
    end
    sending = nil
    if why then M.Print(why) end
    Lock()
    Draw()
end

-- One letter: the first waiting item, the subject, the money on the first.
local function Next()
    local guid = queue[1]
    local at = guid and Where(guid)
    if guid and not at then -- sold or destroyed while waiting
        table.remove(queue, 1)
        return Next()
    end
    local s = sending
    if not guid and (s.sent > 0 or s.total > 0) then -- the last letter went, or every item is gone
        sending = nil
        Listen()
        return Draw()
    end
    if at then
        C_Item.UnlockItem(at)
        ClearCursor()
        PickupContainerItem(at.bagID, at.slotIndex)
        ClickSendMailItemButton()
        if not GetSendMailItem() then return Stop("This item could not be attached.") end
    end
    local subject = s.subject
    if subject == "" then
        local name, _, count = GetSendMailItem()
        subject = count > 1 and name .. " (" .. count .. ")" or name
    elseif s.total > 1 then
        subject = subject .. " [" .. s.sent + 1 .. "/" .. s.total .. "]"
    end
    if s.money > 0 and s.cod then
        SetSendMailCOD(s.money)
    elseif s.money > 0 and s.sent == 0 then
        SetSendMailMoney(s.money)
    end
    s.waiting = guid or true
    SendMail(s.to, subject, s.body)
end

local function Start()
    sending = { to = SendMailNameEditBox:GetText(), subject = SendMailSubjectEditBox:GetText(),
        body = SendMailBodyEditBox:GetText(), money = MoneyInputFrame_GetCopper(SendMailMoney),
        cod = SendMailCODButton:GetChecked(), total = #queue, sent = 0 }
    SendMailMailButton:Disable()
    Next()
end

StaticPopupDialogs.MAIL_SEND_MONEY = {
    text = SEND_MONEY_CONFIRMATION, button1 = ACCEPT, button2 = CANCEL,
    hasMoneyFrame = 1, timeout = 0, hideOnEscape = 1,
    OnShow = function() MoneyFrame_Update(this:GetName() .. "MoneyFrame", MoneyInputFrame_GetCopper(SendMailMoney)) end,
    OnAccept = Start,
}
SendMailMailButton:SetScript("OnClick", function()
    if not SendMailCODButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney) > 0 then
        StaticPopup_Show("MAIL_SEND_MONEY", SendMailNameEditBox:GetText())
    else
        Start()
    end
end)

-- After each letter the client empties the page (SendMailFrame_Reset, before
-- our MAIL_SEND_SUCCESS); the name box keeps the name being mailed, else the last.
local function Prefill()
    local name = sending and sending.to or M.Last()
    if SendMailNameEditBox:GetText() == "" and name then
        SendMailNameEditBox:SetText(name)
        SendMailNameEditBox:HighlightText()
    end
end
hooksecurefunc("SendMailFrame_Reset", Prefill)

-- Events -------------------------------------------------------------------------

local MAIL_ERRORS = { [ERR_MAIL_TO_SELF] = true, [ERR_PLAYER_WRONG_FACTION] = true,
    [ERR_MAIL_TARGET_NOT_FOUND] = true, [ERR_MAIL_REACHED_CAP] = true }

local handlers = {}
function handlers.MAIL_SHOW()
    for event in pairs(handlers) do
        if event ~= "BAG_UPDATE_DELAYED" then events:RegisterEvent(event) end
    end
    Prefill()
end
function handlers.MAIL_CLOSED()
    Stop()
    for _, guid in ipairs(queue) do Unlock(guid) end
    table.wipe(queue)
    Draw()
    events:UnregisterAllEvents()
    events:RegisterEvent("MAIL_SHOW")
end
function handlers.MAIL_SEND_SUCCESS()
    local s = sending
    if not (s and s.waiting) then return end
    if s.waiting ~= true then Detach(s.waiting) end
    s.waiting, s.sent = nil, s.sent + 1
    M.Mailed(s.to)
    Next()
end
-- The next letter starts in the same event as the last one's success, so a
-- failure always belongs to the letter on its way.
function handlers.MAIL_FAILED() Stop() end
function handlers.UI_ERROR_MESSAGE() if sending and MAIL_ERRORS[arg1] then Stop() end end
-- A server update for a waiting item clears its lock; an item gone drops off.
function handlers.BAG_UPDATE_DELAYED()
    for i = #queue, 1, -1 do
        if not Where(queue[i]) then table.remove(queue, i) end
    end
    Lock()
    Listen()
    Draw()
end
events:SetScript("OnEvent", function() handlers[event]() end)
events:RegisterEvent("MAIL_SHOW")
