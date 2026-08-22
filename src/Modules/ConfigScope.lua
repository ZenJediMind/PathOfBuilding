-- Path of Building
--
-- Module: Config Scope
-- Classifies Configuration options as shared (encounter), actor, or player-only.
-- Enemy writes are further classified as encounter state or source-owned ("by you") state.
--
local ConfigScope = { }

local PLAYER_VARS = {
	resistancePenalty = true,
	bandit = true,
	pantheonMajorGod = true,
	pantheonMinorGod = true,
	ignoreItemDisablers = true,
	ignoreJewelLimits = true,
}

-- Sections that remain player-only even when Config is viewing the Mercenary.
-- Skill Options are actor-scoped; keep this table for genuinely player-only sections.
local PLAYER_SECTIONS = {
}

local SHARED_SECTIONS = {
	["Enemy Stats"] = true,
	["Map Modifiers and Player Debuffs"] = true,
}

-- Enemy conditions/multipliers whose wording establishes source ownership.
-- Each actor evaluates these against its own overlay; resulting encounter effects
-- (Shock, Exposure, increased damage taken, ...) are published to shared enemy state.
local SOURCE_OWNED_ENEMY_VARS = {
	ChilledByYou = true,
	ChilledByYourHits = true,
	FrozenByYou = true,
	ChilledByYouSeconds = true,
	FrozenByYouSeconds = true,
	BetweenYouAndLinkedTarget = true,
	NearLinkedTarget = true,
	ChampionIntimidate = true,
	HigherLifePercentThanPlayer = true,
}

-- Actor flags that only apply while that actor's hits have chilled the enemy.
-- These mods do not tag ChilledByYourHits themselves, so usage must be implied
-- for Config visibility and overlay gating.
local CHILL_BY_HITS_EFFECT_FLAGS = {
	ChillEffectIncDamageTaken = true,
	ChillEffectIncColdDamageTaken = true,
	ChillEffectLessDamageDealt = true,
}

local scopeByVar = { }
local enemyStateByVar = { }
local indexed = false

local function isSourceOwnedName(name)
	return name and SOURCE_OWNED_ENEMY_VARS[name] or false
end

local function anySourceOwned(value)
	if type(value) == "table" then
		for _, name in ipairs(value) do
			if isSourceOwnedName(name) then
				return true
			end
		end
		return false
	end
	return isSourceOwnedName(value)
end

function ConfigScope.isSourceOwnedEnemyVar(var)
	return isSourceOwnedName(var)
end

function ConfigScope.isSourceOwnedEnemyMod(mod)
	if not mod or not mod.name then
		return false
	end
	local var = mod.name:match("^Condition:(.+)$") or mod.name:match("^Multiplier:(.+)$")
	return var and isSourceOwnedName(var)
end

function ConfigScope.isSourceOwnedEnemyTag(tag)
	if not tag then
		return false
	end
	if tag.type ~= "Condition" and tag.type ~= "Multiplier" and tag.type ~= "MultiplierThreshold" then
		return false
	end
	return anySourceOwned(tag.var or tag.varList)
end

function ConfigScope.impliesChilledByYourHits(modName)
	return modName and CHILL_BY_HITS_EFFECT_FLAGS[modName] or false
end

-- Last-resort classifier for unannotated apply() bodies that write to the enemy list.
-- Source-owned vs encounter must not be inferred from this probe; that is explicit/named data.
local function applyWritesToEnemy(varData)
	if not varData.apply then
		return false
	end
	local wrote = false
	local dummyControl = {
		SetPlaceholder = function() end,
		SetText = function() end,
		SelByValue = function() end,
	}
	local dummyModList = {
		NewMod = function() end,
		AddMod = function() end,
		AddList = function() end,
	}
	setmetatable(dummyModList, {
		__index = function()
			return function() end
		end,
	})
	local dummyEnemy = {
		NewMod = function()
			wrote = true
		end,
		AddMod = function()
			wrote = true
		end,
		AddList = function()
			wrote = true
		end,
	}
	setmetatable(dummyEnemy, {
		__index = function()
			return function() end
		end,
	})
	local dummyBuild = {
		configTab = {
			input = { },
			varControls = setmetatable({ }, {
				__index = function()
					return dummyControl
				end,
			}),
		},
	}
	pcall(varData.apply, true, dummyModList, dummyEnemy, dummyBuild)
	if wrote then
		return true
	end
	pcall(varData.apply, 1, dummyModList, dummyEnemy, dummyBuild)
	if wrote then
		return true
	end
	pcall(varData.apply, "Fire", dummyModList, dummyEnemy, dummyBuild)
	return wrote
