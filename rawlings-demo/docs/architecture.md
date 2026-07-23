# Lien Workflow Demo — Architecture & Build Reference

**Context:** Demo prototype supporting the Rawlings lien workflow management RFP response
**Status:** Living document — supersedes `lien-import-quick-action-spec.md` and `lien-summary-and-bulk-actions-spec.md` (both merged in and retired)
**Last updated:** 2026-07-23

---

## 1. Purpose & Context

The RFP asks for a platform that manages the full lifecycle of a lien — a health plan client's claim to be reimbursed out of a mass-tort settlement — across six capability areas: **Settlement Configuration, Lien Intake, Claim Evaluation, Settlement Response, Recovery Calculation, and Collection & Disbursement**. A repeating pattern threads through all of it: the platform receives data from a settlement administrator (SFTP/API/portal), processes it, and responds through the same channel. The RFP is explicit that this receive-process-respond pattern is central and must be a core, supported behavior — not a bolt-on integration.

This demo is the **Phase 1 prototype**: carry a single lien from intake through collection using SFTP only, confirming the platform choice, the workflow/automation approach, and the third-party exchange pattern. It is intentionally narrow — it does not build the Liability or Damages services, does not include healthcare claims data management, and does not integrate anything beyond a simulated SFTP exchange. Anything beyond that is a later phase.

### Scope boundary (unchanged from the original RFP)
Out of scope for this prototype: real SFTP polling, Bulk API 2.0 as the demo's actual data path, the Liability/Damages services themselves (their outputs are simulated), per-administrator data quality contracts, duplicate detection, the negotiation workflow and charge line items, multiple rounds of administrator counter-response, production error handling/retry/dead-lettering, and any real reconciliation/payment/disbursement logic.

---

## 2. Data Model

No changes to the object model between what's built and what's planned — the volume/bulk work is additive, reading and writing fields that already exist.

### Objects

| Object | API Name | Role |
|---|---|---|
| Settlement | `Settlement__c` | Parent record; master configuration a lien inherits (administrator, response window, program terms) |
| Lien | `Lien__c` | One claimant's recovery opportunity within one settlement; the thing that moves through stages |
| Response | `Response__c` | Child of Lien; the platform's asserted position, created automatically once coverage is confirmed |

### Settlement Fields

| Field | API Name | Notes |
|---|---|---|
| Administrator | `Administrator__c` | The settlement administrator's name |
| Program Start Date | `Program_Start_Date__c` | Anchors the response-deadline clock |
| Response Window Days | `Response_Window_Days__c` | Commonly 90, per the program's lien resolution terms |
| Status | `Status__c` | e.g. Active |

### Lien Fields

| Field | API Name | Type | Notes |
|---|---|---|---|
| Settlement | `Settlement__c` | Lookup(Settlement__c) | Required — the only required field on Lien__c |
| Claimant Name | `Claimant_Name__c` | Text(100) | |
| Claimant ID | `Claimant_ID__c` | Text(20) | Administrator-assigned identifier |
| Health Plan | `Health_Plan__c` | Lookup(Account) | Enables the sharing/access-control demo |
| Injury Category | `Injury_Category__c` | Text(100) | Mass tort injury category |
| Stage | `Stage__c` | Picklist | See stage values below |
| Intake Date | `Intake_Date__c` | Date | |
| Response Deadline | `Response_Deadline__c` | Date | |
| Coverage Result | `Coverage_Result__c` | Picklist | Confirmed, Unable to Confirm — simulates Liability service output |
| Recoverable Amount | `Recoverable_Amount__c` | Currency | Simulates Damages service output |
| Escalation Reason | `Escalation_Reason__c` | Text(255) | Populated by the Flow on the escalation path |
| Days Remaining | `Days_Remaining__c` | Formula(Number) | `Response_Deadline__c - TODAY()` |
| Deadline Status | `Deadline_Status__c` | Formula(Text) | `IF(Days_Remaining__c > 20, "Green", IF(Days_Remaining__c > 10, "Yellow", "Red"))` |

**Stage picklist values (in order):** Intake, Coverage Confirmed, Escalated, Response Ready, Response Submitted, Negotiation, Agreed, Pre-Validation, Recovery Calculated, Collected, Closed.

`Recovery Calculated` and `Collected` exist purely so the Path (chevron) can visualize the full lifecycle — see Built Components §5.5. Neither is reached by any automation in this prototype.

