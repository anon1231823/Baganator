local _, addonTable = ...

local PopupMode = {
  Tab = "tab",
  Money = "money",
}
BaganatorSingleViewGuildViewMixin = {}

function BaganatorSingleViewGuildViewMixin:OnLoad()
  ButtonFrameTemplate_HidePortrait(self)
  ButtonFrameTemplate_HideButtonBar(self)
  self.Inset:Hide()
  self:RegisterForDrag("LeftButton")
  self:SetMovable(true)

  self.tabsPool = Baganator.ItemViewCommon.GetSideTabButtonPool(self)
  self.currentTab = 1
  self.otherTabsCache = {}
  self.searchMonitors = {}

  for i = 1, MAX_GUILDBANK_TABS do
    table.insert(self.searchMonitors, CreateFrame("Frame", nil, self, "SyndicatorOfflineListSearchTemplate"))
  end

  Syndicator.CallbackRegistry:RegisterCallback("GuildCacheUpdate",  function(_, guild, changes)
    if changes then
      for tabIndex, isChanged in pairs(changes) do
        if isChanged then
          if not self.otherTabsCache[guild] then
            self.otherTabsCache[guild] = {}
          end
          self.otherTabsCache[guild][tabIndex] = nil
          if tabIndex == self.currentTab then
            for _, layout in ipairs(self.Layouts) do
              layout:RequestContentRefresh()
            end
          end
        end
      end
    end
    if self:IsVisible() and self.isLive then
      self:UpdateForGuild(guild, self.isLive)
    end
  end)

  Syndicator.CallbackRegistry:RegisterCallback("GuildNameSet",  function(_, guild)
    if guild then
      self.lastGuild = guild
    end
  end)

  Baganator.CallbackRegistry:RegisterCallback("ContentRefreshRequired",  function()
    for _, layout in ipairs(self.Layouts) do
      layout:RequestContentRefresh()
    end
    if self:IsVisible() then
      self:UpdateForGuild(self.lastGuild, self.isLive)
    end
  end)

  Baganator.CallbackRegistry:RegisterCallback("SettingChanged",  function(_, settingName)
    if not self.lastGuild then
      return
    end
    if tIndexOf(Baganator.Config.VisualsFrameOnlySettings, settingName) ~= nil then
      if self:IsVisible() then
        Baganator.Utilities.ApplyVisuals(self)
      end
    elseif tIndexOf(Baganator.Config.ItemButtonsRelayoutSettings, settingName) ~= nil then
      for _, layout in ipairs(self.Layouts) do
        layout:InformSettingChanged(settingName)
      end
      if self:IsVisible() then
        self:UpdateForGuild(self.lastGuild, self.isLive)
      end
    elseif settingName == Baganator.Config.Options.SHOW_TRANSFER_BUTTON then
      self.TransferButton:SetShown(self.wouldShowTransferButton and Baganator.Config.Get(Baganator.Config.Options.SHOW_TRANSFER_BUTTON))
    elseif settingName == Baganator.Config.Options.GUILD_BANK_SORT_METHOD then
      self:UpdateForGuild(self.lastGuild, self.isLive)
    end
  end)

  Baganator.CallbackRegistry:RegisterCallback("SearchTextChanged",  function(_, text)
    self:ApplySearch(text)
  end)

  FrameUtil.RegisterFrameForEvents(self, {
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "GUILDBANKLOG_UPDATE",
    "GUILDBANK_UPDATE_TEXT",
    "GUILDBANK_UPDATE_WITHDRAWMONEY",
    "GUILDBANK_TEXT_CHANGED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
  })

  Baganator.Utilities.AddBagTransferManager(self) -- self.transferManager

  self.confirmTransferAllDialogName = "Baganator.ConfirmTransferAll_" .. self:GetName()
  StaticPopupDialogs[self.confirmTransferAllDialogName] = {
    text = BAGANATOR_L_CONFIRM_TRANSFER_ALL_ITEMS_FROM_GUILD_BANK,
    button1 = YES,
    button2 = NO,
    OnAccept = function()
      self:RemoveSearchMatches(function() end)
    end,
    timeout = 0,
    hideOnEscape = 1,
  }

  self.warningNotInGuildDialog = "Baganator.NotInGuild" .. self:GetName()
  StaticPopupDialogs[self.warningNotInGuildDialog] = {
    text = ERR_GUILD_PLAYER_NOT_IN_GUILD,
    button1 = OKAY,
    timeout = 0,
    hideOnEscape = 1,
  }

  self.AllButtons = {}
  tAppendAll(self.AllButtons, self.FixedButtons)
  tAppendAll(self.AllButtons, self.LiveButtons)
