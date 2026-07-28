# Rawlings Demo — Build Schedule
**Builder:** Brian (solo)  
**Started:** Monday 20 July, end of day  
**Target:** Working demo by Thursday EOD  
**Tools:** Salesforce Setup UI · SFDX CLI · Claude Code · Flow Builder · Terminal · ngrok

---

## Status: Monday–Thursday schedule below is Complete

Everything from Task M.1 through Th.5 is built and demoed — the full intake-through-response slice with SFTP simulation, escalation routing, deadline monitoring, audit history, and the full-lifecycle Path chevron. See `rawlings-demo/docs/architecture.md` §3 (Built Components) for the current reference — that document is now the source of truth for what's built, and this schedule is kept as a record of how it was built.

**Remaining work:**
- Proving the platform at volume for a partner + technical-consultant audience — scheduled below in [Bulk Actions & Volume Demo](#bulk-actions--volume-demo--in-progress) (V.1–V.6 done, **V.7 remains**). See `rawlings-demo/docs/architecture.md` §4 for the full design.
- ~~Letting a Settlement show its participating health plans~~ — **done**, see [Settlement Health Plan Junction](#settlement-health-plan-junction--done).
- Splitting the live demo settlement from the seeded volume settlement — scheduled below in [Two-Settlement Restructure](#two-settlement-restructure--in-progress) (R.1/R.2 done, **R.3 remains**). See `rawlings-demo/docs/demo-script.md` and `rawlings-demo/docs/demo-script-open-questions.md` for why.
- ~~Replacing the live SFTP-callout demo beat with a lower-risk report export~~ — **superseded**, see [Response Report](#response-report--done). `ResponseFileWriter.cls`'s native-attach rework (§3.6) made Generate Response File the primary live mechanism instead; the report stays built as an ad-hoc alternative, and verifying its Export into a desktop folder is no longer needed since the demo doesn't write files to a folder at all.
- ~~Letting partners see which liens are near deadline without leaving the Settlement page~~ — **done**, see [Liens Near Deadline](#liens-near-deadline--done).
- ~~Making the escalation reason text specific instead of generic~~ — **done**, see [Escalation Reason Text Update](#escalation-reason-text-update--done).
- Replacing the Static Resource-backed import with a live Screen Flow file upload — **proposed, not started**, see [Claimant Import via Screen Flow](#claimant-import-via-screen-flow--proposed). Optional enhancement; does not block R.3/V.7.

Only two things are left before the demo is rehearsed and ready: **Task R.3** (restage browser/desktop for both settlements) and **Task V.7** (full live dry run).

---

## Continue Here (as of 2026-07-27)

Picking up on another machine? Everything build-related is done — seed data, the Flow text edit, the junction object + records + related list placement, the Response report, the Liens Near Deadline list view **and** its page placement (confirmed live on the volume settlement), and the ResponseFileWriter native-attach rework that makes Generate Response File the primary Beat 6 mechanism. Task P.2 (verifying report Export into a desktop folder) is dropped — the demo no longer writes files to a folder at all. What's left is two tasks, no more building:

1. ~~Finish Task H.1~~ — **done** (related list placed and verified, 3 rows).
2. ~~Task P.1 — build the "Liens Ready to Respond" report~~ — **done** (deployed as metadata, verified via REST API — see Response Report section for details).
3. ~~Finish Task D.1~~ — **done** (Related List - Single component placed on the Settlement page, filtered/sorted per spec, confirmed live on the volume settlement).
4. ~~Task P.2 — verify Export~~ — **dropped**, superseded by Generate Response File becoming the primary live mechanism (see Response Report section).
5. **→ NEXT: Task R.3 — restage browser/desktop (15 min):** Tab 1 = live settlement + Escalation Queue tab; bookmark/tab ready for the volume settlement. Confirm Summary tiles + Bulk Advance are visible without searching.

Then **Task V.7 — full live dry run** (see [Bulk Actions & Volume Demo](#bulk-actions--volume-demo--in-progress)) is the last thing standing between here and a rehearsed demo. Full detail for each numbered task above is in its own section further down this document — this block is just the fast-resume summary.

---

## How to Read This Schedule

Each task shows the tool you'll use, a time estimate, and what done looks like. Tasks marked **⚠️ Risk** are the ones most likely to cause problems. Tasks marked **🤖 Claude Code** mean you open Claude Code and let it work rather than writing code yourself.

The schedule is tight but achievable. Wednesday is the hardest day — protect it from meetings.

---

## Tonight — Monday (1–2 hours)
**Goal:** Claude Code session running, scratch org created. Passive work you can do while winding down.

---

**Task M.1 — Verify SFDX CLI**
*Tool: Terminal | Time: 5 min*

Run `sf --version`. If you get a version number, done. If not, install from developer.salesforce.com/tools/salesforcecli, restart Terminal, verify again.

✅ Done when: `sf --version` returns a version number.

**Update (2026-07-26):** CLI wasn't actually on this machine — installed via `npm install --global @salesforce/cli`, then added `%APPDATA%\npm` to the user PATH (npm's global bin dir wasn't on it). Already authenticated to org alias `rawlings-demo` from an earlier session; `sf --version` and `sf org list` both confirmed working.

---

**Task M.2 — Authenticate Dev Hub**
*Tool: Terminal | Time: 10 min*

```bash
sf org login web --set-default-dev-hub --alias devhub
```

Browser opens. Log into your Dev Hub org. Return to Terminal.

✅ Done when: Terminal shows "Successfully authorized."

---

**Task M.3 — Run Claude Code with the briefing doc**
*Tool: 🤖 Claude Code | Time: 30–60 min (mostly waiting)*

Open Claude Code. Paste the full contents of `claude-code-briefing.md` as your opening prompt. Let it run. While it works, do something else — this is the most passive task in the whole build.

When it finishes, verify these exist:
- `force-app/main/default/classes/` — four files (controller, test, response writer, metas)
- `force-app/main/default/lwc/` — two folders (claimantImport, generateResponseFile)
- `force-app/main/default/objects/` — three folders (Settlement__c, Lien__c, Response__c)
- `docs/flow-build-instructions.md`
- `demo/demo_server.py`

If anything is missing, ask Claude Code to generate it before closing the session.

⚠️ **Risk:** Claude Code may ask about field API names or relationships. Answers: objects are `Settlement__c`, `Lien__c`, `Response__c`; Health Plan is a Lookup to Account; Response is Master-Detail to Lien; return type from import is plain Integer.

✅ Done when: All files generated, Claude Code session complete.

---

**Task M.4 — Create the scratch org**
*Tool: Terminal | Time: 10 min*

Navigate to your project folder and run:
```bash
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias rawlings-demo \
  --duration-days 30 \
  --set-default
```

⚠️ **Risk:** If you get a Dev Hub error, go to Setup in your Dev Hub org, search "Dev Hub" in Quick Find, confirm the toggle is On.

✅ Done when: Terminal shows "Successfully created scratch org."

---

**Tonight check:** Scratch org exists. All code files generated by Claude Code. You're ready to deploy tomorrow morning.

---

## Tuesday — Full Day
**Goal by EOD:** Everything deployed, all Setup UI configuration complete, org fully configured and ready for the Flow.

---

### Morning: Deploy Everything

**Task T.1 — Deploy objects and fields**
*Tool: Terminal | Time: 30 min*

```bash
sf project deploy start \
  --source-dir force-app/main/default/objects \
  --target-org rawlings-demo
```

When complete, open the org and verify:
```bash
sf org open --target-org rawlings-demo
```

Setup → Object Manager → confirm Settlement, Lien, and Response objects exist with their fields.

⚠️ **Risk:** Formula field errors if field references haven't deployed yet. If Settlement formula fields on Lien fail, deploy Settlement first as a separate command, then redeploy Lien.

✅ Done when: All three objects in Object Manager with all fields.

---

**Task T.2 — Deploy Apex and run tests**
*Tool: Terminal | Time: 20 min*

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes \
  --target-org rawlings-demo
```

Then run tests:
```bash
sf apex run test \
  --class-names ClaimantImportControllerTest \
  --target-org rawlings-demo \
  --wait 10 \
  --result-format human
```

If tests fail, read the error — it's almost always a field API name mismatch. Fix in Claude Code, redeploy.

✅ Done when: All tests pass, coverage above 75%.

---

**Task T.3 — Deploy LWC and Quick Action metadata**
*Tool: Terminal | Time: 15 min*

```bash
sf project deploy start \
  --source-dir force-app/main/default/lwc \
  --source-dir force-app/main/default/quickActions \
  --target-org rawlings-demo
```

✅ Done when: Deploy completes with no errors.

---

**Task T.4 — Upload Static Resource**
*Tool: Salesforce Setup UI | Time: 15 min*

Setup → Static Resources → New
- Name: `SampleClaimants` (exact, case-sensitive)
- File: `SampleClaimants.csv` from your project's staticresources folder
- Cache Control: Public
- Save

✅ Done when: Static Resource appears in list with name `SampleClaimants`.

---

**Task T.5 — Create Health Plan Account records**
*Tool: Salesforce Setup UI | Time: 15 min*

App Launcher → Accounts (or Sales app). Create three:
- `Health Plan A`
- `Health Plan B`
- `Health Plan C`

Names must match the CSV exactly.

✅ Done when: Three Account records exist.

---

**Task T.6 — Create the Settlement record**
*Tool: Salesforce Setup UI | Time: 15 min*

App Launcher → Settlement. Create one record:
- Settlement Name: `Hip Implant Mass Tort 2024`
- Administrator: `National Settlement Administration`
- Program Start Date: today minus 82 days
- Response Window Days: `90`
- Status: `Active`

✅ Done when: Settlement record saved.

---

### Afternoon: Setup UI Configuration

**Task T.7 — Create the Escalation Queue**
*Tool: Salesforce Setup UI | Time: 20 min*

Setup → Quick Find → Queues → New
- Label: `Lien Escalation Queue`
- API Name: `Lien_Escalation_Queue`
- Supported Objects: add `Lien__c` and `Task`
- Queue Members: add yourself for now
- Save

✅ Done when: Queue appears in Queues list.

---

**Task T.8 — Create user personas**
*Tool: Salesforce Setup UI | Time: 30 min*

Setup → Users → New User. Create two:

**Ops Analyst:**
- Name: `Ops Analyst`
- Email: a real email you can access
- Username: `ops.analyst@rawlings-demo.com`
- Profile: Standard User
- Save → activate via email
- Return to Escalation Queue → add as queue member

**Health Plan A User:**
- Name: `Health Plan A User`
- Email: another real email
- Username: `hpa.user@rawlings-demo.com`
- Profile: Standard User
- Save → activate via email

⚠️ **Risk:** If you hit a license limit, skip Health Plan A User — narrate the access control story rather than demonstrating it live.

✅ Done when: Both users activated, Ops Analyst in queue.

---

**Task T.9 — Add Quick Actions to page layout**
*Tool: Salesforce Setup UI | Time: 20 min*

Setup → Object Manager → Settlement → Page Layouts → Settlement Layout
- Find "Salesforce Mobile and Lightning Experience Actions" section
- Drag `Import Claimants` and `Generate Response File` into that section
- Save

✅ Done when: Both actions in the layout actions section.

---

**Task T.10 — Configure Settlement Lightning Record Page**
*Tool: App Builder | Time: 30 min*

Setup → Object Manager → Settlement → Lightning Record Pages → Edit default page
- Confirm Highlights Panel component is present (Quick Actions appear here)
- Add Related List component for Lien
- Configure Lien related list columns: Lien Name, Claimant Name, Health Plan, Stage, Deadline Status, Days Remaining
- Save → Activate → Activate for all users

✅ Done when: Settlement record shows both Quick Actions in action bar and Lien related list with correct columns.

---

**Task T.11 — Create Escalation Queue list view**
*Tool: Salesforce Setup UI | Time: 15 min*

Go to the Lien tab → list view controls (gear) → New
- Name: `Escalation Queue`
- Filter: Stage equals Escalated
- Columns: Lien Name, Claimant Name, Health Plan, Escalation Reason, Intake Date, Response Deadline, Days Remaining
- Visible to all users
- Save

✅ Done when: List view exists and shows correct filter.

---

**Task T.12 — Add remaining lifecycle stages and configure the Path (chevron)**
*Tool: Terminal + Salesforce Setup UI | Time: 30–40 min*

Goal: make the full lien lifecycle visible on the record — including the stages this prototype doesn't automate (Recovery Calculation, Collection & Disbursement) — so the chevron communicates that the platform is built to track the whole process, not just intake and response.

1. Edit `force-app/main/default/objects/Lien__c/fields/Stage__c.field-meta.xml` and add two new picklist values, inserted before `Closed`:
   - `Recovery Calculated`
   - `Collected`

   Redeploy:
   ```bash
   sf project deploy start \
     --source-dir force-app/main/default/objects/Lien__c/fields/Stage__c.field-meta.xml \
     --target-org rawlings-demo
   ```

2. Setup → Object Manager → Lien → Path Settings → New
   - Object: `Lien`
   - Picklist field: `Stage`
   - Record Type: default/Master
   - Include all stage values in order
   - Optional: set 1–2 key fields per step (e.g., show Recoverable Amount on Coverage Confirmed; skip fields on steps with nothing to show)
   - Activate the Path

3. Add the Path component to the Lien Lightning Record Page (Setup → Object Manager → Lien → Lightning Record Pages → default page → drag Path above the Highlights Panel → Save → Activate for all users).

4. No automation needed for the new stages. Path lets a user click a later step and manually mark the record complete through that point — that's sufficient for the presenter to move a lien from Agreed → Recovery Calculated → Collected live during the demo narration.

⚠️ **Risk:** Only one Path can be active per object/record-type combination — if a duplicate gets created, deactivate the extra one.

✅ Done when: Opening a Lien record shows the full chevron (Intake through Closed), and a demo record can be advanced through the later steps manually.

---

**Task T.13 — Enable field history tracking and add the History related list**
*Tool: Salesforce Setup UI | Time: 20–25 min*

Goal: back up the "the system moved it, not a person" narration beat with real data — every Stage/Status change should show who changed it and when, not just be described in the script.

1. Object Manager → Lien → Fields & Relationships → open `Stage__c` → Edit → check **Track Field History** → Save. Repeat for `Coverage_Result__c` and `Escalation_Reason__c`.
   (Object-level history is already enabled on Lien — `enableHistory` is `true` in the deployed metadata — so the checkbox is available immediately, no object-level step needed first.)

2. Object Manager → Response → Details → Edit → check **Track Field History** at the object level → Save. Then Fields & Relationships → open `Status__c` → Edit → check **Track Field History** → Save.
   (Settlement is intentionally skipped — it's static config data that won't visibly change during the demo, so there's nothing to gain from tracking it.)

3. Add the History related list to the Lien Lightning Record Page (Setup → Object Manager → Lien → Lightning Record Pages → default page → drag the History related list into a tab or section → Save → Activate for all users). Add it to Response too if time allows.

⚠️ **Risk:** Field history only captures changes made *after* tracking is turned on — nothing retroactive. Do this before Wednesday's Flow work (W.2/W.3) so the automated Stage transitions get captured, and before Thursday's dry-run data is created. If you already ran T.14's smoke test before this task, its test records won't have history — that's fine, they get deleted anyway.

✅ Done when: A manually edited Stage or Status value shows up in the History related list with old value, new value, changed by, and timestamp.

---

**Task T.14 — Smoke test the import**
*Tool: Salesforce | Time: 20 min*

Open the Settlement record. Click Import Claimants. Run Import. Confirm:
- Toast fires
- Lien related list shows records
- Some records are at Coverage Confirmed stage (Flow should have fired)
- Some records are at Escalated stage

If no stage transitions happened, the Flow hasn't been built yet — that's tomorrow. For now just confirm the import creates records. Delete the test records after.

✅ Done when: Import creates lien records. Data cleaned up.

---

**Tuesday check:** All code deployed, tests passing, Static Resource uploaded, org fully configured. Everything is in place for the Flow tomorrow.

---

## Wednesday — Full Day
**Goal by EOD:** Flow built and tested, ngrok working, Python server tested, response file end-to-end verified.

This is the hardest day. Protect it.

---

### Morning: The Flow

**Task W.1 — Read flow-build-instructions.md fully before touching Flow Builder**
*Tool: Text editor | Time: 20 min*

Open `docs/flow-build-instructions.md` and read it completely before opening Flow Builder. Have it open alongside Flow Builder throughout the morning. Know where you're going before you start clicking.

---

**Task W.2 — Build the Flow**
*Tool: 🏗️ Flow Builder | Time: 3–4 hours*

Setup → Flows → New Flow → Record-Triggered Flow
- Object: `Lien__c`
- Trigger: A record is created
- Optimize for: Actions and Related Records (after-save)
- Click Done

Build in this order — don't skip ahead:
1. Decision element — the two-condition branch
2. Automated Path: Update Records (Stage to Coverage Confirmed)
3. Automated Path: Create Records (Response record)
4. Escalation Path: Update Records (Stage to Escalated, Escalation Reason)
5. Escalation Path: Create Records (Task assigned to queue)

**For the Task OwnerId:** Setup → Queues → click Lien Escalation Queue → copy the ID from the URL (starts with `00G`). Paste directly into the OwnerId field.

⚠️ **Risk:** Always use the field picker dropdowns — never type field API names manually.

⚠️ **Risk:** Save frequently. Flow Builder does not auto-save.

Save as `Lien Automation on Create` → Activate.

✅ Done when: Flow saved, activated, Status = Active in Flows list.

---

**Task W.3 — Test the Flow**
*Tool: Salesforce Setup UI | Time: 45 min*

Run the Import Claimants action again on your Settlement record. This time the Flow should fire on creation.

Verify automated path:
- Coverage Confirmed liens exist in related list
- Each has a child Response record with Draft status and correct amount

Verify escalation path:
- Escalated liens exist
- Each has escalation reason populated
- Each has a Task assigned to the Lien Escalation Queue

⚠️ **Risk:** If routing isn't happening, confirm the Flow is Activated not just Saved. Open Flow Builder → Debug to trace execution.

Delete test records after verifying. Empty org ready for afternoon.

✅ Done when: Both paths verified, test data cleaned up.

---

### Afternoon: ngrok and Response File

**Task W.4 — Set up ngrok**
*Tool: Terminal | Time: 20 min*

If not installed: ngrok.com → sign up free → download → `ngrok config add-authtoken YOUR_TOKEN`

Start ngrok:
```bash
ngrok http 8765
```

Note the `https://` forwarding URL. Leave this Terminal window open all afternoon.

✅ Done when: ngrok running, https URL noted.

---

**Task W.5 — Create Named Credential**
*Tool: Salesforce Setup UI | Time: 15 min*

Setup → Named Credentials → Named Credentials tab → New
- Label: `LocalSFTPDemo`
- Name: `LocalSFTPDemo`
- URL: your ngrok https URL
- Identity Type: Named Principal
- Authentication Protocol: No Authentication
- Check: Allow Merge Fields in HTTP Header
- Check: Allow Merge Fields in HTTP Body
- Save

✅ Done when: Named Credential saved.

---

**Task W.6 — Create Remote Site Setting**
*Tool: Salesforce Setup UI | Time: 10 min*

Setup → Remote Site Settings → New
- Name: `LocalSFTPDemo`
- URL: same ngrok https URL
- Active: checked
- Save

✅ Done when: Remote Site Setting saved.

---

**Task W.7 — Deploy ResponseFileWriter**
*Tool: Terminal | Time: 15 min*

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/ResponseFileWriter.cls \
  --source-dir force-app/main/default/classes/ResponseFileWriter.cls-meta.xml \
  --target-org rawlings-demo
```

✅ Done when: Deploy completes with no errors.

---

**Task W.8 — Create desktop folders and start Python server**
*Tool: Finder + Terminal | Time: 15 min*

Create folders:
- `~/Desktop/sftp-demo/inbound/`
- `~/Desktop/sftp-demo/outbound/`

Copy `SampleClaimants.csv` into inbound.

Open a new Terminal window and start the Python server:
```bash
python3 demo/demo_server.py
```

Leave it running.

✅ Done when: Both folders exist, CSV in inbound, server listening message visible.

---

**Task W.9 — End-to-end test**
*Tool: Salesforce + Desktop | Time: 30 min*

Run Import Claimants to create Coverage Confirmed liens. Then click Generate Response File. Wait up to 30 seconds. A timestamped CSV should appear in the outbound folder. Open it and confirm it contains lien data.

⚠️ **Risk:** If no file appears, check the ngrok terminal for incoming requests. If no request shows, check the Remote Site Setting URL matches ngrok exactly. If request shows but no file, check the Python server terminal for errors.

✅ Done when: CSV appears in outbound with correct data. Clean up test data and empty outbound folder after.

---

**Task W.3b — Add escalation notification (Custom Notification)**
*Tool: Setup UI + Flow Builder | Time: 30–40 min*

Right now the escalation Task's `OwnerId` is set to the queue, which is silent — nothing pings when a lien escalates. Add a real-time notification so escalation is visible the moment it happens, not just discoverable by checking the queue.

1. Setup → Quick Find → **Notification Builder** → Custom Notification Types → New
   - Name: `Lien Escalated`
   - Check both **Desktop** and **Mobile**
   - Save
2. Open Flow Builder → `Lien Automation on Create` → Escalation Path
3. ⚠️ **Risk:** Flow's **Send Custom Notification** action takes a collection of *User* IDs as Recipients — it can't target a Queue ID directly. Add a **Get Records** element before the notification action:
   - Object: `GroupMember`
   - Filter: `GroupId` Equals the Lien Escalation Queue ID
   - How Many: All records, store as a collection of `UserOrGroupId`
4. Add a **Send Custom Notification** action after Create Escalation Task:
   - Notification Type: `Lien Escalated`
   - Recipients: the `UserOrGroupId` collection from step 3
   - Title: `Lien escalated for review`
   - Body: reference claimant name, e.g. `{!$Record.Claimant_Name__c} needs coverage review`
   - Target Reference: the Lien record (so clicking the notification opens it)
5. Save, Activate

✅ Done when: running the import (or Debug) with an escalated lien makes the notification bell badge fire for a queue member (test logged in as, or impersonating, Ops Analyst).

---

**Wednesday check:** Flow built and working on both paths. Response file end-to-end confirmed. The core demo is complete. Thursday is polish only.

---

## Thursday — Morning Only
**Goal by lunch:** Dry run complete, data reset, demo ready.

---

**Task Th.1 — Create pre-built deadline threshold record**
*Tool: Salesforce Setup UI | Time: 20 min*

On your Settlement record, create one Lien record manually:
- Claimant Name: `[Pre-existing] Helen Vasquez`
- Claimant ID: `CLM-PRE-001`
- Health Plan: Health Plan A
- Stage: Coverage Confirmed
- Coverage Result: Confirmed
- Recoverable Amount: 5500
- Intake Date: today minus 82 days

Verify Deadline Status shows Red in the list view. If not, adjust the Settlement's Program Start Date until Days Remaining is 8 or fewer.

✅ Done when: Helen Vasquez record shows Red in list view.

---

**Task Th.2 — Stage the demo environment**
*Tool: Finder + Browser | Time: 15 min*

- Confirm `SampleClaimants.csv` is in the inbound folder
- Confirm outbound folder is empty
- Open browser: Tab 1 = Settlement record (Lien list visible, Helen Vasquez showing Red), Tab 2 = Escalation Queue list view
- Open both desktop folders so they're visible
- Position windows so switching between browser and desktop is quick

✅ Done when: Everything positioned exactly as it will be during the demo.

---

**Task Th.3 — Full dry run**
*Tool: All of the above | Time: 45 min*

Start ngrok. Start Python server. Run the complete demo from start to finish as if the client is in the room. Use the demo script from the spec. Time each section — target is under 10 minutes total.

After the run, note anything awkward or broken.

✅ Done when: Full demo runs clean.

---

**Task Th.4 — Fix issues**
*Tool: Whatever is needed | Time: Up to 2 hours*

Address anything from the dry run. Common issues:
- List view columns wrong → fix in list view editor
- Response file slow → acceptable, adjust narration
- Quick Actions in wrong order → reorder in page layout editor
- Lien list not refreshing after import → ask Claude Code to fix NavigationMixin

✅ Done when: Second dry run runs clean.

---

**Task Th.5 — Reset and lock**
*Tool: Salesforce + Finder | Time: 15 min*

- Delete all test Lien records except Helen Vasquez
- Confirm Helen Vasquez shows Red
- Empty outbound folder
- Confirm inbound CSV is in place
- Leave browser tabs positioned

✅ Done when: Org is in exactly the state it needs to be for the real demo.

---

**Thursday check:** Demo ready. Data clean. Folders staged. You have the rest of the week as buffer if anything needs fixing before the client call.

---

## Day of Demo — Pre-Flight (30 min before)

Do these in order:

1. `ngrok http 8765` — note URL
2. If ngrok URL changed: update Named Credential and Remote Site Setting in Setup
3. `python3 demo/demo_server.py` — confirm listening
4. Open browser tabs: Settlement record, Escalation Queue
5. Open desktop folders: inbound (CSV present), outbound (empty)
6. Silent test: Import → confirm liens + Flow routing → Generate → confirm file appears → delete test data, empty outbound
7. Confirm Helen Vasquez is still Red
8. You're ready

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| ngrok URL changes each session | High | Medium | Always start ngrok first, update Named Credential before testing |
| Demo network blocks ngrok | Medium | High | Test on actual demo network before the meeting. Have narrative fallback ready. |
| Flow not routing on Wednesday | Medium | High | Full day allocated. Use Flow Debug to trace exactly where it fails. |
| Apex field names don't match objects | Medium | Medium | Fix in Claude Code, redeploy — 30 min fix |
| @Future callout takes >30 sec | Low | Low | Narrate "give it a moment" — reads as system working |
| Scratch org user license limit | Low | Low | Use admin account, narrate sharing story |

---

## Quick Reference Commands

```bash
# Open scratch org
sf org open --target-org rawlings-demo

# Deploy objects
sf project deploy start --source-dir force-app/main/default/objects --target-org rawlings-demo

# Deploy classes
sf project deploy start --source-dir force-app/main/default/classes --target-org rawlings-demo

# Deploy LWC + Quick Actions
sf project deploy start --source-dir force-app/main/default/lwc --source-dir force-app/main/default/quickActions --target-org rawlings-demo

# Run tests
sf apex run test --class-names ClaimantImportControllerTest --target-org rawlings-demo --wait 10

# Start ngrok
ngrok http 8765

# Start Python server
python3 demo/demo_server.py

# Check scratch org details/expiry
sf org display --target-org rawlings-demo
```

---

## Bulk Actions & Volume Demo — In Progress

**Goal:** Prove the platform handles a real book of business, not just a 15-row CSV — live, for an audience of partners unfamiliar with CRM plus one technical consultant. Full design: `rawlings-demo/docs/architecture.md` §4.

Scope for this pass: Settlement Lien Summary rollup + Bulk Advance Liens batch action. Permission-set gating is intentionally **not** part of this pass — narrated verbally, not built. Seed volume is ~1,000 synthetic records, not the full 100,000 — the batch mechanism underneath is production-shaped regardless of the demo volume.

---

**Task V.1 — Spike: verify GROUP BY on a formula field**
*Tool: Developer Console / anonymous Apex | Time: 10 min | Non-blocking*

Run an aggregate query grouping by `Deadline_Status__c` against a handful of test Liens. Informational only — the Summary controller design (Task V.3) doesn't depend on the answer either way, since it uses `Days_Remaining__c` WHERE-filters instead.

✅ Done when: answer recorded, whichever way it goes.

---

**Task V.2 — Build `LienBulkStageTransitionBatch` + `BulkStageTransitionController` + test**
*Tool: 🤖 Claude Code / IDE | Time: 2–3 hours*

`Database.Batchable` with `QueryLocator`, batch size 2000. Controller methods: `getStageOptions`, `previewCount`, `enqueueBulkTransition`, `getJobStatus`. Server-side from/to validation; `Escalated` omitted from `getStageOptions()` entirely. No permission-set check — see scope note above.

✅ Done when: test class passes, and a manual test against 10–20 hand-inserted Liens correctly previews, enqueues, and moves records with a Field History entry per record.

---

**Task V.3 — Build `SettlementLienSummaryController` + test**
*Tool: 🤖 Claude Code / IDE | Time: 1 hour*

`getSummary(Id settlementId)` — stage counts (picklist order) + Green/Yellow/Red deadline counts via `Days_Remaining__c` WHERE-filtered `COUNT()` queries (not `GROUP BY` on the formula field).

✅ Done when: test class passes, asserting counts against a known small dataset.

---

**Task V.4 — Build `settlementLienSummary` LWC**
*Tool: 🤖 Claude Code / IDE | Time: 1–1.5 hours*

Stat tiles: Total, Escalated, per-stage row, then Green/Yellow/Red row (Red emphasized). Manual Refresh button. Empty state when zero liens.

✅ Done when: deployed and verified against the existing 15–25 row demo data — tile counts match a manual count.

**Update (2026-07-26):** Redesigned the tile layout — the original flat grid of 12 identical boxes read as one undifferentiated block. Now grouped into three labeled sections: Overview (Total + Escalated), Pipeline Stage (pills, zero-count stages hidden behind an "N stages with 0 liens hidden" note instead of shown dim), and Deadline Status (a proportional Green/Yellow/Red bar with an explicit legend — "Green · 20+ days", "Yellow · 11–20 days", "Red · 10 or fewer days" — so the color thresholds aren't left for a partner to guess at). Added `settlementLienSummary.css` (didn't exist before). Deployed to the `rawlings-demo` org and confirmed live on the Settlement record page.

---

**Task V.5 — Build `bulkStageTransition` LWC + Quick Action + page placement**
*Tool: 🤖 Claude Code / IDE + Salesforce Setup UI | Time: 1.5–2 hours*

Select → Preview → Submitting → Queued → Progress (polls `getJobStatus` every 5s). New `Bulk_Advance_Liens` Quick Action on Settlement; add both the action and `settlementLienSummary` to the Settlement Lightning Record Page (summary above the Lien related list).

✅ Done when: end-to-end verified against small data — preview → submit → toast → poll → completion → Field History entry on a moved record.

---

**Task V.6 — Seed ~1,000 synthetic Lien records**
*Tool: Terminal (`sf apex run`) | Time: 30–45 min*
✅ **Task R.1 done** — volume settlement `Talc Powder Mass Tort 2023` (Id `a02dL00000p27A8QAI`) exists. Do not run this against the live-import settlement.

Write and run `scripts/apex/seedVolumeLiens.apex` targeting the volume settlement's Id — single synchronous anonymous Apex script (no async chunking needed at this volume). ~850 records land at Coverage Confirmed via the automated Flow path; ~150 redistributed across the other 7 downstream stages via a post-insert bulk update. `Claimant_ID__c` prefixed `SYN-` to keep synthetic data distinguishable from the hand-built demo records.

⚠️ **Risk:** the Flow fires on every insert with no bypass — every seeded row must insert as `Coverage_Result__c='Confirmed'` with a positive amount, or it will be forced to `Escalated` and flood the queue. See architecture.md §4.6 for the full reasoning.

✅ Done when: `SELECT COUNT() FROM Lien__c WHERE Settlement__c=:id AND Claimant_ID__c LIKE 'SYN-%'` matches the target distribution, where `:id` is the volume settlement.

**Update (2026-07-26):** `scripts/apex/seedVolumeLiens.apex` written per the §4.6 spec — 850/150 split, 7-stage redistribution (Pre-Validation excluded, matching `BulkStageTransitionController`'s transition map), `Response_Deadline__c` randomized -15 to +75 days, intake dates staggered older for downstream stages. `volumeSettlementName` now set to `'Talc Powder Mass Tort 2023'` — **ready to run**, no longer blocked.

---

**Task V.7 — Full live dry run**
*Tool: Salesforce + Desktop | Time: 30–45 min*

On the volume settlement: Summary tiles reflect ~1,000 total liens with the expected spread. Click Bulk Advance Liens, Coverage Confirmed → Response Ready, confirm preview reads ~850, submit, wait for completion, Refresh, confirm the shift. Spot-check Field History on a few moved records. Rehearse the narration from `docs/demo-script.md` Act 2 (Beats 7–9).

✅ Done when: dry run completes clean at least twice before the real demo.

---

**Bulk Actions check:** Summary + Bulk Advance built and verified at volume. Access control narrated, not enforced. Ready to fold into the existing demo script's new beat.

---

## Settlement Health Plan Junction — Done

**Goal:** Let the Settlement record show its participating health plans directly, so the Settlement Configuration beat of the demo can actually demonstrate that — right now health plan only exists per-Lien. Decorative only: no Apex, no validation rule, no test class. Full design: `rawlings-demo/docs/architecture.md` §4.7.

---

**Task H.1 — Build `Settlement_Health_Plan__c` junction and related list** ✅ Done
*Tool: Salesforce Setup UI | Time: 30–45 min*

1. Setup → Object Manager → Create → Custom Object
   - Label: `Settlement Health Plan`, Plural Label: `Settlement Health Plans`
   - API Name: `Settlement_Health_Plan__c`
2. Add two required Lookup fields:
   - `Settlement__c` — Lookup to Settlement
   - `Health_Plan__c` — Lookup to Account
3. Setup → Object Manager → Settlement → Lightning Record Pages → default page → drag a Related List component onto the page → select `Settlement Health Plans` → Save → Activate.
4. On the demo Settlement record, create 3 junction records linking it to `Health Plan A`, `Health Plan B`, and `Health Plan C` (the same three Accounts used by Import Claimants).

⚠️ **Risk:** none significant — purely declarative, no dependency on the Flow, Apex, or the bulk/volume work above.

✅ Done when: the Settlement record page shows a "Settlement Health Plans" related list with 3 rows.

**Update (2026-07-26):** Steps 1, 2, and 4 done via Claude Code — `Settlement_Health_Plan__c` object + `Settlement__c`/`Health_Plan__c` required Lookup fields deployed as metadata (`force-app/main/default/objects/Settlement_Health_Plan__c/`; `sharingModel` set to `ReadWrite` since there's no Master-Detail field, and `Health_Plan__c`'s delete constraint set to `Restrict` since a required Lookup can't use `SetNull`), and the 3 junction records created on the live settlement via anonymous Apex. Step 3 done manually in Lightning App Builder (a "Settlement Health Plans" related list, `relatedListApiName: Settlement_Health_Plans__r`) — verified by retrieving `Settlement_Record_Page.flexipage-meta.xml` afterward and confirming the component + a live query showing 3 junction records on the live settlement.

---

**Settlement Health Plan check:** Related list built and showing 3 rows on the demo settlement. Update Beat 1 of `rawlings-demo/docs/demo-script.md` to point at it once done.

---

## Two-Settlement Restructure — In Progress

**Goal:** Separate the live-import demo settlement from the seeded volume settlement so the two acts of the demo don't contaminate each other — right now both live on the single Settlement record created in Task T.6, which means the ~1,000-record volume seed (Task V.6) and the pre-built deadline record (Task Th.1) sit on top of the same Lien related list the live import uses. Full reasoning: `rawlings-demo/docs/demo-script-open-questions.md`. Full revised sequence: `rawlings-demo/docs/demo-script.md`.

⚠️ **Run Task R.1 before Task V.6** — the volume seed script needs a target settlement Id that isn't the live one.

---

**Task R.1 — Create the volume settlement** ✅ Done
*Tool: Salesforce Setup UI | Time: 10 min*

App Launcher → Settlement → New. Give it a distinct name and administrator from the live settlement (`Hip Implant Mass Tort 2024`) so it reads as a separate, longer-running program — e.g. `Talc Powder Mass Tort 2023`, administrator `National Settlement Administration` or a different one, Program Start Date well in the past, Response Window Days `90`, Status `Active`.

✅ Done when: a second Settlement record exists, distinct from the live one, with its Id noted for Tasks V.6 and R.2.

**Result:** Created as `Talc Powder Mass Tort 2023` — **Id `a02dL00000p27A8QAI`** — Administrator `Continental Claims Administrators`, Response Window Days `90`, Status `Active`, Program Start Date `2024-11-01`. Distinct from the live settlement (`Hip Implant Mass Tort 2024`, Id `a02dL00000opHs8QAE`). This Id is the target for Task V.6's seed script and Task R.2's record move.

---

**Task R.2 — Move the pre-built deadline record to the volume settlement** ✅ Done
*Tool: Salesforce Setup UI | Time: 15 min*

Re-create `[Pre-existing] Helen Vasquez` (same field values as Task Th.1: Claimant ID `CLM-PRE-001`, Health Plan A, Stage Coverage Confirmed, Coverage Result Confirmed, Recoverable Amount 5500, Intake Date today minus 82 days) against the volume settlement instead. Delete the original record from the live settlement — if it stays there, the live settlement's Lien related list shows 16 rows instead of a clean 15, and it's not consistent with a settlement whose claimants just arrived live.

✅ Done when: Helen Vasquez shows Red on the volume settlement; the live settlement's Lien related list has no leftover pre-built record.

**Update (2026-07-26):** Verified already satisfied from earlier work — `CLM-PRE-001` has `Settlement__c` on the volume settlement (`a02dL00000p27A8QAI`), `Deadline_Status__c = Red` (`Days_Remaining__c = 8`), and the live settlement's Lien related list is a clean 15 rows (`CLM-00001`–`CLM-00015`) with no leftover. Note: her `Stage__c` reads `Response Ready`, not `Coverage Confirmed` as originally specced — she was swept up in an earlier Bulk Advance verification pass before the volume seed existed. Left as-is: `docs/demo-script.md` only references her Red deadline status, never her stage, so nothing depends on the original value.

---

**Task R.3 — Restage the demo environment for two settlements**
*Tool: Browser + Desktop | Time: 15 min*

Update the staging from Task Th.2: Tab 1 = live settlement (Lien list visible, empty until Import Claimants runs) + Escalation Queue list view in a second tab; a third tab or bookmark ready to jump to the volume settlement for Act 2. Confirm the volume settlement's Summary tiles and Bulk Advance action are visible without needing to search for the record.

✅ Done when: both settlements are one click away during rehearsal, matching the Pre-Demo Setup checklist in `docs/demo-script.md`.

---

**Two-Settlement Restructure check:** Live settlement and volume settlement fully separated. Full dry run of `docs/demo-script.md` end to end, both acts, at least twice before the real demo.

---

## Response Report — Done

**Original goal:** Replace the live SFTP-callout demo beat (Generate Response File → `ResponseFileWriter.cls` → Python server → ngrok) with a native Salesforce report + Export, removing the only external, network-dependent moving part in the whole demo. Full reasoning: `rawlings-demo/docs/demo-script-open-questions.md`. Full design: `rawlings-demo/docs/architecture.md` §4.8.

**Superseded:** `ResponseFileWriter.cls` was later reworked to attach the CSV directly to the Settlement record as a Salesforce File instead of POSTing it through the Python server/ngrok — which removed the external dependency at its source, rather than routing around it with a report. Generate Response File is now the **primary** live mechanism for Beat 6; the report stays built as a manual/ad-hoc alternative, not the scripted path. Task P.2 (verifying Export into a desktop folder) is dropped accordingly — the demo doesn't write files to a folder at all anymore.

---

**Task P.1 — Build the "Liens Ready to Respond" report** ✅ Done
*Tool: Salesforce Setup UI | Time: 20–30 min*

Reports tab → New Report → Report Type: `Liens` (Salesforce's auto-generated default type for the custom object; no custom report type needed).
- Filters: `Settlement` equals the live settlement, `Stage` equals `Coverage Confirmed`.
- Columns: Claimant Name, Claimant ID, Health Plan, Recoverable Amount, Response Deadline.
- Save as `Liens Ready to Respond`, in a folder visible to the demo user.

⚠️ **Risk:** none significant — declarative only, no dependency on Apex, the Flow, or the bulk/volume work above.

✅ Done when: running the report against the live settlement after an import shows exactly the Coverage Confirmed liens from that import.

**Update (2026-07-26):** Built via Claude Code as deployable metadata instead of Report Builder clicking — `force-app/main/default/reports/unfiled$public/Liens_Ready_to_Respond.report-meta.xml`, `reportType` `CustomEntity$Lien__c` (the actual API name behind the "Liens" label), filed in the standard Public Reports folder (`unfiled$public`) so it's visible without a new folder. Two non-obvious things the metadata didn't get right on the first pass, found via the Analytics REST API rather than guessing: (1) the report type's real API name isn't just `Lien` — had to hit `/services/data/v67.0/analytics/reportTypes` to find `CustomEntity$Lien__c`; (2) a filter on a Lookup column (`Lien__c.Settlement__c`) needs the related record's **Name** as the filter value, not its Id — using the Id silently matched zero rows with no deploy-time error. Verified end-to-end with a throwaway test Lien inserted via anonymous Apex (Coverage Confirmed, on the live settlement): report correctly returned exactly that 1 row with all 5 columns, then returned to 0 rows after the test record was deleted, confirming both filters work and the live settlement is left clean.

---

**Task P.2 — Verify Export end-to-end into the outbound folder** — **Dropped**
*Tool: Salesforce + Desktop | Time: 10–15 min*

No longer needed: Beat 6 now runs live through Generate Response File (attaches the CSV directly to the Settlement record), not the report + Export + desktop-folder path. The report stays available for a manual/ad-hoc pull if ever needed, but nothing in the scripted demo depends on exporting it to a folder.

---

**Response Report check:** `ResponseFileWriter.cls` reworked to attach natively; Generate Response File is the live Beat 6 mechanism. ngrok and the Python server no longer need to be running for the live demo.

---

## Liens Near Deadline — Done

**Goal:** Let a partner see which liens are actually at risk on a deadline without leaving the Settlement page — right now `Deadline_Status__c` just computes a color; nothing surfaces it to anyone unless they're already looking at the right row. Declarative only, no Apex, no LWC, no test class. Full design: `rawlings-demo/docs/architecture.md` §4.9.

---

**Task D.1 — Add the "Liens Near Deadline" dynamic related list** ✅ Done
*Tool: Salesforce Setup UI / App Builder | Time: 30–45 min*

1. Setup → Object Manager → Settlement → Lightning Record Pages → default page → drag a **Related List - Single** component onto the page.
2. Configure it against the Lien related list:
   - Filter: `Deadline_Status__c` equals `Yellow` OR `Deadline_Status__c` equals `Red`, AND `Stage__c` not equal to `Closed`, AND `Stage__c` not equal to `Collected`.
   - Sort: `Days_Remaining__c` ascending.
   - Columns: Claimant Name, Stage, Days Remaining, Deadline Status.
   - Label the component "Liens Near Deadline".
3. Place it near the Summary tiles (once §V.4/V.5 are built) so both are visible together without scrolling past one to see the other.
4. Save → Activate → Activate for all users.

⚠️ **Risk:** none significant — purely declarative, no dependency on the Flow, Apex, or any other remaining-work section.

✅ Done when: on both settlements, the component shows only Yellow/Red, non-Closed/Collected liens, soonest deadline on top — verified against Helen Vasquez on the volume settlement and, if time allows, a manually-adjusted test record on the live settlement.

**Update (2026-07-26):** Step 2's filter built and deployed via Claude Code as a `Lien__c` List View instead of hand-configuring criteria in App Builder — `Liens_Near_Deadline.listView-meta.xml` (`Deadline_Status__c != 'Green'` AND `Stage__c != 'Closed'` AND `Stage__c != 'Collected'`; `Deadline_Status__c` only ever resolves to Green/Yellow/Red per its formula, so `!= 'Green'` is equivalent to the spec's `in (Yellow, Red)`). Verified via the List View REST API: sample rows returned only Yellow/Red statuses and no Closed/Collected stages, and a SOQL count confirms 381 records org-wide currently match.

**Update (2026-07-27):** Steps 1, 3, and 4 completed in Lightning App Builder — the "Liens Near Deadline" Related List - Single component is live on the Settlement record page, confirmed showing 10+ Red-status rows sorted soonest-first on the volume settlement (`Talc Powder Mass Tort 2023`).

---

**Liens Near Deadline check:** Component built and verified on both settlements. Beat 8 of `docs/demo-script.md` points at it directly.

---

## Escalation Reason Text Update — Done

**Goal:** Replace the generic, hardcoded escalation reason with a specific, feasible one so Beat 5 of the demo has an actual story instead of a label. Right now every escalated lien gets the same text, regardless of cause — it doesn't reflect any real business reason. Full reasoning: `rawlings-demo/docs/demo-script-open-questions.md`.

This is a small edit to an already-built, already-activated Flow (`Lien Automation on Create`, §3.3) — not a new component.

---

**Task E.1 — Update the Escalation Path's Escalation Reason text** ✅ Done
*Tool: Flow Builder | Time: 10–15 min*

1. Setup → Flows → `Lien Automation on Create` → Edit (this deactivates it while editing — reactivate when done).
2. Open the `Update Stage to Escalated` element on the Escalation Path.
3. Change the `Escalation_Reason__c` field value from `Coverage could not be confirmed automatically` to:
   `Health plan enrollment records on file don't confirm this claimant was covered on the treatment date — eligibility needs to be verified with the health plan before liability can be confirmed.`
4. Save → Activate.

`docs/flow-build-instructions.md` step 4a already updated to reflect this as the reference value for anyone rebuilding the Flow from scratch (e.g., a fresh scratch org).

⚠️ **Risk:** low — a literal-text change on an existing, tested element. Re-run a quick import test afterward (Task T.14-style) to confirm escalated liens still route correctly and show the new text; delete test records after.

✅ Done when: an escalated lien shows the new, specific reason text; the demo talk track in Beat 5 matches what's actually on the record.

**Update (2026-07-26):** Done via Claude Code, metadata-first instead of Flow Builder: retrieved the Flow (API name is actually `Lien_Routing_Flow` — "Lien Automation on Create" is just its label), edited the `stringValue` on `Update_Stage_to_Escalated` directly in the retrieved XML, and redeployed. The file's `<status>` was already `Active`, so the deploy activated the new version automatically — no separate reactivation step needed. Verified with a throwaway test Lien (`Coverage_Result__c='Unable to Confirm'`, the actual restricted-picklist value — not `'Denied'`, which doesn't exist on this field): routed to `Escalated` and `Escalation_Reason__c` shows the new text exactly. Test record deleted after.

---

**Escalation Reason Text Update check:** Flow updated and reactivated, verified against a fresh test import. Beat 5 of `docs/demo-script.md` already rewritten to match.

---

## Claimant Import via Screen Flow — Proposed

**Goal:** Beat 0's talk track claims the presenter "uploaded [the file] myself, ahead of time" — right now that's narrated, not real: `Import Claimants` reads a pre-staged `SampleClaimants` Static Resource, and nothing is actually uploaded live. Replace it with a Screen Flow the presenter drives live, using a real File Upload screen component. Full design: `rawlings-demo/docs/architecture.md` §4.10.

This is a new, optional enhancement — not part of the R.3/V.7 path already scheduled to finish rehearsal. Prioritize separately; doesn't block the demo being rehearsal-ready.

---

**Task F.1 — Extract shared import logic into `ClaimantImportService.cls`**
*Tool: 🤖 Claude Code / IDE | Time: 30–45 min*

Move the CSV-parsing/Lien-insert/count logic out of `ClaimantImportController.importClaimants` into `ClaimantImportService.importFromCsv(Id settlementId, Blob csvBody)`. `ClaimantImportController.importClaimants` becomes a thin wrapper: read the Static Resource, call the service. No behavior change for the existing LWC path.

✅ Done when: `ClaimantImportControllerTest` passes unmodified (or with only method-name updates), confirming the refactor didn't change behavior.

---

**Task F.2 — Build `ClaimantFileImportInvocable.cls` + test**
*Tool: 🤖 Claude Code / IDE | Time: 45–60 min*

`@InvocableMethod` taking `settlementId` + `contentVersionId`, reading `ContentVersion.VersionData`, calling `ClaimantImportService.importFromCsv`, returning total/automated/escalated counts. Test inserts a `ContentVersion` with the same sample CSV body (or a small fixture) and asserts counts + created `Lien__c` records, mirroring `ClaimantImportControllerTest`'s assertions.

✅ Done when: test class passes with coverage on both the confirmed and escalated branches.

---

**Task F.3 — Build the Screen Flow `Import Claimant File`**
*Tool: 🏗️ Flow Builder | Time: 1–1.5 hours*

Screen Flow, Settlement record context:
1. Screen — File Upload component, related record = `{!recordId}` (so the upload lands on the Settlement's Files related list automatically).
2. Get Records — latest `ContentVersion` for the uploaded document.
3. Apex Action — `ClaimantFileImportInvocable`.
4. Screen — Display Text showing total/automated/escalated, same wording as today's toast.

⚠️ **Risk:** the File Upload component's output variable (single Id vs. collection) varies by API version — check in Flow Builder before building the Get Records filter.

✅ Done when: running the Flow against a real file upload creates the same Lien mix (automated + escalated) as the existing Static Resource path.

---

**Task F.4 — Add as a Quick Action, decide action-bar placement**
*Tool: Salesforce Setup UI | Time: 20–30 min*

New Flow-type Quick Action on Settlement, `Import_Claimant_File`. Decide: swap it into the primary action-bar slot currently held by `Import Claimants`, keeping the old LWC action available but demoted (same precedent as the Report staying as a manual/ad-hoc alternative to `Generate Response File`, §4.8) — don't delete the Static Resource path.

✅ Done when: Settlement action bar shows the new Flow action in the primary position; the original `Import Claimants` action still exists and still works if clicked.

---

**Task F.5 — Update demo script and rehearse**
*Tool: Text editor + Salesforce | Time: 20–30 min*

Update `docs/demo-script.md` Beat 0/Beat 2: the "I uploaded it myself" line now describes something the presenter actually does live, not something staged beforehand. Save `SampleClaimants.csv` somewhere accessible on the presenter's machine (desktop, or reuse the existing `staticresources` file directly) for the live pick. Rehearse the upload once as part of the next full dry run.

✅ Done when: Beat 0/2 run live end-to-end with the real upload, same automated/escalated split narrated correctly.

---

**Claimant Import via Screen Flow check:** Screen Flow built, verified against the same known-good CSV, old path kept as fallback. Fold into the next full dry run once R.3/V.7 are done.
