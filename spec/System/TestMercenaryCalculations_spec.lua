describe("Permanent Mercenary calculations", function()
	local MercenaryTools = require("Modules/MercenaryTools")
	local configOptions = LoadModule("Modules/ConfigOptions")
	local configVisibility = LoadModule("Modules/ConfigVisibility")
	local function equipmentSlot(slotName)
		return build.itemsTab.activeItemSet[MercenaryTools.itemSlotName(slotName)]
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

	before_each(function()
		newBuild()
		selectScionLuminary()
		allocate("Noble Blood")
		build.characterLevel = 90
		build.characterLevelAutoMode = false
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
		assert.are.equal(2278, env.mercenary.output.Life)
		assert.is_true(env.mercenary.output.CombinedDPS > 0)
		assert.are.equal(1, env.mercenary.output.TrapThrowCount)
		for _, stat in ipairs({ "FullDPS", "EnergyShield", "Armour", "Evasion", "FireResist", "ColdResist", "LightningResist", "ChaosResist", "LifeRegenRecovery", "EnergyShieldRegenRecovery", "EffectiveMovementSpeedMod", "LootRarity" }) do
			assert.is_number(env.mercenary.output[stat], stat)
		end
		assert.are.equal(-90, env.mercenary.modDB:Sum("INC", nil, "DamageTaken"))
		assert.are.near(0.2, env.mercenary.modDB:More({ flags = ModFlag.Dot }, "DamageTaken"), 10 ^ -9)
		-- The permanent-hire Damage penalty belongs to the Mercenary, not to the node
		-- that allows hiring one, so it applies whatever the character has allocated.
		assert.are.near(0.7, env.mercenary.modDB:More(nil, "Damage"), 10 ^ -9)
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
		assert.matches("No usable enabled Mercenary skill", table.concat(env.mercenaryCalculationErrors, "\n"))
	end)

	it("shows and applies Configuration settings required by the Mercenary", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local focusedDamage = {
			name = "Damage", type = "INC", value = 20, source = "Mercenary Config Test", flags = 0, keywordFlags = 0,
			{ type = "Condition", var = "Focused" },
		}
		local helmet = {
			id = 9036, name = "Mercenary Config Test", type = "Helmet", base = { type = "Helmet" }, rarity = "RARE",
			requirements = { dex = 1 }, grantedSkills = { }, modList = { focusedDamage },
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
		assert.is_true(build.configTab.varControls.conditionFocused.shown())
		assert.is_true(build.configTab.varControls.detonateDeadCorpseLife.shown())

		local corpseLifeConfig
		for _, varData in ipairs(configOptions) do
			if varData.var == "detonateDeadCorpseLife" then corpseLifeConfig = varData break end
		end
		assert.is_true(configVisibility.isRelevantForBuild(assert(corpseLifeConfig), build))

		build.configTab.input.conditionFocused = true
		build.configTab.input.detonateDeadCorpseLife = 12345
		env = calculate()
		assert.is_true(env.mercenary.modDB:GetCondition("Focused"))
		assert.are.equal(baseDamage + focusedDamage.value, env.mercenary.modDB:Sum("INC", nil, "Damage"))
		assert.are.equal(12345, env.mercenary.mainSkill.skillData.corpseLife)
	end)

	it("applies the configured Onslaught buff to Mercenary attack DPS", function()
		configure("EleBowRanger", "EleBowRangerFire", "BurningArrowMercenary")
		local bow = new("Item", "Rarity: Normal\nCrude Bow")
		bow.id = 9038
		build.itemsTab.items[bow.id] = bow
		equipmentSlot("Weapon 1").selItemId = bow.id

		local baseline = assert(calculate().mercenary.output)
		build.configTab.input.buffOnslaught = true
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

	it("clamps found-area levels above 100 to the monster damage tables", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary", { foundAreaLevel = 101 })
		local env = assert(calculate(85).mercenary)
		assert.are.equal(100, env.level)
		assert.is_number(env.averageDamage)
		assert.is_true(env.averageDamage > 0)
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

		configure("ChaosMinionWitch", "ChaosMinionWitchChaosHit", "SSMMercenarySoulrendOrb", {
			foundAreaLevel = 83,
			skillMinionSkill = 2,
		})
		env = calculate(83)
		assert.are.equal("GSRitualChaosPulse", env.mercenaryMinion.mainSkill.activeEffect.grantedEffect.id)
		assert.is_true(env.mercenaryMinion.modDB:Flag(nil, "Condition:CannotBeDamaged"))
		assert.is_true(env.mercenaryMinion.modDB:Flag(nil, "AlliesAurasCannotAffectSelf"))
	end)

	it("calculates exported permanent-Mercenary bases and hidden passives", function()
		configure("MeleeAOEMarauder", "MeleeAOEMarauderFireSlam", "InfernalCryMercenary")
		local mercenary = assert(calculate(83).mercenary)
		assert.are.near(298.29000854492, mercenary.averageDamage, 10 ^ -9)
		assert.are.equal(3658, mercenary.output.Life)
		assert.are.equal(61, mercenary.output.LifeRegen)
		assert.are.equal(168, mercenary.modDB:Sum("INC", nil, "Life"))
		assert.are.equal(118, mercenary.modDB:Sum("INC", nil, "Armour"))
		assert.are.equal(320, mercenary.modDB:Sum("INC", nil, "Damage"))
		assert.are.equal(283, mercenary.modDB:Sum("BASE", nil, "Str"))
		assert.are.equal(28, mercenary.modDB:Sum("BASE", nil, "Dex"))
		assert.are.equal(28, mercenary.modDB:Sum("BASE", nil, "Int"))
		assert.are.near(0.7, mercenary.modDB:More(nil, "Damage"), 10 ^ -9)
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
		assert.are.near(1801.5, mercenary.output.AverageHit, 10 ^ -9)
	end)

	it("uses the compared slot actor while sharing the active item set", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local env = calculate()
		local compare, playerBase, actorBases = build.calcsTab.calcs.getMiscCalculator(build)
		assert.are.equal(env.player.output.Life, playerBase.Life)
		assert.are.equal(env.mercenary.output.Life, actorBases.MERCENARY.Life)
		assert.are.equal(env.player.output.Life, compare({ }).Life)
		assert.are.equal(env.mercenary.output.Life, compare({ comparisonActor = "MERCENARY" }).Life)
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
			local item = new("Item", "Rarity: Normal\n"..lowestBaseName(itemType))
			item.id = nextItemId
			nextItemId = nextItemId + 1
			build.itemsTab.items[item.id] = item
			equipmentSlot(slotName).selItemId = item.id
		end

		build.configTab.input.enemyLevel = 83
		build.configTab:BuildModList()
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

	it("accepts imported allied auras but excludes party-only charge effects", function()
		configure("TrapsMinesShadow", "TrapsMinesShadowLightning", "LightningTrapMercenary")
		local baselineDamage = calculate().mercenary.modDB:Sum("INC", nil, "Damage")
		local auraMods = new("ModList")
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
		local recipientBelt = new("Item", "Rarity: Rare\nRecipient Effect\nCloth Belt\nFlasks applied to you have 25% increased Effect")
		recipientBelt.id = 9029
		build.itemsTab.items[recipientBelt.id] = recipientBelt
		equipmentSlot("Belt").selItemId = recipientBelt.id

		local granite = new("Item", "Rarity: Magic\nChemist's Granite Flask of the Opossum\n12% increased Movement Speed during Effect")
		granite.id = 9030
		granite.flaskData.effectInc = 10
		build.itemsTab.items[granite.id] = granite
		build.itemsTab.slots["Flask 1"].selItemId = granite.id
		build.itemsTab.slots["Flask 1"].active = true
		build.itemsTab.activeItemSet["Flask 1"].selItemId = granite.id
		build.itemsTab.activeItemSet["Flask 1"].active = true
		build.configTab.input.customMods = "Flasks applied to you have 30% increased Effect"
		build.configTab:BuildModList()
		local env = calculate()
		local baseArmour = env.mercenary.modDB:Sum("BASE", nil, "Armour")
		local baseMovementSpeed = env.mercenary.modDB:Sum("INC", nil, "MovementSpeed")
		assert.is_true(env.player.modDB.conditions.UsingGraniteFlask)
		assert.is_nil(env.mercenary.modDB.conditions.UsingGraniteFlask)

		local ceinture = new("Item", "Rarity: Unique\nCeinture of Benevolence\nCloth Belt\nNon-Unique Utility Flasks you Use apply to Linked Targets")
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

		local lifeFlask = new("Item", "Rarity: Normal\nEternal Life Flask")
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
		local forbiddenFlask = { id = 9020, type = "Life Flask", rarity = "NORMAL", requirements = { }, grantedSkills = { } }
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

		local nobleBlood = assert(build.spec.allocNodes[46479])
		build.spec.allocNodes[nobleBlood.id] = nil
		nobleBlood.alloc = false
		assert.is_table(calculate(83).mercenary)
		assert.matches("Noble Blood", table.concat(build.mercenaryTab:GetErrors(), "\n"))
		assert.are.equal("TrapsMinesShadowLightning", build.mercenaryTab.profile.buildId)

		for classId, class in pairs(build.spec.tree.classes) do
			if class.name == "Marauder" then build.spec:SelectClass(classId) break end
		end
		assert.is_table(calculate(83).mercenary)
		assert.matches("Scion's Luminary", table.concat(build.mercenaryTab:GetErrors(), "\n"))
		assert.are.equal("TrapsMinesShadowLightning", build.mercenaryTab.profile.buildId)
	end)

	it("applies structural Mercenary supports through their standard support template", function()
		configure("EleBowRanger", "EleBowRangerFire", "BurningArrowMercenary", {
			supports = { { id = "ArrowNovaHigh", tier = 3 } },
		})
		local bow = new("Item", "Rarity: Normal\nCrude Bow")
		local quiver = new("Item", "Rarity: Normal\nSerrated Arrow Quiver")
		bow.id, quiver.id = 9010, 9011
		build.itemsTab.items[bow.id], build.itemsTab.items[quiver.id] = bow, quiver
		equipmentSlot("Weapon 1").selItemId, equipmentSlot("Weapon 2").selItemId = bow.id, quiver.id
		local mercenary = assert(calculate().mercenary)
		assert.is_truthy(mercenary.mainSkill.skillData.projectilesNova)
		assert.is_true(mercenary.output.CombinedDPS > 0)
		assert.are.equal("ArrowNovaHigh", build.mercenaryTab.profile.skills[1].supports[1].id)
	end)

	it("includes Mercenary Mirage Archer damage in Full DPS", function()
		configure("EleBowRanger", "EleBowRangerFire", "BurningArrowMercenary", {
			includeInFullDPS = true,
			supports = { { id = "MirageArcherHigh", tier = 3 } },
		})
		local bow = new("Item", "Rarity: Normal\nCrude Bow")
		local quiver = new("Item", "Rarity: Normal\nSerrated Arrow Quiver")
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

	it("applies Mercenary on-hit curses as auxiliary skills", function()
		configure("MeleeStrikesMarauder", "MeleeStrikesMaraduerPhys", "HeavyStrikeMercenary")
		local mace = new("Item", "Rarity: Normal\nDriftwood Club")
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
		local sword = new("Item", "Rarity: Normal\nRusted Sword")
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
		local function savedState()
			local saved = { elem = "Mercenary", attrib = { } }
			build.mercenaryTab:Save(saved)
			return saved
		end
		local beforeImport = savedState()
		build.mercenaryTab.controls.warrant:SetText("{")
		build.mercenaryTab:ImportWarrant()
		assert.are.same(beforeImport, savedState())
		assert.matches("Invalid Warrant JSON", build.mercenaryTab.importError)
		local saved = savedState()
		build.mercenaryTab:Reset()
		build.mercenaryTab:Load(saved)
		assert.are.same(saved, savedState())

		build.calcsTab:Load({ { elem = "Input", attrib = { name = "showMinion", boolean = "true" } } })
		assert.are.equal("PLAYER_MINION", build.calcsTab.input.actor)
	end)
end)
