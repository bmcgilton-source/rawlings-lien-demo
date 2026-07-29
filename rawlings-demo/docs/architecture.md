# Lien Workflow Demo — Architecture & Build Reference

**Context:** Demo prototype supporting the Rawlings lien workflow management RFP response
**Status:** Living document — supersedes `lien-import-quick-action-spec.md` and `lien-summary-and-bulk-actions-spec.md` (both merged in and retired)
**Last updated:** 2026-07-28

---

## 1. Purpose & Context

The RFP asks for a platform that manages the full lifecycle of a lien — a health plan client's claim to be reimbursed out of a mass-tort settlement — across six capability areas: **Settlement Configuration, Lien Intake, Claim Evaluation, Settlement Response, Recovery Calculation, and Collection & Disbursement**. A repeating pattern threads through all of it: the platform receives data from a settlement administrator (SFTP/API/portal), processes it, and responds through the same channel. The RFP is explicit that this receive-process-respond pattern is central and must be a core, supported behavior — not a bolt-on integration.

This demo is the **Phase 1 prototype**: carry a single lien from intake through collection using SFTP only, confirming the platform choice, the workflow/automation approach, and the third-party exchange pattern. It is intentionally narrow — it does not build the Liability or Damages services, does not include healthcare claims data management, and does not integrate anything beyond a simulated SFTP exchange. Anything beyond that is a later phase.

### Scope boundary (unchanged from the original RFP)
Out of scope for this prototype: real SFTP polling, Bulk API 2.0 as the demo's actual data path, the Liability/Damages services themselves (their outputs are simulated), per-administrator data quality contracts, duplicate detection, the negotiation workflow and charge line items, multiple rounds of administrator counter-response, production error handling/retry/dead-lettering, and any real reconciliation/payment/disbursement logic.

---

## 2. Data Model

No changes to the object model between the original Built Components (§3) and the volume/bulk work (§4.1–§4.9) — that work is additive, reading and writing fields that already exist. The late-lifecycle stretch build (§4.11–§4.12, added 2026-07-28) does add new fields to `Lien__c`, listed below.

### Objects

| Object | API Name | Role |
|---|---|---|
| Settlement | `Settlement__c` | Parent record; master configuration a lien inherits (administrator, response window, program terms) |
| Lien | `Lien__c` | One claimant's recovery opportunity within one settlement; the thing that moves through stages |
| Response | `Response__c` | Child of Lien; the platform's asserted position, created automatically once coverage is confirmed |
| Settlement Health Plan | `Settlement_Health_Plan__c` | Junction; declares which health plan Accounts participate in a Settlement (§4.7) |

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

**Late-lifecycle fields (added 2026-07-28, §4.11 — Negotiate / Record Recovery & Remittance / Approve Disbursement Flows):**

| Field | API Name | Type | Notes |
|---|---|---|---|
| Administrator Position | `Administrator_Position__c` | Currency(16,2) | Collected on the Negotiation screen |
| Agreed Amount | `Agreed_Amount__c` | Currency(16,2) | Collected on the Negotiation screen; history tracked |
| Negotiation Reason | `Negotiation_Reason__c` | Long Text Area | Collected on the Negotiation screen |
| Recovery Amount | `Recovery_Amount__c` | Currency(16,2) | Collected on the Recovery and Remittance screen; history tracked |
| Remittance Amount | `Remittance_Amount__c` | Currency(16,2) | Collected on the Recovery and Remittance screen; history tracked |
| Payment Variance | `Payment_Variance__c` | Formula(Currency) | `Remittance_Amount__c - Agreed_Amount__c` |
| Health Plan Allocation | `Health_Plan_Allocation__c` | Currency(16,2) | Collected on the Disbursement screen |
| Rawlings Allocation | `Rawlings_Allocation__c` | Currency(16,2) | Collected on the Disbursement screen |
| Disbursement Status | `Disbursement_Status__c` | Picklist | Draft (default), Pending Approval, Approved; history tracked |

**Finance instruction audit fields (added 2026-07-28, §4.12 — `FinanceInstructionWriter`):**

| Field | API Name | Type | Notes |
|---|---|---|---|
| Finance Instruction Generated At | `Finance_Instruction_Generated_At__c` | DateTime | Most recent successful generation; history tracked |
| Finance Instruction Generated By | `Finance_Instruction_Generated_By__c` | Lookup(User) | Most recent generating user |
| Finance Instruction Filename | `Finance_Instruction_Filename__c` | Text(255) | Most recent filename; history tracked |

**Stage picklist values (in order):** Intake, Coverage Confirmed, Escalated, Response Ready, Response Submitted, Negotiation, Agreed, Pre-Validation, Recovery Calculated, Collected, Closed.

