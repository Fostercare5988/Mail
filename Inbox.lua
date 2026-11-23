-- Mail: the inbox. Open All, right-click to take one mail, and what the rows
-- and the title show. Functions named here are the client's (FrameXML
-- MailFrame.lua) unless a doc heading of ClassicAPI's docs/API.md is given.
local _, M = ...
if not M.Print then return end -- no ClassicAPI: Names.lua said so

local ROWS = INBOXITEMS_TO_DISPLAY
local WAIT = 3 -- seconds a step waits for its inbox update before asking again
local AUCTION = {} -- the start of each auction mail subject
for _, subject in ipairs({ AUCTION_SOLD_MAIL_SUBJECT, AUCTION_REMOVED_MAIL_SUBJECT, AUCTION_EXPIRED_MAIL_SUBJECT,
    AUCTION_WON_MAIL_SUBJECT, AUCTION_OUTBID_MAIL_SUBJECT }) do
    AUCTION[#AUCTION + 1] = string.gsub(subject, "%%s.*", "")
end

local run -- the take in progress: index, work (the mail being emptied), single, money, fetched, timer
local events = CreateFrame("Frame")
local openAll = CreateFrame("Button", "MailOpenAllButton", InboxFrame, "UIPanelButtonTemplate")

-- Taking ---------------------------------------------------------------------

local function Finish(why)
    if not run then return end
    if run.timer then run.timer:Cancel() end
    if run.money > 0 then M.Print("Collected " .. GetCoinTextureString(run.money) .. ".") end
    if why then M.Print(why) end
    run = nil
    openAll:SetText("Open All")
end

-- One request to the server, then wait for its MAIL_INBOX_UPDATE. A request
-- with no answer is asked again after the inbox is fetched once more.
local function Ask()
    if run and run.work then run.work.asked = nil end
    CheckInbox()
end
-- C_Timer drops a callback's error; this sends it to the error handler (KP-63).
local function AskAgain() xpcall(Ask, geterrorhandler()) end
-- The client may answer inside the request (the inbox already fetched), and
-- that answer can end the take before Wait is reached.
local function Wait()
    if not run then return end
    if run.timer then run.timer:Cancel() end
    run.timer = C_Timer.NewTimer(WAIT, AskAgain)
end

-- Each inbox update moves the take on by one request: the money, then the
-- item, then deleting the emptied mail. Mail with C.O.D., GM mail and letters
-- that carry nothing are passed by.
local function Step()
    if not run then return end
    local i = run.index
    while i <= GetInboxNumItems() do
        local _, _, sender, subject, money, cod, _, item, _, _, _, _, gm = GetInboxHeaderInfo(i)
        local work = run.work
        -- Another mail in its place: the one asked about is gone (deleted).
        if work and (work.sender ~= sender or work.subject ~= subject
            or (work.asked == "delete" and (money > 0 or item))) then work, run.work = nil, nil end
        if not work and cod == 0 and not gm and (money > 0 or item) then
            work = { sender = sender, subject = subject }
            run.work, run.money = work, run.money + money
            GetInboxText(i) -- read first, as opening the mail does
        end
        if work then
            run.index, run.fetched = i, false
            local ask = money > 0 and "money" or item and "item" or "delete"
            if work.asked == ask then return end -- an update that is not the answer
            work.asked = ask
            if ask == "money" then
                TakeInboxMoney(i)
            elseif ask == "item" then
                TakeInboxItem(i)
            else
                DeleteInboxItem(i)
                if run.single then return Finish() end
            end
            return Wait()
        end
        if run.single then return Finish() end
        i = i + 1
    end
    -- The server sends 50 mails at most: ask for the rest until none come.
    if run.single or run.fetched then return Finish() end
    run.index, run.fetched = i, true
    CheckInbox()
    Wait()
end

local function Start(index)
    Finish()
    HideUIPanel(OpenMailFrame)
    run = { index = index or 1, single = index, money = 0 }
    openAll:SetText("Stop")
    Step()
end

openAll:SetPoint("BOTTOM", InboxFrame, "BOTTOM", -10, 90)
openAll:SetWidth(120)
openAll:SetHeight(25)
openAll:SetText("Open All")
openAll:SetScript("OnClick", function() if run then Finish() else Start() end end)

-- A right-click on a row takes that mail; a left-click opens it, as the
-- row's own script did (FrameXML MailFrame.xml, MailItemTemplate).
local function RowClick()
    if arg1 ~= "RightButton" then return InboxFrame_OnClick(this.index) end
    this:SetChecked(nil)
    local _, _, _, _, money, cod, _, item = GetInboxHeaderInfo(this.index)
    if cod == 0 and (money > 0 or item) then Start(this.index) end
end

hooksecurefunc("InboxFrameItem_OnEnter", function()
    if not this.cod and (this.hasItem or this.money) then
        GameTooltip:AddLine("Right-click to take", 0, 1, 0)
        GameTooltip:Show()
    end
end)

-- What the rows and the title show --------------------------------------------

local function Badge(row, texture, x, tip)
    local frame = CreateFrame("Frame", nil, _G["MailItem" .. row .. "ExpireTime"])
    frame:SetWidth(28)
    frame:SetHeight(28)
    frame:SetPoint("TOPRIGHT", frame:GetParent(), "BOTTOMRIGHT", x, 8)
    local image = frame:CreateTexture(nil, "BACKGROUND")
    image:SetAllPoints(frame)
    image:SetTexture("Interface\\AddOns\\Mail\\" .. texture)
    image:SetVertexColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip)
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:Hide()
    return frame