end

local VALID_ENEMY_STATE = {
	source = true,
	encounter = true,
}

local function inferEnemyState(varData)
	if varData.enemyState then
		if not VALID_ENEMY_STATE[varData.enemyState] then
			error("ConfigScope: invalid enemyState '"..tostring(varData.enemyState).."' for "..tostring(varData.var))
		end
		return varData.enemyState
	end
	if anySourceOwned(varData.ifEnemyCond) or anySourceOwned(varData.ifEnemyMult) then
		return "source"
	end
	return "encounter"
end

local function inferScope(varData, sectionScope)
	-- Source-owned enemy predicates are per-actor even if a section default is shared.
	if inferEnemyState(varData) == "source" then
		return "actor"
	end
	if varData.scope then
		return varData.scope
	end
	local var = varData.var or ""
	if var:match("^playerCursed") then
		return "actor"
	end
	-- Minion-state options (minionsCondition*, minionsUse*, ifMinionCond) describe the
	-- viewed actor's minions, including Mercenary minions, so they stay actor-scoped.
	if PLAYER_VARS[var] or var:match("^overrideEmpty") then
		return "player"
	end
	if varData.ifEnemyCond or varData.ifEnemyMult or varData.ifEnemyStat
		or var:match("^enemy") or var:match("^conditionEnemy")
		or var:match("^MapPrefix") or var:match("^MapSuffix")
		or var:match("^multiplierMap") or var == "multiplierSextant" or var == "PvpScaling"
		or var:match("OnEnemy") or var == "ShockStacks" or var == "ScorchStacks"
	then
		return "shared"
	end
	if applyWritesToEnemy(varData) then
		return "shared"
	end
	return sectionScope or "actor"
end

function ConfigScope.index(varList)
	scopeByVar = { }
	enemyStateByVar = { }
	local sectionScope = "actor"
	for _, varData in ipairs(varList or { }) do
		if varData.section then
			if PLAYER_SECTIONS[varData.section] then
				sectionScope = "player"
			elseif SHARED_SECTIONS[varData.section] then
				sectionScope = "shared"
			else
				sectionScope = varData.scope or "actor"
			end
		end
		if varData.var then
			local enemyState = inferEnemyState(varData)
			local scope = inferScope(varData, sectionScope)
			scopeByVar[varData.var] = scope
			enemyStateByVar[varData.var] = enemyState
			varData.resolvedScope = scope
			varData.resolvedEnemyState = enemyState
		end
	end
	indexed = true
end

function ConfigScope.forVar(var)
	if not var then
		return "actor"
	end
	return scopeByVar[var] or "actor"
end

function ConfigScope.forVarData(varData)
	if varData and varData.resolvedScope then
		return varData.resolvedScope
	end
	if varData and varData.var then
		return ConfigScope.forVar(varData.var)
	end
	return "actor"
end

function ConfigScope.enemyStateForVar(var)
	if not var then
		return "encounter"
	end
	return enemyStateByVar[var] or "encounter"
end

function ConfigScope.enemyStateForVarData(varData)
	if varData and varData.resolvedEnemyState then
		return varData.resolvedEnemyState
	end
	if varData and varData.var then
		return ConfigScope.enemyStateForVar(varData.var)
	end
	return "encounter"
end

function ConfigScope.isIndexed()
	return indexed
end

return ConfigScope
