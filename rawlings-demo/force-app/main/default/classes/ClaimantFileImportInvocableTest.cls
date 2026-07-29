@isTest
private class ClaimantFileImportInvocableTest {

    private static final String HEADER = 'Claimant_Name,Claimant_ID,Health_Plan,Injury_Category,Coverage_Result,Recoverable_Amount\n';

    private static Settlement__c createSettlementWithPlanA() {
        Settlement__c settlement = new Settlement__c(Name = 'Test Settlement');
        insert settlement;
        Account planA = new Account(Name = 'Health Plan A');
        insert planA;
        insert new Settlement_Health_Plan__c(Settlement__c = settlement.Id, Health_Plan__c = planA.Id);
        return settlement;
    }

    private static Id createContentVersionAndGetDocumentId(String csv) {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Test Claimant File';
        cv.PathOnClient = 'test.csv';
        cv.VersionData = Blob.valueOf(csv);
        insert cv;

        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        return cv.ContentDocumentId;
    }

    @isTest
    static void testImportFile_positive() {
        Settlement__c settlement = createSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant One,TST-101,Health Plan A,Hip Implant,Confirmed,5000\n';
        Id contentDocumentId = createContentVersionAndGetDocumentId(csv);

        ClaimantFileImportInvocable.Request req = new ClaimantFileImportInvocable.Request();
        req.settlementId = settlement.Id;
        req.contentDocumentId = contentDocumentId;

        Test.startTest();
        List<ClaimantFileImportInvocable.Response> responses = ClaimantFileImportInvocable.importFile(
            new List<ClaimantFileImportInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Expected one response for one request');
        System.assertEquals(1, responses[0].createdCount, 'Expected one lien created from the uploaded file');

        List<Lien__c> liens = [SELECT Id FROM Lien__c WHERE Settlement__c = :settlement.Id];
        System.assertEquals(1, liens.size(), 'Expected the lien to actually exist on the settlement');
    }

    @isTest
    static void testImportFile_returnsAllResultFields() {
        Settlement__c settlement = createSettlementWithPlanA();
        String csv = HEADER
            + 'Created Claimant,TST-102,Health Plan A,Hip Implant,Confirmed,5000\n'
            + 'Escalated Claimant,TST-103,Health Plan A,Hip Implant,Unable to Confirm,\n'
            + 'Rejected Claimant,,Health Plan A,Hip Implant,Confirmed,5000\n';
        Id contentDocumentId = createContentVersionAndGetDocumentId(csv);

        ClaimantFileImportInvocable.Request req = new ClaimantFileImportInvocable.Request();
        req.settlementId = settlement.Id;
        req.contentDocumentId = contentDocumentId;

        Test.startTest();
        List<ClaimantFileImportInvocable.Response> responses = ClaimantFileImportInvocable.importFile(
            new List<ClaimantFileImportInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Expected one response for one request');
        ClaimantFileImportInvocable.Response res = responses[0];
        System.assertEquals(3, res.rowsReceived);
        System.assertEquals(2, res.createdCount);
        System.assertEquals(0, res.updatedCount);
        System.assertEquals(1, res.rejectedCount);
        System.assertEquals(1, res.automatedCount);
        System.assertEquals(1, res.escalatedCount);
        System.assertNotEquals(null, res.rejectionFilename, 'Rejection filename should be populated when rows are rejected');

        List<Lien__c> liens = [SELECT Id FROM Lien__c WHERE Settlement__c = :settlement.Id];
        System.assertEquals(2, liens.size(), 'Expected two liens created from the uploaded file');
    }
}
