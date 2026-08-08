describe("Mercenary equipment validation", function()
	local MercenaryTools = require("Modules/MercenaryTools")
	local tab, itemSet
	local function selectScionLuminary()
		for classId, class in pairs(build.spec.tree.classes) do
			if class.name == "Scion" then build.spec:SelectClass(classId) break end
		end
		for ascendClassId, ascendClass in pairs(build.spec.curClass.classes) do
			if ascendClass.name == "Luminary" then build.spec:SelectAscendClass(ascendClassId) break end
		end
	end

	local function item(fields)
		local value = {
			id = 9001,
			type = "Body Armour",
			rarity = "RARE",
			requirements = { level = 0, str = 0, dex = 0, int = 0 },
			grantedSkills = { },
		}
		for key, fieldValue in pairs(fields or { }) do value[key] = fieldValue end
		return value
	end

	local function selectBuild(buildId, foundAreaLevel)
		tab.profile.buildId = buildId
		tab.profile.foundAreaLevel = foundAreaLevel or 68
	end

	local function allocatePassive(name)
		local node = build.spec.tree.ascendancyMap[name]
		if not node then
			for _, candidate in pairs(build.spec.nodes) do
				if candidate.name == name then node = candidate break end
			end
		end
		node = assert(node, name)
		node = build.spec.nodes[node.id] or node
		node.alloc = true
		build.spec.allocNodes[node.id] = node
		-- A Mercenary's equipment permissions are modifiers, so they only reach the tab
		-- once a calculation has rebuilt the modifier database.
		build.spec.modFlag = true
		build.buildFlag = true
		runCallback("OnFrame")
	end

	before_each(function()
		newBuild()
		selectScionLuminary()
		tab = build.mercenaryTab
		itemSet = build.itemsTab.activeItemSet
	end)

	it("shows every standard player and Mercenary equipment row", function()
		local itemsTab = build.itemsTab
		local equipmentSlots = { "Weapon 1", "Weapon 2", "Helmet", "Body Armour", "Gloves", "Boots", "Amulet", "Ring 1", "Ring 2", "Belt" }
		local flaskSlots = { "Flask 1", "Flask 2", "Flask 3", "Flask 4", "Flask 5" }
		for _, slotName in ipairs(equipmentSlots) do
			assert.is_true(itemsTab.slots[slotName]:IsShown(), slotName)
		end
		for _, slotName in ipairs(flaskSlots) do
			assert.is_true(itemsTab.slots[slotName]:IsShown(), slotName)
		end
		selectBuild("MeleeAOEMarauderFireSlam")
		for _, slotName in ipairs(equipmentSlots) do
			assert.is_true(itemsTab.slots[slotName]:IsShown(), slotName)
			assert.is_true(itemsTab.slots[MercenaryTools.itemSlotName(slotName)]:IsShown(), "Mercenary "..slotName)
		end
		for _, slotName in ipairs(flaskSlots) do
			assert.is_true(itemsTab.slots[slotName]:IsShown(), slotName)
		end
	end)

	it("switches player and Mercenary equipment as one item set", function()
		local itemsTab = build.itemsTab
		local secondSet = itemsTab:NewItemSet()
		table.insert(itemsTab.itemSetOrderList, secondSet.id)
		for id = 9001, 9004 do
			itemsTab.items[id] = item({ id = id, name = "Helmet "..id, type = "Helmet", base = { type = "Helmet" } })
		end
		itemsTab.slots.Helmet:SetSelItemId(9001)
		itemsTab.slots[MercenaryTools.itemSlotName("Helmet")]:SetSelItemId(9002)
		secondSet.Helmet.selItemId = 9003
		secondSet[MercenaryTools.itemSlotName("Helmet")].selItemId = 9004

		itemsTab:SetActiveItemSet(secondSet.id)
		assert.are.equal(9003, itemsTab.slots.Helmet.selItemId)
		assert.are.equal(9004, itemsTab.slots[MercenaryTools.itemSlotName("Helmet")].selItemId)
		itemsTab:SetActiveItemSet(itemSet.id)
		assert.are.equal(9001, itemsTab.slots.Helmet.selItemId)
		assert.are.equal(9002, itemsTab.slots[MercenaryTools.itemSlotName("Helmet")].selItemId)
	end)

	it("persists Mercenary slots in Items instead of a Mercenary item-set reference", function()
		itemSet[MercenaryTools.itemSlotName("Helmet")].selItemId = 9001
		local itemsXml = { }
		build.itemsTab:Save(itemsXml)
		local savedItemId
		for _, node in ipairs(itemsXml) do
			if node.elem == "ItemSet" and tonumber(node.attrib.id) == itemSet.id then
				for _, slot in ipairs(node) do
					if slot.attrib and slot.attrib.name == MercenaryTools.itemSlotName("Helmet") then savedItemId = slot.attrib.itemId end
				end
			end
		end
		assert.are.equal("9001", savedItemId)
		local mercenaryXml = { }
		tab:Save(mercenaryXml)
		assert.is_nil(mercenaryXml.attrib.itemSetId)
	end)

	it("formats validity rows for TextListControl", function()
		tab:RefreshErrors()
		assert.is_true(#tab.errors > 0)
		for _, row in ipairs(tab.errors) do
			assert.are.equal(16, row.height)
		end
	end)

	it("applies single, dual, and triple attribute armour rules", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		assert.is_true(tab:ValidateEquippedItem(item({ requirements = { str = 100, dex = 100 } }), "Body Armour", itemSet))
		assert.is_false(tab:ValidateEquippedItem(item({ requirements = { dex = 100 } }), "Body Armour", itemSet))
		assert.is_false(tab:ValidateEquippedItem(item({ requirements = { str = 1, dex = 1, int = 1 } }), "Body Armour", itemSet))

		selectBuild("AurasMinionsTemplarStaff")
		assert.is_true(tab:ValidateEquippedItem(item({ requirements = { str = 100, int = 100 } }), "Body Armour", itemSet))
		assert.is_false(tab:ValidateEquippedItem(item({ requirements = { str = 100, dex = 1 } }), "Body Armour", itemSet))

		selectBuild("MiscScionPhysDot")
		assert.is_true(tab:ValidateEquippedItem(item({ requirements = { str = 1, dex = 1, int = 1 } }), "Body Armour", itemSet))
	end)

	it("enforces the exact 70 percent found-area level boundary", function()
		selectBuild("MeleeAOEMarauderFireSlam", 47)
		assert.is_false(tab:ValidateEquippedItem(item({ requirements = { level = 68, str = 1 } }), "Body Armour", itemSet))
		tab.profile.foundAreaLevel = 48
		assert.is_true(tab:ValidateEquippedItem(item({ requirements = { level = 68, str = 1 } }), "Body Armour", itemSet))
	end)

	it("requires Legendary slot passives and always rejects unique body armour", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		assert.is_false(tab:ValidateEquippedItem(item({ rarity = "UNIQUE" }), "Body Armour", itemSet))
		local helmet = item({ type = "Helmet", rarity = "UNIQUE", requirements = { str = 1 } })
		assert.is_false(tab:ValidateEquippedItem(helmet, "Helmet", itemSet))
		allocatePassive("Legendary Helmets")
		assert.is_true(tab:ValidateEquippedItem(helmet, "Helmet", itemSet))
	end)

	it("applies every Legendary slot permission", function()
		selectBuild("MeleeStrikesMarauderFire")
		local cases = {
			{ "Helmet", "Helmet", "Legendary Helmets", { str = 1 } },
			{ "Gloves", "Gloves", "Legendary Gloves", { str = 1 } },
			{ "Boots", "Boots", "Legendary Boots", { str = 1 } },
			{ "Amulet", "Amulet", "Legendary Amulets" },
			{ "Ring 1", "Ring", "Legendary Rings" },
			{ "Ring 2", "Ring", "Legendary Rings" },
			{ "Belt", "Belt", "Legendary Belts" },
			{ "Weapon 1", "One Handed Sword", "Legendary Arms" },
			{ "Weapon 2", "One Handed Sword", "Legendary Arms" },
		}
		local allocated = { }
		for index, case in ipairs(cases) do
			local unique = item({ id = 9100 + index, type = case[2], rarity = "UNIQUE", requirements = case[4] or { } })
			if not allocated[case[3]] then
				assert.is_false(tab:ValidateEquippedItem(unique, case[1], itemSet))
				allocatePassive(case[3])
				allocated[case[3]] = true
			end
			assert.is_true(tab:ValidateEquippedItem(unique, case[1], itemSet))
		end
	end)

	it("uses exported main-hand, optional off-hand, shield, and quiver rules", function()
		selectBuild("TrapsMinesShadowLightning")
		assert.is_true(tab:ValidateEquippedItem(item({ type = "Dagger" }), "Weapon 1", itemSet))
		assert.is_false(tab:ValidateEquippedItem(item({ type = "Shield" }), "Weapon 2", itemSet))

		selectBuild("MeleeStrikesMarauderFire")
		assert.is_true(tab:ValidateEquippedItem(item({ type = "Shield" }), "Weapon 2", itemSet))
		assert.is_true(tab:ValidateEquippedItem(item({ type = "One Handed Sword" }), "Weapon 2", itemSet))

		selectBuild("AurasMinionsTemplarSmite")
		assert.is_true(tab:ValidateEquippedItem(item({ type = "Shield" }), "Weapon 2", itemSet))
		assert.is_false(tab:ValidateEquippedItem(item({ type = "Sceptre" }), "Weapon 2", itemSet))

		selectBuild("NonEleBowRangerPhys")
		assert.is_true(tab:ValidateEquippedItem(item({ type = "Bow" }), "Weapon 1", itemSet))
		assert.is_true(tab:ValidateEquippedItem(item({ type = "Quiver" }), "Weapon 2", itemSet))
	end)

	it("rejects shared physical item ids and all item-granted skills", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local shared = item({ type = "Helmet", requirements = { str = 1 } })
		itemSet["Helmet"].selItemId = shared.id
		assert.is_false(tab:ValidateEquippedItem(shared, "Helmet", itemSet))

		local grantedAura = item({ type = "Helmet", id = 9002, requirements = { str = 1 }, grantedSkills = { { skillId = "Anger" } } })
		assert.is_false(tab:ValidateEquippedItem(grantedAura, "Helmet", itemSet))
	end)

	it("preserves current-set Mercenary equipment on reset", function()
		itemSet[MercenaryTools.itemSlotName("Helmet")].selItemId = 9001
		tab:Reset()
		assert.are.equal(itemSet, build.itemsTab.activeItemSet)
		assert.are.equal(9001, itemSet[MercenaryTools.itemSlotName("Helmet")].selItemId)
		assert.are.equal(1, #build.itemsTab.itemSetOrderList)
	end)

	it("imports copied Warrant text into the active loadout", function()
		local mercenaryHelmet = MercenaryTools.itemSlotName("Helmet")
		itemSet[mercenaryHelmet].selItemId = 9001
		local warrantText = [[
Item Class: Map Fragments
Rarity: Normal
Mercenary Warrant
--------
Thalia, the Exquisite
--------
Build: Kineticist
Mercenary Level: 83
--------
Elemental Weakness
Greater Curse Effect (Tier: 3)
Faster Casting (Tier: 2)
--------
Right click this item to view Mercenary details.
--------
Note: ~b/o 1 mirror
]]
		tab.controls.importWarrant:Click()
		local popup = main.popups[1]
		assert.are.equal("Import Mercenary Warrant", popup.title)
		popup.controls.edit:SetText(warrantText)
		popup.controls.import:Click()
		assert.are_not.equal(popup, main.popups[1])
		assert.are.equal("Kineticist", tab.data.builds[tab.profile.buildId].name)
		assert.are.equal(83, tab.profile.foundAreaLevel)
		assert.are.equal("Elemental Weakness", tab.data.skills[tab.profile.mainSkillId].name)
		assert.is_true(tab.profile.importedWarrant)
		assert.are.equal(9001, itemSet[mercenaryHelmet].selItemId)
		local xml = { }
		tab:Save(xml)
		assert.are.equal("true", xml[1].attrib.importedWarrant)
		tab:Reset()
		tab:Load(xml)
		assert.is_true(tab.profile.importedWarrant)
		assert.are.equal("Kineticist", tab.data.builds[tab.profile.buildId].name)
	end)

	it("preserves invalid equipped items for diagnostics", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local invalidHelmet = item({ id = 9015, name = "Invalid Mercenary Helmet", type = "Helmet", base = { type = "Helmet" }, requirements = { int = 1 } })
		build.itemsTab.items[invalidHelmet.id] = invalidHelmet
		build.itemsTab.slots[MercenaryTools.itemSlotName("Helmet")]:SetSelItemId(invalidHelmet.id)
		build.itemsTab:PopulateSlots()
		assert.are.equal(invalidHelmet.id, itemSet[MercenaryTools.itemSlotName("Helmet")].selItemId)
		assert.matches("Helmet: armour attribute alignment", table.concat(tab:GetErrors(), "\n"))
	end)

	it("offers base-compatible warning items with normal item colors", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local invalidHelmet = item({ id = 9018, name = "Selectable Invalid Helmet", type = "Helmet", base = { type = "Helmet" }, requirements = { int = 1 } })
		build.itemsTab.items[invalidHelmet.id] = invalidHelmet
		build.itemsTab:PopulateSlots()
		local helmetSlot = build.itemsTab.slots[MercenaryTools.itemSlotName("Helmet")]
		local candidateIndex
		for index, itemId in ipairs(helmetSlot.items) do
			if itemId == invalidHelmet.id then candidateIndex = index break end
		end
		assert.is_number(candidateIndex)
		assert.matches(colorCodes[invalidHelmet.rarity], helmetSlot.list[candidateIndex], nil, true)
		helmetSlot:SetSelItemId(invalidHelmet.id)
		build.itemsTab:PopulateSlots()
		assert.are.equal(invalidHelmet.id, helmetSlot.selItemId)
		assert.matches("Helmet: armour attribute alignment", table.concat(tab:GetErrors(), "\n"))
	end)

	it("allows Abyss jewels only in sockets on supported equipment", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		local jewel = item({ id = 9016, name = "Mercenary Abyss Jewel", type = "Jewel", base = { type = "Jewel", subType = "Abyss" }, requirements = { level = 1 } })
		assert.is_false(tab:ValidateEquippedItem(jewel, "Helmet Abyssal Socket 1", itemSet))
		local helmet = item({ id = 9017, name = "Mercenary Abyss Helmet", type = "Helmet", base = { type = "Helmet" }, requirements = { str = 1 }, abyssalSocketCount = 1 })
		build.itemsTab.items[helmet.id] = helmet
		itemSet[MercenaryTools.itemSlotName("Helmet")].selItemId = helmet.id
		assert.is_true(tab:ValidateEquippedItem(jewel, "Helmet Abyssal Socket 1", itemSet))
		assert.is_false(tab:IsSlotSupported("Jewel 12345"))
	end)

	it("bounds Full DPS count edits in the Mercenary UI", function()
		tab.profile.skills[1] = { id = "InfernalBlowMercenary", enabled = true, supports = { } }
		tab.controls.skillCount.changeFunc("200")
		assert.are.equal(99, tab.profile.skills[1].count)
		tab.controls.skillCount.changeFunc("0")
		assert.are.equal(1, tab.profile.skills[1].count)
	end)

	it("reuses player gem sort options and persists Mercenary preferences", function()
		local skillOptions = require("Modules/SkillOptions")
		assert.are.same(skillOptions.sortGemTypeList, tab.controls.sortGemsByDPSFieldControl.list)
		local xml = { }
		tab.sortGemsByDPS = false
		tab.sortGemsByDPSField = "TotalDPS"
		tab:Save(xml)
		assert.are.equal("false", xml.attrib.sortGemsByDPS)
		assert.are.equal("TotalDPS", xml.attrib.sortGemsByDPSField)
	end)

	it("keeps unlimited Mercenary loadouts independent while sharing equipment", function()
		local sharedHelmet = MercenaryTools.itemSlotName("Helmet")
		itemSet[sharedHelmet].selItemId = 9019
		tab.profile.buildId = "MeleeAOEMarauderFireSlam"
		tab.profile.skills = { { id = "InfernalBlowMercenary", enabled = true, supports = { } } }
		tab.profile.mainSkillId = "InfernalBlowMercenary"
		tab.profile.title = "First"
		tab:RefreshControls()

		local firstId = tab.activeMercenarySetId
		for index = 1, 16 do
			local set = tab:NewMercenarySet()
			set.title = "Loadout "..index
			table.insert(tab.mercenarySetOrderList, set.id)
		end
		assert.are.equal(17, #tab.mercenarySetOrderList)
		local manager = new("MercenarySetListControl", nil, {0, 0, 350, 200}, tab)
		assert.is_table(manager.controls.copy)
		assert.is_table(manager.controls.delete)

		local secondId = tab.mercenarySetOrderList[2]
		tab:RefreshControls()
		tab.controls.setSelect:SetSel(2)
		assert.are.equal(secondId, tab.activeMercenarySetId)
		tab.profile.buildId = "TrapsMinesShadowLightning"
		tab.profile.foundAreaLevel = 80
		tab.profile.skills = { { id = "LightningTrapMercenary", enabled = true, supports = { } } }
		tab.profile.mainSkillId = "LightningTrapMercenary"
		tab:RefreshControls()
		assert.are.equal(9019, build.itemsTab.activeItemSet[sharedHelmet].selItemId)

		tab.controls.setSelect:SetSel(1)
		assert.are.equal("MeleeAOEMarauderFireSlam", tab.profile.buildId)
		assert.are.equal("InfernalBlowMercenary", tab.profile.mainSkillId)
		assert.are.equal(9019, build.itemsTab.activeItemSet[sharedHelmet].selItemId)

		local xml = { }
		tab:Save(xml)
		assert.are.equal("1", xml.attrib.activeMercenarySet)
		local savedSetCount = 0
		for _, child in ipairs(xml) do
			if child.elem == "MercenarySet" then savedSetCount = savedSetCount + 1 end
		end
		assert.are.equal(17, savedSetCount)

		tab:Load(xml)
		assert.are.equal(17, #tab.mercenarySetOrderList)
		assert.are.equal(firstId, tab.activeMercenarySetId)
		assert.are.equal("InfernalBlowMercenary", tab.profile.mainSkillId)
		assert.are.equal(9019, build.itemsTab.activeItemSet[sharedHelmet].selItemId)
	end)

	it("loads the previous single-profile Mercenary XML format", function()
		tab:Load({
			attrib = {
				buildId = "TrapsMinesShadowLightning",
				foundAreaLevel = "80",
				mainSkillId = "LightningTrapMercenary",
				lifeComparison = "PLAYER",
			},
			{ elem = "Skill", attrib = {
				id = "LightningTrapMercenary",
				enabled = "true",
				includeInFullDPS = "false",
				count = "1",
			} },
		})
		assert.are.equal(1, #tab.mercenarySetOrderList)
		assert.are.equal("TrapsMinesShadowLightning", tab.profile.buildId)
		assert.are.equal("PLAYER", tab.profile.lifeComparison)
		assert.are.equal("LightningTrapMercenary", tab.profile.skills[1].id)
	end)

	it("matches the player skill tip sizing without exposing Calcs state in row text", function()
		tab.profile.skills[1] = { id = "ConsecratedPathMercenary", enabled = true, supports = { } }
		tab.profile.mainSkillId = "ConsecratedPathMercenary"
		tab:RefreshControls()
		local row = tab.controls.skillList:GetRowValue(1, 1, tab.profile.skills[1])
		assert.are.equal(14, tab.controls.skillTip.height)
		assert.is_nil(row:find("(Calcs)", 1, true))
	end)

	it("shows player-style stat tooltips for Mercenary skills and supports", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		tab:SetSkill(1, "ConsecratedPathMercenary")
		local expectedSkillColor = data.skillColorMap[build.data.skills.ConsecratedPathMercenary.color]
		local skillRow = tab.controls.skillList:GetRowValue(1, 1, tab.profile.skills[1])
		assert.are.equal(expectedSkillColor, skillRow:sub(1, #expectedSkillColor))
		local skillOption
		for _, option in ipairs(tab.controls.skill.list) do
			if option.id == "ConsecratedPathMercenary" then skillOption = option break end
		end
		assert(skillOption)
		assert.are.equal(expectedSkillColor, skillOption.label:sub(1, #expectedSkillColor))
		local tooltip = new("Tooltip")
		local function tooltipText()
			local lines = { }
			for _, line in ipairs(tooltip.lines) do if line.text then table.insert(lines, line.text) end end
			return table.concat(lines, "\n")
		end

		tab.controls.skillList:AddValueTooltip(tooltip, 1, tab.profile.skills[1])
		local skillTooltipText = tooltipText()
		assert.matches("Consecrated Path", skillTooltipText)
		assert.matches("Level:", skillTooltipText)
		assert.matches("Slams the ground", skillTooltipText)

		tooltip:Clear(true)
		tab.controls.skill.tooltipFunc(tooltip, "HOVER", 1, { id = "ConsecratedPathMercenary" })
		assert.matches("Consecrated Path", tooltipText())

		tooltip:Clear(true)
		local support = assert(tab.supportControls[1].list[2])
		tab.supportControls[1].tooltipFunc(tooltip, "HOVER", 2, support)
		local supportTooltipText = tooltipText()
		assert.is_true(supportTooltipText:find(tab.data.supports[support.id].name, 1, true) ~= nil)
		assert.is_true(supportTooltipText:find("Mercenary Support, Tier ", 1, true) ~= nil)
		assert.matches("Supported Skills gain", supportTooltipText)
	end)

	it("uses the Mercenary effective level in skill tooltips", function()
		selectBuild("TrapsMinesShadowLightning", 80)
		build.configTab.enemyLevel = 60
		tab:SetSkill(1, "LightningTrapMercenary")
		local tooltip = new("Tooltip")
		tab.controls.skillList:AddValueTooltip(tooltip, 1, tab.profile.skills[1])
		local displayedLevel
		for _, line in ipairs(tooltip.lines) do
			displayedLevel = displayedLevel or line.text and line.text:match("Level: %^7(%d+)")
		end
		local actorLevel = MercenaryTools.effectiveLevel(80, 60)
		assert.are.equal(MercenaryTools.skillLevel(build.data.skills.LightningTrapMercenary, actorLevel), tonumber(displayedLevel))
	end)

	it("sorts Mercenary supports by the selected DPS output", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		tab:SetSkill(1, "ConsecratedPathMercenary")
		local selected = tab.profile.skills[1]
		local preferredId = tab.supportControls[1].list[2].id
		local originalCalculator = build.calcsTab.GetMiscCalculator
		local ok, err = pcall(function()
			build.calcsTab.GetMiscCalculator = function()
				return function()
					local supportId = selected.supports[1] and selected.supports[1].id
					local dps = supportId == preferredId and 100 or 10
					return { CombinedDPS = dps, FullDPS = dps }
				end
			end
			tab.sortGemsByDPS = true
			tab.sortGemsByDPSField = "CombinedDPS"
			tab:QueueSupportSort(1)
			while tab.supportSortCoroutine do tab:ProcessSupportSort() end
			assert.are.equal(preferredId, tab.supportControls[1].list[1].id)
			assert.is_nil(selected.supports[1])
		end)
		build.calcsTab.GetMiscCalculator = originalCalculator
		assert.is_true(ok, err)
	end)

	it("keeps support selections contiguous", function()
		tab:SetSkill(1, "ConsecratedPathMercenary")
		local supportId = assert(tab.data.skills.ConsecratedPathMercenary.possibleSupportIds[1])
		tab:SetSupport(5, supportId)
		assert.are.equal(1, #tab.profile.skills[1].supports)
		assert.are.equal(supportId, tab.profile.skills[1].supports[1].id)
	end)

	it("edits the selected skill group and its supports through the UI", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		tab:RefreshControls()
		tab.controls.skillList.controls.new.onClick()
		assert.are.equal(1, #tab.profile.skills)
		local skillEntry
		for _, candidate in ipairs(tab.controls.skill.list) do
			if candidate.id and #(tab.data.skills[candidate.id].possibleSupportIds or { }) > 0 then skillEntry = candidate break end
		end
		assert(skillEntry)
		tab.controls.skill.selFunc(2, skillEntry)
		assert.are.equal(skillEntry.id, tab.profile.skills[1].id)
		local supportEntry = assert(tab.supportControls[1].list[2])
		tab.supportControls[1].selFunc(2, supportEntry)
		assert.are.equal(supportEntry.id, tab.profile.skills[1].supports[1].id)
		tab.supportControls[1].selFunc(1, tab.supportControls[1].list[1])
		assert.are.equal(0, #tab.profile.skills[1].supports)
	end)

	it("registers Ice Shot support pickers with the Mercenary control host", function()
		selectBuild("EleBowRangerClones")
		tab:SetSkill(1, "IceShotMercenary")
		assert.is_true(#tab.supportControls[1].list > 1)
		for index = 1, 5 do
			assert.are.equal(tab.supportControls[index], tab.controls["support"..index])
			assert.is_true(tab.supportControls[index]:IsShown())
		end
		assert.is_nil(tab.controls.skillLink)
	end)

	it("keeps every support slot editable while reporting capacity warnings", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		tab:SetSkill(1, "ConsecratedPathMercenary")
		assert.is_true(tab.supportControls[3].enabled)
		assert.is_true(tab.supportControls[4].enabled)
		local supportId = tab.data.skills.ConsecratedPathMercenary.possibleSupportIds[1]
		local support = tab.data.supports[supportId]
		for index = 1, 4 do tab.profile.skills[1].supports[index] = { id = supportId, tier = support.variant } end
		tab:RefreshControls()
		assert.is_true(tab.supportControls[4].enabled)
		assert.is_true(tab.supportControls[5].enabled)
		assert.matches("has more than 3 supports", table.concat(tab:GetErrors(), "\n"))
	end)

	it("shows clean Mercenary class and build labels", function()
		tab.profile.classId = "AurasMinionsTemplar"
		tab:RefreshControls()
		for _, entry in ipairs(tab.controls.class.list) do
			assert.not_matches("%[DNT%]", entry.label)
		end
		local labels = { }
		for _, entry in ipairs(tab.controls.build.list) do labels[entry.id] = entry.label end
		assert.are.equal("Warpriest", labels.AurasMinionsTemplarSmite)
		assert.are.equal("Infamous Warpriest", labels.AurasMinionsTemplarSmiteNoble)
	end)

	it("offers zero-capacity data skills and reports them as warnings", function()
		tab.profile.classId = "Crit1HShadow"
		tab.profile.buildId = "Crit1HShadowSpectral"
		tab:RefreshControls()
		assert.is_true(#tab.controls.skill.list > 1)
		tab.controls.skillList.controls.new.onClick()
		assert.are.equal(1, #tab.profile.skills)
		assert.matches("allows at most 0 skills", table.concat(tab:GetErrors(), "\n"))
	end)

	it("allows New beyond the six-skill validation limit", function()
		selectBuild("MeleeAOEMarauderFireSlam")
		tab:RefreshControls()
		for _ = 1, 7 do tab.controls.skillList.controls.new.onClick() end
		assert.are.equal(7, #tab.profile.skills)
		assert.is_true(tab.controls.skillList.controls.new.enabled())
		assert.matches("cannot have more than 6", table.concat(tab:GetErrors(), "\n"))
	end)

	it("keeps the selected Calcs skill consistent with skill-row edits", function()
		assert.is_nil(tab.controls.skillMain)
		assert.is_nil(tab.controls.skillMainLabel)
		tab:SetSkill(1, "InfernalBlowMercenary")
		assert.are.equal("InfernalBlowMercenary", tab.profile.mainSkillId)
		tab:SetSkill(1, "CombustMercenary")
		assert.are.equal("CombustMercenary", tab.profile.mainSkillId)
		tab:SetSkill(1, nil)
		assert.is_nil(tab.profile.mainSkillId)
	end)
end)
