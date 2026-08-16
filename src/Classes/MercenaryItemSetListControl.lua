-- Path of Building
--
-- Class: Mercenary Item Set List
-- Mercenary equipment item set list control.
--
local t_insert = table.insert
local t_remove = table.remove
local m_max = math.max

local MercenaryItemSetListClass = newClass("MercenaryItemSetListControl", "ListControl")

function MercenaryItemSetListClass:MercenaryItemSetListControl(anchor, rect, mercenaryTab)
	self:ListControl(anchor, rect, 16, "VERTICAL", true, mercenaryTab:GetMercenaryItemSetOrderList())
	self.mercenaryTab = mercenaryTab
	self.controls.copy = new("ButtonControl"):ButtonControl({"BOTTOMLEFT", self, "TOP"}, {2, -4, 60, 18}, "Copy", function()
		local itemsTab = mercenaryTab.build.itemsTab
		local newSet = copyTable(itemsTab.itemSets[self.selValue], true)
		newSet.id = 1
		while itemsTab.itemSets[newSet.id] do
			newSet.id = newSet.id + 1
		end
		newSet.owner = "Mercenary"
		itemsTab.itemSets[newSet.id] = newSet
		self:RenameSet(newSet, true)
	end)
	self.controls.copy.enabled = function()
		return self.selValue ~= nil
	end
	self.controls.delete = new("ButtonControl"):ButtonControl({"LEFT", self.controls.copy, "RIGHT"}, {4, 0, 60, 18}, "Delete", function()
		self:OnSelDelete(self.selIndex, self.selValue)
	end)
	self.controls.delete.enabled = function()
		return self.selValue ~= nil and #self.list > 1
	end
	self.controls.rename = new("ButtonControl"):ButtonControl({"BOTTOMRIGHT", self, "TOP"}, {-2, -4, 60, 18}, "Rename", function()
		self:RenameSet(mercenaryTab.build.itemsTab.itemSets[self.selValue])
	end)
	self.controls.rename.enabled = function()
		return self.selValue ~= nil
	end
	self.controls.new = new("ButtonControl"):ButtonControl({"RIGHT", self.controls.rename, "LEFT"}, {-4, 0, 60, 18}, "New", function()
		self:RenameSet(mercenaryTab.build.itemsTab:NewItemSet(nil, "Mercenary"), true)
	end)
	return self
end

function MercenaryItemSetListClass:RenameSet(itemSet, addOnName)
	local controls = { }
	controls.label = new("LabelControl"):LabelControl(nil, {0, 20, 0, 16}, "^7Enter name for this Mercenary equipment set:")
	controls.edit = new("EditControl"):EditControl(nil, {0, 40, 350, 20}, itemSet.title, nil, nil, 100, function(buf)
		controls.save.enabled = buf:match("%S")
	end)
	controls.save = new("ButtonControl"):ButtonControl(nil, {-45, 70, 80, 20}, "Save", function()
		local itemsTab = self.mercenaryTab.build.itemsTab
		itemSet.title = controls.edit.buf
		if addOnName then
			t_insert(itemsTab.itemSetOrderList, itemSet.id)
			t_insert(self.list, itemSet.id)
			self.selIndex = #self.list
			self.selValue = itemSet.id
		end
		itemsTab.modFlag = true
		itemsTab:AddUndoState()
		itemsTab.build:SyncLoadouts()
		if addOnName then
			self.mercenaryTab:SetItemSet(itemSet.id)
		else
			self.mercenaryTab:RefreshControls()
		end
		main:ClosePopup()
	end)
	controls.save.enabled = false
	controls.cancel = new("ButtonControl"):ButtonControl(nil, {45, 70, 80, 20}, "Cancel", function()
		if addOnName then
			self.mercenaryTab.build.itemsTab.itemSets[itemSet.id] = nil
		end
		main:ClosePopup()
	end)
	main:OpenPopup(370, 100, itemSet.title and "Rename" or "Set Name", controls, "save", "edit", "cancel")
end

function MercenaryItemSetListClass:GetRowValue(column, _, itemSetId)
	if column == 1 then
		local itemSet = self.mercenaryTab.build.itemsTab.itemSets[itemSetId]
		return (itemSet.title or "Mercenary Equipment")..(itemSetId == self.mercenaryTab.itemSetId and "  ^9(Active)" or "")
	end
end

function MercenaryItemSetListClass:OnOrderChange()
	local itemsTab = self.mercenaryTab.build.itemsTab
	local mercenaryItemSets = { }
	for _, itemSetId in ipairs(self.list) do
		mercenaryItemSets[itemSetId] = true
	end
	local nextIndex = 1
	for index, itemSetId in ipairs(itemsTab.itemSetOrderList) do
		if mercenaryItemSets[itemSetId] then
			itemsTab.itemSetOrderList[index] = self.list[nextIndex]
			nextIndex = nextIndex + 1
		end
	end
	itemsTab.modFlag = true
end

function MercenaryItemSetListClass:OnSelClick(_, itemSetId, doubleClick)
	if doubleClick and itemSetId ~= self.mercenaryTab.itemSetId then
		self.mercenaryTab:SetItemSet(itemSetId)
	end
end

function MercenaryItemSetListClass:OnSelDelete(index, itemSetId)
	if #self.list <= 1 then return end
	local itemSet = self.mercenaryTab.build.itemsTab.itemSets[itemSetId]
	main:OpenConfirmPopup("Delete Mercenary Equipment Set", "Are you sure you want to delete '"..(itemSet.title or "Mercenary Equipment").."'?", "Delete", function()
		local itemsTab = self.mercenaryTab.build.itemsTab
		t_remove(self.list, index)
		for orderIndex, candidateId in ipairs(itemsTab.itemSetOrderList) do
			if candidateId == itemSetId then
				t_remove(itemsTab.itemSetOrderList, orderIndex)
				break
			end
		end
		itemsTab.itemSets[itemSetId] = nil
		self.selIndex = nil
		self.selValue = nil
		if itemSetId == self.mercenaryTab.itemSetId then
			self.mercenaryTab:SetItemSet(self.list[m_max(1, index - 1)])
		else
			self.mercenaryTab:RefreshControls()
		end
		itemsTab.modFlag = true
		itemsTab:AddUndoState()
		itemsTab.build:SyncLoadouts()
	end)
end

function MercenaryItemSetListClass:OnSelKeyDown(_, itemSetId, key)
	if key == "F2" then
		self:RenameSet(self.mercenaryTab.build.itemsTab.itemSets[itemSetId])
	end
end