end

function BaganatorSingleViewGuildViewMixin:OnEvent(eventName, ...)
  if eventName == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
    local interactType = ...
    if interactType == Enum.PlayerInteractionType.GuildBanker then
      if GuildBankFrame:GetScript("OnHide") ~= nil then
        GuildBankFrame:SetScript("OnHide", nil)
        local hiddenFrame = CreateFrame("Frame")
        hiddenFrame:Hide()
        GuildBankFrame:SetParent(hiddenFrame)
      end
      self.lastGuild = Syndicator.API.GetCurrentGuild()
      -- Special case, classic, where Blizzard still opens the Guild Bank UI
      -- even if there's no guild
      if self.lastGuild == nil then
        StaticPopup_Show(self.warningNotInGuildDialog)
        CloseGuildBankFrame()
      else
        self.isLive = true
        self:Show()
      end
    end
  elseif eventName == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local interactType = ...
    if interactType == Enum.PlayerInteractionType.GuildBanker then
      self.isLive = false
      self:Hide()
    end
  elseif eventName == "GUILDBANKLOG_UPDATE" and self.LogsFrame:IsVisible() then
    if self.LogsFrame.showing == PopupMode.Tab then
      self.LogsFrame:ApplyTab()
    else
      self.LogsFrame:ApplyMoney()
    end
  elseif eventName == "GUILDBANK_UPDATE_TEXT" and self.TabTextFrame:IsVisible() then
    self.TabTextFrame:ApplyTab()
  elseif eventName == "GUILDBANK_TEXT_CHANGED" and self.TabTextFrame:IsVisible() then
    QueryGuildBankText(GetCurrentGuildBankTab());
  elseif eventName == "PLAYER_REGEN_DISABLED" then
    self.WithdrawButton:Disable()
    self.DepositButton:Disable()
  elseif eventName == "PLAYER_REGEN_ENABLED" then
    self.WithdrawButton:SetEnabled(self.canWithdraw)
    self.DepositButton:Enable()
  elseif eventName == "GUILDBANK_UPDATE_WITHDRAWMONEY" and self:IsVisible() then
    self:UpdateForGuild(self.lastGuild, self.isLive)
  end
end

function BaganatorSingleViewGuildViewMixin:OnShow()
  self:UpdateForGuild(self.lastGuild, self.isLive)
end

function BaganatorSingleViewGuildViewMixin:OnHide()
  self:HideInfoDialogs()
  CloseGuildBankFrame()
end

function BaganatorSingleViewGuildViewMixin:HideInfoDialogs()
  self.LogsFrame:Hide()
  self.TabTextFrame:Hide()
end

function BaganatorSingleViewGuildViewMixin:ApplySearch(text)
  if not self:IsShown() then
    return
  end

  for _, monitor in ipairs(self.searchMonitors) do
    monitor:Stop()
  end

  if self.isLive then
    self.GuildLive:ApplySearch(text)
  else
    self.GuildCached:ApplySearch(text)
  end

  if text == "" then
    for _, tabButton in ipairs(self.Tabs) do
      tabButton.Icon:SetAlpha(1)
    end
    return
  end

  -- Highlight tabs with items that match

  local guildData = Syndicator.API.GetGuild(self.lastGuild)

  for index, tab in ipairs(guildData.bank) do
    if not self.otherTabsCache[self.lastGuild] then
      self.otherTabsCache[self.lastGuild] = {}
    end

    if self.otherTabsCache[self.lastGuild][index] == nil then
      self.otherTabsCache[self.lastGuild][index] = Syndicator.Search.GetBaseInfoFromList(tab.slots)
    end

    self.searchMonitors[index]:StartSearch(self.otherTabsCache[self.lastGuild][index], text, function(matches)
      if #matches > 0 then
        self.Tabs[index].Icon:SetAlpha(1)
      else
        self.Tabs[index].Icon:SetAlpha(0.2)
      end
    end)
  end
