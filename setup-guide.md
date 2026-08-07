# AccessXI Final Fantasy XI Setup Guide

Last reviewed: 2026-07-27

This guide is for a blind player setting up Final Fantasy XI with AccessXI. It assumes you are using speech for the accessible parts and OCR for the first PlayOnline update screen, which appears before AccessXI can safely provide native PlayOnline speech.

The most important thing to know is that Final Fantasy XI setup has two different account layers:

- Your Square Enix account. This is the account you use on the Square Enix Account Management website.
- Your PlayOnline ID. This is the old Final Fantasy XI login ID. Square Enix creates or shows it after Final Fantasy XI is registered to your Square Enix account.

Write down these four things before you start PlayOnline:

- Square Enix ID.
- Square Enix password.
- PlayOnline ID.
- PlayOnline password.

The PlayOnline ID is not your Square Enix ID. Square Enix support describes PlayOnline IDs as four capital letters followed by four numbers, for example `ABCD1234`.

## Important Install Order

Install and update PlayOnline Viewer before running the AccessXI installer. AccessXI's native PlayOnline accessibility is built against the fully updated PlayOnline Viewer files. It deliberately stays disabled on an older or unrecognized `app.dll` rather than risk crashing the viewer.

The first PlayOnline update screen is not expected to speak. Use your screen reader's OCR to find and activate `Update`, then use OCR again to confirm that the download started. After PlayOnline finishes updating and restarts, close it and install AccessXI.

The recommended order is:

1. Create or prepare your Square Enix account.
2. Buy and register Final Fantasy XI.
3. Download and install PlayOnline Viewer and Final Fantasy XI.
4. Start the normal PlayOnline Viewer once, before installing AccessXI.
5. Use OCR to find the Version Update screen and activate `Update`.
6. Use OCR to confirm that the update started, then wait for it to finish.
7. If PlayOnline restarts and offers another update, repeat the OCR-assisted update until no Version Update screen remains.
8. Close PlayOnline.
9. Run the AccessXI installer.
10. Start PlayOnline through the AccessXI launcher and continue with the member setup steps below.

If AccessXI was already installed before PlayOnline was updated, you do not need to uninstall it. The installer supports an update-safe mode, but native PlayOnline menu hooks stay disabled until the recognized updated viewer files are present. Finish the PlayOnline update with OCR, close PlayOnline, and start it again through AccessXI.

## Links You Need First

Create or manage your Square Enix account:

- Square Enix account registration: https://secure.square-enix.com/regist/
- Square Enix Account Management: https://secure.square-enix.com/

Buy and register Final Fantasy XI:

- Official Final Fantasy XI client download page: https://www.playonline.com/ff11us/download/media/install_win.html
- Square Enix Store Final Fantasy XI page, region may redirect: https://sqex.to/ffxi_store_na
- Official account and registration-code guide: https://www.playonline.com/ff11us/intro/regist/
- Official Square Enix support install guide: https://support.na.square-enix.com/faqarticle.php?id=20&kid=59270&la=1

Official PlayOnline setup and login references:

- PlayOnline first-time setup support article: https://support.na.square-enix.com/faqarticle.php?id=20&kid=77435&la=1
- Final Fantasy XI login support article: https://support.na.square-enix.com/faqarticle.php?id=20&kid=77473&la=1
- Final Fantasy XI service fee and character-option information: https://www.playonline.com/ff11us/envi/charge.html
- Official PlayOnline Viewer manual, including Version Update instructions: https://support.na.square-enix.com/document/manual/20/FFXI_manual_vc09_AE5.pdf

OCR references:

- NVDA Windows OCR: focus PlayOnline and press `NVDA+R`. NVDA recognizes the current navigator object, which normally follows focus: https://download.nvaccess.org/releases/stable/documentation/en/userGuide.html#Win10Ocr
- JAWS Convenient OCR for the current application window: press `Insert+Spacebar`, then `O`, then `W`. With the laptop keyboard layout, press `Caps Lock+Spacebar`, then `O`, then `W`: https://www.freedomscientific.com/training/jaws/hotkeys/

