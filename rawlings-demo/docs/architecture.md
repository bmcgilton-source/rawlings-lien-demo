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
| Settlement Health Plan | `Settlement_Health_Plan__c` | Junction; declares which health plan Accounts participate in a Settlement (planned, §4.7) |

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

**Targets a second Settlement record, not the live-import one.** Per the demo script's two-settlement design (see `demo-script-open-questions.md` and `docs/demo-script.md`), this seed runs against a dedicated "volume" Settlement — created solely to hold the seeded book of business — never the settlement the live Import Claimants action runs against during the demo. Keeping them separate is what lets the live settlement's Lien related list and Escalation Queue stay a clean, countable 15-ish rows throughout the demo, with no filtering required to hide the seeded volume. The pre-built deadline threshold record (§3.13, `[Pre-existing] Helen Vasquez`) also belongs on this volume settlement, not the live one — see §5 remaining steps.

**Constraint discovered during design:** `Lien Automation on Create` fires on *every* insert with no bypass. Any seeded row that doesn't satisfy `Coverage_Result__c='Confirmed' AND Recoverable_Amount__c>0` gets forced to `Escalated` — flooding the Escalation Queue and wrecking the existing "3 out of 15" escalation story. So every seeded row must insert as `Confirmed` with a positive amount (landing at `Coverage Confirmed` via the automated path, which also creates a Draft `Response__c` — a consistent side effect, not a problem); rows destined for a different stage get moved there by a **separate bulk `update` after the insert completes** (an update doesn't re-trigger a record-*created* flow).