end

function BaganatorSingleViewGuildViewMixin:OnDragStart()
  if not Baganator.Config.Get(Baganator.Config.Options.LOCK_FRAMES) then
    self:StartMoving()
    self:SetUserPlaced(false)
  end
end

function BaganatorSingleViewGuildViewMixin:OnDragStop()
  self:StopMovingOrSizing()
  self:SetUserPlaced(false)
  local point, _, relativePoint, x, y = self:GetPoint(1)
  Baganator.Config.Set(Baganator.Config.Options.GUILD_VIEW_POSITION, {point, UIParent:GetName(), x, y})
end

function BaganatorSingleViewGuildViewMixin:OpenTabEditor()
  GuildBankPopupFrame:Hide()
  if not CanEditGuildBankTabInfo(GetCurrentGuildBankTab()) then
    UIErrorsFrame:AddMessage(BAGANATOR_L_CANNOT_EDIT_GUILD_BANK_TAB_ERROR, 1.0, 0.1, 0.1, 1.0)
    return
  end
  if Baganator.Constants.IsRetail then
    GuildBankPopupFrame.mode = IconSelectorPopupFrameModes.Edit
  end
  GuildBankPopupFrame:Show()
  if not Baganator.Constants.IsRetail then
    GuildBankPopupFrame:Update()
  end
  GuildBankPopupFrame:SetParent(self)
  GuildBankPopupFrame:ClearAllPoints()
  GuildBankPopupFrame:SetClampedToScreen(true)
  GuildBankPopupFrame:SetFrameLevel(999)
  GuildBankPopupFrame:SetPoint("LEFT", self, "RIGHT", self.Tabs[1]:GetWidth(), 0)
end

function BaganatorSingleViewGuildViewMixin:UpdateTabs(guildData)
  local tabScaleFactor = 37
  if Baganator.Config.Get(Baganator.Config.Options.REDUCE_SPACING) then
    tabScaleFactor = 40
  end
  local tabScale = math.min(1, Baganator.Config.Get(Baganator.Config.Options.BAG_ICON_SIZE) / tabScaleFactor)
  -- Prevent regenerating the tabs if the base info hasn't changed since last
  -- time. This avoids failed clicks on the tabs if done quickly.
  if
    -- Need to add/remove the purchase tab button
    ((not self.isLive and not self.purchaseTabAdded) or (self.isLive and (self.purchaseTabAdded or not IsGuildLeader() or GetNumGuildBankTabs() >= MAX_BUY_GUILDBANK_TABS))) and
    -- Changed tab visual data (name, icon or visibility)
    self.lastTabData and tCompare(guildData.bank, self.lastTabData, 2) then
    for _, tab in ipairs(self.Tabs) do
      tab:SetScale(tabScale)
    end
    return
  end

  self.tabsPool:ReleaseAll()

  local lastTab
  local tabs = {}
  self.lastTabData = {}
  for index, tabInfo in ipairs(guildData.bank) do
    local tabButton = self.tabsPool:Acquire()
    tabButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tabButton.Icon:SetTexture(tabInfo.iconTexture)
    tabButton:SetScript("OnClick", function(_, button)
      self:SetCurrentTab(index)
      self:UpdateForGuild(self.lastGuild, self.isLive)
      if self.isLive and button == "RightButton" then
        self:OpenTabEditor()
      end
    end)
    if not lastTab then
      tabButton:SetPoint("TOPLEFT", self, "TOPRIGHT", 0, -20)
    else
      tabButton:SetPoint("TOPLEFT", lastTab, "BOTTOMLEFT", 0, -12)
    end
    tabButton.SelectedTexture:Hide()
    tabButton:SetScale(tabScale)
    tabButton:Show()
    tabButton.tabName = tabInfo.name
    tabButton:SetEnabled(tabInfo.isViewable)
    tabButton.Icon:SetDesaturated(not tabInfo.isViewable)
    lastTab = tabButton
    table.insert(tabs, tabButton)
    table.insert(self.lastTabData, CopyTable(tabInfo, 1))
  end

  if self.isLive and GetNumGuildBankTabs() < MAX_BUY_GUILDBANK_TABS and IsGuildLeader() then
    local tabButton = self.tabsPool:Acquire()
    tabButton.Icon:SetTexture("Interface\\GuildBankFrame\\UI-GuildBankFrame-NewTab")
    tabButton:SetScript("OnClick", function()
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION);
      StaticPopup_Show("CONFIRM_BUY_GUILDBANK_TAB")
    end)
    if not lastTab then
      tabButton:SetPoint("TOPLEFT", self, "TOPRIGHT", 0, -20)
    else
      tabButton:SetPoint("TOPLEFT", lastTab, "BOTTOMLEFT", 0, -12)
    end
    tabButton.SelectedTexture:SetShown(false)
    tabButton:SetScale(tabScale)
    tabButton:Show()
    tabButton.tabName = BUY_GUILDBANK_TAB
    tabButton:SetEnabled(true)
    tabButton.Icon:SetDesaturated(false)
    table.insert(tabs, tabButton)
    self.purchaseTabAdded = true
  else
    self.purchaseTabAdded = false
  end

  self.Tabs = tabs
