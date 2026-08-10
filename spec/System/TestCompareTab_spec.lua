describe("CompareTab", function()
	it("imports Mercenary builds and preserves their Calcs skill selection", function()
		local MercenaryTools = require("Modules/MercenaryTools")
		newBuild()
		build.mercenaryTab.profile = {
			classId = "EleBowRanger",
			buildId = "EleBowRangerClones",
			foundAreaLevel = 68,
			mainSkillId = "MirrorArrowMercenary",
			lifeComparison = "AUTO",
			skills = {
				{ id = "MirrorArrowMercenary", enabled = true, includeInFullDPS = true, supports = { } },
				{ id = "IceShotMercenary", enabled = true, includeInFullDPS = false, supports = { } },
			},
		}
		build.mercenaryTab:Changed()
		local mercenaryItemSet = build.mercenaryTab:GetItemSet(true)
		local item = new("Item", "Rarity: Normal\nCrude Bow")
		item.id = 999903
		build.itemsTab.items[item.id] = item
		mercenaryItemSet[MercenaryTools.itemSlotName("Weapon 1")].selItemId = item.id
		build.calcsTab.input.actor = "MERCENARY"
		build.configTab.input.enemyLevel = 83
		build.configTab:BuildModList()
		build.calcsTab:BuildOutput()

		local compareTab = build.compareTab
		assert.is_true(compareTab:ImportBuild(assert(build:SaveDB("mercenary-compare")), "Mercenary"))
		local entry = assert(compareTab:GetActiveCompare())
		compareTab:UpdateSetSelectors(entry)
		assert.is_true(compareTab.controls.cmpMainSkill:IsShown())
		assert.are.equal(2, #compareTab.controls.cmpMainSkill.list)
		compareTab.controls.cmpMainSkill:SetSel(2)
		assert.are.equal("IceShotMercenary", entry.mercenaryTab.profile.mainSkillId)
		entry.mercenaryTab.profile.mainSkillId = "MirrorArrowMercenary"
		entry.mercenaryTab:Changed()
		compareTab.compareViewMode = "CALCS"
		compareTab:RefreshCalcsSkillControls(entry)
		assert.is_true(entry.calcsTab:IsMercenaryActor())
		assert.is_true(compareTab.controls.cmpCalcsMainSkill:IsShown())
		assert.are.equal(2, #compareTab.controls.cmpCalcsMainSkill.list)
		compareTab.controls.cmpCalcsMainSkill:SetSel(2)
		assert.are.equal("IceShotMercenary", entry.mercenaryTab.profile.mainSkillId)
	end)

	it("hides skill detail controls after removing the final comparison", function()
		newBuild()
		local compareTab = build.compareTab
		compareTab.compareEntries = { { label = "Test" } }
		compareTab.activeCompareIndex = 1
		local controls = {
			compareTab.controls.cmpMainSkill,
			compareTab.controls.cmpSkillPart,
			compareTab.controls.cmpStageCount,
			compareTab.controls.cmpMineCount,
			compareTab.controls.cmpMinion,
			compareTab.controls.cmpMinionSkill,
		}
		for _, control in ipairs(controls) do
			control.shown = true
		end

		compareTab:RemoveBuild(1)

		for _, control in ipairs(controls) do
			assert.is_false(control:IsShown())
		end
	end)
	it("reproduces matching-socket gem quality when comparing a build with itself", function()
		newBuild()
		build.itemsTab:CreateDisplayItemFromRaw(
			"Rarity: RARE\nTest Subject\nSage's Robe\nQuality: 0\nSockets: B-B-B\nImplicits: 0\n")
		build.itemsTab:AddDisplayItem()
		build.skillsTab:PasteSocketGroup("Slot: Body Armour\nFireball 20/0  1\n")
		runCallback("OnFrame")
		assert.are.equals(10, build.calcsTab.mainOutput.GemQuality)

		-- doesn't actually save to a file, just encodes as xml
		local entry = new("CompareEntry"):CompareEntry(build:SaveDB("code"), "Self")

		assert.is_true(entry.skillsTab.socketGroupList[1].gemList[1].matchesSocket)
		assert.are.equals(build.calcsTab.mainOutput.GemQuality, entry.calcsTab.mainOutput.GemQuality)
		assert.are.equals(build.calcsTab.mainOutput.CombinedDPS, entry.calcsTab.mainOutput.CombinedDPS)
	end)

	it("copies an item from the visible Mercenary set into the primary Mercenary set", function()
		local MercenaryTools = require("Modules/MercenaryTools")
		newBuild()
		build.mercenaryTab.profile = {
			classId = "EleBowRanger",
			buildId = "EleBowRangerClones",
			foundAreaLevel = 68,
			mainSkillId = "MirrorArrowMercenary",
			lifeComparison = "AUTO",
			skills = { { id = "MirrorArrowMercenary", enabled = true, supports = { } } },
		}
		build.mercenaryTab:Changed()
		local primaryMercenarySet = assert(build.mercenaryTab:GetItemSet(true))
		local item = new("Item", "Rarity: Normal\nCrude Bow")
		build.itemsTab:AddItem(item, true)
		primaryMercenarySet[MercenaryTools.itemSlotName("Weapon 1")].selItemId = item.id

		build.configTab.input.enemyLevel = 83
		build.configTab:BuildModList()
		build.calcsTab:BuildOutput()
		local compareTab = build.compareTab
		assert.is_true(compareTab:ImportBuild(assert(build:SaveDB("mercenary-copy")), "Mercenary"))
		local entry = assert(compareTab:GetActiveCompare())
		entry.itemsTab:SetViewItemSet(assert(entry.mercenaryTab.itemSetId))
		build.itemsTab:SetViewItemSet(primaryMercenarySet.id)
		build.calcsTab:BuildOutput()
		local _, baseOutput, actorOutputs = build.calcsTab:GetMiscCalculator()
		assert.are.equal(actorOutputs.MERCENARY, baseOutput)

		local playerWeapon = build.itemsTab.activeItemSet["Weapon 1"]
		playerWeapon.selItemId = 0
		compareTab:CopyCompareItemToPrimary("Weapon 1", entry, true)

		local copiedItemId = primaryMercenarySet[MercenaryTools.itemSlotName("Weapon 1")].selItemId
		assert.is_true(copiedItemId > 0)
		assert.are.equal("Crude Bow", build.itemsTab.items[copiedItemId].name)
		assert.are.equal(0, playerWeapon.selItemId)
	end)
	end)
end)
