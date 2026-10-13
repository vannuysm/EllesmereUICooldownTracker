# In-game buff-state checks

Enable Lua errors with `/console scriptErrors 1`. Set Buff Bars to **Always**, lock the tracker, and leave Unlock Mode. Choose two learned, self-cast timed buffs A and B with different durations (for example, a paladin's Blessing of Might and Seal of Righteousness). Use exact names initially. Change lists through the Tracked Buffs editor and profiles through the Profiles page, without reloading between changes.

1. **Removal:** Track `[A, B]`, activate only A, then remove A while its timer is running. B must stay hidden. Unlock the tracker briefly: B must have its own label/icon, an empty bar, and no countdown.
2. **Reordering:** Restore `[A, B]` with only A active and move B above A. Only A must show. Activate B too, then reorder again: visible bars must follow the configured order with their own icons, names, and durations. Repeat with A inactive and B active.
3. **Profiles:** Save one profile with `[A, B]` and another with `[B]`. Activate only A and load the first, then the second. B must not display A or its countdown. Load the first again and confirm A is tracked normally. Also load a profile replacing A at index 1 with a third inactive buff C; C must not inherit A's state.
4. **Surplus frames:** With two active bars, remove the second entry. Run the command below immediately and again after its former expiration time. The frame must be hidden and every printed tracking field must be nil. Repeat after disabling Buff Bars and removing the entry. Re-enable and add a different inactive buff at index 2; it must start empty.

   ```lua
   /run local b=EUICT_Buff.items[2]; print(b:IsShown(),b.entry,b.aura,b.auraID,b.lastDuration,b.endsAt,b.synthetic,b.timerObject)
   ```

   On clients with duration-object status bars, also run `/dump EUICT_Buff.items[2].bar:GetTimerDuration():IsActive()` after removal: the replacement zero-duration object must be inactive. Verify the icon cooldown sweep has stopped. The reset uses a guarded [CreateDuration](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/DurationUtilDocumentation.lua) and [SetTimerDuration](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua); clients without those APIs use the manual bar value and cooldown clear.
5. **Unchanged entries and unreadability:** Track only A, cast it, and record `/dump EUICT_Buff.items[1].lastDuration`. Let it expire naturally; the bar must disappear while that duration remains. Cast A again, then use the test-only command below to make aura queries fail deterministically. Existing A must continue its fallback countdown. Recast A: a synthetic timer must restart using A's recorded duration. Inspect `/dump EUICT_Buff.items[1].synthetic` and `/dump EUICT_Buff.items[1].endsAt`.

   ```lua
   /run EUICT_TestAuras={}; for _,k in ipairs({"GetBuffDataByIndex","GetAuraDataByAuraInstanceID","GetPlayerAuraBySpellID"}) do EUICT_TestAuras[k]=C_UnitAuras[k]; C_UnitAuras[k]=function() error("test aura unreadability") end end
   ```

   While queries still fail, replace A with B at the same index and cast B. For an entry without a built-in duration (Consecration has one), `lastDuration`, `synthetic`, and `endsAt` must remain nil: B must not borrow A's duration. Restore the APIs, repeat the A setup and unreadability simulation, then remove all entries while A's synthetic timer is active and repeat the surplus-state check for frame 1. These overrides affect other aura consumers too; use a test session and restore them immediately with the command below, or `/reload`. Do not run the override twice without restoring it.

   ```lua
   /run for k,v in pairs(EUICT_TestAuras) do C_UnitAuras[k]=v end EUICT_TestAuras=nil
   ```

6. **Prefixes and combat:** With normal APIs restored, track a prefix such as `Seal of`, activate a matching buff, and change to another matching buff. Tracking and recasts must still work for that unchanged prefix. Repeat expiration and recasting in combat on clients that restrict aura values; check for Lua errors and correct fallback timing. The test overrides above exercise query failures, but do not reproduce actual secret values or verify the client's timer engine.
