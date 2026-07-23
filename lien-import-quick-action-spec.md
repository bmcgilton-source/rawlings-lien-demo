# Technical Spec: Claimant Import and Response File Generation — Automation-First Approach
**Feature:** Simulated SFTP Receive-Process-Respond with Automated Lien Processing  
**Status:** Draft  
**Context:** Demo prototype — Rawlings lien workflow management proposal  
**Author:** Brian  
**Last updated:** 2026-07-22

---

## Purpose

Provide a single-click Quick Action on the Settlement record that simulates the SFTP integration layer picking up an inbound claimant file and loading it into Salesforce as Lien records — then immediately demonstrates the platform's automation capability by processing those records without further user intervention. A second Quick Action generates a response CSV file that a local Python server writes to a visible Outbound folder on the demo machine. Together these two actions make the receive-process-respond pattern physically visible: a file in an Inbound folder, liens created and processed in Salesforce, a response file appearing in an Outbound folder. The goal is to show that the system does the work, and only involves a human when it encounters something it cannot resolve on its own.

---

## Background

The Rawlings RFP emphasizes two things in equal measure: the receive-process-respond pattern as the central behavior of the platform, and the requirement that the process run fully automated with human escalation only when necessary. The earlier version of this spec focused on the import mechanic. This version extends it to show what happens immediately after import — which is where the automation story lives.

In production, the trigger is the integration layer polling a settlement administrator's SFTP server, picking up a claimant file, validating and transforming records, and loading them into Salesforce via Bulk API 2.0. A Platform Event then fires the workflow engine. For the demo, the Quick Action replaces the SFTP and middleware layers. The Salesforce-side behavior — automated processing, stage transitions, Response record creation, and escalation routing — is real and runs as it would in production.

The demo narrative reframes accordingly: the button simulates the integration layer. Everything that happens after the button is the platform doing what the client is buying.

---

## Scope

### In scope
- Quick Action on the Settlement object for claimant import
- Apex controller reading a Static Resource CSV and inserting Lien records, including simulated service output fields
- LWC dialog for import: confirmation UI, loading state, and outcome toast
- Static Resource containing sample claimant data with pre-populated coverage and damages fields
- Record-triggered Flow evaluating each Lien on creation and branching to either the automated path or the escalation path
- Automated path: stage advancement to Coverage Confirmed, automatic Response record creation at Draft status
- Escalation path: stage set to Escalated, Task created and assigned to escalation queue, escalation reason recorded
- Escalation queue list view showing all liens requiring human attention
- Two additional `Stage__c` picklist values (`Recovery Calculated`, `Collected`) and a Lightning Path (chevron) on the Lien record showing the full lifecycle, including the stages this prototype doesn't automate
- Field history tracking on Lien (`Stage__c`, `Coverage_Result__c`, `Escalation_Reason__c`) and Response (`Status__c`), with a History related list on the Lien page
- Pre-built deadline-threshold lien record demonstrating the deadline monitoring story
- Page layout and App Builder configuration
- **Response file generation:** Apex callout class that queries Coverage Confirmed liens, builds a response CSV, and POSTs it to a local Python server
- **Generate Response File Quick Action:** LWC dialog on the Settlement record that triggers the Apex callout
- **Local Python HTTP server:** receives the POST from Apex and writes the response CSV to a local Outbound folder
- **Demo desktop folders:** Inbound and Outbound folders visible on the demo machine during the presentation
- **Pre-staged inbound CSV:** the SampleClaimants file sitting in the Inbound folder before the demo begins

### Out of scope
- Actual SFTP polling or file transfer
- Bulk API 2.0 (this demo uses synchronous DML; Bulk API is the production architecture)
- The Liability service or Damages service (coverage result and recoverable amount are simulated in the CSV)
- Per-administrator data quality contracts or row-level validation rules
- Duplicate detection against existing Lien records
- The negotiation workflow and charge line items
- Multiple rounds of administrator counter-response
- Production error handling, retry logic, or dead-letter queuing
- Recovery calculation and collection/disbursement logic — `Recovery Calculated` and `Collected` are Path steps only, advanced manually; no reconciliation, payment calculation, or disbursement automation backs them

---

## Data Model

### Objects

| Object | API Name | Notes |
|---|---|---|
| Settlement | `Settlement__c` | Parent record the action fires from |
| Lien | `Lien__c` | Created by the import; processed by the Flow |
| Response | `Response__c` | Child of Lien; created automatically by the Flow |

### Lien Fields