end

function BaganatorSingleViewGuildViewMixin:HighlightCurrentTab()
  if not self.Tabs then
    return
  end
  for tabIndex, tab in ipairs(self.Tabs) do
    tab.SelectedTexture:SetShown(tabIndex == self.currentTab)
  end
end

function BaganatorSingleViewGuildViewMixin:SetCurrentTab(index)
  Baganator.CallbackRegistry:TriggerEvent("TransferCancel")
  self.currentTab = index
  self:HighlightCurrentTab()

  if self.isLive then
    SetCurrentGuildBankTab(self.currentTab)
    QueryGuildBankTab(self.currentTab)
    if GuildBankPopupFrame:IsShown() then
      self:OpenTabEditor()
    end
    if self.LogsFrame:IsShown() and self.LogsFrame.showing == PopupMode.Tab then
      local tabInfo = Syndicator.API.GetGuild(self.lastGuild).bank[index]
      if not tabInfo then
        self.LogsFrame:Hide()
      else
        self:ShowTabLogs()
      end
    end
    if self.TabTextFrame:IsShown() then
      local tabInfo = Syndicator.API.GetGuild(self.lastGuild).bank[index]
      if not tabInfo then
        self.TabTextFrame:Hide()
      else
        self:ShowTabText()
      end
    end
  else
    self.LogsFrame:Hide()
  end
end

