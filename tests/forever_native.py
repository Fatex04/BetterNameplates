"""Integration regressions for Forever's stock nameplate frame shape (Lua 5.1).

Uses BNP's local strict widget fixture; no other addon or live account data is required.
"""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tests/forever_native_fixture.lua'

NATIVE = r'''
cvars={nameplateStyle='0'}
C_CVar={GetCVar=function(key) return cvars[key] end,
    SetCVar=function(key,value) cvars[key]=tostring(value) end}
Enum={NamePlateStyle={Classic=6}}
plate=CreateFrame('Frame','FixtureNamePlate',UIParent)
plate.namePlateUnitToken='nameplate1'
plate.UnitFrame=CreateFrame('Frame',nil,plate)
unitFrame=plate.UnitFrame
unitFrame.unit='nameplate1'
unitFrame.name=unitFrame:CreateFontString()
unitFrame.name:SetText('Native Name')
unitFrame.name.privateContent=true
unitFrame.HealthBarsContainer=CreateFrame('Frame',nil,unitFrame)
bar=CreateFrame('StatusBar',nil,unitFrame.HealthBarsContainer)
unitFrame.HealthBarsContainer.healthBar=bar
bar.Text=bar:CreateFontString(); bar.Text.text=opaque('health'); bar.Text.privateContent=true
unitFrame.LevelFrame=CreateFrame('Frame',nil,unitFrame)
level=unitFrame.LevelFrame:CreateFontString()
level.text=opaque('level'); level.privateContent=true
unitFrame.LevelFrame.LevelText=level
level:SetAlpha(1)
C_NamePlate={GetNamePlates=function() return {plate} end,
    GetNamePlateForUnit=function() return plate end}
UnitExists=function() return true end
UnitCanAttack=function() return false end
UnitIsDeadOrGhost=function() return false end
UnitAffectingCombat=function() return false end
UnitGUID=function() return 'fixture-guid' end
GetTime=function() return 10 end
IsInGroup=function() return false end
NamePlateDriverFrame=CreateFrame('Frame','NamePlateDriverFrame',UIParent)
function NamePlateDriverFrame:UpdateNamePlateOptions()
    self.nativeUpdates=(self.nativeUpdates or 0)+1
    bar.Text:SetFont('NativeFont',10,'')
end
'''


class StockPlates(unittest.TestCase):
    def boot(self, before=''):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(FIXTURE.read_text(encoding='utf-8'))
        lua.execute(NATIVE)
        lua.execute(before)
        addon = lua.table()
        for name in ('Forever.lua', 'Locales.lua', 'Core.lua'):
            lua.execute((ROOT / name).read_text(encoding='utf-8-sig'), 'BetterNameplates', addon)
        lua.execute("dispatch('ADDON_LOADED','BetterNameplates'); flushTimers()")
        self.assertEqual(lua.eval('#reportedErrors'), 0)
        return lua

    def test_nested_forever_bar_gets_readable_native_fonts_without_alias_injection(self):
        lua = self.boot()
        self.assertEqual(lua.eval('cvars.nameplateStyle'), '6')
        self.assertIsNone(lua.eval('unitFrame.healthBar'))
        self.assertIsNotNone(lua.eval('unitFrame.BetterNameplatesOverlay'))
        self.assertEqual(lua.eval('bar.Text.font[2]'), 12)
        self.assertEqual(lua.eval('level.font[2]'), 13)
        self.assertEqual(lua.eval('unitFrame.name.font[2]'), 12)
        self.assertFalse(lua.eval('unitFrame.BetterNameplatesOverlay.inlineName.shown'))
        self.assertFalse(lua.eval('unitFrame.BetterNameplatesOverlay.inlineLevel.shown'))
        self.assertEqual(lua.eval('#BetterNameplatesDB.foreverDiagnostics.errors'), 0)

    def test_disabling_restores_native_fonts_shadows_and_plate_style(self):
        lua = self.boot()
        lua.execute('BetterNameplates.db.enabled=false; BetterNameplates:ApplyNameplateScale(); flushTimers()')
        self.assertEqual(lua.eval('cvars.nameplateStyle'), '0')
        self.assertEqual(lua.eval('bar.Text.font[2]'), 10)
        self.assertEqual(lua.eval('level.font[2]'), 10)
        self.assertEqual(list(lua.eval('bar.Text.shadowColor').values()), [0, 0, 0, 0])

    def test_native_options_refresh_is_followed_by_font_update(self):
        lua = self.boot()
        lua.execute('NamePlateDriverFrame:UpdateNamePlateOptions(); flushTimers()')
        self.assertEqual(lua.eval('NamePlateDriverFrame.nativeUpdates'), 1)
        self.assertEqual(lua.eval('bar.Text.font[2]'), 12)

    def test_secret_health_name_level_are_never_scanned_or_reformatted(self):
        lua = self.boot("unitFrame.name.text=opaque('name'); UnitCanAttack=function() return opaque('reaction') end")
        lua.execute("dispatch('UNIT_HEALTH','nameplate1'); flushTimers()")
        self.assertEqual(lua.eval('bar.Text.text.label'), 'health')
        self.assertEqual(lua.eval('unitFrame.name.text.label'), 'name')
        self.assertEqual(lua.eval('level.text.label'), 'level')
        self.assertEqual(lua.eval('level.alpha'), 1)
        self.assertEqual(lua.eval('#BetterNameplatesDB.foreverDiagnostics.errors'), 0)

    def test_forbidden_plates_are_skipped(self):
        lua = self.boot('plate.forbidden=true')
        self.assertIsNone(lua.eval('unitFrame.BetterNameplatesOverlay'))
        self.assertEqual(lua.eval('bar.Text.font[2]'), 10)

    def test_combat_scale_change_waits_for_regen(self):
        lua = self.boot('combat=true')
        self.assertEqual(lua.eval('cvars.nameplateStyle'), '0')
        self.assertTrue(lua.eval('BetterNameplates.pendingScale'))
        lua.execute("combat=false; dispatch('PLAYER_REGEN_ENABLED'); flushTimers()")
        self.assertEqual(lua.eval('cvars.nameplateStyle'), '6')

    def test_restricted_threat_does_not_remove_stock_labels(self):
        lua = self.boot("UnitCanAttack=function() return true end; UnitDetailedThreatSituation=function() error('restricted threat') end")
        self.assertFalse(lua.eval('unitFrame.BetterNameplatesOverlay.threatFrame.shown'))
        self.assertEqual(lua.eval('bar.Text.font[2]'), 12)
        self.assertEqual(lua.eval('unitFrame.name.text'), 'Native Name')

    def test_manifest_aliases_target_forever_and_load_flavor_first(self):
        manifests = [(ROOT / name).read_text(encoding='utf-8-sig') for name in
                     ('BetterNameplates.toc', 'BetterNameplates_Camelot.toc', 'BetterNameplates_Forever.toc')]
        self.assertEqual(len(set(manifests)), 1)
        self.assertIn('## Interface: 16001', manifests[0])
        self.assertLess(manifests[0].index('Forever.lua'), manifests[0].index('Core.lua'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
