// Full reset + reseed for Settlement B ("Talc Powder Mass Tort 2023", a02dL00000p27A8QAI),
// the volume settlement used for Act 2. Unlike Settlement A, this settlement's liens are never
// imported live from a file — they're script-generated — so a delete alone would leave it empty.
// This script deletes everything currently on the settlement, then recreates both pieces:
//   1. ~1,000 synthetic liens (same generation logic as seedVolumeLiens.apex)
//   2. The hand-built late-lifecycle demo lien (CLM-PRE-002, Angela Whitfield) that
//      resetLateLifecycleDemo.apex depends on (today-build-plan.md, Tier 2 stretch section)
//
// Run via: sf apex run --file scripts/apex/resetSettlementB.apex --target-org rawlings-demo
//
// Prerequisite: Health Plan A/B/C Accounts must already exist (created by Import Claimants
// running at least once on Settlement A). If they don't exist yet, this script stops before
// deleting anything.

Id settlementId = 'a02dL00000p27A8QAI'; // Talc Powder Mass Tort 2023

List<Account> healthPlans = [
    SELECT Id, Name FROM Account WHERE Name IN ('Health Plan A', 'Health Plan B', 'Health Plan C')
];
if (healthPlans.size() < 3) {
    System.debug(
        'Expected 3 Health Plan Accounts (Health Plan A/B/C) — found ' + healthPlans.size() +
        '. Run Import Claimants at least once first so these Accounts exist. Nothing deleted.'
    );
    return;
}
Map<String, Id> healthPlanIdByName = new Map<String, Id>();
for (Account acct : healthPlans) {
    healthPlanIdByName.put(acct.Name, acct.Id);
}

// --- 1. Delete everything currently on Settlement B ---

List<Lien__c> existingLiens = [SELECT Id FROM Lien__c WHERE Settlement__c = :settlementId];
Set<Id> existingLienIds = new Map<Id, Lien__c>(existingLiens).keySet();

// Files (rejection/response CSVs attached to the Settlement, Finance Instruction CSVs
// attached to its Liens) aren't cascade-deleted with their parent records, so each demo
// run leaves ContentDocuments behind unless they're explicitly cleaned up here.
Set<Id> contentDocumentIds = new Set<Id>();
for (ContentDocumentLink cdl : [
    SELECT ContentDocumentId
    FROM ContentDocumentLink
    WHERE LinkedEntityId = :settlementId
    OR LinkedEntityId IN :existingLienIds
]) {
    contentDocumentIds.add(cdl.ContentDocumentId);
}
if (!contentDocumentIds.isEmpty()) {
    delete [SELECT Id FROM ContentDocument WHERE Id IN :contentDocumentIds];
}
System.debug('Deleted ' + contentDocumentIds.size() + ' Files (rejection/response/finance-instruction CSVs) from Settlement B and its Liens.');

if (!existingLienIds.isEmpty()) {
    delete [SELECT Id FROM Task WHERE WhatId IN :existingLienIds];
    delete existingLiens; // cascades delete of child Response__c records (Master-Detail)
}
System.debug('Deleted ' + existingLiens.size() + ' existing liens (and their Response child records) from Settlement B.');

// --- 2. Reseed ~1,000 synthetic liens (mirrors seedVolumeLiens.apex) ---

// Escalated is never a target — every seeded row must insert as Confirmed with a positive
// Recoverable_Amount__c or the on-create Flow forces it to Escalated (architecture.md §4.6).
// Pre-Validation is deliberately excluded from redistribution — it isn't part of
// BulkStageTransitionController's transition map either, so no other mechanism in this build
// ever moves a lien through it.
List<String> redistributionStages = new List<String>{
    'Response Ready', 'Response Submitted', 'Negotiation',
    'Agreed', 'Recovery Calculated', 'Collected', 'Closed'
};
List<String> injuryCategories = new List<String>{ 'Hip Implant', 'Hernia Mesh' };

Integer totalCount = 1000;
Integer redistributeCount = 150; // last 150 of the 1000 move off Coverage Confirmed post-insert

List<Lien__c> toInsert = new List<Lien__c>();
List<String> plannedStage = new List<String>(); // parallel to toInsert; 'Coverage Confirmed' or a redistribution target