function BaganatorSingleViewGuildViewMixin:UpdateForGuild(guild, isLive)
  guild = guild or ""
  Baganator.Utilities.ApplyVisuals(self)

  local guildWidth = Baganator.Config.Get(Baganator.Config.Options.GUILD_VIEW_WIDTH)

  self.isLive = isLive

  self.GuildCached:SetShown(not self.isLive)
  self.GuildLive:SetShown(self.isLive)

  local guildData = Syndicator.API.GetGuild(guild)
  if not guildData then
    self:SetTitle("")
    return
  else
    self.lastGuild = guild
    self:SetTitle(BAGANATOR_L_XS_GUILD_BANK:format(guildData.details.guild))
  end

  if self.isLive then
    if self.currentTab ~= GetCurrentGuildBankTab() then
      self.currentTab = GetCurrentGuildBankTab()
      if GuildBankPopupFrame:IsShown() then
        self:OpenTabEditor()
      end
    end
  end
  for _, button in ipairs(self.LiveButtons) do
    button:SetShown(self.isLive)
  end

  self:UpdateTabs(guildData)
  self:HighlightCurrentTab()

  local active

  if not self.isLive then
    self.GuildCached:ShowGuild(guild, self.currentTab, guildWidth)
    self.GuildCached:SetShown(#guildData.bank > 0)
    active = self.GuildCached
  else
    self.GuildLive:ShowGuild(guild, self.currentTab, guildWidth)
    self.GuildLive:SetShown(#guildData.bank > 0)
    active = self.GuildLive
  end

  local searchText = self.SearchWidget.SearchBox:GetText()

  self:ApplySearch(searchText)

  if guildData.bank[1] then
    self.Tabs[1]:SetPoint("LEFT", active, "LEFT")
  end

  local sideSpacing = 13
  if Baganator.Config.Get(Baganator.Config.Options.REDUCE_SPACING) then
    sideSpacing = 8
  end

  self.SearchWidget:SetSpacing(sideSpacing)

  local detailsHeight = 0
  if self.isLive then
    local _, _, _, canDeposit, _, remainingWithdrawals = GetGuildBankTabInfo(self.currentTab)
    local depositText = canDeposit and GREEN_FONT_COLOR:WrapTextInColorCode(YES) or RED_FONT_COLOR:WrapTextInColorCode(NO)
    local withdrawText
    if remainingWithdrawals == -1 then
      withdrawText = GREEN_FONT_COLOR:WrapTextInColorCode(BAGANATOR_L_UNLIMITED)
    elseif remainingWithdrawals == 0 then
      withdrawText = RED_FONT_COLOR:WrapTextInColorCode(NO)
    else
      withdrawText = FormatLargeNumber(remainingWithdrawals)
    end
    self.WithdrawalsInfo:SetText(BAGANATOR_L_GUILD_WITHDRAW_DEPOSIT_X_X:format(withdrawText, depositText))
    local guildMoney = GetGuildBankMoney()
    local withdrawMoney = math.min(GetGuildBankWithdrawMoney(), guildMoney)
    if not CanWithdrawGuildBankMoney() or withdrawMoney == 0 then
      self.canWithdraw = false
      withdrawMoney = 0
      self.WithdrawButton:Disable()
    else
      self.canWithdraw = true
      self.WithdrawButton:Enable()
    end
    self.Money:SetText(BAGANATOR_L_GUILD_MONEY_X_X:format(GetMoneyString(withdrawMoney, true), GetMoneyString(guildMoney, true)))
    self.NoTabsText:SetPoint("TOP", self, "CENTER", 0, 15)
    detailsHeight = 30

    self.SortButton:SetShown(canDeposit
      and #guildData.bank > 0
      -- Use 7*14 to cover that every item in a tab can be sorted
      and (remainingWithdrawals == -1 or remainingWithdrawals > #guildData.bank * 7*14)
      and addonTable.ExternalGuildBankSorts[Baganator.Config.Get(Baganator.Config.Options.GUILD_BANK_SORT_METHOD)]
      and Baganator.Config.Get(Baganator.Config.Options.SHOW_SORT_BUTTON)
    )

    if self.SortButton:IsShown() then
      self.TransferButton:SetPoint("RIGHT", self.SortButton, "LEFT")
    else
      self.TransferButton:SetPoint("RIGHT", self.CustomiseButton, "LEFT")
    end

    self.wouldShowTransferButton = remainingWithdrawals == -1 or remainingWithdrawals > 0
    self.TransferButton:SetShown(self.wouldShowTransferButton and Baganator.Config.Get(Baganator.Config.Options.SHOW_TRANSFER_BUTTON))
    self.LogsFrame:ApplyTabTitle()
  else -- not live
    self.wouldShowTransferButton = false
    self.WithdrawalsInfo:SetText("")
    self.Money:SetText(BAGANATOR_L_GUILD_MONEY_X:format(GetMoneyString(Syndicator.API.GetGuild(guild).money, true)))
    self.NoTabsText:SetPoint("TOP", self, "CENTER", 0, 5)
    detailsHeight = 10

    self.TransferButton:Hide()
    self.SortButton:Hide()
    self.LogsFrame:Hide()
  end

  active:ClearAllPoints()
  active:SetPoint("TOPLEFT", sideSpacing + Baganator.Constants.ButtonFrameOffset, -50)

  self.SearchWidget:SetShown(active:IsShown())
  self.NotVisitedText:SetShown(not active:IsShown() and not guildData.details.visited)
  self.NoTabsText:SetShown(not active:IsShown() and guildData.details.visited)
  self.Money:SetShown(active:IsShown() or guildData.details.visited)

  self.WithdrawalsInfo:SetPoint("BOTTOMLEFT", sideSpacing + Baganator.Constants.ButtonFrameOffset, 30)
  self.Money:SetPoint("BOTTOMLEFT", sideSpacing + Baganator.Constants.ButtonFrameOffset, 10)
  self.DepositButton:SetPoint("BOTTOMRIGHT", self, -sideSpacing + 1, 6)

  local height = 6
  -- active will be hidden if no guild bank tabs have been purchased
  if active:IsShown() then
    height = height + active:GetHeight()
  end
  self:SetSize(
    active:GetWidth() + sideSpacing * 2 + Baganator.Constants.ButtonFrameOffset,
    height + 60 + detailsHeight
  )

  self.ButtonVisibility:Update()

  Baganator.CallbackRegistry:TriggerEvent("ViewComplete")
end

function BaganatorSingleViewGuildViewMixin:RemoveSearchMatches(callback)
  local matches = self.GuildLive.SearchMonitor:GetMatches()

  local emptyBagSlots = Baganator.Transfers.GetEmptyBagsSlots(Syndicator.API.GetCharacter(Syndicator.API.GetCurrentCharacter()).bags, Syndicator.Constants.AllBagIndexes)

  local status, modes = Baganator.Transfers.FromGuildToBags(matches, Syndicator.Constants.AllBagIndexes, emptyBagSlots)

  self.transferManager:Apply(status, modes or {"GuildCacheUpdate"}, function()
    self:RemoveSearchMatches(callback)
  end, function()
    callback()
  end)
end

function BaganatorSingleViewGuildViewMixin:Transfer(button)
  if self.SearchWidget.SearchBox:GetText() == "" then
    StaticPopup_Show(self.confirmTransferAllDialogName)
  else
    self:RemoveSearchMatches(function() end)
  end
end

function BaganatorSingleViewGuildViewMixin:CombineStacksAndSort()
  local sortsDetails = addonTable.ExternalGuildBankSorts[Baganator.Config.Get(Baganator.Config.Options.GUILD_BANK_SORT_METHOD)]
  sortsDetails.callback()
end

function BaganatorSingleViewGuildViewMixin:ToggleTabText()
  if self.TabTextFrame:IsShown() then
    self.TabTextFrame:Hide()
    return
  end
  self:HideInfoDialogs()
  self.TabTextFrame:Show()
  self:ShowTabText()
end

function BaganatorSingleViewGuildViewMixin:ShowTabText()
  self.TabTextFrame:Show()
  self.TabTextFrame:ApplyTab()
  self.TabTextFrame:ApplyTabTitle()
  QueryGuildBankText(GetCurrentGuildBankTab());
end

function BaganatorSingleViewGuildViewMixin:ToggleTabLogs()
  if self.LogsFrame.showing == PopupMode.Tab and self.LogsFrame:IsShown() then
    self.LogsFrame:Hide()
    return
  end
  self:ShowTabLogs()
end

function BaganatorSingleViewGuildViewMixin:ShowTabLogs()
  self:HideInfoDialogs()
  self.LogsFrame:Show()
  self.LogsFrame:ApplyTab()
  self.LogsFrame:ApplyTabTitle()
  QueryGuildBankLog(GetCurrentGuildBankTab());
end

function BaganatorSingleViewGuildViewMixin:ToggleMoneyLogs()
  if self.LogsFrame.showing == PopupMode.Money and self.LogsFrame:IsShown() then
    self.LogsFrame:Hide()
    return
  end
  self:HideInfoDialogs()
  self.LogsFrame:Show()
  self.LogsFrame:SetTitle(BAGANATOR_L_MONEY_LOGS)
  self.LogsFrame:ApplyMoney()
  QueryGuildBankLog(MAX_GUILDBANK_TABS + 1);
end

BaganatorGuildLogsTemplateMixin = {}
function BaganatorGuildLogsTemplateMixin:OnLoad()
  ButtonFrameTemplate_HidePortrait(self)
  ButtonFrameTemplate_HideButtonBar(self)
  self.Inset:Hide()
  self:RegisterForDrag("LeftButton")
  self:SetMovable(true)
  self:SetClampedToScreen(true)
  ScrollUtil.RegisterScrollBoxWithScrollBar(self.TextContainer:GetScrollBox(), self.ScrollBar)

  Baganator.CallbackRegistry:RegisterCallback("SettingChanged",  function(_, settingName)
    if tIndexOf(Baganator.Config.VisualsFrameOnlySettings, settingName) ~= nil then
      if self:IsVisible() then
        Baganator.Utilities.ApplyVisuals(self)
      end
    end
  end)
end

function BaganatorGuildLogsTemplateMixin:OnShow()
  Baganator.Utilities.ApplyVisuals(self)
  self:ClearAllPoints()
  self:SetPoint(unpack(Baganator.Config.Get(Baganator.Config.Options.GUILD_VIEW_DIALOG_POSITION)))
  Baganator.Utilities.AutoSetGuildSortMethod()
end

function BaganatorGuildLogsTemplateMixin:OnDragStart()
  if not Baganator.Config.Get(Baganator.Config.Options.LOCK_FRAMES) then
    self:StartMoving()
    self:SetUserPlaced(false)
  end
end

function BaganatorGuildLogsTemplateMixin:OnDragStop()
  self:StopMovingOrSizing()
  self:SetUserPlaced(false)
  local point, _, relativePoint, x, y = self:GetPoint(1)
  Baganator.Config.Set(Baganator.Config.Options.GUILD_VIEW_DIALOG_POSITION, {point, UIParent:GetName(), relativePoint, x, y})
end

function BaganatorGuildLogsTemplateMixin:ApplyTabTitle()
  if self.showing ~= PopupMode.Tab then return
  end

  local tabInfo = Syndicator.API.GetGuild(Syndicator.API.GetCurrentGuild()).bank[GetCurrentGuildBankTab()]
  if tabInfo ~= nil then
    self:SetTitle(BAGANATOR_L_X_LOGS:format(tabInfo.name))
  else
    self:SetTitle("")
  end
end

function BaganatorGuildLogsTemplateMixin:ApplyTab()
  self.showing = PopupMode.Tab

  if #Syndicator.API.GetGuild(Syndicator.API.GetCurrentGuild()).bank == 0 then
    self.TextContainer:SetText(BAGANATOR_L_GUILD_NO_TABS_PURCHASED)
    return
  end

  -- Code for logs copied from Blizzard lua dumps and modified
	local tab = GetCurrentGuildBankTab();
	local numTransactions = GetNumGuildBankTransactions(tab);

	local msg = "";
	for i = numTransactions, 1, -1 do
		local type, name, itemLink, count, tab1, tab2, year, month, day, hour = GetGuildBankTransaction(tab, i);
		if ( not name ) then
			name = UNKNOWN;
		end
		name = NORMAL_FONT_COLOR_CODE..name..FONT_COLOR_CODE_CLOSE;
		if ( type == "deposit" ) then
			msg = msg .. format(GUILDBANK_DEPOSIT_FORMAT, name, itemLink);
			if ( count > 1 ) then
				msg = msg..format(GUILDBANK_LOG_QUANTITY, count);
			end
		elseif ( type == "withdraw" ) then
			msg = msg .. format(GUILDBANK_WITHDRAW_FORMAT, name, itemLink);
			if ( count > 1 ) then
				msg = msg..format(GUILDBANK_LOG_QUANTITY, count);
			end
		elseif ( type == "move" ) then
			msg = msg .. format(GUILDBANK_MOVE_FORMAT, name, itemLink, count, GetGuildBankTabInfo(tab1), GetGuildBankTabInfo(tab2));
		end
    msg = msg..GUILD_BANK_LOG_TIME:format(RecentTimeDate(year, month, day, hour))
    msg = msg .. "\n"
	end

  if numTransactions == 0 then
    msg = BAGANATOR_L_NO_TRANSACTIONS_AVAILABLE
  end

  self.TextContainer:SetText(msg)
end

function BaganatorGuildLogsTemplateMixin:ApplyMoney()
  self.showing = PopupMode.Money
  -- Code for logs copied from Blizzard lua dumps and modified
  local numTransactions = GetNumGuildBankMoneyTransactions();
  local msg = ""
  for i=numTransactions, 1, -1 do
    local type, name, amount, year, month, day, hour = GetGuildBankMoneyTransaction(i);
    if ( not name ) then
      name = UNKNOWN;
    end
    name = NORMAL_FONT_COLOR_CODE..name..FONT_COLOR_CODE_CLOSE;
    local money = GetDenominationsFromCopper(amount);
    if ( type == "deposit" ) then
      msg = msg .. format(GUILDBANK_DEPOSIT_MONEY_FORMAT, name, money);
    elseif ( type == "withdraw" ) then
      msg = msg .. format(GUILDBANK_WITHDRAW_MONEY_FORMAT, name, money);
    elseif ( type == "repair" ) then
      msg = msg .. format(GUILDBANK_REPAIR_MONEY_FORMAT, name, money);
    elseif ( type == "withdrawForTab" ) then
      msg = msg .. format(GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT, name, money);
    elseif ( type == "buyTab" ) then
      if ( amount > 0 ) then
        msg = msg .. format(GUILDBANK_BUYTAB_MONEY_FORMAT, name, money);
      else
        msg = msg .. format(GUILDBANK_UNLOCKTAB_FORMAT, name);
      end
    elseif ( type == "depositSummary" ) then
      msg = msg .. format(GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT, money);
    end
    msg = msg..GUILD_BANK_LOG_TIME:format(RecentTimeDate(year, month, day, hour))
    msg = msg .. "\n"
  end

  if numTransactions == 0 then
    msg = BAGANATOR_L_NO_TRANSACTIONS_AVAILABLE
  end

  self.TextContainer:SetText(msg)
end

BaganatorGuildTabTextTemplateMixin = {}
function BaganatorGuildTabTextTemplateMixin:OnLoad()
  ButtonFrameTemplate_HidePortrait(self)
  ButtonFrameTemplate_HideButtonBar(self)
  self.Inset:Hide()
  self:RegisterForDrag("LeftButton")
  self:SetMovable(true)
  self:SetClampedToScreen(true)
  ScrollUtil.RegisterScrollBoxWithScrollBar(self.TextContainer:GetScrollBox(), self.ScrollBar)

  self.TextContainer:GetEditBox():SetMaxLetters(500)

  Baganator.CallbackRegistry:RegisterCallback("SettingChanged",  function(_, settingName)
    if tIndexOf(Baganator.Config.VisualsFrameOnlySettings, settingName) ~= nil then
      if self:IsVisible() then
        Baganator.Utilities.ApplyVisuals(self)
      end
    end
  end)
end

function BaganatorGuildTabTextTemplateMixin:OnShow()
  Baganator.Utilities.ApplyVisuals(self)
  self:ClearAllPoints()
  self:SetPoint(unpack(Baganator.Config.Get(Baganator.Config.Options.GUILD_VIEW_DIALOG_POSITION)))
end

function BaganatorGuildTabTextTemplateMixin:ApplyTab()
  local currentTab = GetCurrentGuildBankTab()

  if #Syndicator.API.GetGuild(Syndicator.API.GetCurrentGuild()).bank == 0 then
    self.TextContainer:SetText(BAGANATOR_L_GUILD_NO_TABS_PURCHASED)
    self.SaveButton:Hide()
    self.TextContainer:GetEditBox():SetEnabled(false)
    return
  end

  self.TextContainer:SetText(GetGuildBankText(currentTab))
  local canEdit = CanEditGuildTabInfo(currentTab)
  self.SaveButton:SetShown(canEdit)
  self.TextContainer:GetEditBox():SetEnabled(canEdit)
end

function BaganatorGuildTabTextTemplateMixin:ApplyTabTitle()
  local tabInfo = Syndicator.API.GetGuild(Syndicator.API.GetCurrentGuild()).bank[GetCurrentGuildBankTab()]
  if tabInfo ~= nil then
    self:SetTitle(BAGANATOR_L_X_INFORMATION:format(tabInfo.name))
  else
    self:SetTitle("")
  end
end

function BaganatorGuildTabTextTemplateMixin:OnDragStart()
  if not Baganator.Config.Get(Baganator.Config.Options.LOCK_FRAMES) then
    self:StartMoving()
    self:SetUserPlaced(false)
  end
end

function BaganatorGuildTabTextTemplateMixin:OnDragStop()
  self:StopMovingOrSizing()
  self:SetUserPlaced(false)
  local point, _, relativePoint, x, y = self:GetPoint(1)
  Baganator.Config.Set(Baganator.Config.Options.GUILD_VIEW_DIALOG_POSITION, {point, UIParent:GetName(), x, y})
end