| Field | API Name | Type | Notes |
|---|---|---|---|
| Settlement | `Settlement__c` | Lookup(Settlement__c) | Required |
| Claimant Name | `Claimant_Name__c` | Text(100) | |
| Claimant ID | `Claimant_ID__c` | Text(20) | |
| Health Plan | `Health_Plan__c` | Lookup(Account) | Lookup preferred; enables sharing demo |
| Injury Category | `Injury_Category__c` | Text(100) | |
| Stage | `Stage__c` | Picklist | See stage values below |
| Intake Date | `Intake_Date__c` | Date | |
| Response Deadline | `Response_Deadline__c` | Date | |
| Coverage Result | `Coverage_Result__c` | Picklist | Confirmed, Unable to Confirm |
| Recoverable Amount | `Recoverable_Amount__c` | Currency | Simulates Damages service output |
| Escalation Reason | `Escalation_Reason__c` | Text(255) | Populated by Flow on escalation path |
| Days Remaining | `Days_Remaining__c` | Formula(Number) | `Response_Deadline__c - TODAY()` |
| Deadline Status | `Deadline_Status__c` | Formula(Text) | Green / Yellow / Red based on Days Remaining |

**Stage picklist values (in order):**
Intake, Coverage Confirmed, Escalated, Response Ready, Response Submitted, Negotiation, Agreed, Pre-Validation, Recovery Calculated, Collected, Closed

`Recovery Calculated` and `Collected` exist so the Path (chevron) can visualize the full lifecycle. Neither is reached by automation in this prototype — see Component 11.

**Deadline Status formula:**
```
IF(Days_Remaining__c > 20, "Green",
  IF(Days_Remaining__c > 10, "Yellow", "Red"))
```

### Response Fields

| Field | API Name | Type | Notes |
|---|---|---|---|
| Lien | `Lien__c` | Master-Detail(Lien__c) | |
| Claimed Amount | `Claimed_Amount__c` | Currency | Copied from Lien Recoverable Amount by Flow |
| Status | `Status__c` | Picklist | Draft, Submitted, Sent |
| Response Date | `Response_Date__c` | Date | Set to today by Flow |

---

## Components

### 1. Static Resource — `SampleClaimants`

A UTF-8 encoded CSV file uploaded to Salesforce as a Static Resource. Contains simulated claimant data including pre-populated coverage results and recoverable amounts that stand in for the outputs of the Liability and Damages services in production.

**Filename on disk:** `SampleClaimants.csv`  
**Static Resource name:** `SampleClaimants` (case-sensitive — the Apex references this by name)  
**Cache control:** Public  
**Format:** CSV with header row

### Column Definitions

| Column | Index | Description |
|---|---|---|
| Claimant_Name | 0 | Full name of the claimant |
| Claimant_ID | 1 | Administrator-assigned claimant identifier |
| Health_Plan | 2 | Health Plan Account name (must match Account record exactly) |
| Injury_Category | 3 | Mass tort injury category |
| Coverage_Result | 4 | Confirmed or Unable to Confirm — simulates Liability service output |
| Recoverable_Amount | 5 | Dollar amount — simulates Damages service output; blank if not confirmed |

### Data Design for Demo

The CSV should be structured to produce a visible split when the import runs:

- **~85% of rows:** `Coverage_Result = Confirmed` with a `Recoverable_Amount`. These will auto-advance and generate Response records.
- **~15% of rows:** `Coverage_Result = Unable to Confirm` with no amount. These will route to the escalation queue.

This ratio makes the automation story visible — the list view shows most liens having already moved past Intake while a handful sit in Escalated, waiting for a human.

### Sample File

```
Claimant_Name,Claimant_ID,Health_Plan,Injury_Category,Coverage_Result,Recoverable_Amount
James Holloway,CLM-00001,BlueCross Premier,Hip Implant,Confirmed,4250.00
Maria Santos,CLM-00002,Aetna Select,Hip Implant,Confirmed,6100.00
Robert Chen,CLM-00003,BlueCross Premier,Hip Implant,Confirmed,3875.00
Patricia Williams,CLM-00004,United Standard,Hernia Mesh,Unable to Confirm,
David Kim,CLM-00005,Aetna Select,Hip Implant,Confirmed,5200.00
Linda Okafor,CLM-00006,United Standard,Hernia Mesh,Confirmed,4900.00
Michael Torres,CLM-00007,BlueCross Premier,Hernia Mesh,Confirmed,3400.00
Susan Nakamura,CLM-00008,Aetna Select,Hip Implant,Unable to Confirm,
Thomas Adeyemi,CLM-00009,United Standard,Hip Implant,Confirmed,7800.00
Jennifer Walsh,CLM-00010,BlueCross Premier,Hernia Mesh,Confirmed,4100.00
Marcus Johnson,CLM-00011,Aetna Select,Hip Implant,Confirmed,5550.00
Diana Reyes,CLM-00012,United Standard,Hip Implant,Confirmed,6200.00
Kevin Park,CLM-00013,BlueCross Premier,Hernia Mesh,Unable to Confirm,
Sarah Mitchell,CLM-00014,Aetna Select,Hernia Mesh,Confirmed,3750.00
Carlos Mendez,CLM-00015,United Standard,Hip Implant,Confirmed,4400.00
```

**Demo guidance:** Keep to 15–25 rows. Match Health Plan names exactly to Account records in the org. Adjust the ratio of confirmed to escalated rows to taste — three escalated records out of fifteen creates a clean visual story without burying the automation.