AccessXI native dependency link, only needed if the installer or PlayOnline fails with runtime errors:

- Microsoft Visual C++ Redistributable downloads: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist

## Account And Game Setup Before PlayOnline

1. Create a Square Enix account, or make sure you can log in to your existing one.
2. Purchase Final Fantasy XI. New players usually want Final Fantasy XI: Ultimate Collection Seekers Edition, because it includes the game and expansion content.
3. Download the Final Fantasy XI Windows client from the official download page.
4. Download every part of the split installer into the same folder.
5. Run `FFXIFullSetup_US.part1.exe` to extract the installer folder.
6. In the extracted folder, run `FFXISetup.exe`.
7. When the installer asks what to install, choose PlayOnline Viewer, Final Fantasy XI, and the expansion packs.
8. Log in to Square Enix Account Management.
9. Choose `PlayOnline / FINAL FANTASY XI`.
10. Add or register the Final Fantasy XI service account using the registration code from your purchase email.
11. Add at least one character option or Content ID. Final Fantasy XI requires a service account and at least one playable character slot.
12. Find and write down your PlayOnline ID and PlayOnline password. You will need them in the PlayOnline Viewer.

If you use a one-time password or security token on your Square Enix account, keep that device or app nearby. If you do not use a token, leave one-time password set to not used when PlayOnline asks.

## Update PlayOnline Before Installing AccessXI

The official PlayOnline manual says that a Version Update screen appears when a newer viewer is available and that the player selects `Update` to download and install it. Complete this update before expecting AccessXI's native PlayOnline speech.

1. Start the normal PlayOnline Viewer from its Windows shortcut or Start menu entry.
2. Wait for the PlayOnline window and update prompt to finish loading.
3. Run OCR on the PlayOnline application window.
4. Find `Version Update` and `Update` in the OCR result.
5. If your OCR tool can activate or route the mouse to recognized text, activate `Update` from the OCR result.
6. Otherwise, return to the PlayOnline window. If `Update` is the focused or default button, press Enter once.
7. Run OCR again. Progress or download text means the update started.
8. If OCR still shows the unchanged Version Update prompt, do not keep pressing Enter blindly. Use Tab or the arrow keys once, run OCR again, and activate `Update` only when you have located it.
9. Wait for the update to finish. Do not close PlayOnline or turn off the computer while files are being installed.
10. If PlayOnline restarts and presents another Version Update screen, repeat these steps.
11. When the Version Update screen no longer appears and PlayOnline reaches its ordinary setup or member screen, close PlayOnline.

OCR is only being used here to expose the same update prompt and progress information a sighted player sees. AccessXI cannot safely enable its native hooks on the old viewer merely to make that old update screen speak.

## Install AccessXI After PlayOnline Is Updated

After PlayOnline Viewer and Final Fantasy XI are installed and the PlayOnline update has finished, run the AccessXI installer. Do not run the AccessXI installer before installing PlayOnline, because it must find `pol.exe`.

When the AccessXI installer opens:

1. Choose where AccessXI should be installed, or keep the default destination.
2. Confirm the PlayOnline executable path.
3. Click `Install`.
4. The installer should report `Updated PlayOnline Viewer recognized`. This means the installed viewer matches the build supported by this AccessXI release.
5. If the installer instead reports update-safe mode, PlayOnline is still old or is a build this AccessXI release does not recognize. AccessXI can remain installed, but its native PlayOnline speech will stay disabled. Finish the PlayOnline update with OCR and restart PlayOnline.
6. If the installer detects missing Microsoft Visual C++ runtimes, choose whether to let it run the bundled Microsoft installers before AccessXI installs.
7. On the finish screen, leave `Open setup guide when I click Finish` checked if you want this guide to open after installation.

### Upgrading From An Older AccessXI Installer

Current AccessXI releases use a native PlayOnline accessibility component. During an upgrade, the installer checks for the exact folders and PlayOnline files created by older AccessXI installers. When those AccessXI ownership markers are present, it backs up and removes those obsolete files automatically.