`Recovery Calculated` and `Collected` were originally added purely so the Path (chevron) could visualize the full lifecycle with no automation behind them — see §3.11. As of §4.11, `Agreed`, `Pre-Validation`, and `Collected` are now real automated transitions reached by the three late-lifecycle Flows (`Recovery Calculated` is still Path-only, skipped by `Lien_Record_Recovery_Remittance`'s Recovery-and-Remittance screen, which moves straight from `Agreed` to either `Pre-Validation` or `Collected`).

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
Reads the `SampleClaimants` Static Resource and delegates parsing/insert to `ClaimantImportService.importFromCsv(settlementId, csvBody)` (extracted 2026-07-28, see §4.10, so the Static Resource path and the new live file-upload path share exactly one place that understands the CSV format). The shared service parses each CSV row (quoted-field-aware), bulk-inserts `Lien__c` records with `Stage__c='Intake'`, `Intake_Date__c=today`, `Response_Deadline__c=today+90`, resolves `Health_Plan__c` by matching Account name, then queries back the inserted records to report automated-vs-escalated counts to the LWC. Test classes: `ClaimantImportControllerTest` (unmodified, passes against the refactor), `ClaimantImportServiceTest`.

**Superseded 2026-07-28, same day — see §4.13:** the description above is the pre-validation shape. `importClaimants` now returns a typed `ClaimantImportResult` (created/updated/rejected/automated/escalated counts, rejection filename), and `ClaimantImportService.importFromCsv` now runs the full data-quality gate from `claimant-intake-validation-spec.md` — required-field, allowed-value, Health-Plan-participation, and duplicate/existing-Lien checks — before any Lien is created or updated.

### 3.3 Record-Triggered Flow — `Lien Automation on Create`
Fires on every `Lien__c` insert (after-save, no bypass mechanism). Decision: `Coverage_Result__c = 'Confirmed' AND Recoverable_Amount__c > 0`.
- **Automated path:** `Stage__c → Coverage Confirmed`, creates a child `Response__c` (`Status__c='Draft'`, `Claimed_Amount__c` = the Lien's recoverable amount, `Response_Date__c=today`).
- **Escalation path (default/catch-all outcome):** `Stage__c → Escalated`, `Escalation_Reason__c` populated, creates a `Task` assigned to the `Lien Escalation Queue`, due 5 days out, plus a Custom Notification (`Lien Escalated`) sent to queue members.

Build reference: `docs/flow-build-instructions.md`.

### 3.4 LWC — `claimantImport`
`lightning__RecordAction` on Settlement. States: Default (confirm/cancel) → Loading (spinner) → Success (sticky toast: total/automated/escalated counts) → Error. Uses `NavigationMixin` to refresh the Settlement view so the Lien related list reflects new records.

**Superseded 2026-07-28 — see §4.13:** the toast now reports the full `ClaimantImportResult` breakdown (rows processed, created, updated, rejected, automated, escalated, rejection filename) and switches to a `warning` variant instead of `success` whenever `rejectedCount > 0`.

### 3.5 Quick Action — `Import Claimants`
LWC-type Quick Action on `Settlement__c`, icon `utility:upload`.

### 3.6 Apex — `ResponseFileWriter.cls`
```
@AuraEnabled public static String generateResponseFile(Id settlementId)
```
Queries all `Coverage Confirmed` liens for the settlement, builds a CSV, and attaches it directly to the Settlement record as a Salesforce File (`ContentVersion` + `ContentDocumentLink`, `ShareType='V'`, `Visibility='AllUsers'`). Fully synchronous, native DML — no callout, no external dependency. Returns the generated filename so the LWC can reference it in the toast.

Previously this POSTed to a local Python HTTP server over an ngrok tunnel via Named Credential `LocalSFTPDemo` — replaced because the LWC's success toast fires unconditionally regardless of whether the callout actually landed (see §4.8), so a stale tunnel or a server that wasn't running produced a silent, undetectable failure live. The `LocalSFTPDemo` Named Credential and `demo/demo_server.py` have been removed; there's no longer an external process or tunnel to keep alive for this beat.

### 3.7 LWC — `generateResponseFile`
Same pattern as `claimantImport`. Toast fires on completion of a synchronous Apex call — "Response file attached" — and the modal itself switches to a results state showing a `lightning-datatable` of the generated rows (claimant, health plan, recoverable amount, response deadline), so the result is visible without navigating away or relying on Salesforce's file-preview rendering. The CSV is also attached to the Settlement's Files related list for download/audit.

### 3.8 Quick Action — `Generate Response File`

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

## 4. Planned Components — Status: **Done, except final rehearsal**

Added in response to a reviewer's observation: a single settlement can carry up to 100,000 liens, and everything past Coverage Confirmed in the built prototype only moves one record at a time via the Path. That's fine for a demo record or two — it doesn't show a workflow an administrator could actually run at real volume. This section is the design for closing that gap, revised through discussion to fit a specific audience: **partners at the firm unfamiliar with CRM, plus one technical consultant.** That audience shapes the design as much as the RFP requirement does — see §4.5.

Everything below is built and deployed. What remains is not a build task: restaging the browser/desktop for both settlements (Task R.3) and a full live dry run (Task V.7) — see `rawlings-demo-build-schedule.md`.

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

**Volume capped at ~1,000 — a platform constraint, not a dramatic-number-avoidance choice:**
- Seed **~1,000 synthetic Lien records** total: **~850 land at `Coverage Confirmed`** (the Bulk Advance pool), **~150 spread across the other 7 downstream stages** (~20 each) via the post-insert redistribution update — the spread still matters for the Summary tiles to read as "a real book of business across the lifecycle" rather than one giant blob in a single stage.
- **The seed script is one plain synchronous anonymous Apex run (`sf apex run --file`), not `Queueable`/`Batchable`.** That choice is what actually bounds the achievable volume: Salesforce's 10,000-DML-rows-per-transaction governor limit applies to any single synchronous execution, in any org. At ~1,000 seed rows the script uses ≈3,150 DML rows (1,000 insert + 1,000 Flow-update + 1,000 Flow-Response-create + 150 redistribution-update) — there's headroom to push toward ~3,000 seed rows before hitting that ceiling, but not materially past it without hitting the wall the same way.
- **Going meaningfully larger (toward the RFP's 100,000-lien scale) is out of scope for this pass** — it requires the same async/chunked approach `LienBulkStageTransitionBatch` already uses for stage transitions (a `Database.Batchable` seed, or multiple sequential synchronous runs), which is real additional engineering, not a config change. Not worth building for a demo where the mechanism — not the magnitude — is what needs to land with this audience (§4.5). If a bigger number is ever needed, this is where that work would go.
- **Trade-off, accepted:** at ~1,000 records the Bulk Advance batch (size 2000) will likely resolve in a single chunk rather than visibly stepping through multiple progress increments. Given the visual-first framing, that's fine — the moment that matters is "a real pool of liens moves in one action," not "watch it chunk." The mechanism is still real underneath for when the consultant asks.
- `Coverage Confirmed → Response Ready` is the target transition — a real pipeline point the map already supports, and nothing downstream depends on further automation, so the bucket can be re-run in rehearsal.
- Synthetic rows use `Claimant_ID__c` prefix `SYN-` (vs. the hand-built demo data's `CLM-` prefix) so they're identifiable and cleanable independently of the 15–25 row demo data and the Helen Vasquez record.
- `Health_Plan__c` resolved by round-robin against the 3 existing Health Plan Accounts (created by a prior Import Claimants run).
- `Response_Deadline__c` randomized (~-15 to +75 days from today) and `Intake_Date__c` randomized per target stage, so the Green/Yellow/Red tiles look realistic rather than degenerate.

### 4.7 Settlement Health Plan Junction (done)
Added in response to a gap surfaced while reviewing the demo script: the RFP describes Settlement Configuration as the "system of record for a settlement, its participating health plans, its lien resolution program terms" — but nothing in the current or planned data model lets a Settlement show its participating health plans as a set. `Health_Plan__c` today is a Lookup that only exists on `Lien__c`, populated per-claimant at import time. A Settlement can't have more than one health plan on it without a junction, since a Lookup only points one way.

**Simplest implementation, decorative only (no enforcement):**
- New object `Settlement_Health_Plan__c` with two required Lookup fields: `Settlement__c` (Lookup to `Settlement__c`) and `Health_Plan__c` (Lookup to `Account`).
- No Apex, no LWC, no validation rule. Add it as a related list on the Settlement Lightning Record Page — a plain Lookup relationship supports a related list without needing Master-Detail.
- Done: 3 junction records hand-created on the demo settlement, linking it to the same 3 Health Plan Accounts already used by Import Claimants / the volume seed, so Beat 1 of the demo script has a real related list to show.
- **Explicitly not built:** no constraint tying a Lien's `Health_Plan__c` to its Settlement's configured junction records. A Lien can still reference any Health Plan Account regardless of what's junction-linked to its Settlement. Enforcing that (a validation rule cross-referencing the junction) is a small follow-on if this ever needs to be a real business rule rather than a demo visual — see open question below.
- No test class needed — declarative-only, nothing to unit test.

### 4.8 "Liens Ready to Respond" report (built, not the live path)
Added when the live demo's response-file beat was reworked: the originally-built `ResponseFileWriter.cls` → Python server → ngrok pathway was the only part of the whole demo with an external dependency — a local process, a tunnel, a per-session URL, and the venue's network all had to cooperate. That's a real risk concentrated in one beat, for no benefit the audience could actually see (the callout was async; all they saw was a toast and a file appearing a few seconds later either way) — and worse, the LWC's toast fired on success regardless of whether the callout actually landed, so a dead tunnel would fail silently mid-demo.

**Originally scripted as the live-demo replacement, no longer used that way:** a standard Salesforce Report on `Lien__c`, filtered to a given Settlement and `Stage__c = 'Coverage Confirmed'`, columns covering Claimant Name, Claimant ID, Health Plan, Recoverable Amount, Response Deadline. Built and deployed as report metadata, verified end-to-end via the Analytics REST API. Uses the platform's native Export function — no Apex, no LWC, no external server.

**`ResponseFileWriter.cls` has since been reworked (§3.6)** from the local-server callout to a native `ContentVersion`/`ContentDocumentLink` attach on the Settlement record — no external dependency at all. That removed the original reason the report was kept as the live path (tunnel/network risk) in the first place, so **Generate Response File is now the primary live mechanism for Beat 6** — the Settlement's Files related list (empty → populated) serves as the visual bookend from Beat 0 instead of the `outbound/` folder. The report stays built and deployed as a manual/ad-hoc alternative — e.g. if Generate Response File is ever unavailable — but it's no longer part of the scripted path, and verifying its Export into a desktop folder is no longer required. It's correctly described as a stand-in for where a future middleware layer would sit, per §8 (Future State): real delivery to an administrator's SFTP server in production runs through a middleware integration layer (MuleSoft or AWS Transfer Family + Lambda) — Salesforce doesn't speak SFTP directly, and building that layer is explicitly out of scope for this prototype.

- No custom report type needed — Salesforce auto-generates a default report type for custom objects.
- No test class — declarative-only.

### 4.9 "Liens Near Deadline" dynamic related list (done)
Added in response to a gap surfaced while reviewing the demo script: the deadline story (§3.13, `Deadline_Status__c` Red/Yellow/Green) only ever computes a color on a formula field — nothing surfaces which liens are at risk to a person. Someone has to already be looking at the right record or list to notice. That's a real difference from the escalation path, which actively pushes a Task and a Custom Notification (§3.3) the moment it happens. The Summary tiles (§4.3) help at the aggregate level — a Red count — but don't show *which* liens make up that count without leaving the page.

**Simplest implementation, in-context, no code:** a native Dynamic Related List (Single) component on the Settlement Lightning Record Page, scoped to the Lien child relationship:
- Filter: `Deadline_Status__c` in (`Yellow`, `Red`) AND `Stage__c` not in (`Closed`, `Collected`) — same exclusion logic as the Summary controller's deadline breakdown (§4.1), kept consistent.
- Sort: `Days_Remaining__c` ascending, so the most urgent liens are on top.
- Columns: Claimant Name, Stage, Days Remaining, Deadline Status.
- Placed on the Settlement page alongside (not replacing) the Summary tiles — tiles give the count, this list gives the actual records, both visible without navigating away.
- No Apex, no LWC, no test class — pure Lightning App Builder configuration, same build tier as §4.7.
- **Deliberately not built:** clicking a Summary tile to filter this list would require custom LWC event-wiring between the two components. Left out — both components independently reflect current state, which solves the actual gap (a partner can see who's at risk without hunting) without the added build complexity.
- On the seeded volume settlement, this list will show more than just the one hand-placed deadline record, since `Response_Deadline__c` is randomized across a wide range at seed time (§4.6) — a side benefit, not something built specifically for this.

### 4.10 Claimant import via Screen Flow — Status: **Built and browser-verified 2026-07-28**
Beat 0's talk track claims the presenter "uploaded [the file] myself, ahead of time" — but the actual import (`ClaimantImportController.importClaimants`) reads a pre-staged `SampleClaimants` Static Resource; nothing is uploaded live, so the claim was narrated, not demonstrated. Built mid-day 2026-07-28 (outside the day's original plan — added because the presenter wanted Beat 0/2 to show an actual file landing live) to close that gap by replacing the invisible Static Resource read with a live file upload the presenter performs in the room.

**Built:**
- `ClaimantImportService.importFromCsv(Id settlementId, Blob csvBody)` — the CSV-parsing/Lien-insert logic extracted out of `ClaimantImportController` (§3.2) so both the Static Resource path and the new upload path call the same method.
- `ClaimantFileImportInvocable` — `@InvocableMethod` Apex action taking a Settlement Id + ContentDocumentId, reads the `ContentVersion` and calls `ClaimantImportService.importFromCsv`.
- `claimantFileUpload` LWC (`lightning__FlowScreen` target), wrapping `lightning-file-upload`. **Built as a fallback after the native `flowruntime:fileUpload` screen component turned out not to exist in this org/API version** — the risk the original design called out in advance.
- `Import_Claimant_File` Screen Flow, launched as a Lightning Quick Action on Settlement — simpler than first drafted, since the custom LWC outputs a single Id directly (no collection-extraction workaround needed):
  1. **Upload Claimant File** screen — the `claimantFileUpload` LWC, related record = the Settlement (so the `ContentDocumentLink` lands in the Settlement's existing Files related list alongside the outbound response file from §3.6).
  2. **Import File** — Apex Action calling `ClaimantFileImportInvocable`.
  3. **Import Results** screen — total/automated/escalated counts as Display Text (the toast-based version stays on the original `Import Claimants` action). **Superseded 2026-07-28 — see §4.13:** this screen now shows the full created/updated/rejected/automated/escalated breakdown, with a separate "Import complete with data-quality issues" variant (including the rejection filename) that displays only when `rejectedCount > 0`.
- `Settlement__c.Import_Claimant_File` Quick Action, added **first** in the Settlement action bar (`numVisibleActions` bumped 3→4 on `Settlement_Record_Page.flexipage-meta.xml`). The original `Import Claimants` action stays deployed as a manual fallback — swap which one is primary rather than deleting either, per the design's original guidance.
- Presenter uploads the exact same `SampleClaimants.csv` content from local disk — this changes *visibility* of the receive step, not the data, so the known-good CSV and the 85/15 automated/escalated split are unaffected.

**Verified via CLI (original build):** all Apex — 6/6 tests passing (`ClaimantImportServiceTest`, `ClaimantFileImportInvocableTest`), including one that inserts a real `ContentVersion` and drives the invocable end-to-end.

**Browser-verified 2026-07-28, later the same day, as a byproduct of testing §4.13:** the Flow screen itself, the `lightning-file-upload` interaction, and the Flow↔LWC data binding all worked live — uploading `ClaimantValidationDemo.csv` (a local file, picked through the browser's file dialog) through `Import_Claimant_File` correctly reached the Import Results screen with accurate counts, and the uploaded file landed in the Settlement's Files related list alongside the generated rejection file. This exercises the exact same Flow/LWC/binding this section originally flagged as unverified, so that gap is now closed — see §4.13 for the specific validation-logic results.

**Fallback if it doesn't work live:** the old `Import Claimants` action is still live in the action bar — fall back to it and keep the pre-staged disclosure exactly as `demo-script.md` already has it. Nothing about this addition can break the existing working path; it's additive.

**Side benefit:** the Settlement's Files related list now shows both the inbound upload (Beat 0/2) and the outbound response file (Beat 6) — reinforces the receive→process→respond framing already central to the script, rather than just fixing an accuracy gap.

### 4.11 Late-lifecycle guided Flows (Negotiate / Record Recovery & Remittance / Approve Disbursement) — Status: **Built 2026-07-28 (stretch scope); not yet browser-verified end-to-end**
Added per `today-build-plan.md`'s Tier 2 stretch scope — a single-lien negotiation → recovery → disbursement → closure journey, explicitly scoped to *not* touch anything Mario's scripted demo depends on (§4.1–§4.10). Adds the late-lifecycle fields listed in §2 to `Lien__c`, all added to `Rawlings_Demo_Access`; field history tracking enabled on `Agreed_Amount__c`, `Recovery_Amount__c`, `Remittance_Amount__c`, `Disbursement_Status__c`. No new `Stage__c` values needed — `Agreed`, `Pre-Validation`, `Collected`, `Closed` already existed on the picklist (originally Path-visualization-only, per §3.11).

Originally built as one combined `Complete Lien Journey` Screen Flow. Split 2026-07-28 into three independent Screen Flows, one per control point, each its own Quick Action on the Lien action bar (placed before `Generate Finance Instruction`, §4.12). The rationale: Negotiation and Recovery/Remittance are not the same real-world event — remittance depends on the administrator's payment actually arriving, which normally happens well after agreement is reached — so bundling all three into one guided session implied a same-sitting timeline that doesn't hold in production. Each flow re-queries the Lien independently (no shared Flow-interview state across steps) and gates itself on the Lien's current `Stage__c`, showing a "Not Eligible" screen naming the required stage if the record isn't ready for that action.

**`Lien_Negotiate`** (`recordId` input, `Lien__c`) — Quick Action `Negotiate`:
1. **Get Lien / Get Settlement**, gated by `Decision_Eligible_For_Negotiation` — requires `Stage__c='Response Submitted'` and `Recoverable_Amount__c > 0`; otherwise a "Not Eligible" screen names the current stage.
2. **Lien Overview** — displays claimant, settlement, current stage, asserted amount.
3. **Negotiation** screen — collects Administrator Position, Agreed Amount, Negotiation Reason; sets `Stage__c → Agreed`.
4. **Negotiation Recorded** completion screen — confirms the captured values and that recovery/remittance is a separate action for whenever the payment lands.

**`Lien_Record_Recovery_Remittance`** (`recordId` input, `Lien__c`) — Quick Action `Record Recovery & Remittance`:
1. **Get Lien**, gated by `Decision_Eligible_For_Recovery` — requires `Stage__c='Agreed'`; otherwise "Not Eligible."
2. **Recovery and Remittance** screen — displays the Lien's stored Agreed Amount, collects Recovery Amount and Remittance Amount; `Decision_Payment_Match` branches on whether remittance equals the Lien's Agreed Amount:
   - **Match:** `Stage__c → Collected`, ends at a "Recovery Recorded" completion screen (ready for disbursement approval).
   - **Mismatch:** `Stage__c → Pre-Validation`, populates `Escalation_Reason__c` (reused field) with a variance explanation, creates a payment-review Task, ends at a "Payment Review Needed" exception screen — does not proceed to Disbursement.

**`Lien_Approve_Disbursement`** (`recordId` input, `Lien__c`) — Quick Action `Approve Disbursement`:
1. **Get Lien**, gated by `Decision_Eligible_For_Disbursement` — requires `Stage__c='Collected'`; otherwise "Not Eligible."
2. **Disbursement** screen — displays the Lien's stored Remittance Amount, collects Health Plan Allocation and Rawlings Allocation (must sum to Remittance Amount); sets `Disbursement_Status__c → Approved`, `Stage__c → Closed`.
3. **Complete** screen — displays claimant, all captured amounts (read from the Lien record, including the `Payment_Variance__c` formula field), final stage/status.

**No dynamic action-visibility gating built** — same posture as `Generate Finance Instruction` (§4.12): all three buttons sit in the action bar regardless of the Lien's current stage; each flow's own "Not Eligible" screen is the guard, not action visibility. A production follow-on, same as the `Generate_Finance_Instructions` custom-permission question.

**Demo data:** a dedicated Lien on the volume settlement (`Talc Powder Mass Tort 2023`, Settlement B, `a02dL00000p27A8QAI`) — `Claimant_ID__c='CLM-PRE-002'`, Angela Whitfield, Health Plan A, seeded at `Stage__c='Coverage Confirmed'`, `Recoverable_Amount__c=18500` (Record Id `a00dL00003YfQ1SQAV`), so the flows can be demoed start-to-finish rather than picked up mid-journey. Target demo values: Administrator Position $14,000, Agreed Amount $15,250, Recovery/Remittance $15,250 (zero variance), Health Plan Allocation $12,200, Rawlings Allocation $3,050, Disbursement Status Approved. Reset via `scripts/apex/resetLateLifecycleDemo.apex` (clears all eight late-lifecycle fields, restores `Stage__c='Coverage Confirmed'`, deletes any `Review: Payment variance` Task) — verified running clean, under a minute.

**Not yet verified — needs a browser:** none of the three flows has been run end-to-end in a live session since the split; per `today-build-plan.md`'s checklist, this is only folded into the demo script if it runs clean in rehearsal. If it isn't demo-ready, the beat runs exactly as previously scripted (Path narration, "not built yet").

### 4.12 Finance Instruction Generator — Status: **Built and browser-verified 2026-07-28 (stretch scope); §4.11's guided Flow itself still needs its own browser verification**
Full spec: `docs/finance-instruction-generator-spec.md`. Adds a final, auditable artifact to the lifecycle — after a Lien reaches `Closed` with `Disbursement_Status__c='Approved'` (i.e. after the `Negotiate` / `Record Recovery & Remittance` / `Approve Disbursement` flows, §4.11), an authorized user generates a Finance instruction CSV, attached to the Lien as a Salesforce File. Salesforce does not move funds; it generates and preserves the instruction Finance would consume — explicitly framed as a stand-in for a future Finance integration, same "boundary" framing as §4.8 for outbound SFTP.

**Apex — `FinanceInstructionWriter.cls`** (+ `FinanceInstructionWriterTest.cls`):
```
@AuraEnabled
public static FinanceInstructionResult generateInstruction(Id lienId)
```
Validates eligibility (Stage = Closed; Disbursement Status = Approved; all financial fields populated and non-negative; Payment Variance within $0.01 of zero; Health Plan + Rawlings Allocation sums to Remittance Amount within $0.01) before doing anything — any failure throws an `AuraHandledException` with a business-readable message, no File created. On success: builds a one-row, quote-escaped CSV (`Finance_Instruction_<Claimant_ID>_<YYYYMMDD-HHmmss>.csv`), inserts it as a `ContentVersion` + `ContentDocumentLink` attached to the Lien (`ShareType='V'`, `Visibility='AllUsers'` — same native-attach pattern as `ResponseFileWriter`, §3.6), then updates the three Finance-instruction audit fields (§2) on the Lien. Repeated generation is allowed and expected — each click produces a new timestamped File and updates the "most recent" audit fields without deleting prior Files.

**LWC — `generateFinanceInstruction`** (`lightning__RecordAction`): Confirmation → Loading (duplicate-submit guarded) → Success (filename, agreed/remittance amounts, both allocations; toast "Finance instruction attached: `<filename>`"; refreshes the record so Files and audit fields update) → Error (business-readable Apex message inline, no toast).

**Quick Action** `Generate Finance Instruction` on `Lien__c`, placed after `Negotiate` / `Record Recovery & Remittance` / `Approve Disbursement` in the Lien action bar (§4.11). No dynamic action-visibility gating built (server-side validation is enforced regardless); a `Generate_Finance_Instructions` custom permission is called out in the spec as a production follow-on, not built for the demo.

**Browser-verified 2026-07-28:** confirmed live against a manually-imported Lien with `Stage__c` and the financial fields set directly on the record (not via the `Negotiate` / `Record Recovery & Remittance` / `Approve Disbursement` guided screens) — the action button rendered in the Lien action bar (required a hard refresh of the record tab after the metadata deploy; Lightning Experience caches FlexiPage action bars client-side, so a newly-deployed action doesn't always appear until the page is reloaded), the eligibility check correctly rejected generation with a business-readable message while Recovery/Remittance/Allocation fields were still blank, and after entering the spec's demo values (Agreed/Recovery/Remittance $15,250; Health Plan Allocation $12,200; Rawlings Allocation $3,050; Disbursement Status Approved) generation succeeded — CSV attached to the Lien's Files related list. This verifies `FinanceInstructionWriter`/`generateFinanceInstruction` end-to-end but is **not** a verification of §4.11's guided Flow screens themselves, since the eligible state was reached by direct field edits, not by running the Negotiation/Recovery/Disbursement screens live.

### 4.13 Claimant Intake Validation and Rejection Handling — Status: **Built, deployed, and browser-verified live 2026-07-28 (later same day)**
Full spec: `docs/claimant-intake-validation-spec.md`. Closes a gap the reviewer flagged in the original importer: it parsed rows and created Liens, but never validated claimant data against an agreed data-quality contract, and it conflated two different outcomes — a bad *row* (intake rejection, the administrator's problem) versus a valid Lien whose *coverage* couldn't be confirmed (claim-evaluation escalation, a Rawlings ops problem). This build makes that distinction explicit and auditable, per the full-spec option (not the spec's "one-day cut line") — including existing-Lien update handling and partial DML, not just the required-field/duplicate/rejection-CSV minimum.

**New typed contract** (§9 of the spec) — `ClaimantImportResult.cls` and `ClaimantRowError.cls`, both top-level classes so `ClaimantImportController`, `ClaimantFileImportInvocable`, and their tests all use one shared shape instead of the old ad hoc `Map<String, Integer>`: `rowsReceived`, `createdCount`, `updatedCount`, `rejectedCount`, `automatedCount`, `escalatedCount`, `rejectionFilename`, `rejectionContentDocumentId`, and a `rowErrors` list (`rowNumber`/`claimantId`/`claimantName`/`rejectionCode`/`rejectionReason`; `originalRow` deliberately left un-`@AuraEnabled` so raw source rows never reach the client, per the spec's explicit instruction).

**`ClaimantImportService.importFromCsv` rewritten** to run the full pipeline from the spec, all outside per-row SOQL/DML loops:
- File-level gate (stops the import with no Lien touched at all): empty file, BOM/line-ending normalization, exact-header match (rejects reordered/renamed/extra/missing columns), no-data-rows, 1&nbsp;MB / 2,000-row demo guardrails.
- Row-level gate, 14 rules applied in the spec's fixed priority order so the rejection reason is deterministic per row: column count; required Claimant Name/ID; Claimant ID length (fits `Text(20)`); required/known/participating Health Plan (cross-references `Settlement_Health_Plan__c`, not just Account existence); required Injury Category; allowed Coverage Result values; Recoverable Amount required-when-Confirmed/numeric/non-negative/positive-when-Confirmed; and case-insensitive duplicate-Claimant-ID-within-file.
- Existing-Lien handling: a valid row matching an existing `Settlement__c` + `Claimant_ID__c` updates that Lien (claimant/health-plan/injury/coverage/amount fields; Intake Date and Stage/Response are preserved, per the spec's routing-behavior note that the create-triggered Flow doesn't re-fire on update) instead of inserting a duplicate; more than one match rejects the row (`AMBIGUOUS_EXISTING_LIEN`).
- `Database.insert(records, false)` / `Database.update(records, false)` so one bad record's DML failure doesn't discard the rest of the batch — failures convert to rejections (`LIEN_CREATE_FAILED`/`LIEN_UPDATE_FAILED`) with the record Id stripped out of the surfaced message.
- Automated/escalated counts are still computed by re-querying only the newly-*created* Liens after `Lien_Routing_Flow` runs, same pattern as the original importer — updated Liens are deliberately excluded from that count, since their Stage is preserved, not re-evaluated.
- When any row is rejected, a `Claimant_Import_Rejections_<timestamp>.csv` (`Row_Number,Claimant_ID,Claimant_Name,Rejection_Code,Rejection_Reason`, fully quote-escaped) is generated and attached to the Settlement via `ContentVersion`/`ContentDocumentLink` — same native-attach pattern as `ResponseFileWriter` (§3.6) and `FinanceInstructionWriter` (§4.12). No file is generated when every row is valid.

**Callers updated to the typed result:** `ClaimantImportController.importClaimants` now returns `ClaimantImportResult` directly (the spec's "preferred" backward-compatibility option, not the wrapper-map fallback); `ClaimantFileImportInvocable.Response` carries the same six counts plus the rejection filename for the Screen Flow. `claimantImport` LWC toast and `Import_Claimant_File` Flow's results screen both updated to show the full breakdown (§3.2, §3.4, §4.10 above cross-reference here).

**New demo fixture — `ClaimantValidationDemo.csv`** (Static Resource, separate from `SampleClaimants.csv`): 15 rows matching the spec's §15/16 table exactly — 8 Confirmed + 2 Unable to Confirm (10 creates, split 8 automated / 2 escalated), 1 row updating existing claimant `CLM-00001` from `SampleClaimants.csv` (demonstrates the update path), and 4 intentional rejections (unknown/nonparticipating Health Plan, missing Claimant ID, nonnumeric amount, and a duplicate-in-file of the same `CLM-00001` used for the update row, positioned after it). Not yet wired into a Quick Action or the demo script — the current `Import_Claimant_File` Screen Flow still targets whatever file the presenter uploads live, so this fixture is available to upload manually to demonstrate the rejection path, but no button points at it yet.

**Test coverage — deployed and run, all passing:** `ClaimantImportServiceTest` (22 methods, covering all 19 service-level cases the spec's §17 lists plus an `AMBIGUOUS_EXISTING_LIEN` case and two blank/zero-amount variants the spec's required list doesn't call out by name), `ClaimantFileImportInvocableTest` (2 methods, the second asserting every `Response` field is populated — §17 item 20), and the pre-existing `ClaimantImportControllerTest` (3 methods — see fix below). **27/27 passing** via `sf project deploy start -l RunSpecifiedTests` against the `rawlings-demo` org, deploy ID `0AfdL00000ePP6kSAG`. A dry-run (`--dry-run`) was run first to validate compilation and tests before committing the deploy.

**Bug caught by the dry-run — `ClaimantImportControllerTest.cls` fixed as part of this deploy:** this pre-existing test (not otherwise touched by this build) called `ClaimantImportController.importClaimants` expecting the old `Map<String, Integer>` return — the org-wide Apex compile step that runs on every deploy would have failed without fixing it, even though the file itself was outside this build's original scope. Updated to consume `ClaimantImportResult`, and its `createSettlement()` helper now also inserts `Settlement_Health_Plan__c` junction records for all three Health Plan Accounts — without that, the plan-participation check added by this build would have rejected every row of the real `SampleClaimants.csv` this test reads via `SeeAllData=true`.

**Browser-verified live, 2026-07-28:** presenter uploaded `ClaimantValidationDemo.csv` through `Import_Claimant_File` against the live settlement (`Hip Implant Mass Tort 2024`, cleared to zero Liens beforehand via `scripts/apex/resetSettlementA.apex`). Result: **11 created (9 Coverage Confirmed, 2 Escalated), 0 updated, 4 rejected, 15 rows received** — verified after the fact via direct SOQL against the org, not just the on-screen toast. The rejection CSV was pulled and read back (`ContentVersion.VersionData`, via anonymous Apex) and matches exactly: `UNKNOWN_HEALTH_PLAN`/`MISSING_CLAIMANT_ID`/`INVALID_RECOVERABLE_AMOUNT`/`DUPLICATE_IN_FILE` with correct row numbers, claimant names, and quote-escaping. Both the uploaded source file and the generated rejection file confirmed attached to the Settlement's Files related list via `ContentDocumentLink`.

**Update-path caveat, now empirically confirmed rather than theoretical:** because the live settlement had zero pre-existing Liens at test time, the fixture's `CLM-00001` "update" row had nothing to match and created a new Lien instead of updating one — 11 created / 0 updated, not the fixture's designed 10 created / 1 updated. The validation/rejection logic itself is fully verified; exercising the update branch specifically requires re-seeding `CLM-00001` (e.g. via `Import Claimants`/`SampleClaimants.csv`) before uploading `ClaimantValidationDemo.csv` on top of it.

**Regression risk to the already-working Act 1 path — resolved by the same live test, not just checked:** the validation-demo upload used all three Health Plan Accounts (`Health Plan A`, `B`, `C` — the same ones `SampleClaimants.csv` uses) against the live settlement, and every row referencing them passed the plan-participation check live. This is the same validation code path `SampleClaimants.csv`/`Import Claimants` runs through, so the participation-check regression risk is resolved in practice, though the `Import Claimants` button itself hasn't been separately re-clicked since the deploy.

**Deploy was scoped to exclude the flexipages and permission set already showing local changes** (`Lien_Record_Page.flexipage-meta.xml`, `Settlement_Record_Page.flexipage-meta.xml`, `Rawlings_Demo_Access.permissionset-meta.xml`) — those reflect in-org edits made directly through Setup that don't exist in the local working copy; deploying them would have overwritten that work. Only the 20 files specific to this build (plus the one pre-existing test fix above) were included in the `--source-dir` list.

**Reset script proven reusable for this build too:** `scripts/apex/resetSettlementA.apex` (pre-existing, from the Two-Settlement Restructure work) wasn't written with this build in mind, but works unmodified for it — it deletes by Settlement Id regardless of Claimant ID prefix, so it clears `SampleClaimants.csv`-derived and `ClaimantValidationDemo.csv`-derived Liens (and their Response/Task children) uniformly. Run twice live during this build's testing to cycle the live settlement back to empty between import attempts.

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
11. Files related list added to the Settlement Lightning Record Page so `Generate Response File`'s output is visible in one click.

### Also done (Planned Components, §4 — all built)
12. `LienBulkStageTransitionBatch` + `BulkStageTransitionController` (+ test) built and verified against small data, then at the ~850-record Coverage Confirmed pool.
13. `SettlementLienSummaryController` (+ test) and `settlementLienSummary` LWC built and verified — tiles confirmed against both the 15-ish live settlement and the ~1,000-record volume settlement.
14. `bulkStageTransition` LWC + `Bulk_Advance_Liens` Quick Action + flexipage placement built and verified end-to-end (preview → submit → toast → poll → Field History entry).
15. Volume settlement (`Talc Powder Mass Tort 2023`) created; `seedVolumeLiens.apex` run against it — ~1,000 records seeded, ~850 at Coverage Confirmed, distribution verified by count.
16. Pre-built deadline threshold record (`[Pre-existing] Helen Vasquez`, `CLM-PRE-001`) moved to the volume settlement; live settlement confirmed clean.
17. `Settlement_Health_Plan__c` junction object + related list built; 3 junction records hand-created and verified on the live settlement (§4.7).
18. "Liens Ready to Respond" Report built and verified via the Analytics REST API (§4.8) — kept as a manual/ad-hoc alternative, no longer the scripted live path.
19. `Liens_Near_Deadline` List View built and verified, then placed as a Dynamic Related List (Single) component on the Settlement Lightning Record Page — confirmed live on the volume settlement (§4.9).

The `GROUP BY` on a formula field question (§9) was sidestepped by design — the Summary controller filters on `Days_Remaining__c` instead — so it was never a blocker and doesn't need a spike.

### Also done, 2026-07-28
20. `ClaimantImportService` extracted; `ClaimantImportController` refactored to delegate to it; `ClaimantFileImportInvocable` + `claimantFileUpload` LWC + `Import_Claimant_File` Screen Flow built and deployed; `Import_Claimant_File` Quick Action added first in the Settlement action bar (§4.10). **Browser-verified later the same day** (as part of testing item 23) — the Flow screen, file-upload interaction, and Flow↔LWC data binding all confirmed working live.
21. Nine late-lifecycle `Lien__c` fields deployed; `Rawlings_Demo_Access` and field history tracking updated; built as one combined `Complete_Lien_Journey` Screen Flow, then split the same day into three independent Screen Flows — `Lien_Negotiate`, `Lien_Record_Recovery_Remittance`, `Lien_Approve_Disbursement` — each its own Quick Action (`Negotiate`, `Record Recovery & Remittance`, `Approve Disbursement`) on the Lien action bar; dedicated demo record (`CLM-PRE-002`, Angela Whitfield) seeded on the volume settlement; `resetLateLifecycleDemo.apex` verified running clean (§4.11). None of the three flows yet run end-to-end in a browser.
22. Three finance-instruction audit fields deployed; `FinanceInstructionWriter.cls` (+ test) and `generateFinanceInstruction` LWC built and deployed; `Generate Finance Instruction` Quick Action added to the Lien action bar after `Negotiate` / `Record Recovery & Remittance` / `Approve Disbursement` (§4.12). **Verified live 2026-07-28** — generation succeeded against a manually-eligible Lien, eligibility validation observed rejecting an incomplete record. The three guided flows themselves (§4.11) are still unverified in a browser.
23. `ClaimantImportResult.cls` + `ClaimantRowError.cls` added; `ClaimantImportService.importFromCsv` rewritten with the full validation/duplicate/update/rejection-CSV pipeline; `ClaimantImportController` and `ClaimantFileImportInvocable` updated to the typed result; `claimantImport` LWC and `Import_Claimant_File` Flow's results screen updated to show the full breakdown; `ClaimantValidationDemo.csv` Static Resource added; pre-existing `ClaimantImportControllerTest` fixed for the new return type and plan-participation requirement (§4.13). **Deployed and browser-verified live 2026-07-28** — `sf project deploy start`, 27/27 Apex tests passing (deploy ID `0AfdL00000ePP6kSAG`), flexipages/permission set deliberately excluded from the deploy scope; live upload of `ClaimantValidationDemo.csv` produced 11 created/0 updated/4 rejected with a correctly-formatted rejection CSV attached to the Settlement, confirmed by direct query.

### Remaining
1. **Task R.3 — Restage the browser/desktop for both settlements** (see `rawlings-demo-build-schedule.md`): live settlement + Escalation Queue in one tab set, volume settlement one click away for Act 2.
2. **Task V.7 — Full live dry run**, both acts, run at least twice clean before the real demo: on the volume settlement, Summary tiles reflect ~1,000 total liens with the expected spread → Bulk Advance Coverage Confirmed → Response Ready → preview reads ~850 → submit → job completes → Refresh confirms the shift → spot-check Field History on a few moved records.
3. **Browser verification of the 2026-07-28 builds** — items 20, 22, and 23 are now verified live. Item 21 (the three late-lifecycle guided flows themselves — `Lien_Negotiate`, `Lien_Record_Recovery_Remittance`, `Lien_Approve_Disbursement`) is still unexercised in a live session. Per `today-build-plan.md`, item 21 is stretch scope: it only gets folded into the live demo (Beat 9) if it runs clean in rehearsal; otherwise Mario's demo runs unchanged.
4. **Re-click `Import Claimants` against `SampleClaimants.csv` specifically** — item 23's live test used `ClaimantValidationDemo.csv` and the same three Health Plans `SampleClaimants.csv` relies on, so the participation-check regression risk is resolved in practice, but the original Static-Resource-backed button itself hasn't been separately clicked since the deploy. Also worth exercising the update path directly (re-seed `CLM-00001` via `Import Claimants` first, then upload `ClaimantValidationDemo.csv` on top of it) since the live test so far only exercised create/reject, not update.

---

## 6. Demo Script

**Superseded by `docs/demo-script.md`.** The version originally drafted here assumed a single settlement carrying both the live import and the seeded volume; that created a real problem — the live settlement's Lien related list and Escalation Queue would show the ~1,000 pre-seeded rows mixed in with the ~15 live-imported ones, undercutting the "this was just fifteen claimants" framing needed before the volume reveal. `docs/demo-script.md` fixes this with a two-settlement, two-act structure (Act 1: full intake-through-response loop on a clean live settlement; Act 2: the same platform at scale on a second, pre-loaded settlement) and is now the authoritative script, beat by beat, with talk track. See `demo-script-open-questions.md` for the reasoning behind the split.

---

## 7. Acceptance Criteria

### Import / Automated / Escalation paths, Deadline Monitoring, Cancel, Error States, Access Control, Path, History
Unchanged from the built prototype — see the original acceptance criteria; all currently pass. (Access Control criterion: a Health Plan A user sees only Health Plan A liens in the related list — already verified.)

### Summary Component (built — verify in Task V.7 dry run)
- [ ] `settlementLienSummary` renders on the Settlement record page above the Lien related list
- [ ] Stage tiles appear in pipeline order, not alphabetical
- [ ] Escalated count is broken out as its own tile
- [ ] Deadline tiles (Green/Yellow/Red) exclude Closed and Collected liens, computed via `Days_Remaining__c` WHERE-filters (not `GROUP BY` on the formula field)
- [ ] Refresh button re-runs the queries and updates all tiles
- [ ] A settlement with zero liens shows an empty state, not zeroed tiles

### Bulk Advance Liens (built — verify in Task V.7 dry run)
- [ ] Action appears in the Settlement action bar (no permission-set gating in this build pass — access is whatever the demo user's profile already grants)
- [ ] `Escalated` never appears as a From Stage option
- [ ] Preview count matches an independent list-view filter count for the same From Stage
- [ ] Confirm is disabled when the preview count is 0
- [ ] Submitting enqueues a Batch Apex job and returns immediately with a toast — the UI does not block waiting for the batch to finish
- [ ] The seeded ~850-record Coverage Confirmed bucket advances to Response Ready without hitting governor limits
- [ ] Every record moved by the batch shows the stage change in its History related list, attributed to the running user
- [ ] Submitting an invalid From/To pair via a direct Apex call (bypassing the LWC) throws `AuraHandledException`

### Settlement Health Plan Junction (done)
- [x] `Settlement_Health_Plan__c` related list renders on the Settlement record page
- [x] The demo settlement shows 3 junction records, matching the 3 Health Plan Accounts used elsewhere in the demo
- [x] No enforcement exists yet tying a Lien's `Health_Plan__c` to its Settlement's junction records — a Lien can still reference any Health Plan Account (documented gap, not a defect)

### "Liens Ready to Respond" Report (built, not the live path)
- [x] Report filters correctly to a given Settlement and `Stage__c = 'Coverage Confirmed'`
- [x] Export produces a file readable outside Salesforce (Excel/CSV) with claimant, health plan, recoverable amount, and response deadline visible
- [x] `ResponseFileWriter.cls` and `generateResponseFile` LWC deployed and functional, attaching to the Settlement record natively — this is now the primary live mechanism for Beat 6, and the report is the additional/ad-hoc path, not the other way around

### "Liens Near Deadline" dynamic related list (done)
- [x] Renders on the Settlement Lightning Record Page alongside the Summary tiles
- [x] Shows only liens with `Deadline_Status__c` in (Yellow, Red) and `Stage__c` not in (Closed, Collected)
- [x] Sorted by `Days_Remaining__c` ascending (most urgent first)
- [x] On the volume settlement, shows more than just the one pre-built deadline record, reflecting the randomized seed data
- [x] No Apex, no LWC — pure Lightning App Builder configuration

### Claimant Import via Screen Flow (built and browser-verified 2026-07-28, §4.10)
- [x] `ClaimantImportService.importFromCsv` shared by both the Static Resource and upload paths; original `ClaimantImportControllerTest` **updated 2026-07-28** for the typed result and plan-participation requirement (§4.13) — no longer unmodified, but still passing (3/3)
- [x] `ClaimantFileImportInvocable` drives a real `ContentVersion` end-to-end in Apex tests
- [x] `Import_Claimant_File` Screen Flow completes live: upload → parse → results screen, with correct created/updated/rejected/automated/escalated counts — verified via `ClaimantValidationDemo.csv` (§4.13)
- [x] Uploaded file lands in the Settlement's Files related list — confirmed via `ContentDocumentLink` query after the live upload
- [x] Original `Import Claimants` action stays live in the action bar as a fallback

### Claimant Intake Validation and Rejection Handling (built, deployed, and browser-verified live 2026-07-28, later same day, §4.13)
- [x] `sf project deploy start` succeeds for the new/changed classes, Flow, LWC, and Static Resource — deploy ID `0AfdL00000ePP6kSAG`
- [x] `ClaimantImportServiceTest`, `ClaimantFileImportInvocableTest`, and `ClaimantImportControllerTest` all pass in the org — 27/27
- [x] Exact-header, required-field, allowed-value, Health-Plan-participation, and duplicate/existing-Lien validation implemented per `claimant-intake-validation-spec.md` §5–§8, in the spec's fixed priority order
- [x] `Database.insert/update(records, false)` used so one bad record doesn't discard the rest of the batch
- [x] Rejection CSV generated and attached to the Settlement only when `rejectedCount > 0`; no file created when every row is valid — confirmed live, byte-for-byte correct (row/code/reason/escaping) via direct query
- [x] `ClaimantImportController` and `ClaimantFileImportInvocable` both return/consume the typed `ClaimantImportResult` shape
- [x] `SampleClaimants.csv` / the original `Import Claimants` action's Health Plans validated live — the same three Accounts, same participation check, all passed during the `ClaimantValidationDemo.csv` live test; the `Import Claimants` button itself hasn't been separately re-clicked
- [x] `ClaimantValidationDemo.csv` uploaded live through `Import_Claimant_File` — produced 11 created / 0 updated / 4 rejected (not the fixture's designed 10/1/4, since the live settlement had no pre-existing `CLM-00001` to update at test time; re-seed it first to exercise the update branch specifically)
- [x] `Import_Claimant_File` Screen Flow's results screen reached correctly with accurate data on a run with `rejectedCount > 0`; the specific visual difference between the two display variants wasn't independently eyeballed, only inferred from the correct underlying counts

### Late-lifecycle guided Flows — Negotiate / Record Recovery & Remittance / Approve Disbursement (built 2026-07-28, stretch scope — not yet browser-verified, §4.11)
- [x] Nine late-lifecycle fields deployed on `Lien__c`, added to `Rawlings_Demo_Access`, history tracking enabled on four of them
- [x] All three quick actions launch from a selected Lien with the correct record ID
- [ ] Each flow's "Not Eligible" stage guard correctly blocks/allows based on current `Stage__c`
- [ ] Happy path (Negotiation → matched Recovery/Remittance → Disbursement) ends at `Closed` with `Disbursement_Status__c='Approved'`
- [ ] Mismatch path (Remittance ≠ Agreed Amount) ends at `Pre-Validation` with a payment-review Task created, does not reach Disbursement
- [ ] Disbursement screen enforces Health Plan + Rawlings Allocation summing to Remittance Amount
- [ ] Updated values and Field History entries appear on the Lien after completion
- [x] `resetLateLifecycleDemo.apex` verified running clean, under a minute
- [ ] Beat 9 teaser decision made explicitly — in or out for Mario's demo

### Finance Instruction Generator (built and browser-verified 2026-07-28, stretch scope, §4.12)
- [x] `FinanceInstructionWriter.generateInstruction` and `FinanceInstructionWriterTest` deployed
- [x] Eligible Closed/Approved lien produces a correctly-ordered, quote-escaped CSV in one click, attached as a File on the Lien — verified live
- [x] Ineligible lien (missing financial values observed live; not-Closed/not-Approved/variance/allocation-mismatch cases covered by `FinanceInstructionWriterTest`) is rejected with a business-readable error and no File created
- [ ] Repeated generation creates a new timestamped File each time and updates the three audit fields without deleting prior Files — covered by `FinanceInstructionWriterTest`, not yet exercised live
- [ ] `generateFinanceInstruction` LWC prevents duplicate submission while processing — not yet exercised live
- [x] No dynamic action-visibility gating built (server-side validation enforced regardless, per spec)

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
| What seed volume proves the point without excess build/seed risk? | **Resolved:** ~1,000 records (~850 in one bucket), seeded synchronously in a single anonymous Apex run. The volume is capped by that approach, not chosen for effect — a synchronous run is bounded by Salesforce's 10,000-DML-rows-per-transaction governor limit (≈3,150 DML rows used at 1,000 seed records, so there's headroom to ~3,000 before hitting it, but not materially past that without switching to an async/`Batchable` seed). Going larger is possible but is real additional build work, not attempted for this pass since the demo only needs to prove the mechanism, not hit a specific magnitude. |
| Should the 90-day clock start from Intake Date or a Readiness Date on the Settlement? | Open — confirm with client; RFP implies the clock is program-defined. |
| Who holds the eventual permission set / ops-manager role in the client's real org model? | Open — confirm with client once access control is actually built. |
| Does the client want a completion notification when a bulk job finishes? | Open — likely a fast follow, out of scope for this build pass. |
| Should `Response Ready → Response Submitted` bulk-advancing also trigger the outbound response-file generation? | Open — flagged as a likely Phase 2 integration point between the import and bulk-transition mechanisms; currently the bulk tool only changes `Stage__c`. |
| Should a Lien's Health Plan be constrained to its Settlement's configured `Settlement_Health_Plan__c` junction records? | Open — §4.7 ships decorative-only (no enforcement) for the demo. Revisit if this needs to be a real business rule rather than a demo visual. |
| Should `Import Claimants` stay backed by a Static Resource, or move to a live Screen Flow file upload? | **Built and browser-verified 2026-07-28** — see §4.10. Live upload is now the primary Settlement action; Static Resource path kept as fallback. |
| Is the `Negotiate` / `Record Recovery & Remittance` / `Approve Disbursement` / `Generate Finance Instruction` stretch build ready for Mario's demo (Beat 9)? | Open — `Generate Finance Instruction` itself is now browser-verified (§4.12), but that was tested against a Lien made eligible by direct field edits, not by running the three earlier guided screens, which are still unverified live (§4.11). Beat 9 readiness still hinges on those flows running clean at the 2:35pm rehearsal per `today-build-plan.md`. If not, Beat 9 runs exactly as previously scripted. |
| If the Beat 9 teaser goes in, does the talk track need rewriting? | Open — the current Beat 9 line assumes an already-negotiated record; the seeded demo Lien (`CLM-PRE-002`) instead starts at `Coverage Confirmed`, so the line should shift to "watch this lien's whole life happen live" if the teaser is used. |
| Should `Generate Finance Instructions` be gated behind a custom permission in production? | Open — called out in `finance-instruction-generator-spec.md` §13 as a production follow-on; not built for the demo, same posture as the Bulk Advance permission-set question above. |
| Full claimant-intake-validation spec, or the spec's "one-day cut line"? | **Resolved 2026-07-28:** built the full spec — existing-Lien updates and partial DML included, not deferred. See §4.13. |
| Does enforcing Health-Plan-participation on import regress the existing `SampleClaimants.csv` / Act 1 path? | **Resolved live 2026-07-28:** the `ClaimantValidationDemo.csv` live test used the same three Health Plan Accounts against the live settlement and all passed the participation check. The `Import Claimants` button itself hasn't been separately re-clicked since the deploy, but it runs the identical validation code against the identical data. |
| Should `ClaimantValidationDemo.csv` get its own Quick Action or demo-script beat, or stay a manual upload for now? | Open — browser-verified working as a manual upload (§4.13), but nothing in the demo script or action bar points at it yet. |
