-- Tumstock: corrections to the LibRangeCheck item tables, verified on WoW Forever.
-- Normally an item's range comes from its use-spell at runtime (Checks.lua);
-- these are the fallback when that cannot be read.
local _, T = ...

-- Real ranges where the tables are ambiguous or wrong (probes and spell data,
-- 2026-10-12).
T.VerifiedItemYards = {
    [2012] = 20,    -- tables 20 and 40; said "out" at 15-25 yd
    [22048] = 150,  -- table 20; spell 150 (said "in" at 15-25 yd)
    [996] = 35,     -- table 40; spell 35
    [221315] = 60,  -- table 50; spell 60
}

-- "yards:itemID" entries that gave wrong answers in probes.
T.BadItems = {}
