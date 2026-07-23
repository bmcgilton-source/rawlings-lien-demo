# Technical Spec: Settlement Lien Summary and Bulk Stage Transitions
**Feature:** Aggregate lien status rollup on the Settlement record, plus criteria-based bulk stage advancement
**Status:** Draft
**Context:** Demo prototype — Rawlings lien workflow management proposal
**Author:** Brian
**Last updated:** 2026-07-23

---

## Purpose

Give a Settlement record two things it doesn't have today: a rollup that answers "what's the state of this settlement's liens right now" without opening a list view and counting, and a way to move a batch of liens forward a stage without touching them one at a time. Both are aggregate/criteria-based rather than row-selection-based, so they hold up whether the settlement has 15 liens or 100,000.

---

## Background

In review, the reviewer stressed that a single settlement can carry up to 100,000 liens. The prototype as specced in [lien-import-quick-action-spec.md](lien-import-quick-action-spec.md) automates Intake → Coverage Confirmed / Escalated, but every stage after that — Response Ready → Response Submitted, Negotiation → Agreed, Recovery Calculated → Collected → Closed — is advanced one record at a time via the Path (chevron) component (see that spec's Component 11). That's fine for a demo record or two. It does not describe a workflow a settlement administrator could actually run against 100,000 liens, and if the demo implies otherwise, it undersells the platform and oversells the manual-Path story.

This spec adds the two pieces the reviewer's comment implies are missing:

1. **Summary** — a rollup of lien counts by stage and by deadline status, so an ops user opens the Settlement and immediately sees where the book of business stands.
2. **Bulk action** — a way to advance a filtered set of liens (by current stage) to the next stage in one operation, backed by Batch Apex so it scales to the full 100,000 without hitting governor limits or requiring UI row selection (Lightning list view selection tops out around 2,000 rows and is still a human clicking through pages — it was never going to get to 100,000).

Both components are additive to the existing data model. No new objects, and no changes to the automation Flow from the import spec.

---

## Scope

### In scope
- `Settlement Lien Summary` LWC: stage-count breakdown and deadline-status (Green/Yellow/Red) breakdown for a Settlement's liens, via aggregate SOQL
- Manual refresh on the summary component (no live push during an in-flight batch — see Out of scope)
- `Bulk Advance Liens` Quick Action on Settlement: pick a From Stage and a To Stage from a constrained, server-validated transition map, preview the affected count, submit
- `LienBulkStageTransitionBatch` — Batch Apex class that performs the update, chunked automatically regardless of volume
- Job progress surfaced in the LWC via polling `AsyncApexJob` (batches processed / total batches)
- Reliance on the Field History Tracking already enabled on `Lien__c.Stage__c` (per the import spec) for per-record audit trail of bulk-driven changes — no new logging object needed
- A permission set gating who can fire the bulk action (recommended, not optional — see Component 4)

### Out of scope
- Any computation behind the transitions themselves — this tool changes `Stage__c` only, exactly like the Path does today. It does not calculate recovery amounts, validate negotiation terms, or drive disbursement. Same boundary the import spec already drew around Recovery Calculated / Collected.
- Bulk-resolving Escalated liens. Escalation exists specifically to force individual human review; the bulk tool cannot use `Escalated` as a From Stage. An ops user resolves an escalation manually (moving it back to `Coverage Confirmed` or wherever), after which it's eligible for bulk treatment like any other lien.
- Bulk editing any field other than `Stage__c` (no bulk edit of `Recoverable_Amount__c`, `Escalation_Reason__c`, etc.)
- Undo/rollback UI. A batch that moved 40,000 liens to the wrong stage is not reversible from the LWC. Field History has the old values; reversal would be a manually-run corrective batch, not a button.
- Live/pushed progress updates to the Summary component while a batch runs elsewhere (no Platform Event or Lightning Message Service wiring in v1). The user clicks Refresh.
- Scheduling bulk transitions to run automatically (e.g., nightly sweep of Response Ready → Response Submitted). This spec is user-initiated only; a scheduled version is a natural Phase 2 but isn't here.

---

## Data Model

No new custom objects or fields. Both components read/write fields that already exist on `Lien__c` (`Stage__c`, `Deadline_Status__c`, `Settlement__c`).

| Object | API Name | Role in this spec |
|---|---|---|
| Settlement | `Settlement__c` | Hosts both the summary component and the bulk action Quick Action |
| Lien | `Lien__c` | Target of aggregate queries and the batch update |

---

## Components

### 1. Apex Controller — `SettlementLienSummaryController`

**File:** `force-app/main/default/classes/SettlementLienSummaryController.cls`

**Method signature:**
```
@AuraEnabled(cacheable=true)
public static LienSummary getSummary(Id settlementId)
```

**Behavior:**
1. Runs an aggregate query grouped by `Stage__c`, scoped to the settlement:
   ```sql
   SELECT Stage__c, COUNT(Id) cnt FROM Lien__c
   WHERE Settlement__c = :settlementId
   GROUP BY Stage__c
   ```
2. Runs a second aggregate query grouped by `Deadline_Status__c`, scoped to liens not yet at a terminal stage:
   ```sql
   SELECT Deadline_Status__c, COUNT(Id) cnt FROM Lien__c
   WHERE Settlement__c = :settlementId
   AND Stage__c NOT IN ('Closed', 'Collected')
   GROUP BY Deadline_Status__c
   ```
3. Assembles both into an inner class `LienSummary` with:
   - `totalLiens` (Integer)
   - `stageCounts` (`List<StageCount>` — `stage`, `count` — ordered to match the `Stage__c` picklist order, not alphabetically)
   - `deadlineCounts` (`Integer greenCount`, `yellowCount`, `redCount`)
   - `escalatedCount` (pulled out of `stageCounts` separately so the LWC can headline it, since escalation is the story the existing Escalation Queue list view already tells)
4. Both queries are aggregate `COUNT(Id)` — cost is proportional to index scan, not row count returned, so this holds up at 100,000 rows the same way it does at 15.

**Open item:** confirm in-org that `GROUP BY` on a formula text field (`Deadline_Status__c`) is accepted by the aggregate query — simple non-nested formulas normally are, but verify before demo (see Open Questions).

**Test class:** `SettlementLienSummaryControllerTest` — asserts counts against a known set of inserted liens across multiple stages and deadline buckets.

---

### 2. LWC — `settlementLienSummary`

**Directory:** `force-app/main/default/lwc/settlementLienSummary/`

**Target:** `lightning__RecordPage` (App Builder component, not a Quick Action — this is a persistent tile row, not a modal)

**Layout:**
- A row of stat tiles across the top: Total Liens, Escalated, then one tile per pipeline stage with its count
- A second row: three tiles for Green / Yellow / Red deadline counts, with the Red tile visually emphasized (this is the same signal the existing list view surfaces per-record; here it's the settlement-wide headline number)
- A "Refresh" button (calls `refreshApex` on the wired result) — explicitly manual, since a bulk batch may be running against the same data and the count should update on demand, not flicker mid-batch
- Empty state: "No liens on this settlement yet" if `totalLiens` is 0

**Data:** wired to `SettlementLienSummaryController.getSummary`, `recordId` from `@api recordId` (standard record-page context).

---

### 3. Apex Controller — `BulkStageTransitionController`

**File:** `force-app/main/default/classes/BulkStageTransitionController.cls`

**Method signatures:**
```
@AuraEnabled(cacheable=true)
public static List<String> getStageOptions()

@AuraEnabled(cacheable=true)
public static Integer previewCount(Id settlementId, String fromStage)

@AuraEnabled
public static Id enqueueBulkTransition(Id settlementId, String fromStage, String toStage)

@AuraEnabled(cacheable=true)
public static BatchJobStatus getJobStatus(Id jobId)
```

**Allowed transition map** (server-enforced — the LWC's To Stage combobox is populated from this, but the Apex re-validates on submit so a crafted client call can't force an invalid jump):

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

`Escalated` never appears as a From Stage option — omitted from `getStageOptions()` entirely, not just filtered client-side.

**Behavior:**
- `getStageOptions()`: returns the From Stage list (map keys above)
- `previewCount(settlementId, fromStage)`: `SELECT COUNT() FROM Lien__c WHERE Settlement__c = :settlementId AND Stage__c = :fromStage` — used by the LWC to show "This will affect 42,318 liens" before the user confirms
- `enqueueBulkTransition(settlementId, fromStage, toStage)`:
  1. Validates `toStage` against the map for the given `fromStage`; throws `AuraHandledException` if not a valid pair
  2. Validates `settlementId` is not null
  3. `Database.executeBatch(new LienBulkStageTransitionBatch(settlementId, fromStage, toStage), 2000)`
  4. Returns the `AsyncApexJob` Id so the LWC can poll it
- `getJobStatus(jobId)`: queries `AsyncApexJob` (`Status`, `JobItemsProcessed`, `TotalJobItems`, `NumberOfErrors`) and returns a small wrapper for the progress bar

**Test class:** `BulkStageTransitionControllerTest` — asserts invalid transition pairs throw, valid ones enqueue a job, and `previewCount` matches inserted test data. Use `Test.startTest()/stopTest()` to force the batch to run synchronously in test context and assert the resulting `Stage__c` values.

---

### 4. Batch Apex — `LienBulkStageTransitionBatch`

**File:** `force-app/main/default/classes/LienBulkStageTransitionBatch.cls`

```
public class LienBulkStageTransitionBatch implements Database.Batchable<SObject>, Database.Stateful
```

**Constructor:** `LienBulkStageTransitionBatch(Id settlementId, String fromStage, String toStage)`

**`start(Database.BatchableContext bc)`:**
```sql
SELECT Id, Stage__c FROM Lien__c
WHERE Settlement__c = :settlementId AND Stage__c = :fromStage
```
Returned as a `Database.QueryLocator` — this is what makes the volume a non-issue. A `QueryLocator` can serve up to 50 million rows; the governor limits that bite at 100,000+ rows in a single transaction simply don't apply here because the framework chunks it into per-batch execute contexts automatically.

**`execute(Database.BatchableContext bc, List<Lien__c> scope)`:**
- Sets `Stage__c = toStage` on every record in scope
- `update scope;`
- Field History Tracking on `Stage__c` (already enabled per the import spec) captures the old/new value and timestamp for every record, same as a manual Path change would — no separate logging needed

**`finish(Database.BatchableContext bc)`:**
- Queries the completed `AsyncApexJob` for `NumberOfErrors` / `TotalJobItems`
- No email or notification in v1 (the LWC polling covers the in-session case); a production version would send a completion notification since a 100,000-record batch runs well past the length of a UI session — see Future State

**Batch size:** 2,000 (Salesforce max) — chosen for throughput; no reason to run smaller for a same-object, single-field update.

**Governor limits:** none of concern. Each batch of 2,000 does one `update` DML call touching one field — nowhere near the 10,000 DML row limit or the 150 DML statement limit per transaction.

---

### 5. Quick Action — `Bulk Advance Liens`

**File:** `force-app/main/default/quickActions/Settlement__c.Bulk_Advance_Liens.quickAction-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<QuickAction xmlns="http://soap.sforce.com/2006/04/metadata">
    <actionSubtype>ScreenAction</actionSubtype>
    <label>Bulk Advance Liens</label>
    <lightningWebComponent>bulkStageTransition</lightningWebComponent>
    <optionsCreateFeedItem>false</optionsCreateFeedItem>
    <type>LightningWebComponent</type>
</QuickAction>
```

---

### 6. LWC — `bulkStageTransition`

**Directory:** `force-app/main/default/lwc/bulkStageTransition/`

**Target:** `lightning__RecordAction` / `ScreenAction`

**States:**

| State | Trigger | UI |
|---|---|---|
| Select | Action opens | From Stage combobox (via `getStageOptions`); To Stage combobox populates once From Stage is chosen (single valid option per the map — rendered as a disabled/pre-filled field, not a free choice, since each From Stage maps to exactly one To Stage) |
| Preview | From Stage chosen | Calls `previewCount`; shows "This will advance **{count}** liens from **{fromStage}** to **{toStage}**." Confirm / Cancel buttons. If count is 0, disable Confirm and show "No liens in this stage." |
| Submitting | Confirm clicked | Spinner, "Queuing batch job..." |
| Queued | `enqueueBulkTransition` returns a job Id | Sticky toast: "Bulk transition started — {count} liens moving from {fromStage} to {toStage}. This runs in the background; large volumes may take several minutes." Modal closes. |
| Progress (optional, same session) | If the user reopens the action or a progress panel while the job is running | Polls `getJobStatus` every 5s, shows a progress bar (`JobItemsProcessed / TotalJobItems`) until `Status = 'Completed'` |

**Why the To Stage field is constrained rather than a free combobox:** the transition map is one-to-one (each From Stage has exactly one valid next stage). Presenting it as a locked confirmation rather than an open choice removes an entire class of "what if they pick Closed from Intake" input validation on the client, and makes the confirmation copy read as a statement of fact rather than a form.

---

## Deployment Steps

1. Deploy `SettlementLienSummaryController.cls` + test, `BulkStageTransitionController.cls` + test, `LienBulkStageTransitionBatch.cls`
2. Deploy `settlementLienSummary` and `bulkStageTransition` LWCs
3. Create the `Bulk Advance Liens` Quick Action on `Settlement__c`
4. Add `settlementLienSummary` to the Settlement Lightning Record Page, above the Lien related list
5. Add `Bulk Advance Liens` to the Settlement action bar, alongside `Import Claimants` and `Generate Response File`
6. Create a permission set (`Bulk_Lien_Stage_Actions`) granting access to the Quick Action and the two new Apex classes; assign only to ops-manager-type users. Do not expose the action to every profile that can see a Settlement record — see Component 4 rationale and Open Questions.
7. End-to-end verify:
   - Open a Settlement with liens across multiple stages
   - Confirm the Summary component tiles match a manual count (use demo-scale data — 15–50 records — for verification, since exact counts are checkable by eye at that volume)
   - Click Bulk Advance Liens, pick a From Stage with a nonzero count, confirm the preview count matches, submit
   - Confirm the toast fires and, after a short delay, the Summary component (on Refresh) reflects the moved records
   - Confirm Field History on a moved record shows the stage change
   - Confirm a user without the permission set does not see the Bulk Advance Liens action

---

## Acceptance Criteria

### Summary Component
- [ ] `settlementLienSummary` renders on the Settlement record page above the Lien related list
- [ ] Stage tiles appear in pipeline order, not alphabetical
- [ ] Escalated count is broken out as its own tile
- [ ] Deadline tiles (Green/Yellow/Red) exclude Closed and Collected liens from the denominator
- [ ] Refresh button re-runs the aggregate queries and updates all tiles
- [ ] A settlement with zero liens shows an empty state, not zeroed tiles with no context

### Bulk Advance Liens
- [ ] Action appears in the Settlement action bar for users with the `Bulk_Lien_Stage_Actions` permission set, and is absent for users without it
- [ ] `Escalated` never appears as a From Stage option
- [ ] Preview count matches an independent list-view filter count for the same From Stage
- [ ] Confirm is disabled when the preview count is 0
- [ ] Submitting enqueues a Batch Apex job and returns immediately with a toast — the UI does not block waiting for the batch to finish
- [ ] A batch run against 10,000+ synthetic test records (or the closest volume practical in a scratch org) completes without hitting governor limits
- [ ] Every record moved by the batch shows the stage change in its History related list, attributed to the running user, not left blank
- [ ] Submitting the action with an invalid From/To pair via a direct Apex call (bypassing the LWC) throws `AuraHandledException` — server-side validation, not just client-side

---

## Open Questions

| Question | Owner | Blocking? |
|---|---|---|
| Does `GROUP BY` on the `Deadline_Status__c` formula field work as written, or does it need to be a stored (non-formula) field for aggregation? | Brian | Yes — verify before demo build |
| Who should actually hold the `Bulk_Lien_Stage_Actions` permission set in the client's org model — is there an existing "Settlement Ops Manager" profile/role, or does one need to be defined for this proposal? | Confirm with client | Yes — needed before permission set is scoped |
| Should the bulk tool support a volume large enough to require chaining (i.e., a single From Stage bucket exceeding the practical batch count for a demo)? Not a technical blocker (QueryLocator handles it natively) but affects what volume we stage for the demo to make the "no problem at 100,000" claim credible on screen | Brian | No — recommend seeding one deliberately large synthetic stage bucket (10,000+) for the demo rather than only the 15–25 row dataset used elsewhere |
| Does the client want a completion notification (email, Chatter post, or similar) when a bulk job finishes, given it may outlast the ops user's session? Out of scope for v1 per this spec, but likely a fast follow | Confirm with client | No |
| Should `Response Ready` bulk-advancing to `Response Submitted` also trigger the outbound response-file generation (Component 6 in the import spec), or does that remain a separate manual action? Currently this spec only changes `Stage__c`, nothing else | Brian | No — flag as a likely Phase 2 integration point between the two specs |

---

## Future State (Production Architecture)

Unlike the import spec's demo-vs-production split, the bulk transition mechanism specced here **is already production-shaped** — `Database.Batchable` with a `QueryLocator` is exactly how this would run at real scale, not a simulation of it. What changes going to production:

1. A completion notification (Platform Event → email/Slack, or a Chatter post on the Settlement) once `finish()` runs, since a 100,000-record batch will usually outlast the initiating user's session
2. A scheduled/nightly variant (`Schedulable`) for transitions the business wants swept automatically rather than user-triggered — e.g., a nightly job advancing everything that's sat in `Response Submitted` past the administrator's SLA window
3. Error handling in `finish()` — surfacing `NumberOfErrors` from `AsyncApexJob` to an ops-facing record rather than leaving it to be checked manually in Setup → Apex Jobs
4. Possibly a lightweight audit object if the client needs a queryable log of "who ran which bulk transition, when, on how many records" beyond what Field History provides per-record — Field History answers "what changed on this lien," not "what bulk operations has this settlement been subject to." Worth a client conversation before building it speculatively.
5. The Summary component's aggregate queries would move behind a short server-side cache (e.g., Platform Cache) only if usage patterns show the same Settlement's summary being loaded repeatedly in short succession across many users — not needed at anticipated demo or early-production usage.
