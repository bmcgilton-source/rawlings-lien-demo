# Flow Build Instructions — Lien Automation on Create

Reference for Task W.2 in the build schedule. Read this fully before opening Flow Builder.
Corresponds to spec section "3. Record-Triggered Flow — `Lien Automation on Create`".

Do not skip ahead — build in the order below and save after each major element.

---

## 0. Prerequisites

Before starting, confirm these exist (all from Tuesday):
- `Lien__c`, `Response__c`, `Settlement__c` objects with all fields deployed
- `Lien Escalation Queue` queue created (Setup → Queues), with its Queue ID copied
  (Setup → Queues → click the queue → copy the `00G...` ID from the browser URL)
- At least one test Settlement record to run the import against

---

## 1. Create the Flow

1. Setup → Quick Find → **Flows** → **New Flow**
2. Choose **Record-Triggered Flow** → Next
3. Object: `Lien`
4. Trigger the Flow when: **A record is created**
5. Set Entry Conditions: **None** (evaluate on every create)
6. Optimize the Flow for: **Actions and Related Records** (this is the after-save option)
7. Click **Done**

---

## 2. Decision Element — the routing branch

A Decision element has two parts: the **outcome(s) you define** (each with its own conditions), and an implicit **Default Outcome** — a fallback path that fires whenever none of your defined outcomes match. The Default Outcome never takes conditions of its own, but its label is editable, and we want it renamed too so both branches read clearly later in the canvas.

1. Click the **+** node right after the Start element
2. Search for and select **Decision**
3. Label: `Coverage Confirmed?` (API name auto-fills)
4. In the **Outcome Details** panel for the first (only) outcome, rename it to `Automated Path`
5. Set its condition requirements to **All Conditions Are Met (AND)**
6. Add condition 1: `{!$Record.Coverage_Result__c}` **Equals** `Confirmed`
7. Add condition 2: `{!$Record.Recoverable_Amount__c}` **Greater Than** `0`
8. Click the **Default Outcome** tab/section of the same Decision element and rename its label to `Escalation Path`. Don't add conditions to it — it's the catch-all for anything that doesn't match the Automated Path conditions above (e.g. `Unable to Confirm`, or a missing amount).
9. Save the Flow: name it `Lien Automation on Create` when prompted.

---

## 3. Automated Path (top branch: Coverage Confirmed)

### 3a. Update the Lien stage
1. On the `Automated Path` branch, click **+** → **Update Records**
2. Label: `Update Stage to Coverage Confirmed`
3. How to Find Records to Update: **Use the record that triggered the flow**
4. Set Field Values:
   - `Stage__c` = `Coverage Confirmed` (use the picklist value picker, not free text)

### 3b. Create the Response record
1. Click **+** immediately after the Update Records element (same branch) → **Create Records**
2. Label: `Create Response Record`
3. How Many Records to Create: **One**
4. Object: `Response`
5. Set Field Values:
   - `Lien__c` = `{!$Record.Id}`
   - `Claimed_Amount__c` = `{!$Record.Recoverable_Amount__c}`
   - `Status__c` = `Draft`
   - `Response_Date__c` = `{!$Flow.CurrentDate}`

Save.

---

## 4. Escalation Path (bottom branch: default outcome)

### 4a. Update the Lien stage and reason
1. On the default/escalation branch, click **+** → **Update Records**
2. Label: `Update Stage to Escalated`
3. How to Find Records to Update: **Use the record that triggered the flow**
4. Set Field Values:
   - `Stage__c` = `Escalated`
   - `Escalation_Reason__c` = `Coverage could not be confirmed automatically`

### 4b. Create the escalation Task
1. Click **+** after the Update Records element (same branch) → **Create Records**
2. Label: `Create Escalation Task`
3. How Many Records to Create: **One**
4. Object: `Task`
5. Set Field Values (the UI shows these by their labels, not API names):
   - `Subject` = `Review: Coverage confirmation required`
   - `Related To ID` (this is `WhatId`) = `{!$Record.Id}` — pick it via the field picker: "Triggering Lien__c > Record ID"
   - `Assigned To ID` (this is `OwnerId`) = the Lien Escalation Queue ID (paste the `00G...` ID you copied in step 0 — **type/paste it directly into the field**, do not use the field picker for this one)
   - `Due Date` (this is `ActivityDate`) = create the Formula resource first (see 4c below), then reference it here
   - `Description` = just type this directly into the Value box as literal text, curly braces included — Flow Builder resolves the merge field inline, no separate resource needed:
     `Lien routed to escalation. Coverage result: {!$Record.Coverage_Result__c}`

### 4c. Formula resource for the Task due date
Flow doesn't do date arithmetic inline in a field-value box by default — create a resource first:
1. Left rail → **Manager** tab → **New Resource**
2. Resource Type: **Formula**
3. API Name: `TaskDueDate`
4. Data Type: **Date**
5. Formula: `{!$Flow.CurrentDate} + 5`
6. Save, then go back to the Create Records (Task) element and set `ActivityDate` = `{!TaskDueDate}`

Save.

---

## 5. Save and Activate

1. Flow Label: `Lien Automation on Create`
2. Save (Ctrl+S or the Save button) — **Flow Builder does not auto-save**, save after every element you're confident in
3. Click **Activate** in the top right
4. Confirm the Flows list shows Status = **Active**

---

## 6. Test with Debug Mode (before running the full import)

1. In Flow Builder, click **Debug**
2. Since this is a record-triggered flow, Debug will ask you to either use an existing record or simulate values
3. Run twice:
   - Once simulating `Coverage_Result__c = Confirmed`, `Recoverable_Amount__c = 5000` → confirm the debug trace shows the Automated Path firing, Stage becomes `Coverage Confirmed`, and a Response record path is taken
   - Once simulating `Coverage_Result__c = Unable to Confirm`, `Recoverable_Amount__c` blank → confirm the Escalation Path fires, Stage becomes `Escalated`, Task creation path is taken

If either path doesn't fire as expected, check the Decision element's condition logic before touching anything else — this is almost always where routing bugs live.

---

## 7. Full test via Import Claimants (Task W.3)

Once Debug looks right, run the actual `Import Claimants` quick action against a real Settlement record and verify:
- Coverage Confirmed liens exist with a child Response record (Draft status, correct Claimed_Amount__c)
- Escalated liens exist with Escalation_Reason__c populated and a Task assigned to the Lien Escalation Queue, due 5 days out

Delete test records afterward per the schedule.