for (Integer i = 0; i < totalCount; i++) {
    Lien__c lien = new Lien__c();
    lien.Settlement__c = settlementId;
    lien.Claimant_ID__c = 'SYN-' + String.valueOf(i + 1).leftPad(5, '0');
    lien.Claimant_Name__c = 'Synthetic Claimant ' + String.valueOf(i + 1).leftPad(5, '0');

    Account plan = healthPlans[Math.mod(i, healthPlans.size())];
    lien.Health_Plan__c = plan.Id;
    lien.Health_Plan_Text__c = plan.Name;
    lien.Injury_Category__c = injuryCategories[Math.mod(i, injuryCategories.size())];

    lien.Coverage_Result__c = 'Confirmed';
    lien.Recoverable_Amount__c = 1500 + Math.mod(i * 37, 8500);

    // All rows insert at Intake so the on-create Flow evaluates them; rows past index 849
    // get moved to a downstream stage by the separate post-insert update below.
    lien.Stage__c = 'Intake';

    Boolean isRedistributed = i >= (totalCount - redistributeCount);
    if (isRedistributed) {
        Integer stageIndex = Math.mod(i, redistributionStages.size());
        String targetStage = redistributionStages[stageIndex];
        plannedStage.add(targetStage);
        // Older intake dates the further along the pipeline, so downstream liens read as
        // having been in-flight longer rather than all landing on the same day.
        Integer depth = stageIndex + 1;
        lien.Intake_Date__c = Date.today().addDays(-(40 * depth + Math.mod(i, 20)));
    } else {
        plannedStage.add('Coverage Confirmed');
        lien.Intake_Date__c = Date.today().addDays(-(10 + Math.mod(i, 60)));
    }

    // Rows 0-9 land Red (6-10 days out, never past due) and rows 10-109 land Yellow (11-20
    // days out) — never overlapping the redistribution range above, which starts at 850 — so
    // Beat 9 of demo-script.md has a sizable Yellow population (~100) with a small Red group
    // on top and Angela Whitfield's 5-day deadline still the most urgent. Everything else
    // lands comfortably Green (25-90 days out).
    Integer redCount = 10;
    Integer yellowCount = 100;
    Integer nearDeadlineCount = redCount + yellowCount;
    if (i < redCount) {
        lien.Response_Deadline__c = Date.today().addDays(6 + Math.mod(i, 5));
    } else if (i < nearDeadlineCount) {
        lien.Response_Deadline__c = Date.today().addDays(11 + Math.mod(i, 10));
    } else {
        lien.Response_Deadline__c = Date.today().addDays(25 + Math.mod(i * 29, 66));
    }

    toInsert.add(lien);
}

insert toInsert;
System.debug('Inserted ' + toInsert.size() + ' synthetic Liens.');

List<Lien__c> toRedistribute = new List<Lien__c>();
for (Integer i = 0; i < toInsert.size(); i++) {
    if (plannedStage[i] != 'Coverage Confirmed') {
        toRedistribute.add(new Lien__c(Id = toInsert[i].Id, Stage__c = plannedStage[i]));
    }
}
update toRedistribute;
System.debug('Redistributed ' + toRedistribute.size() + ' Liens across downstream stages.');

// --- 3. Recreate the hand-built late-lifecycle demo lien ---
// Same fields as originally built (today-build-plan.md Tier 2, 2:15-2:35 section). Inserting at
// Stage__c = 'Coverage Confirmed' directly (not Intake) fires the routing Flow and creates the
// Draft Response (Claimed_Amount__c = 18500) automatically, same as the first time this was built.

Lien__c lateLifecycleLien = new Lien__c();
lateLifecycleLien.Settlement__c = settlementId;
lateLifecycleLien.Claimant_ID__c = 'CLM-PRE-002';
lateLifecycleLien.Claimant_Name__c = 'Angela Whitfield';
lateLifecycleLien.Health_Plan__c = healthPlanIdByName.get('Health Plan A');
lateLifecycleLien.Health_Plan_Text__c = 'Health Plan A';
lateLifecycleLien.Coverage_Result__c = 'Confirmed';
lateLifecycleLien.Stage__c = 'Coverage Confirmed';
lateLifecycleLien.Recoverable_Amount__c = 18500;
// Explicit near-term deadline so this record reads as urgent (Red) and sorts to the top
// of the "Liens Near Deadline" list view for Beat 9 of demo-script.md — without this, the
// on-create Flow leaves Response_Deadline__c null and the record won't appear as "soonest."
lateLifecycleLien.Intake_Date__c = Date.today().addDays(-85);
lateLifecycleLien.Response_Deadline__c = Date.today().addDays(5);
insert lateLifecycleLien;
System.debug('Recreated late-lifecycle demo lien CLM-PRE-002 (Angela Whitfield): ' + lateLifecycleLien.Id);

Map<String, Integer> finalCounts = new Map<String, Integer>();
for (AggregateResult ar : [
    SELECT Stage__c stage, COUNT(Id) cnt
    FROM Lien__c
    WHERE Settlement__c = :settlementId
    GROUP BY Stage__c
]) {
    finalCounts.put((String) ar.get('stage'), (Integer) ar.get('cnt'));
}
System.debug('Final stage distribution for Settlement B: ' + finalCounts);