The cleanup removes only files with exact old AccessXI ownership markers. It preserves unrelated launchers, other games, other mods, and unknown files instead of guessing. The native `ddraw.dll`, `AccessXI.PolNative.asi`, and its Prism dependency remain installed because they are the current PlayOnline accessibility path.

## Dependency Warning

If PlayOnline or the AccessXI native accessibility component crashes with a dialog like this:

```text
Microsoft Visual C++ Runtime Library
Runtime Error!
Program: C:\Program...
This application has requested the Runtime to terminate it in an unusual way.
```

install the runtime dependencies, then try again.

Install both x86 and x64 versions of the Visual C++ Redistributable. PlayOnline is a 32-bit program, so the x86 package matters even on a 64-bit copy of Windows.

The AccessXI installer includes these Microsoft Visual C++ dependencies. No separate mod framework or .NET Desktop Runtime is required by current AccessXI releases.

## First Accessible PlayOnline Launch After Installing AccessXI

After updating PlayOnline and installing AccessXI:

1. Start PlayOnline through the AccessXI launcher.
2. AccessXI should begin speaking the mapped PlayOnline screens.
3. If a Version Update screen appears instead, native PlayOnline speech may remain silent because the viewer changed. Use OCR to finish the update, close PlayOnline, and install the newest AccessXI release if speech does not return after restarting.

You may land on one of these:

- A `Network`, `Next`, `Cancel` screen.
- An `Add New Registration` screen.
- A `For Members` screen.

You want `For Members`.

If you accidentally activate the new registration option instead of `For Members`, press Alt+F4 to close PlayOnline, then start again. Do not continue through the new registration path.

## Add Your PlayOnline Member

On the `For Members` screen:

1. Press Enter on `For Members`.
2. PlayOnline may put focus inside a text field. Press Escape once so you can arrow freely in the menu.
3. The setup fields and buttons should read.
4. If you go right and land on `What is a PlayOnline ID?`, go left again.
5. Use Up and Down to move through the setup fields.

Fill in the fields in this order.

### Member Name

1. Move to `Member Name`.
2. Press Enter to enter the field.
3. Type any name you want. This is just a local label for this PlayOnline member.
4. Press Escape to leave the field.

### PlayOnline ID

1. Move to `PlayOnline ID`.
2. Press Enter to enter the field.
3. Type the PlayOnline ID from Square Enix Account Management.
4. Press Escape to leave the field.

### Set Password And PlayOnline Password

`Set Password` should speak its current value and each choice while its small menu is open.

1. Move to `Set Password`.
2. Press Enter.
3. Use Up or Down until AccessXI says `Set Password, Save`. Do not press Left or Right here, because Left or Right can close this small menu.
4. Press Enter to select `Save`. This makes the PlayOnline password field appear below `Set Password`.
5. Move to the PlayOnline password field.
6. Press Enter.
7. The software keyboard may appear. Ignore it.
8. Type your PlayOnline password on the real keyboard.
9. Press Enter to confirm the PlayOnline password. Do not press Escape for this password field.

### Member Password

Skip `Member Password`. It is optional and only protects this local PlayOnline Viewer member on this computer.

### Square Enix ID

1. Move to `Square Enix ID`.
2. Press Enter.
3. Type your Square Enix ID.
4. Press Escape to leave the field.

### One-Time Password

Skip this unless you use a Square Enix security token or software token. If you do use one, set this according to your token setup.

### Register

1. Move to `Register`.
2. Press Enter.
3. Choose `Yes`.
4. Use OCR to confirm the success message. It should say the member was registered successfully.
5. Press Enter on `OK`.
6. You may have to press Enter once more.

After this, PlayOnline should put you on the main PlayOnline member screen.

## Log In Through PlayOnline The First Time

The main PlayOnline member screen has two separate rows or groups. The right side has the main options. If you go left, it should place you on your member name.

Your saved member name should speak when you move to it.

1. Move left to your member name.
2. Press Enter.
3. Choose `Login`.
4. When PlayOnline asks for `Square Enix Password`, press Enter.
5. Type the Square Enix password you use on the Square Enix Account Management website.
6. Press Enter if the field needs confirmation.
7. Press Down once to reach `Connect`.
8. Press Enter on `Connect`.