---

### 2. Apex Controller — `ClaimantImportController`

**File:** `force-app/main/default/classes/ClaimantImportController.cls`

**Method signature:**
```
@AuraEnabled
public static Map<String, Integer> importClaimants(Id settlementId)
```

Returns a Map rather than a plain Integer so the LWC can display both the total created count and the escalated count in the success toast (e.g., "15 liens created. 12 processing automatically, 3 routed to escalation queue.").

**Behavior:**
1. Queries the `SampleClaimants` Static Resource body
2. Splits on newline, skips the header row, skips blank rows
3. Parses each row using a quoted-field-aware CSV parser
4. Builds a `Lien__c` record per row, setting:
   - `Stage__c = 'Intake'`
   - `Intake_Date__c = Date.today()`
   - `Response_Deadline__c = Date.today().addDays(90)`
   - `Coverage_Result__c` from column 4
   - `Recoverable_Amount__c` from column 5 (parsed as Decimal; blank rows set to null)
5. Bulk inserts the list — the record-triggered Flow fires automatically on insert
6. Queries back the inserted records to count how many are Escalated vs. Coverage Confirmed (the Flow will have already run by the time the query executes)
7. Returns the counts map to the LWC

**Note on Flow timing:** Record-triggered Flows that run before-save complete synchronously within the DML transaction. After-save Flows run asynchronously. For the stage transition and Response record creation to be visible immediately after the import toast clears, build the Flow as a before-save Flow for the stage transition and a separate after-save Flow for the Response record creation. Alternatively, handle both in a single after-save Flow and accept a one to two second delay before the related list reflects the final state.

**Error handling:**
- If the Static Resource is not found, throws `AuraHandledException` with a human-readable message
- If `cols.size() < 5`, the row is skipped silently
- DML exceptions propagate to the LWC catch handler

**Governor limit considerations:**  
At 25 rows this runs comfortably within synchronous limits. For production, replace with Bulk API 2.0.

**Test class:** `ClaimantImportControllerTest`  
Minimum coverage: positive test (valid CSV, records created, counts returned), negative test (missing Static Resource, exception thrown), escalation test (Unable to Confirm rows produce Escalated stage after Flow runs — use `Test.startTest() / stopTest()` to ensure Flow execution).

---

### 3. Record-Triggered Flow — `Lien Automation on Create`

**Flow type:** Record-Triggered Flow  
**Object:** `Lien__c`  
**Trigger:** A record is created  
**Optimize for:** Actions and Related Records (after-save)

This Flow is the core of the automation story. It fires on every Lien creation and makes the routing decision the system would make in production after the Liability and Damages services have returned their results.

#### Flow Logic

```
START: Lien created
  │
  ├─ Decision: Coverage confirmed and amount present?
  │    Condition: Coverage_Result__c = 'Confirmed'
  │              AND Recoverable_Amount__c > 0
  │
  ├─ YES → Automated Path
  │         1. Update Lien: Stage__c = 'Coverage Confirmed'
  │         2. Create Response__c record:
  │              Lien__c = {lien record ID}
  │              Claimed_Amount__c = {Recoverable_Amount__c}
  │              Status__c = 'Draft'
  │              Response_Date__c = {today}
  │
  └─ NO  → Escalation Path
            1. Update Lien: Stage__c = 'Escalated'
            2. Update Lien: Escalation_Reason__c = 'Coverage could not be confirmed automatically'
            3. Create Task:
                 Subject = 'Review: Coverage confirmation required'
                 WhatId = {lien record ID}
                 OwnerId = {Escalation Queue ID}
                 ActivityDate = {today + 5 days}
                 Description = 'Lien routed to escalation. Coverage result: ' 
                               + {Coverage_Result__c}
```

#### Escalation Queue

Create a Salesforce Queue named `Lien Escalation Queue` on the Lien object. Tasks created by the escalation path are assigned to this queue. Members of the queue (ops users assigned to handle exceptions) see escalated work in their Task list and in the Escalation Queue list view.

---

### 4. LWC — `claimantImport`

**Directory:** `force-app/main/default/lwc/claimantImport/`

**Target:** `lightning__RecordAction`  
**Action type:** `ScreenAction`

#### States

| State | Trigger | UI |
|---|---|---|
| Default | Action opens | Descriptive text explaining what the import simulates, Run Import and Cancel buttons |
| Loading | Run Import clicked | Spinner with "Processing claimant file..." label |
| Success | Apex returns counts | Modal closes, sticky success toast showing total created, automated count, and escalated count |
| Error | Apex throws | Sticky error toast, modal stays open |

#### Success Toast Message Format
```
"15 liens created — 12 processing automatically, 3 routed to escalation queue."
```

This phrasing is deliberate. It's the automation story in one sentence, visible in the room without needing to navigate anywhere.

#### Post-Success Navigation
Uses `NavigationMixin.Navigate` to return to the Settlement record view, reloading the Lien related list. The list view should be configured to show Stage so the split between Coverage Confirmed and Escalated is immediately visible.