### Response Fields

| Field | API Name | Type | Notes |
|---|---|---|---|
| Lien | `Lien__c` | Master-Detail(Lien__c) | |
| Claimed Amount | `Claimed_Amount__c` | Currency | Copied from Lien's Recoverable Amount by the Flow |
| Status | `Status__c` | Picklist | Draft, Submitted, Sent |
| Response Date | `Response_Date__c` | Date | Set to today by the Flow |

---

## 3. Built Components — Status: **Done**

These are implemented and demoed today.

### 3.1 Static Resource — `SampleClaimants`
A 15–25 row CSV (`Static Resource` name `SampleClaimants`, case-sensitive) with pre-populated `Coverage_Result` and `Recoverable_Amount` columns standing in for the Liability/Damages services' outputs. Data is designed so ~85% of rows are `Confirmed` (auto-advance) and ~15% are `Unable to Confirm` (escalate) — enough to make the automation/escalation split visible without burying it.

### 3.2 Apex Controller — `ClaimantImportController.cls`
```
@AuraEnabled
public static Map<String, Integer> importClaimants(Id settlementId)
```
Reads the `SampleClaimants` Static Resource, parses each CSV row (quoted-field-aware), bulk-inserts `Lien__c` records with `Stage__c='Intake'`, `Intake_Date__c=today`, `Response_Deadline__c=today+90`, resolves `Health_Plan__c` by matching Account name, then queries back the inserted records to report automated-vs-escalated counts to the LWC. Test class: `ClaimantImportControllerTest`.

