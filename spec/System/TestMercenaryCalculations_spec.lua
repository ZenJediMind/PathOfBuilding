describe("Permanent Mercenary calculations", function()
	local MercenaryTools = require("Modules/MercenaryTools")
	local configOptions = LoadModule("Modules/ConfigOptions")
	local configVisibility = LoadModule("Modules/ConfigVisibility")
	local function equipmentSlot(slotName)
		return assert(build.mercenaryTab:GetItemSet(true))[slotName]
	end

	local function selectScionLuminary()
		local scionId
		for classId, class in pairs(build.spec.tree.classes) do
			if class.name == "Scion" then scionId = classId break end
		end
		build.spec:SelectClass(assert(scionId))
		local luminaryId
		for ascendClassId, ascendClass in pairs(build.spec.curClass.classes) do
			if ascendClass.name == "Luminary" then luminaryId = ascendClassId break end
		end
		build.spec:SelectAscendClass(assert(luminaryId))
	end

	local function allocate(name)
		local node
		for _, candidate in pairs(build.spec.nodes) do
			if candidate.name == name and (not node or candidate.id < node.id) then node = candidate end
		end
		node = node or build.spec.tree.ascendancyMap[name]
		node = assert(node, name)
		node = build.spec.nodes[node.id] or node
		if node.path then
			build.spec:AllocNode(node)
		else
			node.alloc = true
			build.spec.allocNodes[node.id] = node
		end
		return node
	end

	local function configure(classId, buildId, skillId, fields)
		fields = fields or { }
		local profile = build.mercenaryTab.profile
		profile.classId = classId
		profile.buildId = buildId
		profile.foundAreaLevel = fields.foundAreaLevel or 68
		profile.mainSkillId = skillId
		profile.lifeComparison = fields.lifeComparison or "AUTO"
		profile.skills = { {
			id = skillId,
			enabled = true,
			includeInFullDPS = fields.includeInFullDPS == true,
			count = fields.count or 1,
			skillPart = fields.skillPart,
			skillMinionSkill = fields.skillMinionSkill,
			supports = fields.supports or { },
		} }
		build.mercenaryTab:Changed()
		if buildId then
			build.mercenaryTab:GetItemSet(true)
		end
	end

	local function configureSkill(skillId, fields)
		for buildId, mercBuild in pairs(build.data.mercenaries.builds) do
			for _, id in ipairs(mercBuild.skillIds or { }) do
				if id == skillId then
					configure(mercBuild.classId, buildId, skillId, fields)
					return
				end
			end
		end
		error("no Mercenary build exports "..skillId)
	end

	local function calculate(enemyLevel)
		build.configTab.input.enemyLevel = enemyLevel or 83
		build.configTab:BuildModList()
		build.spec.modFlag = true
		build.buildFlag = true
		runCallback("OnFrame")
		runCallback("OnFrame")
		return build.calcsTab.mainEnv
	end

	local function rallyingWeaponFlat(actor, stat)
		local total = 0
		for _, value in ipairs(actor.modDB:Tabulate("BASE", { keywordFlags = KeywordFlag.Attack }, stat)) do
			if value.mod.source == "Rallying Cry" then
				total = total + value.value
			end
		end
		return total
	end

	before_each(function()
		newBuild()
		selectScionLuminary()
		allocate("Noble Blood")
		build.characterLevel = 90
		build.characterLevelAutoMode = false
	end)

	it("calculates the selected Mercenary loadout independently", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local firstId = build.mercenaryTab.activeMercenarySetId
		local firstEnv = calculate()
		assert.are.equal("LightningTrapMercenary", firstEnv.mercenary.mainSkill.activeEffect.grantedEffect.id)

		local second = build.mercenaryTab:NewMercenarySet()
		table.insert(build.mercenaryTab.mercenarySetOrderList, second.id)
		build.mercenaryTab:SetActiveMercenarySet(second.id)
		build.mercenaryTab.profile.classId = "TrapsMinesShadow"
		build.mercenaryTab.profile.buildId = "TrapsMinesShadowLightning"
		build.mercenaryTab.profile.mainSkillId = "ZealotryMercenary"
		build.mercenaryTab.profile.skills = { { id = "ZealotryMercenary", enabled = true, supports = { } } }
		local secondEnv = calculate()
		assert.are.equal("ZealotryMercenary", secondEnv.mercenary.mainSkill.activeEffect.grantedEffect.id)

		build.mercenaryTab:SetActiveMercenarySet(firstId)
		local firstAgainEnv = calculate()
		assert.are.equal("LightningTrapMercenary", firstAgainEnv.mercenary.mainSkill.activeEffect.grantedEffect.id)
	end)

	it("keeps grouped Mercenary classes after refreshing controls", function()
		build.mercenaryTab:Changed()
		assert.are.equal(7, #build.mercenaryTab.controls.class.list)
		assert.are.equal("Templar (Str / Int)", build.mercenaryTab.controls.class.list[1].label)
	end)

	it("calculates the selected actor and explicitly selected Full DPS", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", {
			includeInFullDPS = true,
			count = 2,
			skillPart = 1,
			supports = { { id = "AddedLightningHigh", tier = 3 } },
		})
		local env = calculate()
		assert.is_table(env.mercenary)
		assert.are.equal("Mercenary", env.mercenary.type)
		assert.are.equal(68, env.mercenary.level)
		assert.are.equal(2160, env.mercenary.output.Life)
		assert.is_true(env.mercenary.output.CombinedDPS > 0)
		assert.are.equal(1, env.mercenary.output.TrapThrowCount)
		for _, stat in ipairs({ "FullDPS", "EnergyShield", "Armour", "Evasion", "FireResist", "ColdResist", "LightningResist", "ChaosResist", "LifeRegenRecovery", "EnergyShieldRegenRecovery", "EffectiveMovementSpeedMod", "LootRarity" }) do
			assert.is_number(env.mercenary.output[stat], stat)
		end
		assert.are.equal(-90, env.mercenary.modDB:Sum("INC", nil, "DamageTaken"))
		assert.are.near(0.2, env.mercenary.modDB:More({ flags = ModFlag.Dot }, "DamageTaken"), 10 ^ -9)
		-- The permanent-hire Damage penalty belongs to the constructed Mercenary
		-- actor, not to the Noble Blood node that allows hiring one.
		local penalty = MercenaryTools.permanentDamageMore(env.mercenary.level, build.data.mercenaries.permanentMercenaryDamageMore)
		assert.are.near(1 + penalty / 100, env.mercenary.modDB:More(nil, "Damage"), 10 ^ -9)
		assert.are.near(env.mercenary.output.CombinedDPS * 2, env.mercenary.output.FullDPS, 10 ^ -6)
		assert.are.near(env.mercenary.output.FullDPS, build.calcsTab.mainOutput.FullDPS, 10 ^ -6)
		assert.is_table(env.mercenary.output.SkillDPS)
		assert.is_number(env.mercenary.output.FullDotDPS)
		assert.is_true(#env.mercenary.output.SkillDPS > 0)
		assert.is_nil(env.minion)
		local fullDPSWithoutPlayerAura = env.mercenary.output.FullDPS
		build.skillsTab:PasteSocketGroup("Zealotry 20/0  1")
		env = calculate()
		assert.is_true(env.mercenary.modDB.conditions.AffectedByZealotry)
		assert.is_true(env.mercenary.output.FullDPS > fullDPSWithoutPlayerAura)
		build.skillsTab:PasteSocketGroup("Arc 20/0  1")
		build.skillsTab.socketGroupList[#build.skillsTab.socketGroupList].includeInFullDPS = true
		env = calculate()
		assert.is_true(build.calcsTab.mainOutput.FullDPS > env.mercenary.output.FullDPS)

		build.calcsTab.input.actor = "MERCENARY"
		build.buildFlag = true
		runCallback("OnFrame")
		assert.are.near(env.mercenary.output.CombinedDPS, build.calcsTab.calcsOutput.CombinedDPS, 10 ^ -6)
		build.calcsTab.input.actor = "MERCENARY_MINION"
		build.buildFlag = true
		runCallback("OnFrame")
		assert.matches("unavailable", build.calcsTab.calcsOutput.ActorUnavailableMessage)
	end)

	it("does not rebuild after the final Mercenary Full DPS skill", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", { includeInFullDPS = true })
		local calcs = build.calcsTab.calcs
		local originalInitEnv = calcs.initEnv
		local initEnvCalls = 0
		calcs.initEnv = function(...)
			initEnvCalls = initEnvCalls + 1
			return originalInitEnv(...)
		end
		local fullDPS = calcs.calcFullDPS(build, "CALCULATOR", { })
		local includedSkillInitCalls = initEnvCalls

		build.mercenaryTab.profile.skills[1].includeInFullDPS = false
		initEnvCalls = 0
		local emptyFullDPS = calcs.calcFullDPS(build, "CALCULATOR", { })
		local emptyInitCalls = initEnvCalls
		calcs.initEnv = originalInitEnv

		assert.is_true(fullDPS.mercenaryDPS > 0)
		assert.are.equal(1, includedSkillInitCalls)
		assert.are.equal(0, emptyFullDPS.mercenaryDPS)
		assert.are.equal(0, emptyInitCalls)
	end)

	it("does not initialize an incomplete Mercenary actor without an enabled skill", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		build.mercenaryTab.profile.skills[1].enabled = false
		local env = calculate()
		assert.is_nil(env.mercenary)
		assert.matches("Enable at least one Mercenary skill", table.concat(env.mercenaryCalculationErrors, "\n"))
	end)

	it("fails closed on an unknown Mercenary build", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		build.mercenaryTab.profile.buildId = "NotARealBuild"
		local env = calculate()
		assert.is_nil(env.mercenary)
		assert.matches("Select a Mercenary class and build", table.concat(env.mercenaryCalculationErrors or { }, "\n"))
	end)

	it("fails closed when more than six skills are configured", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalBlowMercenary")
		local profile = build.mercenaryTab.profile
		profile.skills = { }
		for _, skillId in ipairs(build.data.mercenaries.builds.MeleeAOEMarauderFireSlam.skillIds) do
			table.insert(profile.skills, { id = skillId, enabled = true, supports = { } })
			if #profile.skills == 7 then break end
		end
		profile.mainSkillId = profile.skills[1].id
		local env = calculate()
		assert.is_nil(env.mercenary)
		assert.matches("cannot have more than 6", table.concat(env.mercenaryCalculationErrors or { }, "\n"))
	end)

	it("fails closed on duplicate skills and does not substitute another main skill", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local profile = build.mercenaryTab.profile
		table.insert(profile.skills, { id = "LightningTrapMercenary", enabled = true, supports = { } })
		local env = calculate()
		assert.is_nil(env.mercenary)
		assert.matches("Duplicate skill", table.concat(env.mercenaryCalculationErrors or { }, "\n"))

		profile.skills = {
			{ id = "LightningTrapMercenary", enabled = false, supports = { } },
			{ id = "ZealotryMercenary", enabled = true, supports = { } },
		}
		profile.mainSkillId = "LightningTrapMercenary"
		env = calculate()
		assert.is_nil(env.mercenary)
		assert.is_true(not env.mercenary)
		assert.matches("disabled", table.concat(env.mercenaryCalculationErrors or { }, "\n"))
	end)

	it("fails closed on pool overage, invalid supports, and an unconfigured main skill", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "FissureSlamMercenary")
		local profile = build.mercenaryTab.profile
		table.insert(profile.skills, { id = "TectonicSlamFireMercenary", enabled = true, supports = { } })
		local env = calculate()
		assert.is_nil(env.mercenary)
		assert.matches("Skill pool", table.concat(env.mercenaryCalculationErrors or { }, "\n"))

		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", {
			supports = {
				{ id = "AddedLightningHigh", tier = 3 },
				{ id = "AddedLightningMid", tier = 2 },
			},
		})
		env = calculate()
		assert.is_nil(env.mercenary)
		assert.matches("Duplicate support family", table.concat(env.mercenaryCalculationErrors or { }, "\n"))

		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		build.mercenaryTab.profile.mainSkillId = "ZealotryMercenary"
		env = calculate()
		assert.is_nil(env.mercenary)
		assert.matches("Selected Calcs skill is not configured", table.concat(env.mercenaryCalculationErrors or { }, "\n"))
	end)

	it("does not calculate a Mercenary with illegal equipment", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local uniqueBody = {
			id = 9040, name = "Illegal Unique Body", type = "Body Armour", base = { type = "Body Armour" },
			rarity = "UNIQUE", requirements = { str = 1 }, grantedSkills = { }, modList = { },
		}
		build.itemsTab.items[uniqueBody.id] = uniqueBody
		equipmentSlot("Body Armour").selItemId = uniqueBody.id
		local env = calculate()
		assert.is_nil(env.mercenary)
		assert.matches("Body Armour", table.concat(env.mercenaryCalculationErrors or { }, "\n"))

		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local dexHelmet = {
			id = 9043, name = "Dex Helmet", type = "Helmet", base = { type = "Helmet" },
			rarity = "RARE", requirements = { dex = 1 }, grantedSkills = { }, modList = { },
		}
		build.itemsTab.items[dexHelmet.id] = dexHelmet
		equipmentSlot("Helmet").selItemId = dexHelmet.id
		env = calculate()
		assert.is_nil(env.mercenary)
		assert.matches("Helmet", table.concat(env.mercenaryCalculationErrors or { }, "\n"))

		configure("EleBowRanger", "EleBowRangerFire", "BurningArrowMercenary")
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		bow.id = 9044
		build.itemsTab.items[bow.id] = bow
		equipmentSlot("Weapon 1").selItemId = bow.id
		env = calculate()
		assert.is_nil(env.mercenary)
		assert.matches("Weapon 2", table.concat(env.mercenaryCalculationErrors or { }, "\n"))
	end)

	it("leaves an unconfigured Mercenary as a clean no-actor state", function()
		local env = calculate()
		assert.is_nil(env.mercenary)
		assert.is_nil(env.mercenaryCalculationErrors)
	end)

	it("does not calculate a configured Mercenary without its item set", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		assert.is_table(build.mercenaryTab:GetItemSet(false))
		build.mercenaryTab.itemSetId = 99999
		local env = calculate()
		assert.is_nil(env.mercenary)
		assert.is_nil(env.mercenaryMinion)
		assert.is_not_nil(env.mercenaryCalculationErrors)
		assert.matches("No Mercenary item set is available", table.concat(env.mercenaryCalculationErrors, "\n"))
		assert.is_nil(build.calcsTab.calcsEnv.mercenary)
		local _, _, actorOutputs = build.calcsTab:GetMiscCalculator()
		assert.is_nil(actorOutputs.MERCENARY)
	end)

	it("shows and applies Configuration settings required by the Mercenary", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local focusedDamage = {
			name = "Damage", type = "INC", value = 20, source = "Mercenary Config Test", flags = 0, keywordFlags = 0,
			{ type = "Condition", var = "Focused" },
		}
		local helmet = {
			id = 9036, name = "Mercenary Config Test", type = "Helmet", base = { type = "Helmet" }, rarity = "RARE",
			requirements = { str = 1 }, grantedSkills = { }, modList = { focusedDamage },
		}
		build.itemsTab.items[helmet.id] = helmet
		equipmentSlot("Helmet").selItemId = helmet.id

		local env = calculate()
		local baseDamage = env.mercenary.modDB:Sum("INC", nil, "Damage")
		local focusedConditionSource
		for _, mod in ipairs(env.conditionsUsed.Focused or { }) do
			if mod.source == focusedDamage.source then focusedConditionSource = mod.source end
		end
		assert.are.equal(focusedDamage.source, focusedConditionSource)
		assert.is_false(build.configTab.varControls.conditionFocused.shown())
		assert.is_false(build.configTab.varControls.detonateDeadCorpseLife.shown())
		build.configTab:SetViewActor("mercenary")
		assert.is_true(build.configTab.varControls.conditionFocused.shown())
		assert.is_true(build.configTab.varControls.detonateDeadCorpseLife.shown())

		local corpseLifeConfig
		for _, varData in ipairs(configOptions) do
			if varData.var == "detonateDeadCorpseLife" then corpseLifeConfig = varData break end
		end
		assert.is_false(configVisibility.isRelevantForBuild(assert(corpseLifeConfig), build, "player"))
		assert.is_true(configVisibility.isRelevantForBuild(corpseLifeConfig, build, "mercenary"))

		build.configTab:EnsureActorConfig(build.configTab.configSets[build.configTab.activeConfigSetId])
		build.configTab.configSets[build.configTab.activeConfigSetId].actors.mercenary.input.conditionFocused = true
		build.configTab.configSets[build.configTab.activeConfigSetId].actors.mercenary.input.detonateDeadCorpseLife = 12345
		env = calculate()
		assert.is_true(env.mercenary.modDB:GetCondition("Focused"))
		assert.are.equal(baseDamage + focusedDamage.value, env.mercenary.modDB:Sum("INC", nil, "Damage"))
		assert.are.equal(12345, env.mercenary.mainSkill.skillData.corpseLife)
	end)

	it("shows Stationary config from ActorCondition on the actor that uses it", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local stationaryDamage = {
			name = "Damage", type = "INC", value = 20, source = "Mercenary Stationary Test", flags = 0, keywordFlags = 0,
			{ type = "ActorCondition", var = "Stationary" },
		}
		local helmet = {
			id = 9051, name = "Mercenary Stationary Test", type = "Helmet", base = { type = "Helmet" }, rarity = "RARE",
			requirements = { str = 1 }, grantedSkills = { }, modList = { stationaryDamage },
		}
		build.itemsTab.items[helmet.id] = helmet
		equipmentSlot("Helmet").selItemId = helmet.id
		calculate()
		assert.is_false(build.configTab.varControls.conditionStationary.shown())
		build.configTab:SetViewActor("mercenary")
		assert.is_true(build.configTab.varControls.conditionStationary.shown())
	end)

	it("does not treat player Leeching Life as valid from Mercenary Leeching mods", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local leechingDamage = {
			name = "Damage", type = "INC", value = 20, source = "Mercenary Leech Test", flags = 0, keywordFlags = 0,
			{ type = "Condition", var = "Leeching" },
		}
		local helmet = {
			id = 9050, name = "Mercenary Leech Test", type = "Helmet", base = { type = "Helmet" }, rarity = "RARE",
			requirements = { str = 1 }, grantedSkills = { }, modList = { leechingDamage },
		}
		build.itemsTab.items[helmet.id] = helmet
		equipmentSlot("Helmet").selItemId = helmet.id

		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.input.conditionLeechingLife = true
		calculate()

		local leechingLifeConfig, leechingConfig
		for _, varData in ipairs(configOptions) do
			if varData.var == "conditionLeechingLife" then
				leechingLifeConfig = varData
			elseif varData.var == "conditionLeeching" then
				leechingConfig = varData
			end
		end
		assert.is_false(configVisibility.isRelevantForBuild(assert(leechingLifeConfig), build, "player"))
		assert.is_false(configVisibility.isRelevantForBuild(assert(leechingConfig), build, "player"))
		assert.is_true(configVisibility.isRelevantForBuild(leechingConfig, build, "mercenary"))

		configSet.actors.mercenary.input.conditionLeechingLife = true
		build.configTab:SetViewActor("mercenary")
		assert.is_false(configVisibility.isRelevantForBuild(leechingLifeConfig, build, "player"))
		assert.is_true(configVisibility.isRelevantForBuild(leechingLifeConfig, build, "mercenary"))

		build.configTab:SetViewActor("player")
		assert.is_true(build.configTab.varControls.conditionLeechingLife.shown())
		local label = build.configTab.varControls.conditionLeechingLife.label
		if type(label) == "function" then
			label = label()
		end
		assert.matches("%^xDD0022", assert(label))
	end)

	it("applies Vigilant Strike's default cooldown bypass to the Mercenary", function()
		configureSkill("VigilantStrikeMercenary")
		local mace = new("Item"):Item("Rarity: Normal\nDriftwood Club")
		mace.id = 9041
		build.itemsTab.items[mace.id] = mace
		equipmentSlot("Weapon 1").selItemId = mace.id
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		local bypassed = assert(calculate().mercenary)
		configSet.actors.mercenary.input.VigilantStrikeBypassCD = false
		local onCooldown = assert(calculate().mercenary)
		assert.is_true(bypassed.output.Speed > onCooldown.output.Speed)
		build.configTab:SetViewActor("mercenary")
		assert.is_true(build.configTab.varControls.VigilantStrikeBypassCD.shown())
		build.configTab:SetViewActor("player")
		assert.is_false(build.configTab.varControls.VigilantStrikeBypassCD.shown())
	end)

	it("applies Toxic Rain pod overlap to the Mercenary", function()
		configureSkill("ToxicRainMercenary")
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9042, 9043
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id
		local baseline = assert(calculate().mercenary)
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.input.toxicRainPodOverlap = 5
		local overlapped = assert(calculate().mercenary)
		assert.are.equal(5, overlapped.mainSkill.skillData.podOverlapMultiplier)
		assert.is_true(overlapped.output.CombinedDPS > baseline.output.CombinedDPS)
		build.configTab:SetViewActor("mercenary")
		assert.is_true(build.configTab.varControls.toxicRainPodOverlap.shown())
	end)

	it("applies Flame Wall projectile added fire to Mercenary Kinetic Blast of Clustering", function()
		configureSkill("KineticBlastAltMercenary")
		local wand = new("Item"):Item("Rarity: Normal\nDriftwood Wand")
		local shield = new("Item"):Item("Rarity: Normal\nTwig Spirit Shield")
		wand.id, shield.id = 9060, 9061
		build.itemsTab.items[wand.id], build.itemsTab.items[shield.id] = wand, shield
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = wand.id, shield.id
		local profile = build.mercenaryTab.profile
		table.insert(profile.skills, { id = "FlameWallMercenary", enabled = true, count = 1, supports = { } })
		build.mercenaryTab:Changed()
		local baseline = assert(calculate().mercenary)
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.input.flameWallAddedDamage = true
		local flamed = assert(calculate())
		local fireCfg = { flags = ModFlag.Projectile }
		assert.is_true(flamed.mercenary.modDB:GetCondition("FlameWallAddedDamage"))
		assert.is_true(flamed.mercenary.modDB:Sum("BASE", fireCfg, "FireMin") > baseline.modDB:Sum("BASE", fireCfg, "FireMin"))
		assert.is_true(flamed.mercenary.output.CombinedDPS > baseline.output.CombinedDPS)
		build.configTab:SetViewActor("mercenary")
		assert.is_true(build.configTab.varControls.flameWallAddedDamage.shown())
	end)

	it("applies Mercenary Withered stacks to the shared enemy", function()
		configureSkill("WitherTotemMercenary")
		local staff = new("Item"):Item("Rarity: Normal\nGnarled Branch")
		staff.id = 9044
		build.itemsTab.items[staff.id] = staff
		equipmentSlot("Weapon 1").selItemId = staff.id
		local profile = build.mercenaryTab.profile
		table.insert(profile.skills, { id = "EssenceDrainAltMercenary", enabled = true, includeInFullDPS = true, count = 1, supports = { } })
		build.mercenaryTab:Changed()
		assert(calculate())
		assert.is_true(build.configTab.varControls.multiplierWitheredStackCount.shown())
		profile.mainSkillId = "EssenceDrainAltMercenary"
		build.mercenaryTab:Changed()
		local baseline = assert(calculate())
		local baselineDot = baseline.mercenary.output.TotalDot or 0
		build.configTab.input.multiplierWitheredStackCount = 15
		local withered = assert(calculate())
		local witherMods = 0
		for _, mod in ipairs(build.configTab.enemyModList) do
			if mod.name == "Multiplier:WitheredStack" then
				witherMods = witherMods + 1
				assert.are.equal(15, mod.value)
			end
		end
		assert.are.equal(1, witherMods)
		assert.is_not_nil(withered.enemy.modDB.mods["Multiplier:WitheredStack"])
		assert.is_true(withered.enemy.modDB:Sum("INC", nil, "ChaosDamageTaken") > 0)
		assert.is_true((withered.mercenary.output.TotalDot or 0) > baselineDot)
	end)

	it("applies Withered chaos taken once when both actors can wither", function()
		configureSkill("WitherTotemMercenary")
		local staff = new("Item"):Item("Rarity: Normal\nGnarled Branch")
		staff.id = 9045
		build.itemsTab.items[staff.id] = staff
		equipmentSlot("Weapon 1").selItemId = staff.id
		build.skillsTab:PasteSocketGroup("Wither 20/0  1")
		build.configTab.input.multiplierWitheredStackCount = 15
		local env = assert(calculate())
		local witheredSources = 0
		for _, mod in ipairs(env.enemy.modDB.mods["ChaosDamageTaken"] or { }) do
			if mod.source == "Withered" then
				witheredSources = witheredSources + 1
			end
		end
		assert.are.equal(1, witheredSources)
	end)

	it("applies the configured Onslaught buff to Mercenary attack DPS", function()
		configure("EleBowRanger", "EleBowRangerFire", "BurningArrowMercenary")
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9038, 9039
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id

		local baseline = assert(calculate().mercenary.output)
		build.configTab:EnsureActorConfig(build.configTab.configSets[build.configTab.activeConfigSetId])
		build.configTab.configSets[build.configTab.activeConfigSetId].actors.mercenary.input.buffOnslaught = true
		local configured = assert(calculate().mercenary)

		assert.is_true(configured.modDB:GetCondition("Onslaught"))
		assert.is_true(configured.output.Speed > baseline.Speed)
		assert.is_true(configured.output.CombinedDPS > baseline.CombinedDPS)
	end)

	it("scales up to the current area without downscaling high-level Mercenaries", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", { foundAreaLevel = 40 })
		assert.are.equal(40, calculate(30).mercenary.level)
		assert.are.equal(60, calculate(60).mercenary.level)
		build.mercenaryTab.profile.foundAreaLevel = 68
		assert.are.equal(68, calculate(68).mercenary.level)
		build.mercenaryTab.profile.foundAreaLevel = 80
		assert.are.equal(80, calculate(90).mercenary.level)
	end)

	it("calculates unarmed damage at found-area level 100", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", { foundAreaLevel = 100 })
		local env = calculate(85)
		assert.are.equal(100, env.mercenary.level)
		assert.is_number(env.mercenary.averageDamage)
		assert.is_true(env.mercenary.averageDamage > 0)
	end)

	it("fails closed on found-area levels above 100", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", { foundAreaLevel = 101 })
		local env = calculate(85)
		assert.is_nil(env.mercenary)
		assert.matches("Found%-area level must be an integer between 1 and 100", table.concat(env.mercenaryCalculationErrors or { }, "\n"))
	end)

	it("uses base gem behavior and both Mercenary and inherent skill levels for base spell damage", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", { foundAreaLevel = 82 })
		local level82Skill = assert(calculate(90).mercenary.mainSkill)
		assert.are.equal(26, level82Skill.activeEffect.level)
		assert.is_true(level82Skill.skillFlags.trap)
		assert.is_nil(level82Skill.skillFlags.selfCast)
		assert.are.equal(1260, level82Skill.skillData.LightningMin)
		assert.are.equal(3780, level82Skill.skillData.LightningMax)

		build.mercenaryTab.profile.foundAreaLevel = 83
		local level83Skill = assert(calculate(90).mercenary.mainSkill)
		assert.are.equal(26, level83Skill.activeEffect.level)
		assert.are.equal(1329, level83Skill.skillData.LightningMin)
		assert.are.equal(3986, level83Skill.skillData.LightningMax)

		build.mercenaryTab.profile.foundAreaLevel = 84
		assert.are.equal(27, assert(calculate(90).mercenary.mainSkill).activeEffect.level)
	end)

	it("calculates Mercenary-exclusive base spell damage and explicit hit parts", function()
		configure("Crit1HShadow", "Crit1HShadowPhysSpell", "DonutCircleMercenary", { foundAreaLevel = 83, skillPart = 1 })
		local outer = calculate(83).mercenary
		assert.is_true(outer.mainSkill.skillFlags.hit)
		assert.is_true(outer.mainSkill.skillFlags.area)
		assert.are.equal(3167, outer.mainSkill.skillData.PhysicalMin)
		assert.are.equal(3500, outer.mainSkill.skillData.PhysicalMax)
		local outerDamageMore = outer.mainSkill.skillModList:More(outer.mainSkill.skillCfg, "Damage")
		build.mercenaryTab.profile.skills[1].skillPart = 2
		local centre = calculate(83).mercenary
		assert.are.equal("Centre", centre.mainSkill.skillPartName)
		assert.are.near(outerDamageMore * 1.5, centre.mainSkill.skillModList:More(centre.mainSkill.skillCfg, "Damage"), 10 ^ -9)

		configure("PhysConvertTemplar", "PhysConvertTemplarFire", "HolyFireMortarMercenary", { foundAreaLevel = 83, skillPart = 1 })
		local first = calculate(83).mercenary
		local firstHitDamageMore = first.mainSkill.skillModList:More(first.mainSkill.skillCfg, "Damage")
		build.mercenaryTab.profile.skills[1].skillPart = 2
		local secondHit = calculate(83).mercenary
		assert.are.equal("Second Hit", secondHit.mainSkill.skillPartName)
		assert.are.near(firstHitDamageMore * 0.4, secondHit.mainSkill.skillModList:More(secondHit.mainSkill.skillCfg, "Damage"), 10 ^ -9)
	end)

	it("applies extracted Mercenary-exclusive buffs and debuffs", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderNonSlam", "WindSlashMercenary", { foundAreaLevel = 83 })
		local baseline = calculate(83).mercenary
		local baseDamage = baseline.modDB:Sum("INC", nil, "Damage")
		local baseSpeed = baseline.modDB:Sum("INC", nil, "Speed")
		local baseMovementSpeed = baseline.modDB:Sum("INC", nil, "MovementSpeed")
		table.insert(build.mercenaryTab.profile.skills, { id = "EnrageMercenary", enabled = true, count = 1, supports = { } })
		local enraged = calculate(83).mercenary
		assert.is_true(enraged.modDB.conditions.AffectedByEnrage)
		assert.are.equal(baseDamage + 35, enraged.modDB:Sum("INC", nil, "Damage"))
		assert.are.equal(baseSpeed + 40, enraged.modDB:Sum("INC", nil, "Speed"))
		assert.are.equal(baseMovementSpeed + 60, enraged.modDB:Sum("INC", nil, "MovementSpeed"))

		configure("Crit1HShadow", "Crit1HShadowPhysSpell", "TemporalAnomalyMercenary", { foundAreaLevel = 83 })
		assert.are.equal(-25, calculate(83).enemy.modDB:Sum("INC", nil, "ActionSpeed"))

		configure("MeleeAOEMarauder", "MeleeAOEMarauderPhysSlam", "VaalVitalityMercenary", { foundAreaLevel = 83 })
		local vitality = calculate(83)
		assert.are.equal(26, vitality.mercenary.mainSkill.activeEffect.level)
		assert.is_true(vitality.player.modDB.conditions.AffectedByVaalVitality)
		assert.are.near(580 / 60, vitality.player.modDB:Sum("BASE", nil, "LifeRegenPercent"), 10 ^ -9)
	end)

	it("uses extracted Mercenary minion skills at the summoned actor level", function()
		configure("AurasMinionsTemplar", "AurasMinionsTemplarSmite", "SSMHolySpectresMercenary", {
			foundAreaLevel = 83,
			includeInFullDPS = true,
			count = 4,
			skillMinionSkill = 2,
		})
		local mace = new("Item"):Item("Rarity: Normal\nDriftwood Club")
		local shield = new("Item"):Item("Rarity: Normal\nTwig Spirit Shield")
		mace.id, shield.id = 9050, 9051
		build.itemsTab.items[mace.id], build.itemsTab.items[shield.id] = mace, shield
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = mace.id, shield.id
		local env = calculate(83)
		local summon = env.mercenary.mainSkill
		local fireball = env.mercenaryMinion.mainSkill
		assert.are.equal(83, env.mercenaryMinion.level)
		assert.are.equal("HolyFireElementalFireball", fireball.activeEffect.grantedEffect.id)
		assert.are.equal(2, fireball.activeEffect.level)
		assert.are.equal(1654, fireball.skillData.FireMin)
		assert.are.equal(2561, fireball.skillData.FireMax)
		assert.are.equal(2, summon.activeEffect.srcInstance.skillMinionSkill)
		assert.is_true(env.mercenaryMinion.output.TotalDPS > 0)
		assert.are.near(env.mercenaryMinion.output.TotalDPS * 4 + env.mercenary.output.FullDotDPS, env.mercenary.output.FullDPS, 10 ^ -6)

		equipmentSlot("Weapon 1").selItemId = 0
		equipmentSlot("Weapon 2").selItemId = 0
		configure("ChaosMinionWitch", "ChaosMinionWitchChaosHit", "SSMMercenarySoulrendOrb", {
			foundAreaLevel = 83,
			skillMinionSkill = 2,
		})
		env = calculate(83)
		assert.are.equal("GSRitualChaosPulse", env.mercenaryMinion.mainSkill.activeEffect.grantedEffect.id)
		assert.is_true(env.mercenaryMinion.modDB:Flag(nil, "Condition:CannotBeDamaged"))
		assert.is_true(env.mercenaryMinion.modDB:Flag(nil, "AlliesAurasCannotAffectSelf"))
	end)

	it("fails closed when an extracted Mercenary minion has no skill data", function()
		configure("ChaosMinionWitch", "ChaosMinionWitchInstability", "SSMMercenaryRelic")
		local dagger = new("Item"):Item("Rarity: Normal\nGlass Shank")
		local shield = new("Item"):Item("Rarity: Normal\nTwig Spirit Shield")
		dagger.id, shield.id = 9052, 9053
		build.itemsTab.items[dagger.id], build.itemsTab.items[shield.id] = dagger, shield
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = dagger.id, shield.id
		local env = calculate(83)
		assert.is_nil(env.mercenary)
		assert.matches("Unholy Relic has no exported skills", table.concat(env.mercenaryCalculationErrors or { }, "\n"))
	end)

	it("calculates exported permanent-Mercenary bases and hidden passives", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local env = calculate(83)
		local mercenary = assert(env.mercenary)
		assert.are.equal(build.data.monsterConstants["base_critical_strike_multiplier"] - 100, mercenary.modDB:Sum("BASE", nil, "CritMultiplier"))
		assert.are.equal(build.data.monsterConstants["critical_ailment_dot_multiplier_+"], mercenary.modDB:Sum("BASE", { skillCond = { CriticalStrike = true } }, "DotMultiplier"))
		assert.are.near(298.29000854492, mercenary.averageDamage, 10 ^ -9)
		assert.are.equal(3320, mercenary.output.Life)
		assert.are.near(713.8, mercenary.output.LifeRegen, 10 ^ -9)
		assert.are.equal(150, mercenary.modDB:Sum("INC", nil, "Life"))
		assert.are.equal(100, mercenary.modDB:Sum("INC", nil, "Armour"))
		assert.are.equal(295, mercenary.modDB:Sum("INC", nil, "Damage"))
		assert.are.equal(208, mercenary.modDB:Sum("BASE", nil, "Str"))
		assert.are.equal(21, mercenary.modDB:Sum("BASE", nil, "Dex"))
		assert.are.equal(21, mercenary.modDB:Sum("BASE", nil, "Int"))
		local penalty = MercenaryTools.permanentDamageMore(mercenary.level, build.data.mercenaries.permanentMercenaryDamageMore)
		assert.are.near(1 + penalty / 100, mercenary.modDB:More(nil, "Damage"), 10 ^ -9)
	end)

	it("tapers permanent Mercenary and Mercenary-minion damage between levels 45 and 83", function()
		local function sourceMore(modDB)
			for _, value in ipairs(modDB:Tabulate("MORE", nil, "Damage")) do
				if value.mod.source == "Permanent Mercenary" then
					return value.mod.value
				end
			end
			return 0
		end
		local expected = { [44] = 0, [45] = 0, [46] = -1, [82] = -29, [83] = -30 }
		for _, level in ipairs({ 44, 45, 46, 82, 83 }) do
			configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", {
				foundAreaLevel = level,
			})
			local env = calculate(level)
			assert.are.equal(level, env.mercenary.level)
			assert.are.equal(expected[level], sourceMore(env.mercenary.modDB), "skill penalty at "..level)
			assert.is_true(env.mercenary.output.CombinedDPS > 0)
		end
		for _, level in ipairs({ 44, 45, 46, 82, 83 }) do
			configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary", {
				foundAreaLevel = level,
			})
			local env = calculate(level)
			assert.is_table(env.mercenaryMinion)
			assert.are.equal(expected[level], sourceMore(env.mercenaryMinion.modDB), "minion penalty at "..level)
			assert.is_true(env.mercenaryMinion.output.TotalDPS > 0)
		end
	end)

	it("calculates Corrupted Blood from allied-monster damage and hit rate", function()
		configure("MiscScion", "MiscScionPhysDot", "BladeVortexAltMercenary", { includeInFullDPS = true })
		local env = calculate()
		local activeSkill = env.mercenary.mainSkill
		assert.are.near(env.mercenary.averageDamage * 366 / 6000, activeSkill.skillData.PhysicalDot, 10 ^ -9)
		assert.are.equal(5, activeSkill.skillData.corruptedBloodStacks)
		assert.is_true(env.mercenary.output.CorruptingBloodDPS > 0)
		assert.are.near(env.mercenary.output.CombinedDPS, env.mercenary.output.FullDPS, 10 ^ -6)
	end)

	it("calculates Infernal Cry's on-death fire explosion", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local mercenary = assert(calculate(83).mercenary)
		assert.is_true(mercenary.mainSkill.skillData.explodeCorpse)
		assert.are.equal("Fire", mercenary.mainSkill.skillData.corpseExplosionDamageType)
		assert.are.near(0.08, mercenary.mainSkill.skillData.corpseExplosionLifeMultiplier, 10 ^ -9)
		-- Found-area 68 is inside the 3.29.1 taper, so this hit includes -18% more Damage
		-- rather than the -30% endgame cap.
		assert.are.near(1984.5, mercenary.output.AverageHit, 10 ^ -9)
	end)

	it("uses the compared slot actor with separate player and Mercenary equipment", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local env = calculate()
		local compare, playerBase, actorBases = build.calcsTab.calcs.getMiscCalculator(build)
		assert.are.equal(env.player.output.Life, playerBase.Life)
		assert.are.equal(env.mercenary.output.Life, actorBases.MERCENARY.Life)
		assert.are.equal(env.player.output.Life, compare({ }).Life)
		assert.are.equal(env.mercenary.output.Life, compare({ comparisonActor = "MERCENARY" }).Life)
	end)

	it("rejects a missing explicit override item set id", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local compare = build.calcsTab.calcs.getMiscCalculator(build)
		local ok, err = pcall(compare, { itemSetId = 99999 })
		assert.is_true(not ok)
		assert.matches("Unknown item set id", tostring(err))
		assert.is_number(compare({ }).Life)
	end)

	it("uses player, Animate Guardian, and Mercenary equipment simultaneously", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local itemsTab = build.itemsTab
		local guardianSet = itemsTab:NewItemSet()
		guardianSet.title = "Animate Guardian"
		table.insert(itemsTab.itemSetOrderList, guardianSet.id)
		local mercenarySet = assert(build.mercenaryTab:GetItemSet(true))

		local playerHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		local guardianHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		local mercenaryHelmet = new("Item"):Item("Rarity: Normal\nLeather Cap")
		itemsTab:AddItem(playerHelmet, true)
		itemsTab:AddItem(guardianHelmet, true)
		itemsTab:AddItem(mercenaryHelmet, true)
		itemsTab.activeItemSet.Helmet.selItemId = playerHelmet.id
		guardianSet.Helmet.selItemId = guardianHelmet.id
		mercenarySet["Helmet"].selItemId = mercenaryHelmet.id

		build.skillsTab:PasteSocketGroup("Animate Guardian 20/0  1")
		local guardianGroup = build.skillsTab.socketGroupList[#build.skillsTab.socketGroupList]
		build.mainSocketGroup = #build.skillsTab.socketGroupList
		local guardianGem
		for _, gem in ipairs(guardianGroup.gemList) do
			if gem.nameSpec == "Animate Guardian" or gem.gemData and gem.gemData.name == "Animate Guardian" or gem.grantedEffect and gem.grantedEffect.name == "Animate Guardian" then
				guardianGem = gem
				break
			end
		end
		guardianGem = assert(guardianGem)
		guardianGem.skillMinionItemSet = guardianSet.id
		guardianGem.skillMinionItemSetCalcs = guardianSet.id

		local env = calculate()
		assert.are.equal(playerHelmet, env.player.itemList.Helmet)
		assert.are.equal(guardianHelmet, env.minion.itemList.Helmet)
		assert.are.equal(mercenaryHelmet, env.mercenary.itemList.Helmet)
	end)

	it("uses the active Mercenary equipment item set for calculations", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local itemsTab = build.itemsTab
		local firstSet = assert(build.mercenaryTab:GetItemSet(true))
		local secondSet = itemsTab:NewItemSet()
		secondSet.title = "Alternate Equipment"
		table.insert(itemsTab.itemSetOrderList, secondSet.id)
		local firstHelmet = new("Item"):Item("Rarity: Normal\nLeather Cap")
		local secondHelmet = new("Item"):Item("Rarity: Normal\nLeather Cap")
		itemsTab:AddItem(firstHelmet, true)
		itemsTab:AddItem(secondHelmet, true)
		firstSet["Helmet"].selItemId = firstHelmet.id
		secondSet["Helmet"].selItemId = secondHelmet.id

		build.mercenaryTab:SetItemSet(secondSet.id)
		local env = calculate()
		assert.are.equal(secondSet.id, build.mercenaryTab.itemSetId)
		assert.are.equal(secondHelmet, env.mercenary.itemList.Helmet)
	end)

	it("uses the dedicated Mercenary set for trade stat replacements", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local itemsTab = build.itemsTab
		local mercenarySet = assert(build.mercenaryTab:GetItemSet(true))
		local currentHelmet = new("Item"):Item("Rarity: Normal\nLeather Cap")
		itemsTab:AddItem(currentHelmet, true)
		mercenarySet["Helmet"].selItemId = currentHelmet.id

		local tradeQuery = itemsTab.tradeQuery
		tradeQuery.tradeQueryGenerator = new("TradeQueryGenerator"):TradeQueryGenerator(itemsTab)
		tradeQuery.slotTables[1] = { slotName = "Helmet", itemSetId = mercenarySet.id }
		tradeQuery.resultTbl[1] = { { item_string = [[Rarity: Rare
Mercenary's Test
Leather Cap
--------
+100 to maximum Life]] } }
		tradeQuery.statSortSelectionList = { { stat = "Life", weightMult = 1 } }

		calculate()
		local _, _, actorOutputs = build.calcsTab:GetMiscCalculator()
		local evaluation = tradeQuery:GetResultEvaluation(1, 1)
		assert.is_number(evaluation[1].output.Life)
		assert.is_true(evaluation[1].output.Life > actorOutputs.MERCENARY.Life)
		assert.is_true(evaluation[1].weight > 0)
	end)

	it("keeps the default comparison baseline on the player while Mercenary gear is visible", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local mercSet = assert(build.mercenaryTab:GetItemSet(true))
		calculate()
		assert(build.itemsTab:SetViewItemSet(mercSet.id))
		build.calcsTab:BuildOutput()
		local calcFunc, calcBase, actorOutputs = build.calcsTab:GetMiscCalculator()
		assert.are.equal(actorOutputs.PLAYER, calcBase)
		assert.are.equal(calcFunc().Life, calcBase.Life)
		assert.is_truthy(actorOutputs.MERCENARY)
		assert.are.equal(calcFunc({ comparisonActor = "MERCENARY" }).Life, actorOutputs.MERCENARY.Life)
	end)

	it("replaces Mercenary helmet life from a visible-set override without changing the player", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local itemsTab = build.itemsTab
		local mercSet = assert(build.mercenaryTab:GetItemSet(true))
		local playerHelmet = new("Item"):Item([[Rarity: Rare
Player Helmet
Iron Hat
--------
+1000 to maximum Life]])
		local mercHelmet = new("Item"):Item("Rarity: Normal\nLeather Cap")
		local replacementHelmet = new("Item"):Item([[Rarity: Rare
Replacement Helmet
Leather Cap
--------
+100 to maximum Life]])
		itemsTab:AddItem(playerHelmet, true)
		itemsTab:AddItem(mercHelmet, true)
		itemsTab:AddItem(replacementHelmet, true)
		itemsTab.activeItemSet.Helmet.selItemId = playerHelmet.id
		mercSet.Helmet.selItemId = mercHelmet.id
		calculate()
		assert(itemsTab:SetViewItemSet(mercSet.id))
		local calcFunc, _, actorOutputs = build.calcsTab:GetMiscCalculator()
		local playerReplacement = calcFunc({
			repSlotName = "Helmet",
			repItem = replacementHelmet,
		})
		local mercReplacement = calcFunc(itemsTab:ItemCalculationOverride("Helmet", replacementHelmet))
		assert.is_true(playerReplacement.Life < actorOutputs.PLAYER.Life)
		assert.is_true(mercReplacement.Life > actorOutputs.MERCENARY.Life)
		assert.are_not.equal(playerReplacement.Life, mercReplacement.Life)
	end)

	it("replaces only Mercenary helmet life when the shared active set is compared as Mercenary", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		assert(build.mercenaryTab:SetItemSet(playerSetId, false))
		local playerHelmet = new("Item"):Item([[Rarity: Rare
Player Helmet
Iron Hat
--------
+100 to maximum Life]])
		local replacementHelmet = new("Item"):Item([[Rarity: Rare
Replacement Helmet
Iron Hat
--------
+1000 to maximum Life]])
		itemsTab:AddItem(playerHelmet, true)
		itemsTab:AddItem(replacementHelmet, true)
		itemsTab.activeItemSet.Helmet.selItemId = playerHelmet.id
		calculate()
		assert(itemsTab:SetViewItemSet(playerSetId, "MERCENARY"))
		local _, _, actorOutputs = build.calcsTab:GetMiscCalculator()
		local env = build.calcsTab.calcs.initEnv(build, "CALCULATOR", itemsTab:ItemCalculationOverride("Helmet", replacementHelmet))
		build.calcsTab.calcs.perform(env)
		assert.are.equal(actorOutputs.PLAYER.Life, env.player.output.Life)
		assert.is_true(env.mercenary.output.Life > actorOutputs.MERCENARY.Life)
	end)

	it("replaces only player helmet life when the shared active set is compared as the player", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local itemsTab = build.itemsTab
		local playerSetId = itemsTab.activeItemSetId
		assert(build.mercenaryTab:SetItemSet(playerSetId, false))
		local playerHelmet = new("Item"):Item([[Rarity: Rare
Player Helmet
Iron Hat
--------
+100 to maximum Life]])
		local replacementHelmet = new("Item"):Item([[Rarity: Rare
Replacement Helmet
Iron Hat
--------
+1000 to maximum Life]])
		itemsTab:AddItem(playerHelmet, true)
		itemsTab:AddItem(replacementHelmet, true)
		itemsTab.activeItemSet.Helmet.selItemId = playerHelmet.id
		calculate()
		assert(itemsTab:SetViewItemSet(playerSetId, "PLAYER"))
		local _, _, actorOutputs = build.calcsTab:GetMiscCalculator()
		local env = build.calcsTab.calcs.initEnv(build, "CALCULATOR", itemsTab:ItemCalculationOverride("Helmet", replacementHelmet))
		build.calcsTab.calcs.perform(env)
		assert.is_true(env.player.output.Life > actorOutputs.PLAYER.Life)
		assert.are.equal(actorOutputs.MERCENARY.Life, env.mercenary.output.Life)
	end)

	it("uses the selected Animate Guardian set for trade stat replacements", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local itemsTab = build.itemsTab
		local configuredGuardianSet = itemsTab:NewItemSet()
		configuredGuardianSet.title = "Configured Guardian"
		table.insert(itemsTab.itemSetOrderList, configuredGuardianSet.id)
		local selectedGuardianSet = itemsTab:NewItemSet()
		selectedGuardianSet.title = "Trader Guardian"
		table.insert(itemsTab.itemSetOrderList, selectedGuardianSet.id)

		local configuredHelmet = new("Item"):Item("Rarity: Normal\nIron Hat")
		local selectedHelmet = new("Item"):Item([[Rarity: Rare
Selected Guardian Helmet
Iron Hat
--------
+10 to maximum Life]])
		local replacementHelmet = new("Item"):Item([[Rarity: Rare
Replacement Guardian Helmet
Iron Hat
--------
+100 to maximum Life]])
		itemsTab:AddItem(configuredHelmet, true)
		itemsTab:AddItem(selectedHelmet, true)
		itemsTab:AddItem(replacementHelmet, true)
		configuredGuardianSet.Helmet.selItemId = configuredHelmet.id
		selectedGuardianSet.Helmet.selItemId = selectedHelmet.id

		build.skillsTab:PasteSocketGroup("Animate Guardian 20/0  1")
		local guardianGroup = build.skillsTab.socketGroupList[#build.skillsTab.socketGroupList]
		build.mainSocketGroup = #build.skillsTab.socketGroupList
		local guardianGem
		for _, gem in ipairs(guardianGroup.gemList) do
			if gem.nameSpec == "Animate Guardian" or gem.gemData and gem.gemData.name == "Animate Guardian" or gem.grantedEffect and gem.grantedEffect.name == "Animate Guardian" then
				guardianGem = gem
				break
			end
		end
		guardianGem = assert(guardianGem)
		guardianGem.skillMinionItemSet = configuredGuardianSet.id
		guardianGem.skillMinionItemSetCalcs = configuredGuardianSet.id

		calculate()
		itemsTab:SetViewItemSet(selectedGuardianSet.id)
		local tradeQueryGenerator = new("TradeQueryGenerator"):TradeQueryGenerator(itemsTab.tradeQuery)
		tradeQueryGenerator:StartQuery(itemsTab.slots.Helmet, {
			itemSetId = selectedGuardianSet.id,
			influence1 = 1,
			influence2 = 1,
			statWeights = { { stat = "Life", weightMult = 1 } },
			requiredMods = { },
		})
		tradeQueryGenerator.calcContext.co = nil
		local baseOutput = tradeQueryGenerator.calcContext.baseOutput
		local replacementOutput = tradeQueryGenerator.calcContext.calcFunc({
			itemSetId = selectedGuardianSet.id,
			comparisonActor = "PLAYER",
			repSlotName = "Helmet",
			repItem = replacementHelmet,
		})

		assert.are.equal(baseOutput.Life, replacementOutput.Life)
		assert.is_true(replacementOutput.Minion.Life > baseOutput.Minion.Life)
	end)

	it("calculates every selectable exported inherent skill and support without runtime errors", function()
		local function contains(values, wanted)
			for _, value in ipairs(values or { }) do if value == wanted then return true end end
			return false
		end
		local buildForSkill = { }
		for _, buildId in ipairs(build.data.mercenaries.buildOrder) do
			local mercenaryBuild = build.data.mercenaries.builds[buildId]
			if #mercenaryBuild.weaponTypes > 0 then
				for _, skillId in ipairs(mercenaryBuild.skillIds) do
					for _, pool in ipairs(mercenaryBuild.skillPools) do
						if contains(pool.skillIds, skillId) and (not pool.countMax or pool.countMax > 0) then
							buildForSkill[skillId] = buildForSkill[skillId] or buildId
							break
						end
					end
				end
			end
		end

		local baseNameByType = { }
		local function lowestBaseName(itemType)
			if baseNameByType[itemType] then return baseNameByType[itemType] end
			local bestName, bestLevel
			for name, base in pairs(build.data.itemBases) do
				if base.type == itemType then
					local level = base.req and base.req.level or 0
					if not bestLevel or level < bestLevel or level == bestLevel and name < bestName then
						bestName, bestLevel = name, level
					end
				end
			end
			baseNameByType[itemType] = assert(bestName, itemType)
			return bestName
		end

		local nextItemId = 990000
		local function equip(slotName, itemType)
			if not itemType or itemType == "None" then return end
			local item = new("Item"):Item("Rarity: Normal\n"..lowestBaseName(itemType))
			item.id = nextItemId
			nextItemId = nextItemId + 1
			build.itemsTab.items[item.id] = item
			equipmentSlot(slotName).selItemId = item.id
		end

		build.configTab.input.enemyLevel = 83
		build.configTab:BuildModList()
		build.mercenaryTab.profile.buildId = build.data.mercenaries.buildOrder[1]
		build.mercenaryTab:Changed()
		local skillIds = { }
		for skillId in pairs(buildForSkill) do table.insert(skillIds, skillId) end
		table.sort(skillIds)
		local testedSupports = { }
		local testedSupportCount = 0
		local inheritedFlagBySkillType = {
			[SkillType.RemoteMined] = "mine",
			[SkillType.SummonsTotem] = "totem",
			[SkillType.Trapped] = "trap",
		}
		for _, skillId in ipairs(skillIds) do
			equipmentSlot("Weapon 1").selItemId = 0
			equipmentSlot("Weapon 2").selItemId = 0
			local buildId = buildForSkill[skillId]
			local mercenaryBuild = build.data.mercenaries.builds[buildId]
			equip("Weapon 1", mercenaryBuild.weaponConfiguration.mainHandTypes[1])
			if mercenaryBuild.weaponConfiguration.offHandRequired then equip("Weapon 2", mercenaryBuild.weaponConfiguration.offHandTypes[1]) end
			build.mercenaryTab.profile = {
				classId = mercenaryBuild.classId,
				buildId = buildId,
				foundAreaLevel = 68,
				mainSkillId = skillId,
				lifeComparison = "AUTO",
				skills = { { id = skillId, enabled = true, includeInFullDPS = true, count = 1, supports = { } } },
			}
			build.spec.modFlag = true
			build.buildFlag = true
			local ok, errorMessage = xpcall(function() build.calcsTab:BuildOutput() end, debug.traceback)
			assert.is_true(ok, skillId..": "..tostring(errorMessage))
			local env = build.calcsTab.mainEnv
			local minionId = build.data.mercenaries.summonedMinions[skillId]
			local noFallbackMinion = minionId and build.data.minions[minionId].noFallbackSkill
			if noFallbackMinion then
				assert.is_nil(env.mercenary, skillId)
				assert.matches("has no exported skills", table.concat(env.mercenaryCalculationErrors or { }, "\n"), skillId)
			else
				assert.is_table(env.mercenary, skillId)
				assert.is_table(env.mercenary.mainSkill, skillId)
				for skillType, flag in pairs(inheritedFlagBySkillType) do
					if env.mercenary.mainSkill.skillTypes[skillType] then assert.is_true(env.mercenary.mainSkill.skillFlags[flag], skillId.." must inherit "..flag) end
				end
				if skillId == "ToxicRainMercenary" then assert.is_true(env.mercenary.mainSkill.skillFlags.projectile) end
				for _, supportId in ipairs(build.data.mercenaries.skills[skillId].possibleSupportIds) do
					if not testedSupports[supportId] then
						local support = build.data.mercenaries.supports[supportId]
						build.mercenaryTab.profile.skills[1].supports = { { id = supportId, tier = support.variant } }
						build.spec.modFlag = true
						build.buildFlag = true
						ok, errorMessage = xpcall(function() build.calcsTab:BuildOutput() end, debug.traceback)
						assert.is_true(ok, supportId.." on "..skillId..": "..tostring(errorMessage))
						assert.is_table(build.calcsTab.mainEnv.mercenary, supportId.." on "..skillId)
						testedSupports[supportId] = true
						testedSupportCount = testedSupportCount + 1
					end
				end
			end
		end
		assert.are.equal(269, #skillIds)
		assert.are.equal(261, testedSupportCount)
	end)

	it("uses player-style charge bonuses", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local env = calculate()
		local modDB = env.mercenary.modDB
		local cfg = env.mercenary.mainSkill.skillCfg
		local constants = build.data.characterConstants
		local function chargeMod(modType, name, multiplier)
			local charges = modDB.multipliers[multiplier] or 0
			modDB.multipliers[multiplier] = charges + 1
			for _, value in ipairs(modDB:Tabulate(modType, cfg, name)) do
				for _, tag in ipairs(value.mod) do
					if tag.type == "Multiplier" and tag.var == multiplier then
						local oneMoreCharge = modDB:EvalMod(value.mod, cfg)
						modDB.multipliers[multiplier] = charges + 2
						local delta = modDB:EvalMod(value.mod, cfg) - oneMoreCharge
						modDB.multipliers[multiplier] = charges
						return delta
					end
				end
			end
			modDB.multipliers[multiplier] = charges
			error("Missing "..multiplier.." bonus for "..name)
		end

		assert.are.near(constants["critical_strike_chance_+%_per_power_charge"], chargeMod("INC", "CritChance", "PowerCharge"), 10 ^ -9)
		assert.are.near(constants["object_inherent_damage_+%_final_per_frenzy_charge"], chargeMod("MORE", "Damage", "FrenzyCharge"), 10 ^ -9)
		assert.are.near(constants["physical_damage_reduction_%_per_endurance_charge"], chargeMod("BASE", "PhysicalDamageReduction", "EnduranceCharge"), 10 ^ -9)
	end)

	it("applies Mercenary Life and Damage small passives to the actor and its minion", function()
		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary")
		local baseline = calculate()
		local mercenaryLife = baseline.mercenary.modDB:Sum("INC", nil, "Life")
		local minionLife = baseline.mercenaryMinion.modDB:Sum("INC", nil, "Life")
		local function hasDamageSmallPassive(modDB)
			for _, value in ipairs(modDB:Tabulate("INC", nil, "Damage")) do
				if value.mod.value == 15 then return true end
			end
			return false
		end
		assert.is_true(hasDamageSmallPassive(baseline.mercenary.modDB))
		assert.is_true(hasDamageSmallPassive(baseline.mercenaryMinion.modDB))

		allocate("Mercenary Life, Light Radius")
		local env = calculate()
		assert.are.equal(mercenaryLife + 15, env.mercenary.modDB:Sum("INC", nil, "Life"))
		assert.are.equal(minionLife + 15, env.mercenaryMinion.modDB:Sum("INC", nil, "Life"))
	end)

	it("routes Mercenary auras and creates Mercenary minions", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "ZealotryMercenary")
		local auraEnv = calculate()
		assert.is_true(auraEnv.player.modDB.conditions.AffectedByZealotry)
		build.skillsTab:PasteSocketGroup("Summon Raging Spirit 20/0  1")
		auraEnv = calculate()
		assert.is_true(auraEnv.minion.modDB.conditions.AffectedByZealotry)

		build.skillsTab:PasteSocketGroup("Arc 20/0  1")
		build.skillsTab.socketGroupList[#build.skillsTab.socketGroupList].includeInFullDPS = true
		build.mercenaryTab.profile.skills[1].enabled = false
		build.mercenaryTab:Changed()
		local playerFullDPSWithoutMercenaryAura = calculate().player.output.FullDPS
		build.mercenaryTab.profile.skills[1].enabled = true
		build.mercenaryTab:Changed()
		auraEnv = calculate()
		assert.is_true(auraEnv.player.modDB.conditions.AffectedByZealotry)
		assert.is_true(auraEnv.player.output.FullDPS > playerFullDPSWithoutMercenaryAura)

		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary")
		local minionEnv = calculate()
		assert.is_table(minionEnv.mercenaryMinion)
		assert.is_table(minionEnv.mercenary.mainSkill.minion)
		assert.are.equal(minionEnv.mercenary, minionEnv.mercenaryMinion.parent)
	end)

	it("routes Mercenary warcries to its own created minion", function()
		configure("AurasMinionsTemplar", "AurasMinionsTemplarSpectres", "AbsolutionMercenary")
		table.insert(build.mercenaryTab.profile.skills, {
			id = "BattlemagesCryMercenary",
			enabled = true,
			count = 1,
			supports = { },
		})
		local env = calculate()
		assert.is_table(env.mercenaryMinion)
		local affectedByBattlemagesCry = false
		for condition in pairs(env.mercenaryMinion.modDB.conditions) do
			if condition:find("Battlemage", 1, true) then affectedByBattlemagesCry = true break end
		end
		assert.is_true(affectedByBattlemagesCry)
	end)

	it("grants Enduring Cry charges to allied players", function()
		configure("MeleeStrikesMarauder", "MeleeStrikesMaraduerPhys", "EnduringCryMercenary")
		local env = calculate()
		assert.is_true(env.player.modDB:Flag(nil, "UseEnduranceCharges"))
		assert.are.equal(3, env.player.modDB:Override(nil, "EnduranceCharges"))
		assert.are.near(10, env.player.modDB:Sum("BASE", nil, "LifeRegenPercent"), 10 ^ -9)
	end)

	it("applies player Rallying Cry weapon damage to the Mercenary", function()
		local weapon = new("Item"):Item([[Rarity: Rare
Rallying Test Sword
Rusted Sword
--------
Adds 500 to 500 Physical Damage]])
		build.itemsTab:AddItem(weapon, true)
		build.itemsTab.activeItemSet["Weapon 1"].selItemId = weapon.id
		build.skillsTab:PasteSocketGroup("Rallying Cry 20/0  1")
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local env = calculate()
		assert.is_true(rallyingWeaponFlat(env.mercenary, "PhysicalMin") > 0)
		assert.is_true(rallyingWeaponFlat(env.mercenary, "PhysicalMax") > 0)
	end)

	it("applies Mercenary Rallying Cry weapon damage to the player", function()
		configure("MeleeAOEStrikeDuelist", "MeleeAOEStrikeDuelistCyclone", "RallyingCryMercenary")
		local weapon = new("Item"):Item([[Rarity: Rare
Rallying Test Greatsword
Corroded Blade
--------
Adds 500 to 500 Physical Damage]])
		build.itemsTab:AddItem(weapon, true)
		equipmentSlot("Weapon 1").selItemId = weapon.id
		local env = calculate()
		assert.is_true(rallyingWeaponFlat(env.player, "PhysicalMin") > 0)
		assert.is_true(rallyingWeaponFlat(env.player, "PhysicalMax") > 0)
		assert.are.equal(0, rallyingWeaponFlat(env.mercenary, "PhysicalMin"))
	end)

	it("applies Rallying Cry's extra minion effect to Mercenary-created minions", function()
		local weapon = new("Item"):Item([[Rarity: Rare
Rallying Test Sword
Rusted Sword
--------
Adds 500 to 500 Physical Damage]])
		build.itemsTab:AddItem(weapon, true)
		build.itemsTab.activeItemSet["Weapon 1"].selItemId = weapon.id
		build.skillsTab:PasteSocketGroup("Rallying Cry 20/0  1")
		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary")
		local env = calculate()
		local mercenaryFlat = rallyingWeaponFlat(env.mercenary, "PhysicalMin")
		local minionFlat = rallyingWeaponFlat(env.mercenaryMinion, "PhysicalMin")
		assert.is_true(mercenaryFlat > 0)
		assert.is_true(minionFlat > mercenaryFlat)
		assert.are.near(2, minionFlat / mercenaryFlat, 0.05)
	end)

	it("treats Mercenary warcries as fully active in Max Hit mode", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local average = calculate().player.modDB:Sum("BASE", nil, "PhysicalDamageGainAsFire")
		assert.is_true(average > 0)
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.input.warcryMode = "MAX"
		local maxHit = calculate().player.modDB:Sum("BASE", nil, "PhysicalDamageGainAsFire")
		assert.is_true(maxHit > average)
	end)

	it("applies player auras to the Mercenary and keeps only the strongest copy", function()
		build.skillsTab:PasteSocketGroup("Zealotry 20/0  1")
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local env = calculate()
		assert.is_true(env.mercenary.modDB.conditions.AffectedByZealotry)
		local spellCfg = { flags = ModFlag.Spell }
		local strongestEffect = env.mercenary.modDB:More(spellCfg, "Damage")

		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "ZealotryMercenary")
		env = calculate()
		assert.are.near(strongestEffect, env.mercenary.modDB:More(spellCfg, "Damage"), 10 ^ -9)

		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary")
		env = calculate()
		assert.is_true(env.mercenaryMinion.modDB.conditions.AffectedByZealotry)
	end)

	it("arbitrates Mercenary curses against its curse limit", function()
		configure("ChaosMinionWitch", "ChaosMinionWitchDot", "BaneMercenary")
		table.insert(build.mercenaryTab.profile.skills, {
			id = "TemporalChainsMercenary",
			enabled = true,
			count = 1,
			supports = { },
		})
		local env = calculate()
		assert.are.equal(1, env.mercenary.modDB.multipliers.CurseOnEnemy)
		assert.is_true(env.enemy.modDB.conditions.Cursed)
	end)

	it("applies a player curse to the enemy once while a Mercenary is present", function()
		build.skillsTab:PasteSocketGroup("Vulnerability 20/0  1")
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local env = calculate()
		assert.is_true(env.enemy.modDB.conditions.Cursed)
		assert.are.equal(1, env.player.modDB.multipliers.CurseOnEnemy)
	end)

	it("accepts imported allied auras but excludes party-only charge effects", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local baselineDamage = calculate().mercenary.modDB:Sum("INC", nil, "Damage")
		local auraMods = new("ModList"):ModList()
		auraMods:NewMod("Damage", "INC", 20, "Imported Party Aura")
		build.partyTab.actor.Aura = { Aura = { ImportedAura = { effectMult = 100, modList = auraMods } } }
		build.partyTab.actor.modDB:NewMod("PartyMemberMaximumEnduranceChargesEqualToYours", "FLAG", true, "Imported Party Member")
		build.partyTab.actor.output.EnduranceChargesMax = 9
		local env = calculate()
		assert.are.equal(baselineDamage + 20, env.mercenary.modDB:Sum("INC", nil, "Damage"))
		assert.is_true(env.mercenary.modDB.conditions.AffectedByImportedAura)
		assert.are.equal(9, env.player.output.EnduranceChargesMax)
		assert.are_not.equals(9, env.mercenary.output.EnduranceChargesMax)

		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary")
		env = calculate()
		assert.is_true(env.mercenaryMinion.modDB.conditions.AffectedByImportedAura)
	end)

	it("exports Mercenary ally effects through the existing Party tab format", function()
		build.partyTab.enableExportBuffs = true
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "ZealotryMercenary")
		calculate()
		assert.is_table(build.partyTab.buffExports.Aura.Zealotry)
		assert.is_true(#build.partyTab.buffExports.Aura.Zealotry.modList > 0)
	end)

	it("exports the strongest copy of a same-name player and Mercenary aura", function()
		build.partyTab.enableExportBuffs = true
		local function exportedEffect()
			calculate()
			return assert(build.partyTab.buffExports.Aura.Zealotry).effectMult
		end
		build.skillsTab:PasteSocketGroup("Arc 20/0  1")
		build.skillsTab:PasteSocketGroup("Zealotry 20/0  1")
		local playerGroup = build.skillsTab.socketGroupList[#build.skillsTab.socketGroupList]
		build.mainSocketGroup = 1
		build.configTab.input.customMods = "Zealotry has 200% increased Aura Effect"
		build.configTab:BuildModList()
		local playerStrong = exportedEffect()
		assert.are.near(3, playerStrong, 10 ^ -9)

		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "ZealotryMercenary")
		playerGroup.enabled = false
		local mercDefault = exportedEffect()
		assert.is_true(playerStrong > mercDefault)

		playerGroup.enabled = true
		assert.are.near(playerStrong, exportedEffect(), 10 ^ -9)

		build.configTab.input.customMods = "Zealotry has 50% reduced Aura Effect"
		build.configTab:BuildModList()
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.customModsList = { { title = "Default", enabled = true, text = "Zealotry has 200% increased Aura Effect" } }
		playerGroup.enabled = false
		local mercStrong = exportedEffect()
		build.mercenaryTab.profile.skills[1].enabled = false
		build.mercenaryTab:Changed()
		playerGroup.enabled = true
		local playerWeak = exportedEffect()
		assert.is_true(mercStrong > playerWeak)

		build.mercenaryTab.profile.skills[1].enabled = true
		build.mercenaryTab:Changed()
		assert.are.near(mercStrong, exportedEffect(), 10 ^ -9)
	end)

	it("applies Bestowed Knighthood aura effect and Mercenary taunt mitigation", function()
		allocate("Bestowed Knighthood")
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local env = calculate()
		assert.are.equal(50, env.mercenary.modDB:Sum("INC", nil, "AuraEffectOnSelf"))
		assert.is_true(env.enemy.modDB.conditions.TauntedByMercenary)
		assert.are.near(0.9, env.player.modDB:More(nil, "DamageTaken"), 10 ^ -9)
	end)

	it("automatically applies an enabled player Link skill to the Mercenary", function()
		assert.is_nil(build.skillsTab.controls.linkTarget)
		allocate("Oath of Fealty")
		allocate("Golden Glory")
		build.skillsTab:PasteSocketGroup("Flame Link 20/0  1")
		local linkGroup = build.skillsTab.socketGroupList[#build.skillsTab.socketGroupList]
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", { includeInFullDPS = true })
		local env = calculate()
		local baseDPS = env.mercenary.output.CombinedDPS
		local baseFullDPS = env.mercenary.output.FullDPS
		assert.is_true(env.mercenary.modDB.conditions.AffectedByLink)
		-- Neither Link node modifier changes a number PoB calculates, so both are
		-- recognised as unsupported rather than parsed into an unread flag.
		for _, modLine in ipairs({ "Link Skills have infinite Attachment Duration", "If your Linked Mercenary dies, the Link owner does not also die" }) do
			local mods, unsupported = modLib.parseMod(modLine)
			assert.are.equal(0, #mods, modLine)
			assert.are.equal(modLine, unsupported)
		end
		assert.are.near(0.5, env.player.mainSkill.skillModList:More(env.player.mainSkill.skillCfg, "Cost"), 10 ^ -9)

		linkGroup.enabled = false
		env = calculate()
		assert.is_nil(env.mercenary.modDB.conditions.AffectedByLink)

		linkGroup.enabled = true
		build.configTab.input.customMods = "100% increased Light Radius"
		build.configTab:BuildModList()
		env = calculate()
		assert.is_true(env.mercenary.output.CombinedDPS > baseDPS)
		assert.is_true(env.mercenary.output.FullDPS > baseFullDPS)
		assert.is_true(env.mercenary.modDB.conditions.AffectedByLink)
	end)

	it("applies only player non-unique utility flasks through Ceinture of Benevolence", function()
		build.skillsTab:PasteSocketGroup("Flame Link 20/0  1")
		local linkGroup = build.skillsTab.socketGroupList[#build.skillsTab.socketGroupList]
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local recipientBelt = new("Item"):Item("Rarity: Rare\nRecipient Effect\nCloth Belt\nFlasks applied to you have 25% increased Effect")
		recipientBelt.id = 9029
		build.itemsTab.items[recipientBelt.id] = recipientBelt
		equipmentSlot("Belt").selItemId = recipientBelt.id

		local granite = new("Item"):Item("Rarity: Magic\nChemist's Granite Flask of the Opossum\n12% increased Movement Speed during Effect")
		granite.id = 9030
		granite.flaskData.effectInc = 10
		build.itemsTab.items[granite.id] = granite
		build.itemsTab.slots["Flask 1"].selItemId = granite.id
		build.itemsTab.slots["Flask 1"].active = true
		build.itemsTab.activeItemSet["Flask 1"].selItemId = granite.id
		build.itemsTab.activeItemSet["Flask 1"].active = true
		build.configTab.input.customMods = "Flasks applied to you have 30% increased Effect"
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.customModsList[1].text = "Flasks applied to you have 30% increased Effect"
		configSet.actors.mercenary.customModsList[1].text = "Flasks applied to you have 30% increased Effect"
		build.configTab:BuildModList()
		local env = calculate()
		local baseArmour = env.mercenary.modDB:Sum("BASE", nil, "Armour")
		local baseMovementSpeed = env.mercenary.modDB:Sum("INC", nil, "MovementSpeed")
		assert.is_true(env.player.modDB.conditions.UsingGraniteFlask)
		assert.is_nil(env.mercenary.modDB.conditions.UsingGraniteFlask)

		local ceinture = new("Item"):Item("Rarity: Unique\nCeinture of Benevolence\nCloth Belt\nNon-Unique Utility Flasks you Use apply to Linked Targets")
		ceinture.id = 9031
		build.itemsTab.items[ceinture.id] = ceinture
		build.itemsTab.slots.Belt.selItemId = ceinture.id
		build.itemsTab.activeItemSet.Belt.selItemId = ceinture.id
		env = calculate()
		assert.is_true(env.mercenary.modDB.conditions.UsingFlask)
		assert.is_true(env.mercenary.modDB.conditions.UsingGraniteFlask)
		assert.are.equal(baseArmour + 2475, env.mercenary.modDB:Sum("BASE", nil, "Armour"))
		assert.are.equal(baseMovementSpeed + 19, env.mercenary.modDB:Sum("INC", nil, "MovementSpeed"))

		linkGroup.enabled = false
		env = calculate()
		assert.is_nil(env.mercenary.modDB.conditions.UsingFlask)
		assert.is_nil(env.mercenary.modDB.conditions.UsingGraniteFlask)
		assert.are.equal(baseArmour, env.mercenary.modDB:Sum("BASE", nil, "Armour"))

		linkGroup.enabled = true
		granite.rarity = "UNIQUE"
		env = calculate()
		assert.is_nil(env.mercenary.modDB.conditions.UsingFlask)
		assert.is_nil(env.mercenary.modDB.conditions.UsingGraniteFlask)
		assert.are.equal(baseArmour, env.mercenary.modDB:Sum("BASE", nil, "Armour"))

		local lifeFlask = new("Item"):Item("Rarity: Normal\nEternal Life Flask")
		lifeFlask.id = 9032
		build.itemsTab.items[lifeFlask.id] = lifeFlask
		build.itemsTab.slots["Flask 1"].selItemId = lifeFlask.id
		build.itemsTab.activeItemSet["Flask 1"].selItemId = lifeFlask.id
		env = calculate()
		assert.is_nil(env.mercenary.modDB.conditions.UsingFlask)
		assert.is_nil(env.mercenary.modDB.conditions.UsingEternalLifeFlask)
	end)

	it("uses the player as the Mercenary parent for Link defences", function()
		build.skillsTab:PasteSocketGroup("Vampiric Link 20/0  1")
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local env = calculate()
		assert.are.equal(env.player, env.mercenary.parent)
		assert.are.equal(env.player.output.MaxLifeLeechRatePercent, env.mercenary.output.MaxLifeLeechRatePercent)
	end)

	it("switches Loyal Bodyguard only for a strictly higher Life pool", function()
		allocate("Loyal Bodyguard")
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", { lifeComparison = "MERCENARY" })
		local env = calculate()
		assert.are.equal(20, env.player.modDB:Sum("BASE", nil, "takenFromMercenaryBeforeYou"))
		assert.are.equal(0, env.mercenary.modDB:Sum("BASE", nil, "LifeRecoup"))

		build.mercenaryTab.profile.lifeComparison = "PLAYER"
		env = calculate()
		assert.are.equal(0, env.player.modDB:Sum("BASE", nil, "takenFromMercenaryBeforeYou"))
		assert.are.equal(40, env.mercenary.modDB:Sum("BASE", nil, "LifeRecoup"))

		build.mercenaryTab.profile.lifeComparison = "AUTO"
		local equalizer = {
			id = 9037, name = "Player Life Equalizer", type = "Helmet", base = { type = "Helmet" }, rarity = "RARE",
			requirements = { }, grantedSkills = { }, sockets = { }, modList = { {
				name = "Life", type = "BASE", value = env.mercenary.output.Life - env.player.output.Life,
				source = "Test", flags = 0, keywordFlags = 0,
			} },
		}
		build.itemsTab.items[equalizer.id] = equalizer
		build.itemsTab.slots.Helmet:SetSelItemId(equalizer.id)
		env = calculate()
		assert.are.equal(env.player.output.Life, env.mercenary.output.Life)
		assert.are.equal(0, env.player.modDB:Sum("BASE", nil, "takenFromMercenaryBeforeYou"))
		assert.are.equal(0, env.mercenary.modDB:Sum("BASE", nil, "LifeRecoup"))
	end)

	it("expands Mercenary anoints, item keystones, and presence implicits", function()
		allocate("Legendary Arms")
		allocate("Legendary Helmets")
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local baseline = calculate().mercenary
		local baselineFireResist = baseline.output.FireResist
		local baselineDamage = baseline.modDB:Sum("INC", nil, "Damage")
		local baselineMoreDamage = baseline.modDB:More(nil, "Damage")
		local presenceDamage = {
			name = "Damage", type = "INC", value = 20, source = "Presence Test", flags = 0, keywordFlags = 0,
			{ type = "ActorCondition", actor = "enemy", var = "RareOrUnique" },
		}
		local item = {
			id = 9003,
			name = "Mercenary Test Helmet",
			type = "Helmet",
			base = { type = "Helmet" },
			rarity = "UNIQUE",
			requirements = { level = 1, dex = 1 },
			grantedSkills = { },
			modList = {
				{ name = "GrantedPassive", type = "LIST", value = "diamond skin", source = "Test", flags = 0, keywordFlags = 0 },
				{ name = "Keystone", type = "LIST", value = "resolute technique", source = "Test", flags = 0, keywordFlags = 0 },
				presenceDamage,
			},
			implicitModLines = { { line = "While a Unique Enemy is in your Presence, 20% increased Damage", modList = { presenceDamage } } },
		}
		build.itemsTab.items[item.id] = item
		equipmentSlot("Helmet").selItemId = item.id
		local mercenary = calculate().mercenary
		assert.are.equal(baselineFireResist + 15, mercenary.output.FireResist)
		assert.are.equal(baselineDamage + 20, mercenary.modDB:Sum("INC", nil, "Damage"))
		assert.are.equal(round(baselineMoreDamage * 1.08, 2), mercenary.modDB:More(nil, "Damage"))
		assert.is_true(mercenary.modDB:Flag(nil, "CannotBeEvaded"))
		assert.is_true(mercenary.modDB:Flag(nil, "NeverCrit"))
		mercenary = calculate().mercenary
		local _, _, actorBases = build.calcsTab:GetMiscCalculator()
		assert.are.near(mercenary.output.CombinedDPS, actorBases.MERCENARY.CombinedDPS, 10 ^ -6)
	end)

	it("counts Mercenary equipment sockets as empty", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local baseline = calculate().mercenary
		local baselineLife = baseline.output.Life
		local baselineBaseLife = baseline.modDB:Sum("BASE", nil, "Life")
		local item = {
			id = 9004,
			name = "Mercenary Socket Test",
			type = "Helmet",
			base = { type = "Helmet" },
			rarity = "RARE",
			requirements = { dex = 1 },
			grantedSkills = { },
			sockets = { { color = "R", group = 1 }, { color = "G", group = 1 } },
			modList = {
				{ name = "Life", type = "BASE", value = 40, source = "Test", flags = 0, keywordFlags = 0,
					{ type = "Multiplier", var = "EmptyRedSocketsInAnySlot" } },
			},
		}
		build.itemsTab.items[item.id] = item
		equipmentSlot("Helmet").selItemId = item.id
		local mercenary = calculate().mercenary
		assert.are.equal(1, mercenary.modDB.multipliers.EmptyRedSocketsInAnySlot)
		assert.are.equal(1, mercenary.modDB.multipliers.EmptyGreenSocketsInAnySlot)
		assert.are.equal(baselineBaseLife + 40, mercenary.modDB:Sum("BASE", nil, "Life"))
		assert.is_true(mercenary.output.Life > baselineLife)
	end)

	it("applies socketed Abyss jewel stats to the Mercenary", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local baseline = calculate().mercenary
		local helmet = {
			id = 9005, name = "Mercenary Abyss Helmet", type = "Helmet", base = { type = "Helmet" }, rarity = "RARE",
			requirements = { dex = 1 }, grantedSkills = { }, sockets = { { color = "A", group = 1 } }, abyssalSocketCount = 1, modList = { },
		}
		local jewel = {
			id = 9006, name = "Mercenary Abyss Jewel", type = "Jewel", base = { type = "Jewel", subType = "Abyss" }, rarity = "RARE",
			requirements = { level = 1 }, grantedSkills = { }, modList = {
				{ name = "Life", type = "BASE", value = 40, source = "Test", flags = 0, keywordFlags = 0 },
			},
		}
		build.itemsTab.items[helmet.id], build.itemsTab.items[jewel.id] = helmet, jewel
		equipmentSlot("Helmet").selItemId = helmet.id
		equipmentSlot("Helmet Abyssal Socket 1").selItemId = jewel.id
		local mercenary = calculate().mercenary
		assert.are.equal(baseline.modDB:Sum("BASE", nil, "Life") + 40, mercenary.modDB:Sum("BASE", nil, "Life"))
		assert.are.equal(jewel, mercenary.itemList["Helmet Abyssal Socket 1"])
	end)

	it("displays configuration warnings without blocking calculations", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", { foundAreaLevel = 68 })
		local forbiddenFlask = new("Item"):Item("Rarity: Normal\nSmall Life Flask")
		forbiddenFlask.id = 9020
		build.itemsTab.items[forbiddenFlask.id] = forbiddenFlask
		build.itemsTab.activeItemSet["Flask 1"].selItemId = forbiddenFlask.id
		assert.is_table(calculate(83).mercenary)
		assert.not_matches("Flask 1", table.concat(build.mercenaryTab:GetErrors(), "\n"))
		build.itemsTab.activeItemSet["Flask 1"].selItemId = 0

		build.characterLevel = 48
		assert.is_table(calculate(83).mercenary)
		assert.matches("20 below", table.concat(build.mercenaryTab:GetErrors(), "\n"))
		build.characterLevel = 49
		assert.is_table(calculate(83).mercenary)
		build.characterLevel = 90
	end)

	it("does not apply Mercenary effects to the player without CanHirePermanentMercenary", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "ZealotryMercenary")
		local hired = calculate()
		assert.is_true(hired.player.modDB.conditions.AffectedByZealotry)

		local nobleBlood
		for _, node in pairs(build.spec.allocNodes) do
			if node.name == "Noble Blood" then nobleBlood = node break end
		end
		nobleBlood = assert(nobleBlood, "Noble Blood")
		build.spec.allocNodes[nobleBlood.id] = nil
		nobleBlood.alloc = false
		local unhired = calculate()
		assert.is_nil(unhired.mercenary)
		assert.is_not_true(unhired.player.modDB.conditions.AffectedByZealotry)
		assert.matches("Noble Blood", table.concat(build.mercenaryTab:GetErrors(), "\n"))
		assert.are.equal("TrapsMinesShadowLightning", build.mercenaryTab.profile.buildId)

		for classId, class in pairs(build.spec.tree.classes) do
			if class.name == "Marauder" then build.spec:SelectClass(classId) break end
		end
		assert.is_nil(calculate().mercenary)
		assert.matches("Scion's Luminary", table.concat(build.mercenaryTab:GetErrors(), "\n"))
		assert.are.equal("TrapsMinesShadowLightning", build.mercenaryTab.profile.buildId)
	end)

	it("equips Eber's Unification without granting Void Gaze", function()
		configure("ChaosMinionWitch", "ChaosMinionWitchChaosHitNoble", "DarkPactMercenary")
		allocate("Legendary Helmets")
		local baselineMana = calculate().mercenary.modDB:Sum("BASE", nil, "Mana")
		local ebers = new("Item"):Item([[Rarity: Unique
Eber's Unification
Hubris Circlet
Trigger Level 10 Void Gaze when you use a Skill
150% increased Energy Shield
+80 to maximum Mana
50% increased Stun and Block Recovery
Gain 8% of Elemental Damage as Extra Chaos Damage
]])
		assert.are.equal("VoidGaze", ebers.grantedSkills[1].skillId)
		build.itemsTab:AddItem(ebers, true)
		equipmentSlot("Helmet").selItemId = ebers.id
		local env = calculate()
		assert.is_nil(env.mercenaryCalculationErrors and env.mercenaryCalculationErrors[1], table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_table(env.mercenary)
		assert.are.equal(ebers, env.mercenary.itemList.Helmet)
		assert.are.equal(baselineMana + 80, env.mercenary.modDB:Sum("BASE", nil, "Mana"))
		assert.are.equal(8, env.mercenary.modDB:Sum("BASE", nil, "ElementalDamageGainAsChaos"))
		assert.are.equal(50, env.mercenary.modDB:Sum("INC", nil, "StunRecovery"))
		assert.are.equal(0, #env.mercenary.modDB:List(nil, "ExtraSkill"))
		for _, skill in ipairs(env.mercenary.activeSkillList) do
			assert.are_not.equal("VoidGaze", skill.activeEffect.grantedEffect.id)
		end
	end)

	it("applies structural Mercenary supports through their standard support template", function()
		configure("EleBowRanger", "EleBowRangerFire", "BurningArrowMercenary", {
			supports = { { id = "ArrowNovaHigh", tier = 3 } },
		})
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9010, 9011
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id
		local mercenary = assert(calculate().mercenary)
		assert.is_truthy(mercenary.mainSkill.skillData.projectilesNova)
		assert.is_true(mercenary.output.CombinedDPS > 0)
		assert.are.equal("ArrowNovaHigh", build.mercenaryTab.profile.skills[1].supports[1].id)
	end)

	it("propagates Mercenary supports to summoned minion skills", function()
		configure("EleBowRanger", "EleBowRangerClones", "MirrorArrowMercenary", {
			includeInFullDPS = true,
		})
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9016, 9017
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id

		local baseline = assert(calculate())
		local baselineMinionDPS = assert(baseline.mercenaryMinion.output.TotalDPS)
		local baselineFullDPS = assert(baseline.mercenary.output.FullDPS)
		local support = assert(build.data.mercenaries.supports.AddedColdHigh)
		build.mercenaryTab.profile.skills[1].supports = { { id = support.id, tier = support.variant } }
		build.mercenaryTab:Changed()

		local supported = assert(calculate())
		local minionSkill = assert(supported.mercenaryMinion.mainSkill)
		local hasSupport = false
		for _, effect in ipairs(minionSkill.effectList) do
			if effect.grantedEffect.mercenarySupportId == support.id then hasSupport = true break end
		end
		assert.is_true(hasSupport)
		assert.is_true(supported.mercenaryMinion.output.TotalDPS > baselineMinionDPS)
		assert.is_true(supported.mercenary.output.FullDPS > baselineFullDPS)
	end)

	it("applies Fist of War to Ashen Fissure", function()
		-- Extract: FissureSlamMercenary is not SkillType.Slam, but possibleSupportIds includes FistOfWarHigh.
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "FissureSlamMercenary", {
			supports = { { id = "FistOfWarHigh", tier = 3 } },
		})
		local mercenary = assert(calculate(83).mercenary)
		assert.is_nil(mercenary.mainSkill.skillTypes[SkillType.Slam])
		local hasFistOfWar = false
		for _, effect in ipairs(mercenary.mainSkill.effectList) do
			if effect.grantedEffect.mercenarySupportId == "FistOfWarHigh" then hasFistOfWar = true break end
		end
		assert.is_true(hasFistOfWar)
		assert.is_true(mercenary.output.FistOfWarUptimeRatio > 0)
	end)

	it("counts Barrage of Volley Fire first and final volley projectiles", function()
		configure("NonEleBowRanger", "NonEleBowRangerPhys", "BarrageAltMercenary", { skillPart = 2 })
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9018, 9017
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id

		local skill = assert(calculate(83).mercenary.mainSkill)
		assert.are.equal("All Projectiles", skill.skillPartName)
		assert.are.equal(6, skill.skillData.barrageFinalVolleyAdditionalProjectiles)
		assert.are.equal(16, skill.skillData.dpsMultiplier)
	end)

	it("counts both initial Vaal Double Strike hits", function()
		configure("MeleeAOEStrikeDuelist", "MeleeAOEStrikeDuelistCyclone", "VaalDoubleStrikeMercenary")
		local sword = new("Item"):Item("Rarity: Normal\nCorroded Blade")
		sword.id = 9019
		build.itemsTab.items[sword.id] = sword
		equipmentSlot("Weapon 1").selItemId = sword.id
		local skill = assert(calculate(83).mercenary.mainSkill)
		assert.are.equal(2, skill.skillData.dpsMultiplier)
	end)

	it("counts Vaal Ice Shot Mirage Sharpshooters", function()
		configure("EleBowRanger", "EleBowRangerClones", "VaalIceShotMercenary", {
			supports = { { id = "MultipleProjectilesHigh", tier = 3 } },
		})
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9020, 9021
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id
		local env = calculate(83)
		local skill = assert(env.mercenary.mainSkill)
		assert.are.equal(6, skill.skillData.vaalIceShotMirageCount)
		assert.is_true(env.mercenary.output.ProjectileCount > 1)
		assert.are.equal(7, skill.skillData.dpsMultiplier)
	end)

	it("includes Mercenary Mirage Archer damage in Full DPS", function()
		configure("NonEleBowRanger", "NonEleBowRangerChaos", "CausticArrowMercenary", {
			includeInFullDPS = true,
			supports = { { id = "MirageArcherHigh", tier = 3 } },
		})
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9014, 9015
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id
		local mercenary = assert(calculate().mercenary)
		assert.is_table(mercenary.mainSkill.mirage)
		assert.is_true(mercenary.mainSkill.mirage.output.TotalDPS > 0)
		local mirageBreakdown
		for _, skillDPS in ipairs(mercenary.output.SkillDPS) do
			if skillDPS.source == "Mercenary Mirage" then mirageBreakdown = skillDPS break end
		end
		assert.is_table(mirageBreakdown)
		assert.are.near(mercenary.mainSkill.mirage.output.TotalDPS, mirageBreakdown.dps, 10 ^ -6)
		assert.are.near(mercenary.output.CombinedDPS, mercenary.output.FullDPS, 10 ^ -6)
		assert.is_true(not mercenary.mainSkill.skillCfg.skillCond.usedByMirage)
	end)

	it("uses the player Full DPS count-once option for Mercenary summoning skills", function()
		configure("AurasMinionsTemplar", "AurasMinionsTemplarSpectres", "AbsolutionMercenary", {
			includeInFullDPS = true,
			count = 3,
		})
		build.configTab.input.absolutionSkillDamageCountedOnce = true
		build.configTab:BuildModList()
		local env = calculate()
		assert.is_true(env.skillsUsed.Absolution)
		assert.are.near(env.mercenary.output.TotalDPS + env.mercenaryMinion.output.TotalDPS * 3, env.mercenary.output.FullDPS, 10 ^ -6)
	end)

	it("calculates Full DPS from the persisted Mercenary equipment item set", function()
		configure("EleBowRanger", "EleBowRangerFire", "BurningArrowMercenary", { includeInFullDPS = true })
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9040, 9041
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id

		local itemsXml, mercenaryXml = { }, { }
		build.itemsTab:Save(itemsXml)
		build.mercenaryTab:Save(mercenaryXml)
		local savedItemSetId = build.mercenaryTab.itemSetId
		build.itemsTab:Load(itemsXml)
		build.mercenaryTab:Load(mercenaryXml)

		local env = calculate()
		assert.are.equal(savedItemSetId, build.mercenaryTab.itemSetId)
		assert.are.equal(bow, env.mercenary.itemList["Weapon 1"])
		assert.is_true(env.mercenary.output.FullDPS > 0)
	end)

	it("applies Mercenary on-hit curses as auxiliary skills", function()
		configure("MeleeStrikesMarauder", "MeleeStrikesMaraduerPhys", "HeavyStrikeMercenary")
		local mace = new("Item"):Item("Rarity: Normal\nDriftwood Club")
		mace.id = 9012
		build.itemsTab.items[mace.id] = mace
		equipmentSlot("Weapon 1").selItemId = mace.id
		local env = calculate()
		local foundVulnerability
		for _, activeSkill in ipairs(env.mercenary.activeSkillList) do
			if activeSkill.activeEffect.grantedEffect.id == "Vulnerability" then foundVulnerability = true break end
		end
		assert.is_true(foundVulnerability)
		assert.is_true(env.enemy.modDB.conditions.Cursed)
	end)

	it("uses and persists explicit Mercenary skill parts", function()
		configure("MeleeAOEStrikeDuelist", "DivingDuelist", "ElementalHitColdOnlyMercenary")
		local sword = new("Item"):Item("Rarity: Normal\nRusted Sword")
		sword.id = 9013
		build.itemsTab.items[sword.id] = sword
		equipmentSlot("Weapon 1").selItemId = sword.id
		local env = calculate()
		assert.are.equal(3, env.mercenary.mainSkill.skillPart)
		assert.are.equal("Cold Attack", env.mercenary.mainSkill.skillPartName)
		assert.is_true(env.mercenary.output.CombinedDPS > 0)
		build.mercenaryTab.profile.skills[1].skillPart = 4
		build.mercenaryTab:Changed()
		env = calculate()
		assert.are.equal(4, env.mercenary.mainSkill.skillPart)
	end)

	it("round-trips the Mercenary section and migrates showMinion", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", {
			includeInFullDPS = true,
			count = 2,
			skillPart = 1,
			skillMinionSkill = 2,
			supports = { { id = "AddedLightningHigh", tier = 3 } },
		})
		assert(build.mercenaryTab:GetItemSet(true))
		local function savedState()
			local saved = { elem = "Mercenary", attrib = { } }
			build.mercenaryTab:Save(saved)
			return saved
		end
		local saved = savedState()
		build.mercenaryTab:Reset()
		build.mercenaryTab:Load(saved)
		assert.are.same(saved, savedState())

		build.calcsTab:Load({ { elem = "Input", attrib = { name = "showMinion", boolean = "true" } } })
		assert.are.equal("PLAYER_MINION", build.calcsTab.input.actor)
	end)

	it("shows actor unavailable status without a synthetic mainSkill", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		build.mercenaryTab.itemSetId = 99999
		build.calcsTab.input.actor = "MERCENARY"
		local env = calculate()
		assert.is_nil(env.mercenary)
		assert.is_not_nil(env.mercenaryCalculationErrors)
		assert.is_nil(build.calcsTab:GetDisplayActor(build.calcsTab.calcsEnv))
		assert.is_truthy(build.calcsTab.calcsOutput.ActorUnavailableMessage)
		assert.is_true(build.calcsTab:CheckFlag({ haveOutput = "ActorUnavailableMessage" }))
		assert.is_true(not build.calcsTab:CheckFlag({ flag = "attack" }))
		assert.is_true(not build.calcsTab:CheckFlag({ flag = "minion" }))
		assert.is_true(not build.calcsTab:CheckFlag({ playerFlag = "multiPart" }))
		assert.is_true(not build.calcsTab:CheckFlag({ haveOutput = "Life" }))
		assert.is_true(not build.calcsTab:CheckFlag({ haveOutput = "CombinedDPS" }))
		assert.is_true(env.player.output.Life > 0)
		assert.is_nil(build.calcsTab.calcsOutput.Life)
		assert.is_nil(build.calcsTab.calcsOutput.CombinedDPS)
		for _, section in ipairs(build.calcsTab.sectionList) do
			section:UpdateSize()
			if section.flag == "attack" then
				assert.is_true(not section.enabled, section.id)
			end
		end
		local statusOnly = { output = build.calcsTab.calcsOutput }
		assert.is_nil(statusOnly.mainSkill)
		assert.matches("unavailable", formatCalcStr("{output:ActorUnavailableMessage}", statusOnly))
	end)

	it("applies mercenary minion Full Life config independently of the player", function()
		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary")
		build.skillsTab:PasteSocketGroup("Summon Raging Spirit 20/0  1")
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		local fullLifeMod = "Minions have 100% chance to deal double damage while they are on full life"
		configSet.customModsList[1].text = fullLifeMod
		configSet.actors.mercenary.customModsList[1].text = fullLifeMod
		configSet.actors.mercenary.input.minionsConditionFullLife = true
		local env = calculate()
		assert.is_table(env.mercenaryMinion)
		assert.is_table(env.minion)
		assert.is_true(env.mercenaryMinion.modDB:Flag(nil, "Condition:FullLife"))
		assert.is_not_true(env.minion.modDB:Flag(nil, "Condition:FullLife"))
		assert.are.equal(100, env.mercenaryMinion.modDB:Sum("BASE", nil, "DoubleDamageChance"))
		assert.are.equal(0, env.minion.modDB:Sum("BASE", nil, "DoubleDamageChance"))

		configSet.actors.mercenary.input.minionsConditionFullLife = nil
		configSet.input.minionsConditionFullLife = true
		env = calculate()
		assert.is_not_true(env.mercenaryMinion.modDB:Flag(nil, "Condition:FullLife"))
		assert.is_true(env.minion.modDB:Flag(nil, "Condition:FullLife"))
		assert.are.equal(0, env.mercenaryMinion.modDB:Sum("BASE", nil, "DoubleDamageChance"))
		assert.are.equal(100, env.minion.modDB:Sum("BASE", nil, "DoubleDamageChance"))
	end)

	it("shows minion Full Life config only for the actor whose minions use it", function()
		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary")
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		local fullLifeMod = "Minions have 100% chance to deal double damage while they are on full life"
		configSet.actors.mercenary.customModsList[1].text = fullLifeMod
		local env = calculate()
		assert.is_table(env.mercenaryMinion)
		assert.is_nil(env.minion)

		local fullLifeConfig
		for _, varData in ipairs(configOptions) do
			if varData.var == "minionsConditionFullLife" then fullLifeConfig = varData break end
		end
		assert.is_false(configVisibility.isRelevantForBuild(assert(fullLifeConfig), build, "player"))
		assert.is_true(configVisibility.isRelevantForBuild(fullLifeConfig, build, "mercenary"))
		build.configTab:SetViewActor("player")
		assert.is_false(build.configTab.varControls.minionsConditionFullLife.shown())
		build.configTab:SetViewActor("mercenary")
		assert.is_true(build.configTab.varControls.minionsConditionFullLife.shown())

		configSet.actors.mercenary.customModsList[1].text = ""
		configSet.customModsList[1].text = fullLifeMod
		build.skillsTab:PasteSocketGroup("Summon Raging Spirit 20/0  1")
		env = calculate()
		assert.is_table(env.minion)
		assert.is_true(configVisibility.isRelevantForBuild(fullLifeConfig, build, "player"))
		assert.is_false(configVisibility.isRelevantForBuild(fullLifeConfig, build, "mercenary"))
		build.configTab:SetViewActor("player")
		assert.is_true(build.configTab.varControls.minionsConditionFullLife.shown())
		build.configTab:SetViewActor("mercenary")
		assert.is_false(build.configTab.varControls.minionsConditionFullLife.shown())
	end)

	it("applies mercenary Minions Created Recently to the mercenary, not the player", function()
		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary")
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.input.minionsConditionCreatedRecently = true
		local env = calculate()
		assert.is_true(env.mercenary.modDB:Flag(nil, "Condition:MinionsCreatedRecently"))
		assert.is_not_true(env.player.modDB:Flag(nil, "Condition:MinionsCreatedRecently"))
	end)

	it("uses default projectile distance for a fresh Mercenary projectile skill", function()
		configure("EleBowRanger", "EleBowRangerFire", "BurningArrowMercenary")
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9060, 9061
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		assert.are.equal(40, configSet.actors.mercenary.placeholder.projectileDistance)
		local env = calculate()
		assert.are.equal(40, env.mercenary.mainSkill.skillCfg.skillDist)
	end)

	it("applies DistanceRamp using the Mercenary projectile distance, not the player's", function()
		configure("EleBowRanger", "EleBowRangerFire", "BurningArrowMercenary")
		local bow = new("Item"):Item("Rarity: Normal\nCrude Bow")
		local quiver = new("Item"):Item("Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9062, 9063
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.actors.mercenary.customModsList[1].text = "Projectiles gain Damage as they travel farther, dealing up to 30% more Damage with Hits and Ailments"
		configSet.input.projectileDistance = 70
		local function damageMore()
			local env = calculate()
			local skill = assert(env.mercenary, table.concat(env.mercenaryCalculationErrors or { }, "\n")).mainSkill
			return skill.skillModList:More(skill.skillCfg, "Damage")
		end
		local atDefault = damageMore()
		configSet.actors.mercenary.input.projectileDistance = 70
		local atSeventy = damageMore()
		assert.is_true(atSeventy > atDefault)
		configSet.actors.mercenary.input.projectileDistance = 40
		configSet.input.projectileDistance = 10
		assert.are.near(atDefault, damageMore(), 10 ^ -9)
	end)

	it("reads TotemsSummoned from the Mercenary environment, not the player's", function()
		configureSkill("HolyFlameTotemMercenary")
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.input.TotemsSummoned = 5
		local mercenary = assert(calculate().mercenary, table.concat(build.calcsTab.mainEnv.mercenaryCalculationErrors or { }, "\n"))
		local defaultCount = mercenary.output.ActiveTotemLimit
		assert.is_true(defaultCount >= 1)
		assert.are.equal(defaultCount, mercenary.output.TotemsSummoned)
		configSet.actors.mercenary.input.TotemsSummoned = 3
		mercenary = assert(calculate().mercenary)
		assert.are.equal(3, mercenary.output.TotemsSummoned)
		configSet.input.TotemsSummoned = 1
		mercenary = assert(calculate().mercenary)
		assert.are.equal(3, mercenary.output.TotemsSummoned)
	end)

	it("reads WarcryMaxHit from the Mercenary environment, not the player's", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.input.warcryMode = "AVERAGE"
		configSet.actors.mercenary.input.warcryMode = "AVERAGE"
		local average = assert(calculate().mercenary).output.WarcryEffectMod
		assert.is_true(average > 0)
		configSet.actors.mercenary.input.warcryMode = "MAX"
		local maxHit = assert(calculate().mercenary).output.WarcryEffectMod
		assert.is_true(maxHit > average)
		configSet.input.warcryMode = "MAX"
		configSet.actors.mercenary.input.warcryMode = "AVERAGE"
		assert.are.near(average, assert(calculate().mercenary).output.WarcryEffectMod, 10 ^ -9)
	end)

	it("calculates Mercenary minions with Mercenary physMode, not the player's", function()
		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary")
		local configSet = build.configTab.configSets[build.configTab.activeConfigSetId]
		build.configTab:EnsureActorConfig(configSet)
		configSet.input.physMode = "FIRE"
		configSet.actors.mercenary.input.physMode = "COLD"
		local origBuildModList = build.configTab.BuildModList
		function build.configTab:BuildModList(...)
			origBuildModList(self, ...)
			self.mercenaryModList:NewMod("MinionModifier", "LIST", {
				mod = modLib.createMod("PhysicalDamageGainAsRandom", "BASE", 35)
			}, "Test")
		end
		local function gainAs(env)
			local minion = assert(env.mercenaryMinion, table.concat(env.mercenaryCalculationErrors or { }, "\n"))
			local skill = minion.mainSkill
			return skill.skillModList:Sum("BASE", skill.skillCfg, "PhysicalDamageGainAsFire"),
				skill.skillModList:Sum("BASE", skill.skillCfg, "PhysicalDamageGainAsCold"),
				skill.skillModList:Sum("BASE", skill.skillCfg, "PhysicalDamageGainAsLightning")
		end
		local fire, cold, lightning = gainAs(calculate())
		assert.are.equal(0, fire)
		assert.are.equal(35, cold)
		assert.are.equal(0, lightning)
		configSet.input.physMode = "LIGHTNING"
		fire, cold, lightning = gainAs(calculate())
		assert.are.equal(0, fire)
		assert.are.equal(35, cold)
		assert.are.equal(0, lightning)
		configSet.actors.mercenary.input.physMode = "FIRE"
		fire, cold, lightning = gainAs(calculate())
		assert.are.equal(35, fire)
		assert.are.equal(0, cold)
		assert.are.equal(0, lightning)
	end)

	it("does not copy the player's skill Exposure onto the Mercenary", function()
		build.skillsTab:PasteSocketGroup("Spark 20/0  1\nAwakened Fire Penetration 20/0  1\n")
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local env = calculate()
		assert.is_true(env.player.modDB.conditions.CanApplyFireExposure)
		assert.is_not_true(env.mercenary.modDB.conditions.CanApplyFireExposure)
	end)

	it("detects Exposure from the Mercenary's own skill, not the player's", function()
		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "MoltenStrikeHolyMercenary", {
			supports = { { id = "HolyMoltenStrikeSpecificLightningExposureHigh", tier = 3 } },
		})
		local staff = new("Item"):Item("Rarity: Normal\nGnarled Branch")
		staff.id = 9101
		build.itemsTab.items[staff.id] = staff
		equipmentSlot("Weapon 1").selItemId = staff.id
		build.skillsTab:PasteSocketGroup("Spark 20/0  1")
		local env = calculate()
		assert.is_true(env.mercenary.modDB.conditions.CanApplyLightningExposure)
		assert.is_not_true(env.player.modDB.conditions.CanApplyLightningExposure)
	end)

	it("does not treat the player's Precise Technique as the Mercenary's", function()
		allocate("Precise Technique")
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "TectonicSlamFireMercenary")
		local env = calculate()
		assert.is_true(env.keystonesAdded["Precise Technique"])
		assert.is_true(env.player.output.PreciseTechnique)
		assert.is_not_true(env.mercenary.calcEnv.keystonesAdded["Precise Technique"])
		assert.is_not_true(env.mercenary.output.PreciseTechnique)
	end)

	it("applies Precise Technique from Mercenary equipment, not the player's tree", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "TectonicSlamFireMercenary")
		local helmet = new("Item"):Item([[Rarity: Rare
Precise Technique Test Helm
Iron Hat
--------
Precise Technique
]])
		build.itemsTab:AddItem(helmet, true)
		equipmentSlot("Helmet").selItemId = helmet.id
		local env = calculate()
		assert.is_nil(env.mercenaryCalculationErrors and env.mercenaryCalculationErrors[1], table.concat(env.mercenaryCalculationErrors or { }, "\n"))
		assert.is_not_true(env.keystonesAdded["Precise Technique"])
		assert.is_not_true(env.player.output.PreciseTechnique)
		assert.is_true(env.mercenary.calcEnv.keystonesAdded["Precise Technique"])
		assert.is_true(env.mercenary.output.PreciseTechnique)
	end)

	it("points mercEnv.minion at the Mercenary minion, not the player's", function()
		build.skillsTab:PasteSocketGroup("Raise Zombie 20/0  1")
		configure("AurasMinionsTemplar", "AurasMinionsTemplarStaff", "HeraldOfPurityMercenary")
		local env = calculate()
		assert.is_table(env.minion)
		assert.is_table(env.mercenaryMinion)
		assert.are.equal(env.mercenaryMinion, env.mercenary.calcEnv.minion)
		assert.are_not.equal(env.minion, env.mercenary.calcEnv.minion)
	end)

	it("does not fall through mercEnv.minion to the player's minion", function()
		build.skillsTab:PasteSocketGroup("Raise Zombie 20/0  1")
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local env = calculate()
		assert.is_table(env.minion)
		assert.is_nil(env.mercenaryMinion)
		assert.is_false(env.mercenary.calcEnv.minion)
	end)
end)
