describe("Mercenary API import", function()
	local json = require("dkjson")
	local Import = require("Modules.MercenaryImport")
	local Tools = require("Modules.MercenaryTools")
	local helpers = dofile("../spec/System/MercenaryTestHelpers.lua")
	local file = assert(io.open("../spec/System/mercenary-league-account.json"))
	local fixture = assert(json.decode(file:read("*a")))
	file:close()
	local source = { account = "fixture-account", realm = "pc", league = "Test League" }
	local roster, tab
	before_each(function()
		newBuild()
		build.characterLevel = 97
		tab = build.mercenaryTab
		tab:EnsureData()
		roster = copyTable(fixture.league_account)
		roster.active_mercenary_index = fixture.character.active_mercenary_index
	end)
	after_each(function()
		while main.popups[1] do main:ClosePopup() end
	end)

	local function import(index, destination)
		local profile, err = build.importTab:ImportMercenary(roster.mercenaries[index], source, destination)
		assert.is_table(profile, err)
		return profile
	end

	local function itemCount()
		local count = 0
		for _ in pairs(build.itemsTab.items) do count = count + 1 end
		return count
	end

	local function mercSetId()
		return build.itemsTab:GetActorItemSetId("MERCENARY")
	end

	it("converts both captured rosters with normal validation and exact totals", function()
		local skills, supports, equipment = 0, 0, 0
		for _, hire in ipairs(roster.mercenaries) do
			local profile = assert(Import.profile(hire, tab.data))
			assert.same({ }, Tools.validateProfile(profile, tab.data))
			assert.equals(83, profile.foundAreaLevel)
			assert.is_nil(profile.importedWarrant)
			skills = skills + #profile.skills
			equipment = equipment + #hire.items
			for _, skill in ipairs(profile.skills) do
				supports = supports + #skill.supports
				assert.is_true(skill.enabled)
				assert.is_false(skill.includeInFullDPS)
				assert.equals(1, skill.count)
			end
		end
		assert.same({12, 32, 20}, {skills, supports, equipment})
	end)

	it("resolves optional IDs through hashes without name substitution", function()
		local hire = roster.mercenaries[2]
		local expected = assert(Import.profile(hire, tab.data))
		for _, skill in ipairs(hire.skills) do
			skill.id = nil
			skill.name = "Wrong display name"
			for _, support in ipairs(skill.supports) do support.id = nil end
		end
		assert.same(expected, assert(Import.profile(hire, tab.data)))
	end)

	for _, case in ipairs({ "build hash", "skill hash", "support hash", "skill ID", "support tier", "unknown hash" }) do
		it("rejects "..case.." conflicts without mutating the build", function()
			local hire = roster.mercenaries[1]
			if case == "build hash" then hire.build_hash = -1
			elseif case == "skill hash" then hire.skills[1].hash = -1
			elseif case == "support hash" then hire.skills[1].supports[1].hash = -1
			elseif case == "skill ID" then hire.skills[1].id = "Unsupported"
			elseif case == "support tier" then hire.skills[1].supports[1].tier = 99
			else hire.skills[1].id = nil hire.skills[1].hash = -1 end
			local before = build:SaveDB("code")
			assert.is_nil(build.importTab:ImportMercenary(hire, source))
			assert.equals(before, build:SaveDB("code"))
		end)
	end

	it("imports mercenary equipment through ItemsTab and preserves player and Guardian data", function()
		local itemsTab = build.itemsTab
		build.importTab:ImportItemsAndSkills({ level = 97, equipment = {{ id = "player", name = "", typeLine = "Iron Hat", frameType = 0, inventoryId = "Helm" }} }, false, false, false)
		local guardianSet = build.importTab:GetOrCreateGuardianItemSet()
		build.importTab:ImportItem({ id = "guardian", name = "", typeLine = "Leather Belt", frameType = 0, inventoryId = "Belt" }, nil, false, guardianSet.id)
		local playerBefore = copyTable(itemsTab.activeItemSet)
		local guardianBefore = copyTable(guardianSet)
		local skillsBefore = copyTable(build.skillsTab.socketGroupList)
		local first = import(1)
		local firstSetId = mercSetId()
		assert.is_not_nil(firstSetId)
		assert.are_not.equal(itemsTab.activeItemSetId, firstSetId)
		local second = import(2)
		assert.equals(firstSetId, mercSetId())
		local set = itemsTab.itemSets[mercSetId()]
		for _, slot in ipairs({"Helmet Abyssal Socket 1", "Belt Abyssal Socket 1"}) do
			assert.is_true(set[slot].selItemId > 0)
			assert.equals("Abyss", itemsTab.items[set[slot].selItemId].base.subType)
		end
		assert.same(playerBefore, itemsTab.activeItemSet)
		assert.same(guardianBefore, itemsTab.itemSets[guardianSet.id])
		assert.same(skillsBefore, build.skillsTab.socketGroupList)
		assert.equals(97, build.characterLevel)
		tab:SetActiveMercenarySet(first.id)
		assert.equals(firstSetId, mercSetId())
		assert.is_nil(build.configTab.configSets[build.configTab.activeConfigSetId].actors.mercenary.itemSetId)
	end)

	it("reimports without duplication and clears removed slots", function()
		local first = import(1)
		local second = import(2)
		local firstBefore = copyTable(first)
		second.title = "My renamed hire"
		second.skills[1].includeInFullDPS = true
		second.skills[1].count = 3
		second.skills[1].skillPart = 2
		second.skills[2].enabled = false
		local again = import(2)
		assert.equals(second.id, again.id)
		local afterSecond = itemCount()
		assert.is_true(afterSecond > 0)
		assert.equals(roster.mercenaries[2].name, again.title)
		assert.equals(1, again.skills[1].count)
		assert.is_nil(again.skills[1].skillPart)
		assert.is_false(again.skills[1].includeInFullDPS)
		assert.is_true(again.skills[1].enabled)
		assert.is_true(again.skills[2].enabled)
		for index, item in ipairs(roster.mercenaries[2].items) do
			if item.inventoryId == "Helm" then table.remove(roster.mercenaries[2].items, index) break end
		end
		local updated = import(2)
		local set = build.itemsTab.itemSets[mercSetId()]
		assert.equals(0, set.Helmet.selItemId)
		assert.equals(0, set["Helmet Abyssal Socket 1"].selItemId)
		assert.are.equal(afterSecond - 2, itemCount())
		assert.same(firstBefore, tab.mercenarySets[first.id])
	end)

	it("stages invalid items atomically, including nested items", function()
		import(1)
		local before = build:SaveDB("code")
		roster.mercenaries[2].items[10].typeLine = "Unsupported item base"
		assert.is_nil(build.importTab:ImportMercenary(roster.mercenaries[2], source))
		assert.equals(before, build:SaveDB("code"))
	end)

	it("maps reordered equipment by inventoryId and omits player gem groups", function()
		local hire = roster.mercenaries[1]
		local reversed = { }
		for index = #hire.items, 1, -1 do table.insert(reversed, hire.items[index]) end
		hire.items = reversed
		for _, itemData in ipairs(hire.items) do
			if itemData.inventoryId == "Weapon" then
				itemData.socketedItems = {{ typeLine = "Fireball", socket = 0, properties = { } }}
			end
		end
		local profile = import(1)
		assert.equals(10, itemCount())
		assert.equals(0, #build.skillsTab.socketGroupList)
		local weapon = build.itemsTab.items[build.itemsTab.itemSets[mercSetId()]["Weapon 1"].selItemId]
		assert.equals("Assassin Bow", weapon.baseName)
		assert.equals("Fireball", weapon.socketedGems[1].nameSpec)
		weapon:BuildAndParseRaw()
		assert.equals("Fireball", weapon.socketedGems[1].nameSpec)
		assert.equals(0, #build.skillsTab.socketGroupList)
	end)

	it("applies imported Mercenary socket occupancy to item bonuses", function()
		helpers.allocatePermanentHire()
		helpers.allocate("Legendary Rings")
		tab.profile.classId = "ElementalWitch"
		tab.profile.buildId = "ElementalWitchLightning"
		tab.profile.foundAreaLevel = 83
		tab.profile.mainSkillId = "ArcMercenary"
		tab.profile.skills = { { id = "ArcMercenary", enabled = true, supports = { } } }
		tab:Changed()
		local set = tab:GetItemSet(true)
		local context = { actor = "MERCENARY" }
		local function importRing(socketedItems)
			build.importTab:ImportItem({
				id = "malachai-socket-test", frameType = 3, name = "Malachai's Artifice", typeLine = "Unset Ring",
				sockets = { { group = 0, sColour = "W" } }, socketedItems = socketedItems,
				implicitMods = { "Has 1 Socket" },
				explicitMods = { "-20% to all Elemental Resistances", "+100% to Fire Resistance when Socketed with a Red Gem", "All Sockets are White" },
			}, "Ring 1", false, set.id, context)
		end
		importRing({ })
		local env = helpers.calculateBuild()
		assert.is_table(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		local before = env.mercenary.output.FireResistTotal
		local playerGroupCount = #build.skillsTab.socketGroupList
		importRing({ { typeLine = "Heavy Strike", socket = 0, support = false, properties = { } } })
		env = helpers.calculateBuild()
		local occupied = build.itemsTab.items[set["Ring 1"].selItemId]
		assert.equals(playerGroupCount, #build.skillsTab.socketGroupList)
		assert.equals(before + 100, env.mercenary.output.FireResistTotal)
		assert.equals("Heavy Strike", occupied.socketedGems[1].nameSpec)
	end)

	it("reimports into the same ItemsTab mercenary set when Guardian skills share it", function()
		local profile = import(1)
		local setId = mercSetId()
		local other = tab:NewMercenarySet()
		table.insert(tab.mercenarySetOrderList, other.id)
		build.skillsTab:PasteSocketGroup("Animate Guardian 20/0  1")
		local gem = build.skillsTab.socketGroupList[1].gemList[1]
		gem.skillMinionItemSet = setId
		gem.skillMinionItemSetCalcs = setId
		local updated = import(1)
		assert.equals(profile.id, updated.id)
		assert.equals(setId, mercSetId())
		assert.equals(setId, gem.skillMinionItemSet)
	end)

	it("does not delete items still used by other item sets on reimport", function()
		local profile = import(1)
		local set = build.itemsTab.itemSets[mercSetId()]
		local helmetId = set.Helmet.selItemId
		local spare = build.itemsTab:NewItemSet()
		table.insert(build.itemsTab.itemSetOrderList, spare.id)
		spare.Helmet.selItemId = helmetId
		local oldItem = build.itemsTab.items[helmetId]
		local updated = import(1)
		assert.equals(set.id, mercSetId())
		assert.equals(oldItem, build.itemsTab.items[helmetId])
		assert.equals(helmetId, spare.Helmet.selItemId)
	end)

	it("does not concurrently equip two items that share an API uniqueID", function()
		local hire = roster.mercenaries[1]
		local helmData
		for _, itemData in ipairs(hire.items) do
			if itemData.inventoryId == "Helm" then
				helmData = itemData
				break
			end
		end
		assert.is_table(helmData)
		build.importTab:ImportItemsAndSkills({
			level = 97,
			equipment = {{ id = helmData.id, name = "", typeLine = "Iron Hat", frameType = 0, inventoryId = "Helm" }},
		}, false, false, false)
		local playerHelmetId = build.itemsTab.activeItemSet.Helmet.selItemId
		local playerItem = build.itemsTab.items[playerHelmetId]
		assert.equals(helmData.id, playerItem.uniqueID)
		local before = build:SaveDB("code")
		local imported, message = build.importTab:ImportMercenary(hire, source)
		assert.is_nil(imported)
		assert.matches("still equipped by the player", message)
		assert.equals(before, build:SaveDB("code"))
		assert.equals(playerItem, build.itemsTab.items[playerHelmetId])
		assert.equals(playerHelmetId, build.itemsTab.activeItemSet.Helmet.selItemId)
		local equippedIds = { }
		local function note(itemSet)
			if not itemSet then
				return
			end
			for _, slot in pairs(itemSet) do
				if type(slot) == "table" and slot.selItemId and slot.selItemId ~= 0 then
					local item = build.itemsTab.items[slot.selItemId]
					if item and item.uniqueID then
						equippedIds[item.uniqueID] = equippedIds[item.uniqueID] or { }
						equippedIds[item.uniqueID][item.id] = true
					end
				end
			end
		end
		note(build.itemsTab.activeItemSet)
		note(build.itemsTab:GetActorItemSet("MERCENARY"))
		local shared = equippedIds[helmData.id]
		assert.is_table(shared)
		local distinct = 0
		for id in pairs(shared) do
			distinct = distinct + 1
			assert.equals(playerHelmetId, id)
		end
		assert.equals(1, distinct)
	end)

	it("rejects Mercenary import of an API item still equipped after save and reload", function()
		local hire = roster.mercenaries[1]
		local helmData
		for _, itemData in ipairs(hire.items) do
			if itemData.inventoryId == "Helm" then
				helmData = itemData
				break
			end
		end
		assert.is_table(helmData)
		build.importTab:ImportItemsAndSkills({
			level = 97,
			equipment = {{ id = helmData.id, name = "", typeLine = "Iron Hat", frameType = 0, inventoryId = "Helm" }},
		}, false, false, false)
		local xml = build:SaveDB("code")
		loadBuildFromXML(xml)
		local playerItem = build.itemsTab.items[build.itemsTab.activeItemSet.Helmet.selItemId]
		assert.equals(helmData.id, playerItem.uniqueID)
		local imported, message = build.importTab:ImportMercenary(hire, source)
		assert.is_nil(imported)
		assert.matches("still equipped by the player", message)
	end)

	it("aborts reimport when the player still wears a Mercenary-imported item", function()
		local profile = import(1)
		local helmetId = build.itemsTab.itemSets[mercSetId()].Helmet.selItemId
		build.itemsTab.activeItemSet.Helmet.selItemId = helmetId
		local before = build:SaveDB("code")
		local imported, message = build.importTab:ImportMercenary(roster.mercenaries[1], source)
		assert.is_nil(imported)
		assert.matches("still equipped by the player", message)
		assert.equals(before, build:SaveDB("code"))
		assert.equals(helmetId, build.itemsTab.activeItemSet.Helmet.selItemId)
		assert.equals(helmetId, build.itemsTab.itemSets[mercSetId()].Helmet.selItemId)
	end)

	it("forks a new item set only when the destination is the player's active set", function()
		import(1)
		local destId = mercSetId()
		assert(build.itemsTab:SetActiveItemSet(destId))
		for _, slot in pairs(build.itemsTab.activeItemSet) do
			if type(slot) == "table" and slot.selItemId then
				slot.selItemId = 0
			end
		end
		local playerSet = copyTable(build.itemsTab.activeItemSet)
		import(1)
		assert.not_equals(destId, mercSetId())
		assert.equals(destId, build.itemsTab.activeItemSetId)
		assert.same(playerSet, build.itemsTab.activeItemSet)
		local forked = mercSetId()
		import(1)
		assert.equals(forked, mercSetId())
	end)

	it("requires ambiguous destinations and supports explicitly creating new loadouts", function()
		local original = import(1)
		local duplicate = import(1, 0)
		assert.not_equals(original.id, duplicate.id)
		assert.is_nil(build.importTab:ImportMercenary(roster.mercenaries[1], source))
		assert.equals(original.id, import(1, original.id).id)
	end)

	it("persists lower Mercenary levels, associations and equipment through XML and undo", function()
		roster.mercenaries[1].level = 40
		local first = import(1)
		local xml = { }
		tab:Save(xml)
		tab:Load(xml)
		assert.equals(40, tab.profile.foundAreaLevel)
		assert.equals(first.importAssociation, tab.profile.importAssociation)
		local firstSetId = mercSetId()
		assert.is_not_nil(firstSetId)
		import(2)
		assert.equals(firstSetId, mercSetId())
		build.itemsTab:Undo()
		assert.equals(firstSetId, mercSetId())
		assert.equals(10, itemCount())
		build.itemsTab:Redo()
		assert.equals(firstSetId, mercSetId())
		assert.equals(97, build.characterLevel)
		assert.equals("^7Mercenary level:", tab.controls.levelLabel.label)
	end)

	it("does not persist the account UUID in shareable XML", function()
		local uuid = "550e8400-e29b-41d4-a716-446655440000"
		local profile, err = build.importTab:ImportMercenary(roster.mercenaries[1], {
			account = uuid,
			realm = source.realm,
			league = source.league,
		})
		assert.is_table(profile, err)
		assert.matches("^%x+$", profile.importAssociation)
		assert.equals(64, #profile.importAssociation)
		assert.is_nil(profile.importAssociation:find(uuid, 1, true))
		local xml = build:SaveDB("code")
		assert.is_nil(xml:find(uuid, 1, true))
	end)

	it("hashes legacy reversible associations on load", function()
		local uuid = "550e8400-e29b-41d4-a716-446655440000"
		local hire = roster.mercenaries[1]
		local parts = { uuid, source.realm, source.league, hire.name, tostring(hire.build_hash) }
		for index, value in ipairs(parts) do
			parts[index] = #value .. ":" .. value
		end
		local legacy = table.concat(parts)
		assert.is_truthy(legacy:find(uuid, 1, true))
		import(1)
		tab.profile.importAssociation = legacy
		local xml = { }
		tab:Save(xml)
		tab:Load(xml)
		assert.equals(Import.association(uuid, source.realm, source.league, hire), tab.profile.importAssociation)
		assert.is_nil(tab.profile.importAssociation:find(uuid, 1, true))
		xml = { }
		tab:Save(xml)
		for _, node in ipairs(xml) do
			if node.elem == "MercenarySet" then
				assert.is_nil((node.attrib.importAssociation or ""):find(uuid, 1, true))
			end
		end
	end)

	it("Mercenary undo restores imported profile without creating or deleting item sets", function()
		local first = import(1)
		local firstBuildId = first.buildId
		local firstSetId = mercSetId()
		local firstHelm = build.itemsTab.itemSets[firstSetId].Helmet.selItemId
		assert.is_truthy(firstHelm and firstHelm ~= 0)
		local setCount = #build.itemsTab.itemSetOrderList
		local second = import(2)
		assert.are_not.equal(firstBuildId, second.buildId)
		assert.equals(firstSetId, mercSetId())
		tab:Undo()
		assert.equals(firstBuildId, tab.profile.buildId)
		assert.equals(firstSetId, mercSetId())
		assert.are.equal(setCount, #build.itemsTab.itemSetOrderList)
		assert.is_not_nil(build.itemsTab.itemSets[firstSetId])
		build.itemsTab:Undo()
		assert.equals(firstHelm, build.itemsTab.itemSets[firstSetId].Helmet.selItemId)
	end)

	it("Mercenary undo after import still reverts a later Mercenary edit", function()
		import(1)
		local importedLevel = tab.profile.foundAreaLevel
		tab.profile.foundAreaLevel = 90
		tab:Changed()
		tab:Undo()
		assert.equals(importedLevel, tab.profile.foundAreaLevel)
		assert.equals(10, itemCount())
	end)

	it("Items undo restores imported equipment without restoring Mercenary supports", function()
		local first = import(1)
		local original = copyTable(tab.profile.skills[1].supports)
		assert.is_true(#original > 0)
		table.remove(roster.mercenaries[1].skills[1].supports)
		import(1, first.id)
		assert.are.equal(#original - 1, #tab.profile.skills[1].supports)
		build.itemsTab:Undo()
		assert.are.equal(#original - 1, #tab.profile.skills[1].supports)
		assert.equals(first.id, tab.profile.id)
		tab:Undo()
		assert.same(original, tab.profile.skills[1].supports)
	end)

	it("inactive Mercenary loadouts do not own item sets", function()
		import(1)
		assert.is_true(build.itemsTab:IsItemSetReferenced(mercSetId()))
		local empty = tab:NewMercenarySet(nil, "Empty")
		table.insert(tab.mercenarySetOrderList, empty.id)
		assert.is_nil(empty.itemSetId)
		local xml = { }
		tab:Save(xml)
		tab:Load(xml)
		assert.is_nil(tab.mercenarySets[empty.id].itemSetId)
		assert.is_not_nil(mercSetId())
	end)

	it("selects only valid one-based active positions", function()
		for _, index in ipairs({1, 2}) do roster.active_mercenary_index = index assert.equals(index, Import.activeIndex(roster)) end
		for _, index in ipairs({0, -1, 3, 1.5, "2", false}) do roster.active_mercenary_index = index assert.is_nil(Import.activeIndex(roster)) end
		roster.active_mercenary_index = nil
		assert.is_nil(Import.activeIndex(roster))
		assert.is_nil(Import.activeIndex({mercenaries = { }, active_mercenary_index = 1}))
	end)

	it("walks the popup and imports the active Manyshot hire", function()
		build.importTab:OpenMercenaryImportPopup(roster, source)
		local popup = main.popups[1]
		assert.equals(2, popup.controls.hire.selIndex)
		assert.matches("Manyshot", popup.controls.hire:GetSelValue().label)
		assert.matches("Vorneka", popup.controls.hire:GetSelValue().label)
		assert.matches("%(Active%)", popup.controls.hire:GetSelValue().label)
		assert.equals(1, popup.controls.destination:GetSelValue().id)
		popup.controls.import.onClick()
		assert.equals("EleBowRangerClones", tab.profile.buildId)
		assert.equals("Vorneka Azrus", tab.profile.title)
		assert.equals(1, tab.profile.id)
		assert.equals(12, itemCount())
		main:ClosePopup()
	end)

	it("defaults the first hire when the active index is invalid", function()
		roster.active_mercenary_index = 1
		build.importTab:OpenMercenaryImportPopup(roster, source)
		local popup = main.popups[1]
		assert.equals(1, popup.controls.hire.selIndex)
		assert.matches("Thunderquiver", popup.controls.hire:GetSelValue().label)
		assert.matches("Ruktara", popup.controls.hire:GetSelValue().label)
		main:ClosePopup()
		roster.active_mercenary_index = 0
		build.importTab:OpenMercenaryImportPopup(roster, source)
		assert.equals(1, main.popups[1].controls.hire.selIndex)
		assert.matches("Ruktara", main.popups[1].controls.hire:GetSelValue().label)
		assert.is_nil((main.popups[1].controls.hire:GetSelValue().label):match("%(Active%)"))
		main:ClosePopup()
	end)

	it("does not open a popup for an empty roster", function()
		build.importTab:OpenMercenaryImportPopup({ mercenaries = { } }, source)
		assert.is_nil(main.popups[1])
	end)

	it("reuses the unused default loadout on first import", function()
		assert.equals(1, Import.unusedEmptyId(tab.mercenarySets, tab.mercenarySetOrderList))
		local profile = import(1)
		assert.equals(1, profile.id)
		assert.equals(1, #tab.mercenarySetOrderList)
		assert.equals("Ruktara, the Bullseye", profile.title)
		assert.is_nil(Import.unusedEmptyId(tab.mercenarySets, tab.mercenarySetOrderList))
	end)

	it("does not reimport into copied loadouts", function()
		local original = import(1)
		tab:OpenMercenarySetManagePopup()
		local list = main.popups[1].controls[1]
		list.selValue = original.id
		list.selIndex = 1
		list.controls.copy.onClick()
		main.popups[1].controls.edit.buf = "Copied hire"
		main.popups[1].controls.save.onClick()
		local copyId
		for _, id in ipairs(tab.mercenarySetOrderList) do
			if id ~= original.id then copyId = id end
		end
		assert.equals("Copied hire", tab.mercenarySets[copyId].title)
		assert.is_nil(tab.mercenarySets[copyId].importAssociation)
		assert.equals(original.id, import(1).id)
		assert.is_nil(tab.mercenarySets[copyId].importAssociation)
		assert.equals("Copied hire", tab.mercenarySets[copyId].title)
		main:ClosePopup()
	end)

	it("matches reimports after roster reordering", function()
		local ruktara = import(1)
		local vorneka = import(2)
		roster.mercenaries[1], roster.mercenaries[2] = roster.mercenaries[2], roster.mercenaries[1]
		assert.equals(vorneka.id, build.importTab:ImportMercenary(roster.mercenaries[1], source).id)
		assert.equals(ruktara.id, build.importTab:ImportMercenary(roster.mercenaries[2], source).id)
	end)

	it("accepts empty or omitted support arrays and items without optional fields", function()
		local hire = roster.mercenaries[1]
		assert.equals(0, #hire.skills[2].supports)
		hire.skills[2].supports = nil
		local omitted = assert(Import.profile(hire, tab.data))
		assert.equals(0, #omitted.skills[2].supports)
		hire.skills[2].supports = "nope"
		assert.is_nil(Import.profile(hire, tab.data))
		hire.skills[2].supports = { }
		hire.items[1].sockets = nil
		hire.items[1].socketedItems = nil
		hire.items[1].properties = nil
		hire.items[1].requirements = nil
		local profile = import(1)
		assert.equals(6, #profile.skills)
		assert.equals(0, #profile.skills[2].supports)
	end)

	it("switching Mercenary loadouts changes profile skills while sharing ItemsTab equipment", function()
		helpers.allocatePermanentHire()
		helpers.allocate("Legendary Helmets")
		helpers.allocate("Legendary Belts")
		helpers.allocate("Legendary Amulets")
		helpers.allocate("Legendary Rings")
		local first = import(1)
		local firstSetId = mercSetId()
		local firstLife = helpers.calculateBuild().mercenary.output.Life
		assert.is_true(firstLife > 0)
		local second = import(2)
		assert.equals(firstSetId, mercSetId())
		local secondEnv = helpers.calculateBuild()
		assert.is_table(secondEnv.mercenary, table.concat(secondEnv.mercenaryCalculationErrors or { }, "; "))
		local secondLife = secondEnv.mercenary.output.Life
		assert.is_true(secondLife > 0)
		assert.not_equals(firstLife, secondLife)
		tab:SetActiveMercenarySet(first.id)
		assert.equals(first.buildId, tab.profile.buildId)
		assert.equals(firstSetId, mercSetId())
		tab:SetActiveMercenarySet(second.id)
		assert.equals(second.buildId, tab.profile.buildId)
		assert.equals(firstSetId, mercSetId())
	end)
end)
