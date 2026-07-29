// Full reset + reseed for Settlement A ("Hip Implant Mass Tort 2024", a02dL00000opHs8QAE),
// the live-import settlement used for Act 1. Deletes everything currently on the settlement,
// then recreates the one pre-existing record the combined demo import (ClaimantImportDemo.csv,
// Beat 2, claimant-intake-validation-spec.md) needs to already exist so its "update" row
// (CLM-PRE-003) has something to update instead of creating a duplicate — same precedent as
// resetSettlementB.apex's CLM-PRE-002 (Angela Whitfield) reseed.
//
// Run via: sf apex run --file scripts/apex/resetSettlementA.apex --target-org rawlings-demo
//
// Prerequisite: Health Plan A/B/C Accounts must already exist (created by any prior import).
// If they don't exist yet, this script stops before deleting anything.

Id settlementId = 'a02dL00000opHs8QAE'; // Hip Implant Mass Tort 2024

Account healthPlanA = null;
for (Account acct : [SELECT Id, Name FROM Account WHERE Name = 'Health Plan A' LIMIT 1]) {
    healthPlanA = acct;
}
if (healthPlanA == null) {
    System.debug('Health Plan A Account not found. Run an import at least once first so it exists. Nothing deleted.');
    return;
}

// --- 1. Delete everything currently on Settlement A ---

List<Lien__c> liens = [
    SELECT Id
    FROM Lien__c
    WHERE Settlement__c = :settlementId
];

Set<Id> lienIds = new Map<Id, Lien__c>(liens).keySet();

// Files (rejection/response CSVs attached to the Settlement, Finance Instruction CSVs
// attached to its Liens) aren't cascade-deleted with their parent records, so each demo
// run leaves ContentDocuments behind unless they're explicitly cleaned up here.
Set<Id> contentDocumentIds = new Set<Id>();
for (ContentDocumentLink cdl : [
    SELECT ContentDocumentId
    FROM ContentDocumentLink
    WHERE LinkedEntityId = :settlementId
    OR LinkedEntityId IN :lienIds
]) {
    contentDocumentIds.add(cdl.ContentDocumentId);
}
if (!contentDocumentIds.isEmpty()) {
    delete [SELECT Id FROM ContentDocument WHERE Id IN :contentDocumentIds];
}
System.debug('Deleted ' + contentDocumentIds.size() + ' Files (rejection/response/finance-instruction CSVs) from Settlement A and its Liens.');

if (!lienIds.isEmpty()) {
    delete [
        SELECT Id
        FROM Task
        WHERE WhatId IN :lienIds
    ];

    delete liens; // cascades delete of child Response__c records (Master-Detail)
}

System.debug('Deleted ' + liens.size() + ' liens (and their Response/Task children) from Settlement A.');

// --- 2. Recreate the pre-existing record the combined demo file's update row targets ---
// Inserting at Stage__c = 'Coverage Confirmed' directly (not Intake) fires the routing Flow
// and creates the Draft Response automatically, same pattern as resetSettlementB.apex.

Lien__c preExisting = new Lien__c();
preExisting.Settlement__c = settlementId;
preExisting.Claimant_ID__c = 'CLM-PRE-003';
preExisting.Claimant_Name__c = '[Pre-existing] Priya Anand';
preExisting.Health_Plan__c = healthPlanA.Id;
preExisting.Health_Plan_Text__c = 'Health Plan A';
preExisting.Injury_Category__c = 'Hip Implant';
preExisting.Coverage_Result__c = 'Confirmed';
preExisting.Stage__c = 'Coverage Confirmed';
preExisting.Recoverable_Amount__c = 4800;
preExisting.Intake_Date__c = Date.today().addDays(-14);
preExisting.Response_Deadline__c = Date.today().addDays(76);
insert preExisting;

System.debug('Reset complete. Settlement A now has exactly 1 pre-existing lien (CLM-PRE-003, Priya Anand): ' + preExisting.Id);
