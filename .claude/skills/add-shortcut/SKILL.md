---
name: add-shortcut
description: How to add a Sendpoint global shortcut (ShortcutSlot, HotKeyRegistrar, settings pane, status menu, tests). Use before adding or changing a hotkey.
---

# Adding a shortcut

`ShortcutSlot` lives in `Sources/Sendpoint/Input/ShortcutSettings.swift`. Add a slot in this order:

1. Add the case. Put it in `allCases` (`selectStack` is generated as `selectStackCases`). Add `rawValue`, `title`, and `isOptional`. `.dictate`, `.selectStack`, and `.editLatest` are optional and may have no combo. `clearShortcut` returns immediately unless the slot is optional.
2. Give a required slot a default in `fixedDefaultCombos`. Give an optional slot a default in `optionalDefaultCombos` only when the combo should appear if it is free (select stack, edit latest). Dictate is optional, but its default is in `fixedDefaultCombos`: it starts bound, and clearing it stores the empty unbound marker. An optional slot with no default goes in neither map. The defaults key is `slot.rawValue + "Combo"`.
3. Add a closure on `HotKeyRegistrar.Actions`. Handle the case in the `switch slot` inside `HotKeyRegistrar.register`. `HotKeyName.slot` already wraps every `ShortcutSlot`. Do not add a `HotKeyName` case.
4. Pass that closure from `AppDelegate.registerHotKeys` in `Sources/Sendpoint/App/AppDelegate+Actions.swift`. That closure is the behavior. Edit latest calls `latestNoteEditor?.model.send(.open)`.
5. Show a `ShortcutSpec` in the pane that already lists that group. `SettingsCapturePane` lists `.voiceCapture`, `.capture`, and `.dictate`. `SettingsStacksPane` lists `ShortcutSlot.selectStackCases`, then `.stack`, `.editLatest`, and `.clear`. `SettingsPastingPane` lists `.copy`. `ShortcutRows` writes the combo through `hotKeyRegistrar.updateShortcut`. The recorder is clearable when `slot.isOptional`. Do not call `setShortcut` from the view.
6. `StatusMenuModel.items` shows a combo for voice note, typed note, dictate (only when `dictateCombo` is set), show stack, each stack, copy, and clear. It does not show edit latest. Add a row only if this shortcut belongs in the status menu: a `StatusMenuAction` case, an entry in `items`, and a case in `AppDelegate.perform`. `MainMenu.build` is Close Window and the Edit menu. It does not list `ShortcutSlot`s. Do not add one there.
7. Add a test beside the suite for that group: `VoiceShortcutSettingsTests`, `StackShortcutSettingsTests`, `HotKeyRegistrarTests`, or `StatusMenuModelTests` when the menu shows the combo.

