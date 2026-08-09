# AccessXI

AccessXI adds screen-reader accessibility to Final Fantasy XI and PlayOnline. The release includes an Ashita v4 in-game reader, native PlayOnline speech through Prism, navigation data and sounds, and an installer that keeps the setup together.

[Download the latest AccessXI release](https://github.com/buu420/AccessXI/releases/latest). Download the `AccessXI Installer.exe` release asset unless you specifically need the manual ZIP.

AccessXI does not include Final Fantasy XI, a registration code, or a Square Enix account. Complete the official game setup and the first PlayOnline Viewer update before installing AccessXI.

Documentation reviewed: August 7, 2026.

## Setup

Follow these sections in order. The PlayOnline update in step 3 must finish before AccessXI is installed.

### 1. Get Final Fantasy XI and prepare your account

You need both a Square Enix account and a registered Final Fantasy XI service account.

1. [Create a Square Enix account](https://secure.square-enix.com/regist/), or confirm that you can sign in to your existing account.
2. Purchase Final Fantasy XI. The downloadable client is free, but a new player still needs a paid registration code. North American players can use the [official Square Enix store page](https://na.store.square-enix-games.com/final-fantasy_-xi_-ultimate-collection-seekers-edition---digital); players elsewhere should use their regional Square Enix store.
3. Sign in to [Square Enix Account Management](https://secure.square-enix.com/).
4. Choose `PlayOnline / FINAL FANTASY XI`, add or register the service account with the code from your purchase, and make sure it has at least one active character option. The [official registration guide](https://www.playonline.com/ff11us/intro/regist/) shows the account-management sequence.
5. Save the following credentials somewhere secure before opening PlayOnline:
   - Square Enix ID.
   - Square Enix password.
   - PlayOnline ID.
   - PlayOnline password.

Your PlayOnline ID is not your Square Enix ID. A PlayOnline ID normally looks like four capital letters followed by four numbers, such as `ABCD1234`. The Square Enix credentials are for the website and final login; the PlayOnline credentials identify the older game service account.

If you use a Square Enix security token or software token, keep it available for the one-time-password prompt.

### 2. Install the official client

1. Open the [official Final Fantasy XI Windows client download page](https://www.playonline.com/ff11us/download/media/install_win.html).
2. Download all five files. Keep all five download files in the same folder.
3. Run `FFXIFullSetup_US.part1.exe` to extract the installer.
4. Open the extracted `FFXIFullSetup_US` folder and run `FFXISetup.exe`.
5. For a first installation, select all available applications, including PlayOnline Viewer and Final Fantasy XI, and finish the official installers.

Do not run the AccessXI installer yet.

### 3. Update PlayOnline before installing AccessXI

AccessXI's native PlayOnline support recognizes the fully updated viewer. It stays disabled on an old or unknown `app.dll` rather than attach unsafe hooks.

1. Start the normal PlayOnline Viewer from its Windows shortcut or Start menu entry.
2. Wait for the Version Update screen to load.
3. Use screen-reader OCR on the PlayOnline window to find `Version Update` and `Update`.
4. Activate `Update`, then run OCR again to confirm that download or progress text appeared. Do not keep pressing Enter if OCR still shows the unchanged prompt.
5. Wait for the update to download and install. Do not close PlayOnline during installation.
6. If PlayOnline restarts and offers another update, repeat this step until it reaches the normal member screen without another Version Update prompt.
7. Close PlayOnline.

Useful OCR commands:

- NVDA: focus PlayOnline and press `NVDA+R` for Windows OCR. See the [NVDA OCR documentation](https://download.nvaccess.org/releases/stable/documentation/en/userGuide.html#Win10Ocr).
- JAWS desktop layout: press `Insert+Spacebar`, then `O`, then `W`. In laptop layout, press `Caps Lock+Spacebar`, then `O`, then `W`. See the [JAWS hotkey documentation](https://www.freedomscientific.com/training/jaws/hotkeys/).

The [official PlayOnline Viewer manual](https://support.na.square-enix.com/document/manual/20/FFXI_manual_vc09_AE5.pdf) describes the Version Update flow. OCR is needed only because this screen appears before AccessXI can safely provide native PlayOnline speech.

### 4. Install AccessXI

1. Close PlayOnline and Final Fantasy XI.
2. Open the [latest AccessXI release](https://github.com/buu420/AccessXI/releases/latest), download `AccessXI Installer.exe`, and run it.
3. Keep the default AccessXI destination unless you need another folder.
4. Confirm the detected `pol.exe` path. Browse to the correct PlayOnline executable if auto-detection is wrong.
5. Select `Install`.
6. If the installer reports missing Microsoft Visual C++ runtimes, choose `Yes` to run the bundled Microsoft installers. PlayOnline is 32-bit, so the x86 runtime matters even on 64-bit Windows.
7. Confirm that the installer reports `Updated PlayOnline Viewer recognized`. If it reports update-safe mode, close the installer, finish step 3, and run the newest AccessXI installer again.
8. Select `Finish`. The checked option can open an offline copy of this guide.

Whenever you select `Install`, the installer automatically checks the public GitHub release for the current `AccessXI-Ashita-Installer.zip`. It compares the embedded package with GitHub's SHA-256 release digest. If the release package is different, the installer downloads it, verifies its size, digest, and ZIP structure, and only then extracts it. If the check or download is unavailable, the installer clearly reports that it is using the complete embedded package, so installation still works offline. It never installs a partial or mismatched download.

This automatic check updates the AccessXI payload, including the addon, navigation data, Ashita files, native PlayOnline accessibility files, prerequisites, and offline guide. It does not replace the running installer EXE. If a future release changes the installer program itself, download that newer EXE once; rerunning an updater-enabled installer is enough for normal AccessXI payload updates.

The installer creates an `AccessXI Ashita` desktop shortcut. Use that shortcut to start the game from now on.

When upgrading an older AccessXI installation, the installer removes only obsolete files carrying exact AccessXI ownership markers. It preserves unrelated mods, launchers, and games. Current releases do not require Reloaded or a .NET Desktop Runtime.

### 5. Add your PlayOnline member

Launch `AccessXI Ashita`. PlayOnline should now speak the supported menus.

1. Choose `For Members`. If you accidentally choose new registration, close PlayOnline with `Alt+F4`, relaunch it, and choose `For Members`.
2. Press Enter on `For Members`. If focus begins inside a text field, press Escape once so Up and Down move through the setup fields.
3. Fill the fields in this order:
   - `Member Name`: press Enter, type any local name for this saved member, then press Escape.
   - `PlayOnline ID`: press Enter, type the PlayOnline ID from Square Enix Account Management, then press Escape.
   - `Set Password`: press Enter, use Up or Down until AccessXI says `Set Password, Save`, then press Enter. Do not use Left or Right inside this small choice menu.
   - `PlayOnline Password`: after choosing Save, move to the password field, press Enter, type the PlayOnline password, and press Enter to confirm. Ignore the on-screen software keyboard. Password fields announce entry feedback without speaking the password itself.
   - `Member Password`: skip this optional local-computer password unless you specifically want one.
   - `Square Enix ID`: press Enter, type your Square Enix ID, then press Escape.
   - `One-Time Password`: enable this only if your Square Enix account uses a security or software token.
4. Move to `Register`, press Enter, and choose `Yes`.
5. Use OCR to confirm the registration result, then press Enter on `OK`. A second Enter may be required to return to the member screen.

### 6. Log in and start Final Fantasy XI

1. Move to the saved member name and press Enter.
2. Choose `Login`.
3. At `Square Enix Password`, press Enter and type the password used on the Square Enix Account Management website. Enter a one-time password too if your account uses one.
4. Move to `Connect` and press Enter.
5. On a first login, PlayOnline may ask for a handle name and acceptance of an agreement. Enter any handle name you want. Use OCR for long agreement text, move to the end, and activate `Accept` only after reviewing it.
6. Choose `FINAL FANTASY XI` from the spoken PlayOnline menu.
7. Continue through the Final Fantasy XI start screen. If a game update is required, start it, use OCR to monitor progress, and press Enter when it finishes.

When Final Fantasy XI starts, the AccessXI in-game addon loads automatically. Later sessions begin with the `AccessXI Ashita` shortcut, your saved member, `Login`, `Connect`, and `FINAL FANTASY XI`; the account-registration steps are not repeated.

## Hotkeys

Unless a table says otherwise, the bare-letter accessibility keys work only while Final Fantasy XI is the foreground application, chat input is closed, and Ctrl, Alt, and Shift are not held. AccessXI intercepts those keys before Final Fantasy XI can type them into chat.

### Quick status

| Key | Action |
| --- | --- |
| `D` | Read current debuffs. |
| `B` | Read current buffs. |
| `H` | Read current and maximum HP. |
| `M` | Read current and maximum MP. |
| `X` | Read current experience and experience to next level. |

### Navigation

| Key | Action |
| --- | --- |
| `I` | Start GPS directly for the selected mission, quest, or ordinary destination, or stop the active or pending route. |
| `U` | Previous navigation category. |
| `O` | Next navigation category. |
| `J` | Previous item in the current navigation category. |
| `K` | Repeat the current navigation item. |
| `L` | Next item in the current navigation category. |

The navigation browser places `Missions` immediately before `Quests`.
Missions include active missions plus missions the current character is proven able to start.
Quests include only active quests. Use `J`, `K`, and `L` on either category exactly as you do elsewhere, then press `I` to start GPS directly for the highlighted entry.
There is no separate guide-step navigation menu.

AccessXI starts an objective route only when current-session character state
identifies an exact destination in the current navigation data. Available
nation missions lead to an appropriate gate guard. If the client does not
expose enough state to prove the current step, AccessXI keeps the active entry
visible but says that no verified current destination is available. Map-grid
references, wiki prose, conflicts, and unresolved `???` candidates are never
used to guess a route.

When a supported highlighted gear item has active detail text, `J`, `K`, and `L` read that gear instead of moving through navigation:

| Key | Action |
| --- | --- |
| `J` | Previous line of the highlighted gear details. |
| `K` | Repeat the current gear-detail line. |
| `L` | Next line of the highlighted gear details. |

### Chat history

These keys browse AccessXI's captured chat history when chat input and the native Final Fantasy XI log window are closed.

| Key | Action |
| --- | --- |
| `Home` | Previous chat category. |
| `End` | Next chat category. |
| `Page Up` | Previous, older message in the selected chat category. |
| `Page Down` | Next, newer message in the selected chat category. |

### Status, equipment, and Check details

| Key | Action |
| --- | --- |
| `Alt+I` | Read the current Status, Equipment, or Check overview. |
| `Alt+Shift+I` | Read the selected row details in the Status menu. |

### AccessXI Settings and reload

| Key | Action |
| --- | --- |
| `Ctrl+Shift+C` | Open or close AccessXI Settings. |
| `Ctrl+Shift+R` | Reload the AccessXI reader addon. |

While AccessXI Settings is open, Up and Down move between items, Right or Enter opens or activates an item, Left goes back, and Escape closes the menu. The following numpad controls are also available while that menu is open:

| Key | Action |
| --- | --- |
| `Ctrl+Shift+Numpad 8` | Previous AccessXI Settings item. |
| `Ctrl+Shift+Numpad 2` | Next AccessXI Settings item. |
| `Ctrl+Shift+Numpad 6` | Open or activate the AccessXI Settings item. |
| `Ctrl+Shift+Numpad 4` | Go back in AccessXI Settings. |
| `Ctrl+Shift+Numpad 5` | Repeat the current AccessXI Settings item. |
| `Ctrl+Shift+Numpad 0` | Reload the AccessXI reader addon. |

### Other shortcuts shipped in the AccessXI Ashita profile

| Key | Action |
| --- | --- |
| `Print Screen` | Take a screenshot with the game interface hidden. |
| `Ctrl+V` | Paste clipboard text through Ashita. |
| `F11` | Toggle Ashita ambient lighting. |
| `F12` | Toggle the frames-per-second display. |
| `Ctrl+F1` through `Ctrl+F6` | Target alliance slots `<a10>` through `<a15>`. |
| `Alt+F1` through `Alt+F6` | Target alliance slots `<a20>` through `<a25>`. |

## Troubleshooting

If PlayOnline does not speak:

- Make sure you launched it with the `AccessXI Ashita` desktop shortcut.
- Make sure the initial PlayOnline Viewer update finished before AccessXI was installed.
- If PlayOnline updated after AccessXI was released, install the newest AccessXI release. Native hooks remain disabled on an unrecognized viewer build.
- Use OCR on update, agreement, and other long text screens that appear before or outside the supported native menus.

If the in-game reader stops speaking, press `Ctrl+Shift+R` once to reload it. Do not repeatedly reload while the game is zoning.

If a login is rejected, confirm which credential the prompt requests. The PlayOnline ID and password are different from the Square Enix ID and password.

If a Microsoft Visual C++ Runtime error appears, rerun the AccessXI installer and allow it to install the bundled x86 and x64 runtimes. Microsoft also publishes the [latest supported Visual C++ Redistributables](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).

PlayOnline diagnostics are written under `%USERPROFILE%\AccessXI\logs`. The installed offline guide is `%USERPROFILE%\AccessXI\setup-guide.md` when the default destination is used.

## What AccessXI installs

AccessXI installs the Ashita v4 reader and its resources, navigation data and sounds, a native 32-bit PlayOnline accessibility component, Prism speech support, and the `AccessXI Ashita` desktop shortcut.

AccessXI does not modify `pol.exe`, `app.dll`, or the Final Fantasy XI executables. Native PlayOnline accessibility is loaded by the x86 [Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader) from files owned by AccessXI. Installer backups are made before AccessXI replaces its own loader-side deployment.

## For contributors

Repository layout:

- `ashita/addons/accessxi_reader`: canonical in-game addon source embedded by the installer.
- `src`: native PlayOnline accessibility source.
- `installer`: installer application, scripts, boot profiles, and launcher files.
- `tools`: build, packaging, validation, and diagnostic scripts.
- `data`, `sounds`, and `docs`: navigation data, audio assets, and technical documentation.
- `third-party-notices`: notices for release dependencies.

Mission and quest guide data is generated offline from exact, revisioned BG
Wiki and FFXIclopedia snapshots. Source-specific modules and license notices
remain separate; the in-game addon never makes web requests.

Native PlayOnline components must be built for 32-bit x86. Configure `ASHITA4_SDK_PATH` for the local Ashita v4 SDK and provide the reviewed x86 Prism build expected by `tools/build_pol_native_asi.ps1`.

Build and validate the complete release with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_accessxi_installer_exe.ps1
```

The build produces `dist\AccessXI Installer.exe`, `dist\AccessXI-Ashita-Installer.zip`, and `dist\setup-guide.md`. `README.md` is the single maintained setup guide; the release builder copies it to `setup-guide.md` for the installer and offline release asset.

The package builder takes the addon from `ashita\addons\accessxi_reader`, not from a character-specific runtime cache. See [docs/ashita-addon-distribution-notes.md](docs/ashita-addon-distribution-notes.md) for the source and packaging boundary.

## Known limitations

- Final Fantasy XI does not expose a universal live stage number for every
  quest and mission. AccessXI automatically selects a step only from verified
  current-session packet, key-item, inventory, or world evidence; other guides
  use the player's saved manual step.
- A wiki coordinate is not a walked route. Objectives with unresolved dynamic
  targets, source conflicts, unknown doors, one-way terrain, or no verified nav
  connection remain guide-only instead of starting an unsafe route.
- Help Desk > Adventuring Primer: category titles, article titles, and short detail lines are native or DAT-backed. The long article body pages are texture-backed, so AccessXI leaves them silent rather than inventing text.
- Communications > Friend List > Edit Friend List: friend names are visible in native data, but no reliable selected-row signal has been verified. AccessXI leaves that list silent rather than announce the wrong person.
