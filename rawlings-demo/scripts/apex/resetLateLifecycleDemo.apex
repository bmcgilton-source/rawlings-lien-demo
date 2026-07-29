Lien__c lien = [
    SELECT Id
    FROM Lien__c
    WHERE Claimant_ID__c = 'CLM-PRE-002'
    LIMIT 1
];

lien.Stage__c = 'Coverage Confirmed';
lien.Administrator_Position__c = null;
lien.Agreed_Amount__c = null;
lien.Negotiation_Reason__c = null;
lien.Recovery_Amount__c = null;
lien.Remittance_Amount__c = null;
lien.Health_Plan_Allocation__c = null;
lien.Rawlings_Allocation__c = null;
lien.Disbursement_Status__c = null;
update lien;

delete [
    SELECT Id
    FROM Task
    WHERE WhatId = :lien.Id
    AND Subject = 'Review: Payment variance'
];

System.debug('Reset complete for ' + lien.Id);