---

### 5. Quick Action — Settlement Object

**Action type:** LWC  
**LWC:** `claimantImport`  
**Label:** `Import Claimants`  
**Icon:** `utility:upload`  
**Object:** `Settlement__c`

---

### 6. Apex Callout Class — `ResponseFileWriter`

**File:** `force-app/main/default/classes/ResponseFileWriter.cls`

Queries Coverage Confirmed liens for a Settlement, builds a response CSV, and POSTs it to the local Python server via Named Credential. Uses `@Future(callout=true)` so the callout is asynchronous — the LWC gets an immediate success response and the file appears on the demo machine 2–5 seconds later while you're narrating.

**Method signatures:**
```
@AuraEnabled
public static void generateResponseFile(Id settlementId)

@Future(callout=true)
private static void writeFileAsync(String settlementId)
```

Note: `@Future` methods cannot accept SObject or Id parameters directly — pass settlementId as a String and cast inside the future method.

**Behavior of `generateResponseFile`:**
1. Validates settlementId is not null; throws `AuraHandledException('No settlement specified.')` if so
2. Calls `writeFileAsync(String.valueOf(settlementId))` and returns void immediately
3. The LWC treats the immediate return as success

**Behavior of `writeFileAsync`:**
1. Queries: `SELECT Claimant_ID__c, Claimant_Name__c, Health_Plan__r.Name, Recoverable_Amount__c, Stage__c, Response_Deadline__c FROM Lien__c WHERE Settlement__c = :settlementId AND Stage__c = 'Coverage Confirmed'`
2. Exits silently if no records (demo data will always have confirmed liens at this point)
3. Builds CSV header: `Claimant_ID,Claimant_Name,Health_Plan,Recoverable_Amount,Stage,Response_Deadline`
4. Appends one row per Lien record
5. Generates filename: `response_` + timestamp using `Datetime.now().format('yyyyMMdd_HHmmss')` + `.csv`
6. Builds `HttpRequest`:
   - Endpoint: `callout:LocalSFTPDemo`
   - Method: `POST`
   - Header `Content-Type`: `text/csv`
   - Header `X-Filename`: generated filename
   - Body: CSV string
7. Sends via `new Http().send(req)`; logs response status via `System.debug`
8. No user-facing error handling — demo context only

**Governor limits note:** Add a comment noting `@Future(callout=true)` is used for demo simplicity. Production would use a Platform Event, a Queueable job, proper error handling, and retry logic.

---

### 7. LWC — `generateResponseFile`

**Directory:** `force-app/main/default/lwc/generateResponseFile/`

**Target:** `lightning__RecordAction`
**Action type:** `ScreenAction`

#### `generateResponseFile.html`
Two states:
- **Default:** Heading "Generate Response File", description "Builds the response CSV for all Coverage Confirmed liens on this settlement and writes it to the outbound folder. The file will appear within a few seconds.", "Generate" button (variant brand), "Cancel" button (variant neutral)
- **Loading:** `lightning-spinner` with alternative-text "Generating...", buttons hidden

#### `generateResponseFile.js`
Same pattern as `claimantImport.js`. Key differences:
- Import `generateResponseFile` from `@salesforce/apex/ResponseFileWriter.generateResponseFile`
- On success: toast title "Response file initiated", message "File will appear in the outbound folder in a few seconds.", variant "success", mode "sticky"
- Close action screen and return to Settlement record after toast
- No NavigationMixin needed — just `CloseActionScreenEvent` is sufficient since the Settlement record is already open

**Note on timing:** Because the Apex method is `@Future`, the toast fires before the file is written. This is correct behaviour. The 2–5 second gap between the toast and the file appearing reads as the system doing work. Narrate "give it a moment" and turn to the desktop.

#### `generateResponseFile.js-meta.xml`
Identical structure to `claimantImport.js-meta.xml`.

---

### 8. Quick Action — Generate Response File

**File:** `force-app/main/default/quickActions/Settlement__c.Generate_Response_File.quickAction-meta.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<QuickAction xmlns="http://soap.sforce.com/2006/04/metadata">
    <actionSubtype>ScreenAction</actionSubtype>
    <label>Generate Response File</label>
    <lightningWebComponent>generateResponseFile</lightningWebComponent>
    <optionsCreateFeedItem>false</optionsCreateFeedItem>
    <type>LightningWebComponent</type>
</QuickAction>
```

---

### 9. Python Local Server — `demo_server.py`

Runs on the demo machine throughout the presentation. Listens for POST requests from Salesforce and writes received files to the Outbound folder. No external dependencies — Python 3 standard library only.

**File:** `demo/demo_server.py` (outside `force-app/` — not deployed to Salesforce)

