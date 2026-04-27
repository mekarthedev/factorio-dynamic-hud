A mod for Factorio that hides all HUD/UI by default and then dynamically shows only relevant parts of UI based on player's current in-game actions. Inspired by burn-in marks on my OLED.

# Features

- Keeps currently irrelevant UI hidden. You can reveal all your UI by opening your character inventory.
- Waits for a delay before hiding parts of the UI that stop being relevant right now (configurable delay).
- Shows minimap only while you are driving (configurable).
- Brings up weapons/ammo/toolbar when you are shoting, getting attacked, switching guns, or just managing your armor and ammo.
- Shows quickbar only when using its hotkeys (configurable).
- Shows reasearch progress panel only temporarily to notify about finished research.
- Shows alerts only when there were recent changes to active alerts (configurable).
- Shortcuts bar is kept visible when using wires, so that you can easily switch to a different wire type.
- Hides other mods buttons (configurable).
- Built-in hotkey to disable auto-hiding (Alt + H by default).
- Helps keeping your OLED safe from burn-ins as a bonus.

Look up *Dynamic HUD* in *Settings → Mod settings → Per player* to configure some of the behavior.

# Known issues and limitations

- Blueprints, planners and remotes cannot be selected from hidden quickbar with a hotkey (expected to be fixed in Factorio 2.1).
- When driving a vehicle with a character (not remotely), the vehicle's weapons/ammo bar will not be hidden.
- List of pins, if there are any, will not be hidden (expected to be fixed in Factorio 2.1).
- Hidden UI will not reappear in existing saves on its own after this mod is uninstalled. See below.

# How to uninstall

If you have a save file where UI is hidden with this mod, remember to re-save with all UI turned back on. Use this mod's hotkey (default Alt + H) to turn it on. Otherwise hidden UI would not reappear on its own. After that the mod can be uninstalled.