If login works, PlayOnline changes screens.

## First-Time Handle And License Agreement

The first successful login may ask for a handle name. This name is not important for AccessXI gameplay; you will not normally use the PlayOnline Viewer after setup.

1. Type any handle name you want.
2. Press Tab.
3. Press Enter on `Next`.
4. A menu may pop up. Press Escape to leave that menu.
5. You should now be on the license agreement.

Use OCR freely on these screens. OCR works decently here.

For the license agreement:

1. Press or hold Down Arrow until you reach the bottom of the agreement.
2. Use OCR to confirm you are at the bottom and that the accept button is available.
3. Click or activate `Accept`.
4. Press Enter on `OK`.

If everything worked, you will be in the main PlayOnline Viewer screen. AccessXI should read its menu items and changing banner text. Update, agreement, and other long text screens may still require OCR.

## Starting Final Fantasy XI After The First-Time Setup

You have two choices after reaching the mostly inaccessible main PlayOnline Viewer screen.

### Option A: Start Final Fantasy XI From The Current Viewer Screen

This is a rough fallback.

1. Press Right.
2. Hold Down Arrow and listen for fast movement through a list.
3. Hold Up Arrow until you reach the top.
4. Press Down once.
5. Press Enter if the game does not start automatically.

This can work, but it is not the normal flow you will use later.

### Option B: Exit And Use The Normal Accessible Flow

This is the recommended flow.

1. Press Alt+F4, or press Escape until PlayOnline asks to exit.
2. Choose `Yes` on the exit confirmations.
3. Restart PlayOnline through AccessXI.
4. Select your member name.
5. Select `Login`.
6. Enter your Square Enix password.
7. Move to `Connect`.
8. Press Enter.

This time, the AccessXI PlayOnline plugin should move you to the Final Fantasy XI option.

1. Press Enter on `FINAL FANTASY XI`.
2. On the next game screen, press Enter twice if there are no updates.
3. If the game needs an update, press Enter once to start the update.
4. Wait while the update downloads and installs.
5. Use OCR to check progress.
6. When the update says it is finished, press Enter.

After that, Final Fantasy XI should start, and the in-game AccessXI addon takes over.

## Regular Login After Setup

After the first setup is finished, the normal flow is:

1. Start PlayOnline through AccessXI.
2. Select your member name.
3. Select `Login`.
4. Enter your Square Enix password.
5. Move to `Connect`.
6. Press Enter.
7. Press Enter on `FINAL FANTASY XI`.
8. Press Enter through the Final Fantasy XI start/update screen.

If an update is required, start it with Enter, monitor it with OCR, then press Enter when it finishes.

## Server Note

If you want help from other blind players, Leviathan is currently a good server choice because other AccessXI users may be there.

## Troubleshooting Notes

If nothing speaks after PlayOnline restarts:

- Make sure PlayOnline was started through the AccessXI launcher.
- Make sure the initial PlayOnline Version Update was completed before installing AccessXI.
- If PlayOnline just installed a newer update, install the newest AccessXI release. Native hooks intentionally remain disabled on an unrecognized PlayOnline build.
- Try closing PlayOnline with Alt+F4 and starting again.
- If a Visual C++ Runtime Library dialog appears, install the dependencies listed in the dependency warning section.
- If you are at a PlayOnline update or agreement screen, use OCR until you get through it.

If PlayOnline says the PlayOnline ID or password is wrong:

- Check that you entered the PlayOnline ID, not the Square Enix ID.
- Check that the PlayOnline ID looks like four capital letters followed by four numbers.
- Reset or verify the PlayOnline password in Square Enix Account Management.

If PlayOnline says the Square Enix password is wrong:

- Check that you entered the Square Enix password at the Square Enix password prompt.
- If you use a one-time password, make sure the token setting and token code are correct.

If you accidentally enter the wrong registration or new-member path:

- Close PlayOnline with Alt+F4.
- Start again.
- Choose `For Members`, not the new registration option.