```python
from http.server import HTTPServer, BaseHTTPRequestHandler
import os

OUTBOUND_DIR = os.path.expanduser("~/Desktop/sftp-demo/outbound")

class FileReceiver(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8')
        filename = self.headers.get('X-Filename', 'response.csv')
        os.makedirs(OUTBOUND_DIR, exist_ok=True)
        filepath = os.path.join(OUTBOUND_DIR, filename)
        with open(filepath, 'w') as f:
            f.write(body)
        print(f"Written: {filename}")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

    def log_message(self, format, *args):
        pass  # suppress per-request console noise

print(f"Listening on :8765 → {OUTBOUND_DIR}")
HTTPServer(('0.0.0.0', 8765), FileReceiver).serve_forever()
```

**Start before the demo:** `python3 demo/demo_server.py`

---

### 10. Escalation Queue List View

A saved list view on the Lien object showing all liens requiring human attention.

**List view name:** `Escalation Queue`  
**Filter:** `Stage__c = 'Escalated'`  
**Columns:** Claimant Name, Claimant ID, Health Plan, Injury Category, Escalation Reason, Intake Date, Response Deadline, Assigned To  
**Visibility:** Visible to all users (or scoped to ops profiles)

This list view is a demo prop as much as a functional component. Having it open in a separate browser tab during the demo — showing the escalated records appear as the import runs — makes the exception routing story tangible.

---

### 11. Lightning Path — Lien Stage Visualization (Chevron)

**Purpose:** The proposal's diagram shows five capability areas end to end — Lien Intake, Claim Evaluation, Response, Recovery Calculation, Collection & Disbursement. This prototype only builds real automation for the first two-and-a-half. The Path makes the *whole* lifecycle visible on every Lien record regardless, so the client sees the platform is structured to track the entire process, not just the slice that's automated. It's a visualization layer, not new functionality.

**Configuration (Setup UI, no code):**
- Object: `Lien__c`, Picklist field: `Stage__c`
- Steps shown in picklist order (see updated Stage picklist values above)
- Key fields per step are optional; use sparingly (e.g., Recoverable Amount on Coverage Confirmed) — this is a demo prop, not a data entry surface
- Added to the Lien Lightning Record Page above the Highlights Panel