### 3.3 Record-Triggered Flow — `Lien Automation on Create`
Fires on every `Lien__c` insert (after-save, no bypass mechanism). Decision: `Coverage_Result__c = 'Confirmed' AND Recoverable_Amount__c > 0`.
- **Automated path:** `Stage__c → Coverage Confirmed`, creates a child `Response__c` (`Status__c='Draft'`, `Claimed_Amount__c` = the Lien's recoverable amount, `Response_Date__c=today`).
- **Escalation path (default/catch-all outcome):** `Stage__c → Escalated`, `Escalation_Reason__c` populated, creates a `Task` assigned to the `Lien Escalation Queue`, due 5 days out, plus a Custom Notification (`Lien Escalated`) sent to queue members.

Build reference: `docs/flow-build-instructions.md`.

### 3.4 LWC — `claimantImport`
`lightning__RecordAction` on Settlement. States: Default (confirm/cancel) → Loading (spinner) → Success (sticky toast: total/automated/escalated counts) → Error. Uses `NavigationMixin` to refresh the Settlement view so the Lien related list reflects new records.

### 3.5 Quick Action — `Import Claimants`
LWC-type Quick Action on `Settlement__c`, icon `utility:upload`.

### 3.6 Apex Callout — `ResponseFileWriter.cls`
```
@AuraEnabled public static void generateResponseFile(Id settlementId)
@Future(callout=true) private static void writeFileAsync(String settlementId)
```
Queries all `Coverage Confirmed` liens for the settlement, builds a CSV, POSTs it (via Named Credential `LocalSFTPDemo`) to a local Python HTTP server. `@Future(callout=true)` is a demo simplification — production would use a Platform Event or Queueable with real error handling/retry.

### 3.7 LWC — `generateResponseFile`
Same pattern as `claimantImport`. Toast fires immediately (the callout is async); the file appears in the outbound folder 2–5 seconds later — narrated as "give it a moment."

### 3.8 Quick Action — `Generate Response File`

### 3.9 Python Local Server — `demo/demo_server.py`
Stdlib-only HTTP server on port 8765, writes received POST bodies to `~/Desktop/sftp-demo/outbound/`, exposed to Salesforce via ngrok + Named Credential + Remote Site Setting. Not deployed to Salesforce — runs on the demo machine only.

### 3.10 Escalation Queue List View
Saved list view on Lien, filtered `Stage__c = 'Escalated'`, showing claimant/health plan/escalation reason/deadline columns — the visible "these need a human" story.

### 3.11 Lightning Path (Chevron)
Configured on `Lien__c.Stage__c`, showing all 11 stages in order. This is a **visualization layer only** — it makes the full lifecycle visible on every Lien record even though only Intake → Coverage Confirmed/Escalated → (Response Ready, manually) is automated. A presenter can click into a later step to manually advance a record; no automation fires as a side effect.

| Stage transition | How it's reached |
|---|---|
| Intake → Coverage Confirmed / Escalated | Automated (the Flow) |
| Response Ready → Response Submitted | Manual today |
| Negotiation → Agreed | Manual only — no negotiation workflow built |
| Recovery Calculated → Collected → Closed | Manual only — Path lets a user click through; no reconciliation/payment/disbursement logic behind it |

### 3.12 Field History Tracking
Enabled on `Lien__c` (`Stage__c`, `Coverage_Result__c`, `Escalation_Reason__c`) and `Response__c` (`Status__c`), with a History related list on the Lien record page. Backs the "the system moved it, not a person" narration with real, timestamped data. (Settlement is intentionally left untracked — static config, nothing changes visibly during the demo.)

### 3.13 Pre-Built Deadline Threshold Record
One hand-created Lien (`[Pre-existing] Helen Vasquez`, intake date 82 days back) that shows `Deadline_Status__c = Red` in the list view without needing a live scheduled job — demonstrates deadline monitoring on demand.

---

## 4. Planned Components — Status: **Not started**

Added in response to a reviewer's observation: a single settlement can carry up to 100,000 liens, and everything past Coverage Confirmed in the built prototype only moves one record at a time via the Path. That's fine for a demo record or two — it doesn't show a workflow an administrator could actually run at real volume. This section is the design for closing that gap, revised through discussion to fit a specific audience: **partners at the firm unfamiliar with CRM, plus one technical consultant.** That audience shapes the design as much as the RFP requirement does — see §4.5.

Nothing below exists in the codebase yet.

### 4.1 Apex — `SettlementLienSummaryController.cls` (+ test)
```
@AuraEnabled(cacheable=true)
public static LienSummary getSummary(Id settlementId)
```
Returns `totalLiens`, `stageCounts` (grouped by `Stage__c`, ordered to match picklist order — not alphabetical), `escalatedCount` (broken out separately), and a Green/Yellow/Red deadline breakdown.

**Design note, resolved from the original spec's open question:** rather than `GROUP BY Deadline_Status__c` (grouping on a formula field, which the original draft flagged as unverified), the deadline breakdown uses three separate scoped `COUNT()` queries filtered on the underlying `Days_Remaining__c` number field:
```sql
SELECT COUNT() FROM Lien__c WHERE Settlement__c=:id AND Stage__c NOT IN ('Closed','Collected') AND Days_Remaining__c > 20
SELECT COUNT() FROM Lien__c WHERE Settlement__c=:id AND Stage__c NOT IN ('Closed','Collected') AND Days_Remaining__c > 10 AND Days_Remaining__c <= 20
SELECT COUNT() FROM Lien__c WHERE Settlement__c=:id AND Stage__c NOT IN ('Closed','Collected') AND Days_Remaining__c <= 10
```
This sidesteps the open question entirely (WHERE-filtering on formula fields is unambiguously supported — it's specifically `GROUP BY`/`ORDER BY` that carries restrictions), stays genuinely aggregate/indexed (cost proportional to the scan, not rows returned), and needs no fallback branch. The `Stage__c` breakdown keeps `GROUP BY Stage__c` unchanged — a real picklist field, no risk there.

### 4.2 Apex — `BulkStageTransitionController.cls` (+ test), `LienBulkStageTransitionBatch.cls`
```
@AuraEnabled(cacheable=true) public static List<String> getStageOptions()
@AuraEnabled(cacheable=true) public static Integer previewCount(Id settlementId, String fromStage)
@AuraEnabled public static Id enqueueBulkTransition(Id settlementId, String fromStage, String toStage)
@AuraEnabled(cacheable=true) public static BatchJobStatus getJobStatus(Id jobId)
```
Server-enforced from→to transition map (one valid "to" per "from"):

| From Stage | Valid To Stage |
|---|---|
| Intake | Coverage Confirmed |
| Coverage Confirmed | Response Ready |
| Response Ready | Response Submitted |
| Response Submitted | Negotiation |
| Negotiation | Agreed |
| Agreed | Recovery Calculated |
| Recovery Calculated | Collected |
| Collected | Closed |

`Escalated` never appears as a From Stage — omitted from `getStageOptions()` entirely (escalation exists specifically to force individual human review; an ops user resolves it manually before it's eligible for bulk treatment).

`enqueueBulkTransition` validates the pair server-side (so a crafted client call can't force an invalid jump) and calls `Database.executeBatch(new LienBulkStageTransitionBatch(settlementId, fromStage, toStage), 2000)`.

`LienBulkStageTransitionBatch` is `Database.Batchable<SObject>` using a `Database.QueryLocator` in `start()` (handles up to 50M rows natively — this is what makes 100,000 records a non-issue in production) and a single-field `update` in `execute()`. Field History Tracking (already enabled per §3.12) captures the old/new value and timestamp for every record the batch touches, with no separate logging needed. Exercised via `BulkStageTransitionControllerTest` using `Test.startTest()/stopTest()` — no separate test class needed for the batch itself.

**Scope trim — permission-set gating dropped:** the original design included a `Bulk_Lien_Stage_Actions` permission set gating who can fire this action. That's cut from this build pass — access control for this feature is **narrated verbally** in the demo ("in production, only an ops-manager role would see this button"), not built or enforced. Revisit if a later phase needs it enforced for real.

### 4.3 LWCs

**`settlementLienSummary`** (`lightning__RecordPage`) — a persistent tile row, not a modal. Row 1: Total Liens, Escalated, then one tile per pipeline stage in picklist order. Row 2: Green/Yellow/Red deadline tiles, Red visually emphasized. Manual "Refresh" button (`refreshApex`) — explicitly not live-pushed, since a bulk batch may be running against the same data. Empty state when `totalLiens = 0`.

**`bulkStageTransition`** (`lightning__RecordAction`) — state machine: Select (From Stage combobox; To Stage auto-fills, since the map is one-to-one) → Preview (`previewCount` call, "This will advance **{count}** liens from **{fromStage}** to **{toStage}**") → Submitting → Queued (sticky toast, modal closes) → Progress (polls `getJobStatus` every 5s, progress bar `JobItemsProcessed / TotalJobItems` until `Status = 'Completed'`). Matches the toast/spinner/state-constant conventions already established in `claimantImport`/`generateResponseFile` — this is the first component in the codebase needing polling, so keep the implementation simple (single interval, no backoff).

### 4.4 Quick Action + page placement
- New `Settlement__c.Bulk_Advance_Liens.quickAction-meta.xml`, same structure as the two existing Quick Actions.
- `Settlement_Record_Page.flexipage-meta.xml`: add `Bulk_Advance_Liens` to the highlights-panel action list; add `settlementLienSummary` as a component in the `main` region, positioned above the existing Lien related list.

### 4.5 Demo narrative — visual-first, business-confidence
The audience is partners unfamiliar with CRM concepts plus one technical consultant. Two narration tracks, kept visibly separate:
- **Main track (partners):** open the Settlement, the Summary tiles already show a real-looking book of business (not 15 records). Click Bulk Advance, watch the preview count, confirm, watch it complete, click Refresh, watch the tiles shift. No mention of batches, chunking, or governor limits.
- **Aside track (the consultant):** if asked how this scales to 100,000 — "this is `Database.Batchable` with a `QueryLocator`, the same construct Salesforce uses for million-row jobs. What you just watched process live is the identical code path; at 100,000 it just runs more chunks in the background." This needs to be *true*, not demonstrated live at that volume.

### 4.6 Volume data seeding — `scripts/apex/seedVolumeLiens.apex` (does not exist yet)
No precedent for this in the codebase — `ClaimantImportController` reads a 15–25 row Static Resource synchronously and isn't the right tool for volume seeding.

**Constraint discovered during design:** `Lien Automation on Create` fires on *every* insert with no bypass. Any seeded row that doesn't satisfy `Coverage_Result__c='Confirmed' AND Recoverable_Amount__c>0` gets forced to `Escalated` — flooding the Escalation Queue and wrecking the existing "3 out of 15" escalation story. So every seeded row must insert as `Confirmed` with a positive amount (landing at `Coverage Confirmed` via the automated path, which also creates a Draft `Response__c` — a consistent side effect, not a problem); rows destined for a different stage get moved there by a **separate bulk `update` after the insert completes** (an update doesn't re-trigger a record-*created* flow).

**Simplified design (revised down for this audience — proving the mechanism matters more than a dramatic-looking number):**
- Seed **~1,000 synthetic Lien records** total: **~850 land at `Coverage Confirmed`** (the Bulk Advance pool), **~150 spread across the other 7 downstream stages** (~20 each) via the post-insert redistribution update — the spread still matters for the Summary tiles to read as "a real book of business across the lifecycle" rather than one giant blob in a single stage.
- **This volume fits in a single synchronous transaction — no async `Queueable` chunking needed.** ~1,000 insert + ~1,000 Flow-update + ~1,000 Flow-Response-create + ~150 redistribution-update ≈ 3,150 DML rows, comfortably under the 10,000/transaction ceiling. `seedVolumeLiens.apex` is one plain anonymous Apex script, run once via `sf apex run --file`, with an immediate synchronous result — no queue-draining wait, no timing uncertainty before a rehearsal.
- **Trade-off, accepted:** at ~1,000 records the Bulk Advance batch (size 2000) will likely resolve in a single chunk rather than visibly stepping through multiple progress increments. Given the visual-first framing, that's fine — the moment that matters is "a real pool of liens moves in one action," not "watch it chunk." The mechanism is still real underneath for when the consultant asks.
- `Coverage Confirmed → Response Ready` is the target transition — a real pipeline point the map already supports, and nothing downstream depends on further automation, so the bucket can be re-run in rehearsal.
- Synthetic rows use `Claimant_ID__c` prefix `SYN-` (vs. the hand-built demo data's `CLM-` prefix) so they're identifiable and cleanable independently of the 15–25 row demo data and the Helen Vasquez record.
- `Health_Plan__c` resolved by round-robin against the 3 existing Health Plan Accounts (created by a prior Import Claimants run).
- `Response_Deadline__c` randomized (~-15 to +75 days from today) and `Intake_Date__c` randomized per target stage, so the Green/Yellow/Red tiles look realistic rather than degenerate.

---

## 5. Deployment Steps

### Already done (Built Components, §3)
1. Data model deployed (Settlement, then Lien, then Response — Settlement first since Lien has formula fields referencing it).
2. Escalation Queue created (`Lien Escalation Queue`, supporting `Lien__c` + `Task`).
3. `SampleClaimants` Static Resource uploaded.
4. `Lien Automation on Create` Flow built and activated (Flow Builder, not source-tracked).
5. Apex + LWC deployed (`ClaimantImportController`, `ResponseFileWriter`, `claimantImport`, `generateResponseFile`).
6. Both Quick Actions created and added to the Settlement page layout / Lightning Record Page.
7. Escalation Queue list view created.
8. Lightning Path configured and added to the Lien record page.
9. Field History Tracking enabled; History related list added.
10. Pre-built deadline threshold record created.
11. ngrok + Named Credential (`LocalSFTPDemo`) + Remote Site Setting configured; Python server running.

### Remaining (Planned Components, §4)
1. Verify (quick spike, non-blocking) whether `GROUP BY` on a formula field is accepted in this org — informational only; the controller design above doesn't depend on the answer.
2. Build `LienBulkStageTransitionBatch` + `BulkStageTransitionController` + test, verified against small (10–20 row) data first.
3. Build `SettlementLienSummaryController` + test.
4. Build `settlementLienSummary` LWC, verify tiles against existing 15–25 row demo data (countable by eye).
5. Build `bulkStageTransition` LWC + Quick Action + flexipage placement, verify end-to-end against small data (preview → submit → toast → poll → Field History entry).
6. Run `seedVolumeLiens.apex`, verify record counts and stage distribution (`SELECT COUNT() FROM Lien__c WHERE Settlement__c=:id AND Claimant_ID__c LIKE 'SYN-%'`) match target.
7. Full live dry run: Summary tiles reflect ~1,000 total liens with the expected spread → Bulk Advance Coverage Confirmed → Response Ready → preview reads ~850 → submit → job completes → Refresh confirms the shift → spot-check Field History on a few moved records.
8. Repeat the dry run at least once more before the actual demo.

---

## 6. Demo Script

### Setup (before the room fills)
- Python server running (`python3 demo/demo_server.py`), ngrok running, Named Credential updated with the current ngrok URL.
- Desktop folders visible: `inbound/` (containing `SampleClaimants.csv`), `outbound/` (empty).
- Salesforce Settlement record open, Lien related list empty; Escalation Queue list view open in a second tab.
- Pre-built deadline threshold record visible (already red).
- One silent end-to-end test run completed, then data reset.
- *(Once §4 is built)* Settlement already carries the ~1,000-record seeded volume, so the Summary tiles read as a real book of business from the moment the room walks in.

### Narrative and sequence

**Open with the desktop (30s)** — show the two folders before opening Salesforce. "This is what the SFTP exchange looks like in the demo. The administrator has put their claimant file in the inbound folder. Outbound is empty. That changes by the end of this."

**Frame the settlement (1m)** — open the Settlement record, walk through program terms (administrator, participating health plans, 90-day response window). "Every lien created against this settlement inherits these terms."

**Run the import (1m)** — click Import Claimants. "In production, the integration layer picks up that inbound file automatically. We're triggering that handoff manually today." Let the toast land without narrating it. Explain that coverage/damages results are normally populated by live service calls; today they're pre-populated in the import file to simulate that.

**Show what the system did (2m)** — scroll to the Lien related list. "The system has already processed these. It didn't wait for us." Point to Coverage Confirmed liens (auto-advanced, response position created) and switch to the Escalation Queue tab for the ones that couldn't be resolved automatically ("the system didn't drop them — it routed them, created a task, flagged them for a human").

**Show the automated path in detail (2m)** — open a Coverage Confirmed lien, show stage/intake date/deadline, open the Response child (claimed amount, Draft status). Scroll to History — "every change is recorded. Who, what, when. The system moved it, not a person."

**Show the escalation path in detail (1m)** — open an Escalated lien, show the escalation reason and the assigned Task, due in five days.

**Show the book of business at volume — new beat, once §4 is built (1–2m)** — scroll up or navigate to the Summary tiles at the top of the Settlement. "What you just watched was 15 claimants. This settlement actually carries about a thousand liens across every stage of the lifecycle — here's the current state of all of them at a glance." Click Bulk Advance Liens, pick a From Stage with a real count, show the preview ("this will move ~850 liens"), confirm, let it complete, click Refresh, point at the tiles shifting. "That's not a mockup — it's the same batch mechanism Salesforce uses for jobs into the millions of records. We're showing a smaller pool live to keep this tight; the code path at 100,000 liens is identical, it just runs a few more chunks in the background." (Keep the batch/chunking detail brief and only go deeper if the consultant follows up.)

**Show the deadline story (1m)** — point to the pre-built red record. "This lien has been open for 82 days. The system flagged it automatically when it crossed the 10-day threshold. No one had to check a spreadsheet."

**Show the full lifecycle (30s)** — scroll to the chevron on a lien. "This is the full path a lien takes. What you've seen automatically is intake, coverage, and response. Negotiation, recovery calculation, collection aren't wired up in this prototype, but the platform already tracks where every lien sits against them." Click a later step to show it advance. "Same object model — the remaining stages are additional workflow builds on what's already here, not a different system."

**Generate the response file (1m)** — click Generate Response File. "The platform now sends its position back to the administrator — in production, a file to their SFTP server." Wait the 2–5 seconds ("give it a moment"), open the file on the desktop. "File in. Liens processed. File out."

**Frame what you haven't built (30s)** — "The SFTP polling that detects the inbound file automatically, the Liability and Damages services, the payment reconciliation — those are later phases. Access control on actions like Bulk Advance — restricting it to an ops-manager role — is a permission-set change, not a redesign; we haven't wired that gate into this build yet, but the platform supports it natively. What we've shown today is that the platform manages the workflow correctly from the moment data arrives, closes the loop with a response, and does both at the volume this book of business actually requires."

---

## 7. Acceptance Criteria

### Import / Automated / Escalation paths, Deadline Monitoring, Cancel, Error States, Access Control, Path, History
Unchanged from the built prototype — see the original acceptance criteria; all currently pass. (Access Control criterion: a Health Plan A user sees only Health Plan A liens in the related list — already verified.)

### Summary Component (planned)
- [ ] `settlementLienSummary` renders on the Settlement record page above the Lien related list
- [ ] Stage tiles appear in pipeline order, not alphabetical
- [ ] Escalated count is broken out as its own tile
- [ ] Deadline tiles (Green/Yellow/Red) exclude Closed and Collected liens, computed via `Days_Remaining__c` WHERE-filters (not `GROUP BY` on the formula field)
- [ ] Refresh button re-runs the queries and updates all tiles
- [ ] A settlement with zero liens shows an empty state, not zeroed tiles

### Bulk Advance Liens (planned)
- [ ] Action appears in the Settlement action bar (no permission-set gating in this build pass — access is whatever the demo user's profile already grants)
- [ ] `Escalated` never appears as a From Stage option
- [ ] Preview count matches an independent list-view filter count for the same From Stage
- [ ] Confirm is disabled when the preview count is 0
- [ ] Submitting enqueues a Batch Apex job and returns immediately with a toast — the UI does not block waiting for the batch to finish
- [ ] The seeded ~850-record Coverage Confirmed bucket advances to Response Ready without hitting governor limits
- [ ] Every record moved by the batch shows the stage change in its History related list, attributed to the running user
- [ ] Submitting an invalid From/To pair via a direct Apex call (bypassing the LWC) throws `AuraHandledException`

---

## 8. Future State (Production Architecture)

**Receive-process-respond, generally:** in production, an integration layer (MuleSoft or AWS Transfer Family + Lambda) polls the administrator's SFTP server, validates inbound files against the agreed data quality contract at the integration layer (rejected rows returned as an error file, not silently skipped), and loads valid records via **Bulk API 2.0**, supporting 100K+ records asynchronously. A Platform Event fires on job completion, triggering the Lien Workflow Engine. The Liability and Damages services are called per lien (or per batch), writing results back to `Coverage_Result__c`/`Recoverable_Amount__c` — in the demo these are pre-populated in the import CSV to simulate the service responses. The record-triggered Flow evaluates and routes exactly as it does today, just against real service outputs instead of CSV data. Once a Response is submitted, an outbound Platform Event triggers the integration layer to write a response file back to the administrator's SFTP server.

The demo's Apex controllers should not be carried forward to production without replacing synchronous DML with Bulk API 2.0, replacing CSV simulation with real service callouts, and adding full error handling, idempotency, and job tracking.

**Bulk stage transitions, specifically:** unlike the import path's demo-vs-production split, `LienBulkStageTransitionBatch`'s `Database.Batchable` + `QueryLocator` design **is already production-shaped** — this is exactly how it would run at real scale, not a simulation of it. What changes going to production:
1. A completion notification (Platform Event → email/Slack, or a Chatter post) once `finish()` runs, since a 100,000-record batch will usually outlast the initiating user's session.
2. A scheduled/nightly variant (`Schedulable`) for transitions the business wants swept automatically rather than user-triggered.
3. Error handling in `finish()` surfacing `NumberOfErrors` to an ops-facing record rather than Setup → Apex Jobs.
4. Possibly a lightweight audit object if the client needs "who ran which bulk transition, on how many records" beyond what Field History provides per-record.
5. The permission-set gating dropped from this build pass (§4.2) — required before this is exposed to real users, not optional at that point.

---

## 9. Open Questions

| Question | Status |
|---|---|
| Does `GROUP BY` on a formula text field (`Deadline_Status__c`) work in an aggregate SOQL query? | **Resolved (design-level):** sidestepped — the Summary controller filters on the underlying `Days_Remaining__c` number field instead of grouping on the formula. Still worth a quick spike to confirm the underlying platform behavior for the record. |
| Should the Bulk Advance action be gated behind a permission set? | **Resolved for this pass:** no — dropped for build speed and narrated verbally instead. Revisit before any real user (beyond the demo presenter) gets access. |
| What seed volume proves the point without excess build/seed risk? | **Resolved:** ~1,000 records (~850 in one bucket), seeded synchronously in a single anonymous Apex run — chosen over a more dramatic number because the audience (non-technical partners) needs to see the mechanism work, not a specific magnitude, and a smaller volume is materially simpler and lower-risk to build and rehearse. |
| Should the 90-day clock start from Intake Date or a Readiness Date on the Settlement? | Open — confirm with client; RFP implies the clock is program-defined. |
| Who holds the eventual permission set / ops-manager role in the client's real org model? | Open — confirm with client once access control is actually built. |
| Does the client want a completion notification when a bulk job finishes? | Open — likely a fast follow, out of scope for this build pass. |
| Should `Response Ready → Response Submitted` bulk-advancing also trigger the outbound response-file generation? | Open — flagged as a likely Phase 2 integration point between the import and bulk-transition mechanisms; currently the bulk tool only changes `Stage__c`. |
