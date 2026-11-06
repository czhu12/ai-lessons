# When the harness was wrong

The most useful habit in this whole project: **read every 0 before believing it.** About one failure in five early on
was the harness or the grader, not the agent. Here is each one: what the agent seemed to do wrong, what was actually
wrong, and the fix.

## 1. A dialog nobody could see

**Seen:** Calc tasks where the agent "couldn't edit the sheet".

**Cause:** LibreOffice opened with a modal "Tip of the Day", and after a killed session, a Document Recovery dialog,
both in front of the document.

**Fix:** `ShowTipOfTheDay` off in `registrymodifications.xcu`, and the reset removes the `RecoveryList` entries, the
backup folder and the `.lock` file before each task.

## 2. A spreadsheet cut off at 20,000 characters

**Seen:** right-looking work graded 0.

**Cause:** the grader read files with one command through `/run`, which truncates output.

**Fix:** read in 14,000-byte chunks and join them.

## 3. "The page I'm looking at" was in another window

**Seen:** the agent bookmarked the wrong page (task 7a5a7856).

**Cause:** the harness opened each of the task's tabs as its own window, so the one "in front" wasn't the one OSWorld
means.

**Fix:** one `chromium --new-window` with every URL, the last first, as OSWorld's setup leaves it.

## 4. Chromium wasn't running

**Seen:** the first desktop call on a Chrome settings task wasted, landing on a New Tab page.

**Cause:** setup didn't start Chromium, and Canine's `windows.open_url` with a `chrome://` URL when Chromium isn't
running starts it with the URL on the command line, which Chromium ignores for `chrome://` pages. That last part is a
real Canine bug (chapter 6); the harness now starts Chromium itself, as OSWorld's `launch` step does.

## 5. Missing setup and getter types

Each looked like an agent failure until the task's JSON was read:

- **`host_reference_date`** (the employee-ages task): writes today's date to a file the task depends on. Missing, so
  the agent rightly said the file wasn't there. Now written, and the grader reads it back.
- **`update_browse_history`**: fills Chrome's history database. Now built from OSWorld's empty SQLite file.
- **`get_vm_desktop_path` / `get_vm_directory_tree`**: missing in the stand-in controller. Omarchy sets
  `XDG_DESKTOP_DIR=$HOME`, so "the desktop" is the whole home directory; the tree is limited to three levels.
- **Live cookies** need a CDP connection; switched to reading the cookie file.

## 6. Skipped GUI setup hid which slide the task meant

**Seen:** "Could you help me add a strike-through on the first and second line?" of "our soccer club's to-do list"
(550ce7e7). The agent struck through two lines, said `done`, and got 0.

**Cause:** OSWorld's setup clicks the slide pane and presses Down to bring **slide 5** to the front. The harness
skipped that pyautogui step, so the agent saw slide 1 and picked the first bullet list it found, on slide 2. The right
lines, on the wrong slide.

**Lesson:** a setup click can be part of the instruction ("the one I'm looking at"). *Fix, not yet made:* replay
clicks that select something, or say what's selected in the context line.

## 7. No Ctrl+S, and gold files saved by LibreOffice

**Seen:** "duplicate the last two slides in alternating order" (9ec204e4). The agent's 26 slides were right, checked
three ways. Score 0.

**Cause:** the agent wrote the .pptx with a script. The gold file was saved by LibreOffice, and `compare_pptx_files`
compares shape names and sizes exactly. The script's file kept PowerPoint's names ("Title 4"; LibreOffice writes
"PlaceHolder 2") and sizes a few hundred EMU off LibreOffice's rounding. On OSWorld, the postconfig's Ctrl+S would
have re-saved the document from LibreOffice (which had reloaded the agent's file).

**Tested:** saving the agent's file through headless LibreOffice on another machine fixed the names and sizes, but one
text box's height still differs: LibreOffice sizes it from the fonts it renders with. Only a real Ctrl+S on the
computer would settle it. *Fix, not yet made:* do the postconfig with the computer-use server's keyboard.

## 8. Things outside the harness

- **The laptop slept.** Two runs froze overnight; one counts as 0 in the Qwen results. Batches now run under
  `systemd-inhibit`.
- **A one-off "No running VM pod"** from the port-forward, with the VM up the whole time. The task was rerun.

## Check yourself

**Q: The agent says `done`, its summary describes exactly the right change, and the score is 0. What do you check
first?**

<details>
<summary>Answer</summary>

The task's JSON: the setup steps the harness skipped, and the postconfig. Then the grader's log, for the first
comparison that differed. Both "done but 0" Impress runs were the harness.

</details>

**Q: Why did re-saving with LibreOffice on a laptop not prove whether 9ec204e4 would pass?**

<details>
<summary>Answer</summary>

Shape heights depend on the fonts available where LibreOffice renders. The laptop's fonts aren't the computer's (or
OSWorld's VM's), so one text box came out a different height.

</details>

Next: [Results](04-results.md).