**New picklist values added to `Stage__c` to support this:**
- `Recovery Calculated` — stands in for the Recovery Calculation capability area (reconciling the administrator's figure against the recoverable amount)
- `Collected` — stands in for Collection & Disbursement (remittance reconciliation, payment calculation, disbursement)

**How stages get reached:**
| Stage | How it's reached |
|---|---|
| Intake → Coverage Confirmed / Escalated | Automated — Flow (Component 3) |
| Response Ready → Response Submitted | Manual today; would be automated by the outbound Response file logic in later phases |
| Negotiation → Agreed | Manual only — no negotiation workflow built (explicitly out of scope) |
| Pre-Validation | Not used by current flow; reserved for Phase 2 |
| Recovery Calculated → Collected → Closed | Manual only — Path lets a user click into a later step and advance the record directly; there is no reconciliation, payment calculation, or disbursement logic behind these transitions |

**Demo narration note:** When advancing a record manually through the later steps, say so plainly — the chevron is there to show *where this fits in the full process the platform is designed to run*, not to imply those later stages are already automated. This mirrors the RFP's own scope boundary: Recovery/Damages/Finance logic is intentionally out of the Phase 1 prototype.

---

### 12. Field History Tracking (Audit Trail)

**Purpose:** Backs the demo's own "the system moved it, not a person" narration beat with real data. Without this, that line in the script has nothing to point at.

**Configuration (Setup UI, no code):**
- `Lien__c`: object-level history was already enabled at object creation (`enableHistory = true`). Field-level tracking turned on for `Stage__c`, `Coverage_Result__c`, `Escalation_Reason__c`.
- `Response__c`: object-level history enabled, field-level tracking turned on for `Status__c`.
- `Settlement__c`: intentionally left untracked — static config data, nothing changes visibly during the demo.
- History related list added to the Lien Lightning Record Page (and Response, if time allows).

**Note:** History is not retroactive. This must be configured before the Flow first runs (Wednesday build, Component 3) so the automated Stage transitions — the ones the demo actually narrates — get captured. Any test data created before this was enabled won't show history and should be deleted rather than reused.

---

### 13. Pre-Built Deadline Threshold Record

Create one Lien record manually before the demo with `Response_Deadline__c` set 8 days from demo day. This record will show `Deadline_Status__c = Red` in the list view, demonstrating the deadline monitoring story without needing to run a scheduled Flow live.

**Suggested record values:**
- Claimant Name: `[Pre-existing] Helen Vasquez`
- Stage: `Coverage Confirmed`
- Response Deadline: demo date + 8 days
- Escalation Reason: blank

Narrate this record as: "This lien has been in flight for 82 days. The system flagged it automatically when it crossed the 10-day threshold — the assigned user received a notification and it turned red in the queue. No one had to check a spreadsheet."

---

## Deployment Steps

1. **Create the data model** — all objects and fields in the data model table must exist before deploying code. Create the Response object and its fields first, as the Flow references it.

2. **Create the Escalation Queue**
   - Setup → Queues → New
   - Label: `Lien Escalation Queue`
   - Supported Objects: `Lien__c`, `Task`
   - Add queue members (ops user profiles or individual users)

3. **Upload the Static Resource**
   - Setup → Static Resources → New
   - Name: `SampleClaimants` (case-sensitive)
   - File: `SampleClaimants.csv`
   - Cache control: Public

4. **Build the Flow** in Flow Builder before deploying the Apex and LWC. Test the Flow independently using Flow Builder's debug mode with a manually created Lien record. Confirm that a Confirmed record produces a Coverage Confirmed stage and a Response child record, and that an Unable to Confirm record produces an Escalated stage and a Task.

5. **Start ngrok** to expose the local Python server to Salesforce:
   ```bash
   ngrok http 8765
   ```
   Note the `https://` forwarding URL (e.g. `https://abc123.ngrok.io`). This URL goes into the Named Credential. ngrok must be running whenever you test or demo.

6. **Create the Named Credential** in the scratch org:
   - Setup → Named Credentials → New Legacy Named Credential
   - Label: `LocalSFTPDemo`
   - Name: `LocalSFTPDemo`
   - URL: `https://abc123.ngrok.io` (your ngrok URL — update this each session if ngrok URL changes)
   - Identity Type: Anonymous
   - Authentication Protocol: No Authentication
   - Allow Merge Fields in HTTP Header: checked
   - Allow Merge Fields in HTTP Body: checked
   - Save

7. **Add Remote Site Setting**:
   - Setup → Remote Site Settings → New
   - Name: `LocalSFTPDemo`
   - Remote Site URL: `https://abc123.ngrok.io` (same ngrok URL)
   - Active: checked
   - Save

8. **Deploy Apex and LWC** via SFDX:
   ```bash
   sf project deploy start \
     --source-dir force-app/main/default/classes/ClaimantImportController.cls \
     --source-dir force-app/main/default/classes/ClaimantImportControllerTest.cls \
     --source-dir force-app/main/default/classes/ResponseFileWriter.cls \
     --source-dir force-app/main/default/lwc/claimantImport \
     --source-dir force-app/main/default/lwc/generateResponseFile \
     --target-org <your-org-alias>
   ```

9. **Create both Quick Actions**:
   - Setup → Object Manager → Settlement → Buttons, Links, and Actions → New Action → LWC → `claimantImport` → label "Import Claimants" → Save
   - Repeat → LWC → `generateResponseFile` → label "Generate Response File" → Save

10. **Configure the Settlement Lightning Record Page** in App Builder:
   - Add both Quick Actions (Import Claimants, Generate Response File) to the Highlights Panel
   - Add the Lien related list with Stage and Deadline Status columns visible
   - Save and activate

8. **Create the Escalation Queue list view** on the Lien object

9. **Create the pre-built deadline threshold record** manually

10a. **Add the Path (chevron)** — add `Recovery Calculated` and `Collected` to the `Stage__c` picklist, configure Path Settings on Lien for `Stage__c`, add the Path component to the Lien Lightning Record Page. See Component 11.

11. **Prepare desktop folders:**
   - Create `~/Desktop/sftp-demo/inbound/` and `~/Desktop/sftp-demo/outbound/`
   - Copy `SampleClaimants.csv` into the `inbound/` folder — this sits there before the demo starts
   - Open both folders in Finder/Explorer so they're visible during the demo
   - Start the Python server: `python3 demo/demo_server.py`

12. **End-to-end verify:**
    - Confirm inbound folder contains the CSV, outbound is empty
    - Open a Settlement record with an empty Lien related list
    - Click Import Claimants, run the import
    - Confirm toast fires and Lien list shows Coverage Confirmed and Escalated records
    - Confirm Response child records exist on Coverage Confirmed liens
    - Confirm Tasks assigned to Escalation Queue exist on Escalated liens
    - Click Generate Response File, confirm toast fires
    - Within 5 seconds confirm response CSV appears in the outbound folder
    - Open the response CSV and confirm it contains Coverage Confirmed lien data
    - Confirm pre-built record shows Red deadline status

---

## Acceptance Criteria

### Import — Happy Path
- [ ] The `Import Claimants` action appears in the Settlement action bar
- [ ] Clicking it opens a modal with descriptive text and Run Import / Cancel buttons
- [ ] Clicking Run Import shows a spinner with "Processing claimant file..." label
- [ ] On completion, the modal closes and a sticky toast shows total created, automated count, and escalated count
- [ ] The Settlement record reloads and the Lien related list is visible with Stage column

### Automated Path
- [ ] Each Lien with `Coverage_Result__c = Confirmed` and a `Recoverable_Amount__c` value has `Stage__c = Coverage Confirmed` within two seconds of import completing
- [ ] Each Coverage Confirmed Lien has a child Response record with `Status__c = Draft` and `Claimed_Amount__c` matching the Lien's `Recoverable_Amount__c`
- [ ] No user action was required to produce these records

### Escalation Path
- [ ] Each Lien with `Coverage_Result__c = Unable to Confirm` has `Stage__c = Escalated`
- [ ] Each Escalated Lien has `Escalation_Reason__c` populated with a human-readable message
- [ ] Each Escalated Lien has a child Task assigned to the Lien Escalation Queue with a due date five days from intake
- [ ] Escalated Lien records appear in the Escalation Queue list view

### Deadline Monitoring
- [ ] The pre-built threshold record shows `Deadline_Status__c = Red` in the list view
- [ ] Records with more than 20 days remaining show Green
- [ ] Records with 11–20 days remaining show Yellow

### Cancel
- [ ] Clicking Cancel closes the modal and creates no records

### Error States
- [ ] If the Static Resource is missing, the error toast shows "Sample file not found. Upload SampleClaimants static resource."
- [ ] If Apex throws any other exception, the error toast shows the message and the modal stays open

### Response File Generation
- [ ] The `Generate Response File` action appears in the Settlement action bar alongside Import Claimants
- [ ] Clicking it opens a modal with descriptive text and Generate / Cancel buttons
- [ ] Clicking Generate shows a spinner briefly, then closes with a sticky toast: "Response file initiated — file will appear in the outbound folder in a few seconds."
- [ ] Within 5 seconds of the toast, a timestamped CSV file appears in the local outbound folder
- [ ] The CSV contains one row per Coverage Confirmed lien with Claimant ID, Claimant Name, Health Plan, Recoverable Amount, Stage, and Response Deadline
- [ ] Running the action twice produces two files with different timestamps — no overwrite

### Access Control
- [ ] When logged in as a Health Plan A user, only Health Plan A liens are visible in the related list

### Path (Chevron)
- [ ] Opening any Lien record shows the Path component with all Stage values as steps, in order
- [ ] `Stage__c` includes `Recovery Calculated` and `Collected` before `Closed`
- [ ] A demo record can be manually advanced through Negotiation → Agreed → Recovery Calculated → Collected via the Path UI, with no errors
- [ ] No automation fires as a side effect of advancing through the manual-only stages

### History / Audit Trail
- [ ] The Lien History related list shows an entry when `Stage__c` changes, with old value, new value, changed-by user, and timestamp
- [ ] A Coverage Confirmed lien created via the Flow shows an Intake → Coverage Confirmed history entry with a timestamp seconds after creation
- [ ] The Response History related list shows an entry when `Status__c` changes
- [ ] Settlement does not show a History related list (intentionally not tracked)

---

## Open Questions

| Question | Owner | Blocking? |
|---|---|---|
| What are the actual API names for Lien, Settlement, and Response objects in the demo org? | Brian | Yes — needed before deployment |
| Should Health Plan be a text field or a Lookup to Account? Lookup enables the sharing demo but requires Account records to match CSV values exactly | Brian | Yes — affects data model and CSV |
| Should the Flow run before-save (stage transition only, synchronous) plus after-save (Response creation, async), or entirely after-save? The choice affects how quickly the list view reflects the final state | Brian | Yes — affects Flow build approach |
| What is the Escalation Queue member list for the demo? At minimum one ops user persona needs to be a queue member for the Task assignment story to work | Brian | Yes — needed before Flow deployment |
| Should the deadline monitoring use a scheduled Flow running nightly (production pattern) or a formula field only (demo shortcut)? Formula field is sufficient for the demo and avoids scheduling complexity | Brian | No — formula field recommended for demo |
| Should the 90-day clock start from Intake Date or from a Readiness Date on the Settlement? The RFP implies the clock is program-defined | Confirm with client | No |
| Is ngrok available on the demo machine, or is an alternative needed to expose the local Python server? ngrok free tier is sufficient; confirm it can be installed before build week | Brian | Yes — needed before response file testing |
| Will the demo be delivered on a network that allows outbound HTTPS from Salesforce to the ngrok URL? Corporate or client networks sometimes block this. Test on the actual demo network in advance. | Brian | Yes — test day before |

---

## Demo Script

### Setup (Before the Room Fills)
- Python server running: `python3 demo/demo_server.py`
- ngrok running and Named Credential updated with current ngrok URL
- Two desktop folders open and visible: `inbound/` (containing SampleClaimants.csv), `outbound/` (empty)
- Salesforce Settlement record open in browser, Lien related list visible and empty
- Escalation Queue list view open in a second browser tab
- Pre-built deadline threshold record visible in the list view (already red)
- Confirm end-to-end works with one silent test run before the room fills, then reset data

### Narrative and Sequence

**Open with the desktop (30 seconds)**
Show the two folders before opening Salesforce. "This is what the SFTP exchange looks like in the demo. The administrator has put their claimant file in the inbound folder — 15 claimants, all tied to this settlement. Outbound is empty. That changes by the end of this."

Switch to Salesforce. Move the CSV from Inbound to your desktop or delete it after clicking Import Claimants — a quick manual drag while narrating "file consumed."

**Frame the settlement (1 minute)**
Open the Settlement record. Walk through the program terms — the administrator, the participating health plans, the 90-day response window. "This is the master configuration. Every lien created against this settlement inherits these terms."

**Run the import (1 minute)**
Click Import Claimants. While the modal is open: "In production, the integration layer picks up that inbound file automatically and hands it to Salesforce. We're triggering that handoff manually today."

Click Run Import. Let the toast land without narrating it.

Pause. Let that sit for a moment.

"The coverage result and recoverable amount on these records — in production those fields are populated by automated calls to our Liability and Damages services. The platform calls them, gets the result back, and writes it to the lien. The Flow reacts to those results exactly the way you're about to see. For today we've pre-populated those fields in the import file to simulate what the services would return."

**Show what the system did (2 minutes)**
Scroll to the Lien related list. "The system has already processed these. It didn't wait for us."

Point to the Coverage Confirmed liens. "These twelve had coverage confirmed and a recoverable amount. The platform advanced them automatically and created a response position for each one — ready for review before it goes back to the administrator."

Switch to the Escalation Queue tab. "These three couldn't be resolved automatically. The system didn't drop them — it routed them to the escalation queue, created a task for the ops team, and flagged them for human review."

**Show the automated path in detail (2 minutes)**
Click into a Coverage Confirmed lien. Show the stage, the intake date, the 90-day deadline. Open the Response related record — show the claimed amount, the Draft status. "This response was created by the platform the moment coverage was confirmed. The ops user reviews it and approves it — they don't create it."

Scroll to the History related list. Show the Intake → Coverage Confirmed entry, with the change timestamped seconds after the record was created. "Every change is recorded. Who, what, when. The system moved it, not a person."

**Show the escalation path in detail (1 minute)**
Click into an Escalated lien. Show the escalation reason. Open the related Task — assigned to the queue, due in five days. "The system knew it needed a human and made sure that human has a clear action to take."

**Show the deadline story (1 minute)**
Point to the pre-built red record in the list view. "This lien has been open for 82 days. When it crossed the 10-day threshold the system flagged it automatically. No one had to check a spreadsheet."

**Show the full lifecycle (30 seconds)**
Scroll up to the chevron at the top of the lien. "This is the full path a lien takes — intake, coverage, response, negotiation, recovery calculation, collection. What you've seen so far is intake, coverage, and response running automatically. The stages after that — negotiation, recovery calculation, collection — aren't wired up in this prototype, but the platform already knows they exist and tracks where every lien sits against them." Click a later step to show it advance. "That's not a mockup — it's the same object model. The remaining stages are additional workflow builds on top of what's already here, not a different system."

**Generate the response file (1 minute)**
Back on the Settlement record, click Generate Response File. "The ops team has reviewed the responses. The platform now needs to send its position back to the administrator — in production, that's a file written to the administrator's SFTP server."

Click Generate. Toast fires. Switch to the desktop. Wait the 2–5 seconds in silence — narrate if needed: "Give it a moment..."

The response CSV appears in the outbound folder. Open it briefly. "There it is. The platform's position on every Coverage Confirmed lien — formatted, timestamped, ready for the administrator to pick up."

Point at the two folders — inbound now empty, outbound containing the response file. "File in. Liens processed. File out. That's the pattern."

**Frame what you haven't built (30 seconds)**
"The SFTP polling that would detect the inbound file automatically, the Liability and Damages services that would populate the coverage and amounts, and the payment reconciliation — those are later phases. What we've shown today is that the platform manages the workflow correctly from the moment data arrives, and closes the loop with a response. The exchange pattern your team depends on works."

---

## Future State (Production Architecture)

This Quick Action and demo Flow are simulation only. In production:

1. Integration layer (MuleSoft or AWS Transfer Family + Lambda) polls the settlement administrator's SFTP server on a defined interval
2. Inbound file is validated against the agreed data quality contract at the integration layer — rejected rows returned to the administrator as an error file, not silently skipped
3. Valid records are transformed to Salesforce field format and loaded via **Bulk API 2.0**, supporting 100K+ records asynchronously
4. A **Platform Event** fires on Bulk API job completion, triggering the Lien Workflow Engine
5. The Liability service is called per lien (or per batch) to confirm coverage — result written back to the `Coverage_Result__c` field on the Lien record. **In the demo this field is pre-populated in the import CSV to simulate the service response.**
6. The Damages service is called to calculate the recoverable amount — result written back to the `Recoverable_Amount__c` field. **In the demo this field is also pre-populated in the import CSV.**
7. The record-triggered Flow evaluates the confirmed results and routes accordingly — same logic as the demo Flow, triggered by real service outputs rather than CSV data
8. The Response record, once submitted, triggers an outbound Platform Event that the integration layer picks up and writes as a response file to the administrator's SFTP server

The demo Flow and Apex controller should not be carried forward to production without replacing synchronous DML with Bulk API 2.0, replacing CSV simulation with real service callouts, and adding full error handling, idempotency controls, and job tracking.
