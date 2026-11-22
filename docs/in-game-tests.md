# Testing in the game

These tests check what only playing can show. Each one says what to do, what you
should see, and what to send back. Type each command into the chat box exactly
as shown and press Enter.

## Before you start

1. Get the latest test build. On the pull request (or the latest commit on
   `main`), open the CI run's summary page and download the file under
   Artifacts. GitHub zips it again, so unzip it once to get
   `EarCollector-….zip`.
2. Delete your old `Interface/AddOns/EarCollector` folder, then unzip the new
   zip into `Interface/AddOns/`.
3. Make the game show addon errors, then reload:
   ```
   /console scriptErrors 1
   ```
   ```
   /reload
   ```
   If an error box appears at any point, take a screenshot of it.
4. Turn on the addon's log:
   ```
   /ears debug
   ```
   From now on, chat prints a line for every kill, honorable kill and death the
   addon notices, and saves it. It stays on until you type `/ears debug` again.

When you're done, type `/reload` or log out (the game saves the log only then),
and send the files listed under [Reporting back](#reporting-back).

## Saved data

The addon keeps your ears in files the game saves when you log out. If the game
doesn't load those files back, every ear vanishes at logout. You need two
characters on the same account with the addon enabled for both (a new level 1
character is fine as the second one).

1. On your main character, type:
   ```
   /run EarCollectorDB.check="account" EarCollectorCharDB.check="character" print("Saved")
   ```
   Chat says `Saved`.
2. Type `/reload`. The screen reloads.
3. Type:
   ```
   /run print(EarCollectorDB.check, EarCollectorCharDB.check)
   ```
   Chat should say `account character`.
4. Exit the game completely. Start it again and log in on the same character.
   Type the command from step 3 again. It should still say `account character`.
5. Log out, log in on your second character, and type the command from step 3.
   It should say `account nil`. The settings are shared by all your characters
   ("account"), but each character has its own ears ("nil": this one has none
   of the first character's).

Send back what chat said at steps 3, 4 and 5. The two test words are harmless to
leave in the files.

## Kills

1. Kill any mob. Chat shows a line that starts with `PARTY_KILL` and ends with
   `not a player`. That shows the game tells the addon about your kills.
2. Kill an enemy player in the open world, landing the killing blow yourself.
   Chat shows a line ending in `new ear (you)`, then
   `You collected <name>'s Ear. Appraising the fight...`. When you leave
   combat, chat says `Appraised <name>'s Ear: <grade>.` and a sentence about the
   fight, and the pop-up appears. A line starting `APPRAISAL` shows the arithmetic: send it
   with your report.
3. Hover over the ear's name in that line, or find the ear in the pouch
   (`/ears`). The tooltip shows the victim's full name, surname included, their
   level, race and class. Under "Why it's <grade>", each reason has a green +
   or a red - and one to three squares on the right, for example
   "+ Took more than a full health bar". Then where you killed them, and last, a
   gold sentence in quotes about the fight. If the squares are hard to tell
   apart, or the sentence wraps into a tall, narrow column, take a screenshot.
   If it says "No record of the fight", say so.
4. In a group, let a groupmate land the killing blow on an enemy player. The line
   ends in `new ear (group)`, and the ear names who landed the blow.
5. If you play a class with a pet, let your pet finish an enemy player. The line
   should end in `new ear (you)`. If it ends in `not you or your group`, say so.
6. Kill an enemy player in a battleground. The line ends in `instance:pvp`, and
   no ear drops.

If step 2 prints nothing at all, paste this line, kill another enemy player, and
take a screenshot of what it prints:

```
/run local function S(v)return v==nil and"nil"or issecretvalue(v)and"<S>"or tostring(v)end local f=CreateFrame("Frame")f:RegisterEvent("PARTY_KILL")f:SetScript("OnEvent",function(_,e,a,b)print(e,S(a),S(b))end)
```

## Assists

An assist is an ear for a kill someone outside your group finished, when you
damaged the victim or earned honor for it.

1. Without a group, fight an enemy player alongside a friendly player who isn't
   in your group, and let them land the killing blow. If you earned honor, chat
   shows a line with `+1 honorable kill(s)`, and a few seconds later one ending
   in `new ear (assist)`. The pop-up says "Assist".
2. If you see `honorable kill(s) not tied to one victim` instead, note how many
   enemy players died around that moment.
3. Kill an enemy player whose level shows grey to you. No honorable-kill line
   appears, and the ear is grey (Poor).
4. Hit an enemy player too low to give you honor, and let a guard or a player
   outside your group finish them. When you leave combat, chat shows a line
   ending in `new ear (assist, damage)`, and a grey assist ear drops. If the
   line ends in `no assist:` instead, take a screenshot: it says why.

## Your deaths

The addon reads the game's death recap (the record of what killed you) to learn
who killed you.

1. Have an enemy player kill you in the open world while they're your target or
   their nameplate is showing. About a second after you die, chat shows a line
   that starts with `PLAYER_DEAD`. Its ending says what happened:
   - `death recorded`: it works, and chat also says `<name> killed you.`
   - `no death recap`: the game didn't record who killed you.
   - `recap names no killer`: the record is there, but without a name.
   - `killer isn't an enemy player you saw or damaged (names: ...)`: take a
     screenshot, and note the killer's name as the game showed it on screen.
2. Die to an enemy player you hit during the fight, with your target cleared and
   their nameplate hidden. The line should say
   `death recorded by name, from the damage meter`.
3. Die in a battleground or a dungeon. The line ends in `ignored:` and nothing
   is recorded.

## Vengeance

This needs "Your deaths" to work.

1. Die to an enemy player in the open world. Chat says `<name> killed you.
   Revenge owed: their next ear is worth more.`, they appear on the pouch's
   Rivals tab with 1 under Lost, and their row shows "Avenge" in orange.
2. If you kill them now, the pop-up says "Revenge!", and the ear's tooltip says
   "+ Avenged your death". Their row loses the "Avenge" mark.
3. Die to the same player three times without killing them. Chat says
   `Vengeance owed`. Kill them: the ear is orange (Legendary), the pop-up says
   "Vengeance!" and plays the legendary loot sound, and the ear's tooltip says
   how many deaths it avenged.
4. A player who has killed you at least twice, and more often than you've
   killed them, shows "Nemesis" in red.
5. The Ledger tab's "Ears lost" box counts your deaths.

## Grudges

This needs "Your deaths" to work, and enemy nameplates on (press V).

1. Die to an enemy player, then hover them while they're still around. Under
   their tooltip, an orange line says "You owe them one: their next ear is
   worth more" and a grey line when they took your ear. Nothing else happens:
   no chat line, no pop-up.
2. On a later day (at least 6 hours after you last fought them), let them come
   into view again. Chat says `You owe <name> one. They took your ear on
   <date>. Their next ear is worth more.` Seeing them again that day says
   nothing more. If you're already fighting when they first show up, no
   reminder comes that day.
3. For someone who took your ear three times in a row, step 2 also shows a red
   pop-up framed in orange: "You owe them one", their name, and "Their next ear
   is Legendary". It plays the raid warning sound. If there's no sound, say so.
4. In Options > AddOns > Ear Collector, turn off "Raid warning for an old
   grudge": the next reminder is silent.
5. If none of this happens for someone you know you owe, run `/ears debug`, look
   at them, and send the log.

## The pouch

1. `/ears` opens the pouch with a bag-opening sound, and its close button and
   `/ears` close it with a bag-closing sound. The page buttons make the
   spellbook's page-turn sound. Opening your character sheet or spellbook
   while the pouch is open, then clicking the pouch, brings the pouch in front.
2. On a character's first login with the addon, chat says once how to open
   the pouch. It doesn't say it again after `/reload` or on other characters.
3. The minimap addon drawer lists "Ear Collector" with an ear icon. Hovering it
   shows your totals, and clicking it opens or closes the pouch.
4. In Key Bindings > AddOns, bind a key to "Toggle Ear Pouch" and try it.
5. Press B: the pouch opens with your bags and closes with them, including when
   you close the last bag with its own X. If you opened the pouch with `/ears`
   first, it stays open when the bags close. At a merchant, bank or mailbox your
   bags open but the pouch doesn't. `/ears bags off` stops it opening with your
   bags.
6. Repeat step 4 during a fight. No "action blocked" or "interface action
   failed" message appears.
7. Hover an ear's name in a `You collected` chat line: its tooltip shows, and
   goes when you move away. Click it: the pouch opens on that ear's page,
   highlights it and shows its tooltip.
8. Drag the pouch somewhere else, `/reload`, and open it again. It's where you
   left it.
9. Each slot shows the victim's race as an ear (orc, troll, tauren, undead,
   Skyborne and so on) filling the slot, in one of four skin tones, and the
   same player always gets the same tone. Uncommon and better ears have a frame
   in their grade colour, like items in your bags; Common and Poor have none.
   Poor ears are grey and dimmed. A small dot in the corner shows the victim's
   class colour. If a slot shows a plain green square, the picture didn't load:
   note which race.
10. Collect an ear, then open the pouch: its slot glows. Hovering it stops the
   glow, and so does closing and reopening the pouch.
11. With no ears yet (a new character), the pouch shows "No ears yet" over the
   empty grid, easy to read.
12. Six small coloured squares sit at the top left of the Ears tab, grey to
   orange. Hover the grey one: it says how many Poor ears you have and that
   clicking hides them. Click it, with a checkbox click sound: the square dims
   and gets a red line through it, your Poor ears leave the grid, and the count
   at the top right ends with "N hidden". Close and reopen the pouch, then
   `/reload`: they're still hidden. Click it again to bring them back.
13. Hide Poor, then click a Poor ear's name in chat: the pouch opens on it and
   the grey square is lit again. On another character, nothing is hidden.

## The pop-up

1. Collect an ear. Once the fight ends, a pop-up fades in near the top of the
   screen, in the middle: a bronze panel. If the fight goes on for more than 30
   seconds after the kill, it appears then, saying "Appraising the fight". It shows the ear framed in its grade colour, the name in that colour, and one line under it with the
   grade and the strongest reason, such as "Epic · Outnumbered 1v2". With no
   reason, that line has the level, race and class instead. It says "Ear
   collected" at the top, or "Assist collected" for an assist.
2. A loot sound plays, and a Rare or better ear plays the epic loot sound. A
   Poor ear is silent. Several ears in quick succession play one sound, unless a
   grander one follows.
3. It fades after about 4 seconds. Hovering keeps it up and shows the ear's
   tooltip under it, ending with what clicking does.
4. Left-click opens the pouch on that ear. Right-click dismisses it.
5. Several ears at once stack downward, newest on top, up to three.
6. A Vengeance ear's pop-up says "Vengeance!", with the name in orange.
7. Die to an enemy player: a red pop-up says "<name> took your ear" and
   "Revenge owed", or "Vengeance owed" on the third death. Clicking it opens the
   Rivals tab.
8. `/ears popup move` (or "Move pop-up" in the options) shows a blue stand-in.
   Drag it somewhere, right-click it, and collect an ear: the pop-up appears
   there, and still does after `/reload`. `/ears popup reset` puts it back near
   the top.
9. `/ears sound off` mutes it, and `/ears popup off` stops it.

## Escape

The game keeps a log of addons that interfere with its own buttons (the taint
log). This test checks that closing the pouch with Escape never shows up there.

1. Turn on the log, then reload:
   ```
   /console taintLog 1
   ```
   ```
   /reload
   ```
2. Open the pouch with `/ears` and press Escape. The pouch closes, and the game
   menu doesn't open. Press Escape again: now the game menu opens.
3. Press B (the pouch opens with your bags) and press Escape. Both close, and
   the game menu doesn't open.
4. With the pouch closed, target something and press Escape. Your target clears,
   as it would without the addon.
5. Repeat steps 2 to 4 during a fight (a training dummy will do). Then start
   casting a spell with a cast time, open the pouch, and press Escape: the first
   press stops the cast, the second closes the pouch. No "action blocked" or
   "interface action failed" message appears.
6. Log out, then open `Logs/taint.log` in the game folder and search it for
   `EarCollector`. A line saying the addon changed `UISpecialFrames` is
   expected. Anything else that mentions `EarCollector`, especially next to
   `ADDON_ACTION_BLOCKED`, `ClearTarget`, `SpellStopCasting` or
   `ToggleGameMenu`: copy it into your report.
7. Turn the log off again:
   ```
   /console taintLog 0
   ```

## Options

1. Open Options > AddOns. "Ear Collector" is listed with three sections: "When
   you collect an ear", "Ear Pouch" and "What counts". Each control shows a
   tooltip when you hover over it.
2. Set "Pop-up for" to "Rare and better" and collect an Uncommon ear: no pop-up,
   though the ear is collected. Set it back to "Every ear".
3. `/ears options` opens the same page, and so does right-clicking Ear Collector
   in the minimap addon drawer. Left-clicking it still opens the pouch.
4. Untick "Show a pop-up" and collect an ear: no pop-up, but the ear is
   collected. Tick it again.
5. Type `/ears bags off`, then reopen the page: "Open with your bags" is
   unticked.
6. Set "Repeat kill window" to 0, `/reload`, and reopen the page: it still says
   0 min. Kill the same player twice and you get two ears. Set it back to 10.
7. Click the page's "Defaults" button. Everything returns to its default, and
   the repeat kill window to 10 min.
8. During a fight, type `/ears options`. Chat says the options can't open during
   combat, and no "action blocked" message appears. After the fight it opens.
9. With the taint log on (see "Escape"), change a few options, log out, and
   search `Logs/taint.log` for `EarCollector`. Nothing should mention it except
   the `UISpecialFrames` line.

## Ledger and Rivals

1. Open the pouch. Three tabs sit under it: Ears, Ledger and Rivals. Clicking
   one plays the tab sound and switches pages.
2. The Ledger shows four boxes (Ears, Last 7 days, Assists, Ears lost), a bar
   split by grade with a coloured legend on one line, your top classes with bars
   in class colours, your top zones, and Totals (Players, Kills with repeats).
   Long zone names are cut short, not wrapped.
3. Rivals lists one row per player: anyone marked "Avenge" first, then most
   encounters, with "Lost" and "Last met" columns and the count of rivals in
   the bottom bar. Hovering a row shows a tooltip, and clicking it jumps to their
   latest ear on the Ears tab.
4. With more than ten rivals, the page buttons and the mouse wheel page through
   them. The Ledger hides the page buttons.
5. Collect an ear with the Ledger open: the numbers update.
6. Note anything that overlaps or runs off the window.

## Reporting back

After a `/reload` or logout, attach these to your report (or paste them):

1. `WTF/Account/<ACCOUNT>/SavedVariables/EarCollector.lua`: the addon's log,
   any errors it caught, and your settings.
2. `WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/EarCollector.lua`
   for the character you played: your ears and deaths.
3. Your notes, and screenshots of anything on screen that looked wrong.
4. `Logs/taint.log`, if you did the Escape or Options test and it mentions
   `EarCollector`.

No need to hide names: they're replaced before anything is saved in the
project. The log keeps the newest 300 lines, which holds a long session. If you
test over several sessions, send the files after each one.