end

local rows = {}
for i = 1, ROWS do
    local button = _G["MailItem" .. i .. "Button"]
    button:SetScript("OnClick", RowClick)
    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", _G["MailItem" .. i .. "ButtonIcon"], "BOTTOMRIGHT", -1, 1)
    rows[i] = { count = count,
        returned = Badge(i, "Returned", 0, "This mail was returned to you."),
        auction = Badge(i, "Auction", -24, "This mail is from an auction house.") }
end

local function IsAuction(sender, subject)
    if sender and string.find(sender, "Auction House$") then return true end
    for _, start in ipairs(AUCTION) do
        if string.find(subject or "", start, 1, true) == 1 then return true end
    end
end

hooksecurefunc("InboxFrame_Update", function()
    local total = GetInboxNumItems()
    local first = (InboxFrame.pageNum - 1) * ROWS
    for i, row in ipairs(rows) do
        local index = first + i
        local _, _, sender, subject, _, _, _, _, _, returned = GetInboxHeaderInfo(index)
        local _, _, count = GetInboxItem(index)
        row.count:SetText(count and count > 1 and count or "")
        row.returned:SetShown(index <= total and returned)
        row.auction:SetShown(index <= total and IsAuction(sender, subject))
    end
    InboxTitleText:SetText(INBOX .. " [" .. (total > 0 and InboxFrame.pageNum .. "/" .. math.ceil(total / ROWS) or EMPTY) .. "]")
end)

-- Events ---------------------------------------------------------------------

local handlers = {}
function handlers.MAIL_SHOW()
    for event in pairs(handlers) do events:RegisterEvent(event) end
end
function handlers.MAIL_CLOSED()
    Finish()
    events:UnregisterAllEvents()
    events:RegisterEvent("MAIL_SHOW")
end
function handlers.MAIL_INBOX_UPDATE() Step() end
-- New mail while the mailbox is open. UNVERIFIED: that the client sends it here.
function handlers.UPDATE_PENDING_MAIL() if not run then CheckInbox() end end
function handlers.UI_ERROR_MESSAGE()
    if not (run and run.work) then return end
    if arg1 == ERR_INV_FULL then
        Finish("Your bags are full.")
    elseif arg1 == ERR_ITEM_MAX_COUNT then -- you carry the most of it: leave this mail
        run.work, run.index = nil, run.index + 1
        Step()
    end
end
events:SetScript("OnEvent", function() handlers[event]() end)
events:RegisterEvent("MAIL_SHOW")

-- The mailbox and the friends list open side by side.
UIPanelWindows.MailFrame.pushable = 1
UIPanelWindows.FriendsFrame.pushable = 2