**Simplified design (revised down for this audience — proving the mechanism matters more than a dramatic-looking number):**
- Seed **~1,000 synthetic Lien records** total: **~850 land at `Coverage Confirmed`** (the Bulk Advance pool), **~150 spread across the other 7 downstream stages** (~20 each) via the post-insert redistribution update — the spread still matters for the Summary tiles to read as "a real book of business across the lifecycle" rather than one giant blob in a single stage.
- **This volume fits in a single synchronous transaction — no async `Queueable` chunking needed.** ~1,000 insert + ~1,000 Flow-update + ~1,000 Flow-Response-create + ~150 redistribution-update ≈ 3,150 DML rows, comfortably under the 10,000/transaction ceiling. `seedVolumeLiens.apex` is one plain anonymous Apex script, run once via `sf apex run --file`, with an immediate synchronous result — no queue-draining wait, no timing uncertainty before a rehearsal.
- **Trade-off, accepted:** at ~1,000 records the Bulk Advance batch (size 2000) will likely resolve in a single chunk rather than visibly stepping through multiple progress increments. Given the visual-first framing, that's fine — the moment that matters is "a real pool of liens moves in one action," not "watch it chunk." The mechanism is still real underneath for when the consultant asks.
- `Coverage Confirmed → Response Ready` is the target transition — a real pipeline point the map already supports, and nothing downstream depends on further automation, so the bucket can be re-run in rehearsal.
- Synthetic rows use `Claimant_ID__c` prefix `SYN-` (vs. the hand-built demo data's `CLM-` prefix) so they're identifiable and cleanable independently of the 15–25 row demo data and the Helen Vasquez record.
- `Health_Plan__c` resolved by round-robin against the 3 existing Health Plan Accounts (created by a prior Import Claimants run).
- `Response_Deadline__c` randomized (~-15 to +75 days from today) and `Intake_Date__c` randomized per target stage, so the Green/Yellow/Red tiles look realistic rather than degenerate.

### 4.7 Settlement Health Plan Junction (planned, not started)
Added in response to a gap surfaced while reviewing the demo script: the RFP describes Settlement Configuration as the "system of record for a settlement, its participating health plans, its lien resolution program terms" — but nothing in the current or planned data model lets a Settlement show its participating health plans as a set. `Health_Plan__c` today is a Lookup that only exists on `Lien__c`, populated per-claimant at import time. A Settlement can't have more than one health plan on it without a junction, since a Lookup only points one way.

**Simplest implementation, decorative only (no enforcement):**
- New object `Settlement_Health_Plan__c` with two required Lookup fields: `Settlement__c` (Lookup to `Settlement__c`) and `Health_Plan__c` (Lookup to `Account`).
- No Apex, no LWC, no validation rule. Add it as a related list on the Settlement Lightning Record Page — a plain Lookup relationship supports a related list without needing Master-Detail.
- For the demo settlement, hand-create 3 junction records linking it to the same 3 Health Plan Accounts already used by Import Claimants / the volume seed, so Beat 1 of the demo script has a real related list to show.
- **Explicitly not built:** no constraint tying a Lien's `Health_Plan__c` to its Settlement's configured junction records. A Lien can still reference any Health Plan Account regardless of what's junction-linked to its Settlement. Enforcing that (a validation rule cross-referencing the junction) is a small follow-on if this ever needs to be a real business rule rather than a demo visual — see open question below.
- No test class needed — declarative-only, nothing to unit test.

### 4.8 "Liens Ready to Respond" report (planned, not started)
Added when the live demo's response-file beat was reworked: the built `ResponseFileWriter.cls` → Python server → ngrok pathway (§3.6–3.9) is the only part of the whole demo with an external dependency — a local process, a tunnel, a per-session URL, and the venue's network all have to cooperate. That's a real risk concentrated in one beat, for no benefit the audience can actually see (the callout is async; all they see is a toast and a file appearing a few seconds later either way).

**Replacement for the live demo path:** a standard Salesforce Report on `Lien__c`, filtered to a given Settlement and `Stage__c = 'Coverage Confirmed'`, columns covering Claimant Name, Claimant ID, Health Plan, Recoverable Amount, Response Deadline. Uses the platform's native Export function — no Apex, no LWC, no external server, nothing that can fail on a venue's network. The exported file gets saved into the demo's `outbound/` folder so the visual bookend from Beat 0 (folder starts empty, ends with a file) is unchanged.

**Worth being precise about what `ResponseFileWriter.cls` actually is, so the demo doesn't overclaim it:** it's an Apex callout that POSTs a file to a local HTTP server (§3.6) — a stand-in for the external channel, not a literal SFTP client. Per §8 (Future State), real delivery to an administrator's SFTP server in production runs through a middleware integration layer (MuleSoft or AWS Transfer Family + Lambda) — Salesforce doesn't speak SFTP directly, and building that layer is explicitly out of scope for this prototype. So the reason this path isn't run live isn't just "it's risky" — it was never a preview of the real production mechanism to begin with, only a simulation of the exchange concept over HTTP.

- **`ResponseFileWriter.cls`, `generateResponseFile` LWC, the Python server, and the ngrok/Named Credential setup are not being removed or deprecated** — they remain built and demonstrable on request (e.g., if the consultant wants to see the simulated callout), correctly described as a stand-in for where a future middleware layer would sit. They're simply no longer the path the live demo script runs through. See `docs/demo-script-open-questions.md` for the full reasoning.
- No custom report type needed — Salesforce auto-generates a default report type for custom objects.
- No test class — declarative-only.

### 4.9 "Liens Near Deadline" dynamic related list (planned, not started)
Added in response to a gap surfaced while reviewing the demo script: the deadline story (§3.13, `Deadline_Status__c` Red/Yellow/Green) only ever computes a color on a formula field — nothing surfaces which liens are at risk to a person. Someone has to already be looking at the right record or list to notice. That's a real difference from the escalation path, which actively pushes a Task and a Custom Notification (§3.3) the moment it happens. The Summary tiles (§4.3) help at the aggregate level — a Red count — but don't show *which* liens make up that count without leaving the page.

**Simplest implementation, in-context, no code:** a native Dynamic Related List (Single) component on the Settlement Lightning Record Page, scoped to the Lien child relationship:
- Filter: `Deadline_Status__c` in (`Yellow`, `Red`) AND `Stage__c` not in (`Closed`, `Collected`) — same exclusion logic as the Summary controller's deadline breakdown (§4.1), kept consistent.
- Sort: `Days_Remaining__c` ascending, so the most urgent liens are on top.
- Columns: Claimant Name, Stage, Days Remaining, Deadline Status.
- Placed on the Settlement page alongside (not replacing) the Summary tiles — tiles give the count, this list gives the actual records, both visible without navigating away.
- No Apex, no LWC, no test class — pure Lightning App Builder configuration, same build tier as §4.7.
- **Deliberately not built:** clicking a Summary tile to filter this list would require custom LWC event-wiring between the two components. Left out — both components independently reflect current state, which solves the actual gap (a partner can see who's at risk without hunting) without the added build complexity.
- On the seeded volume settlement, this list will show more than just the one hand-placed deadline record, since `Response_Deadline__c` is randomized across a wide range at seed time (§4.6) — a side benefit, not something built specifically for this.

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
6. Create a second Settlement record (the "volume" settlement — distinct name/administrator from the live-import settlement) to seed volume against, per the two-settlement demo design in §4.6.
7. Run `seedVolumeLiens.apex` against the volume settlement's Id, verify record counts and stage distribution (`SELECT COUNT() FROM Lien__c WHERE Settlement__c=:id AND Claimant_ID__c LIKE 'SYN-%'`) match target.
8. Re-create the pre-built deadline threshold record (`[Pre-existing] Helen Vasquez`) on the volume settlement instead of the live one; remove it from the live settlement if it was created there originally, so the live settlement's Lien related list stays a clean count of only what the live import creates.
9. Full live dry run: on the volume settlement, Summary tiles reflect ~1,000 total liens with the expected spread → Bulk Advance Coverage Confirmed → Response Ready → preview reads ~850 → submit → job completes → Refresh confirms the shift → spot-check Field History on a few moved records.
10. Repeat the dry run at least once more before the actual demo.
11. Build `Settlement_Health_Plan__c` junction object + two Lookup fields; add as a related list on the Settlement Lightning Record Page; hand-create 3 junction records for the live settlement (§4.7).
12. Build the "Liens Ready to Respond" Report on `Lien__c`, filtered by Settlement + Stage = Coverage Confirmed; verify Export produces a usable file, saved to `outbound/` (§4.8).
13. Add a Dynamic Related List (Single) component to the Settlement Lightning Record Page, filtered/sorted per §4.9; verify against both settlements that it shows only Yellow/Red, non-Closed/Collected liens, soonest deadline first.

---

## 6. Demo Script

**Superseded by `docs/demo-script.md`.** The version originally drafted here assumed a single settlement carrying both the live import and the seeded volume; that created a real problem — the live settlement's Lien related list and Escalation Queue would show the ~1,000 pre-seeded rows mixed in with the ~15 live-imported ones, undercutting the "this was just fifteen claimants" framing needed before the volume reveal. `docs/demo-script.md` fixes this with a two-settlement, two-act structure (Act 1: full intake-through-response loop on a clean live settlement; Act 2: the same platform at scale on a second, pre-loaded settlement) and is now the authoritative script, beat by beat, with talk track. See `demo-script-open-questions.md` for the reasoning behind the split.

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

### Settlement Health Plan Junction (planned)
- [ ] `Settlement_Health_Plan__c` related list renders on the Settlement record page
- [ ] The demo settlement shows 3 junction records, matching the 3 Health Plan Accounts used elsewhere in the demo
- [ ] No enforcement exists yet tying a Lien's `Health_Plan__c` to its Settlement's junction records — a Lien can still reference any Health Plan Account (documented gap, not a defect)

### "Liens Ready to Respond" Report (planned)
- [ ] Report filters correctly to a given Settlement and `Stage__c = 'Coverage Confirmed'`
- [ ] Export produces a file readable outside Salesforce (Excel/CSV) with claimant, health plan, recoverable amount, and response deadline visible
- [ ] Demonstrated without ngrok, the Python server, or the Named Credential running — no external dependency in the live path
- [ ] `ResponseFileWriter.cls`, `generateResponseFile` LWC, and the Python server remain deployed and functional, unchanged — this report is an additional path, not a replacement of the built integration

### "Liens Near Deadline" dynamic related list (planned)
- [ ] Renders on the Settlement Lightning Record Page alongside the Summary tiles
- [ ] Shows only liens with `Deadline_Status__c` in (Yellow, Red) and `Stage__c` not in (Closed, Collected)
- [ ] Sorted by `Days_Remaining__c` ascending (most urgent first)
- [ ] On the volume settlement, shows more than just the one pre-built deadline record, reflecting the randomized seed data
- [ ] No Apex, no LWC — pure Lightning App Builder configuration

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
| Should a Lien's Health Plan be constrained to its Settlement's configured `Settlement_Health_Plan__c` junction records? | Open — §4.7 ships decorative-only (no enforcement) for the demo. Revisit if this needs to be a real business rule rather than a demo visual. |
