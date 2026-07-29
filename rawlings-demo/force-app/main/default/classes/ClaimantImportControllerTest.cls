// SeeAllData=true is required here: the controller queries a real Static Resource
// ('SampleClaimants', Task T.4) by hardcoded name, and Apex does not allow DML on
// StaticResource, so a test can't fabricate its own copy. Without SeeAllData=true,
// the query would come back empty in test context even though the resource is
// actually deployed. This is why @testSetup can't be used here either — Salesforce
// does not allow combining @testSetup with @isTest(SeeAllData=true) in the same class,
// so Account/Settlement fixture data is created inline in each test method instead.
@isTest(SeeAllData=true)
private class ClaimantImportControllerTest {

    private static Settlement__c createSettlement() {
        List<Account> plans = new List<Account>{
            new Account(Name = 'Health Plan A'),
            new Account(Name = 'Health Plan B'),
            new Account(Name = 'Health Plan C')
        };
        insert plans;
        Settlement__c settlement = new Settlement__c(Name = 'Test Settlement');
        insert settlement;
        List<Settlement_Health_Plan__c> junctions = new List<Settlement_Health_Plan__c>();
        for (Account plan : plans) {
            junctions.add(new Settlement_Health_Plan__c(Settlement__c = settlement.Id, Health_Plan__c = plan.Id));
        }
        insert junctions;
        return settlement;
    }

    @isTest
    static void testImportClaimants_positive() {
        Settlement__c settlement = createSettlement();

        Test.startTest();
        ClaimantImportResult result = ClaimantImportController.importClaimants(settlement.Id);
        Test.stopTest();

        List<Lien__c> liens = [SELECT Id FROM Lien__c WHERE Settlement__c = :settlement.Id];
        System.assert(liens.size() > 0, 'Expected at least one lien created from the sample CSV');
        System.assertEquals(result.createdCount, liens.size(), 'Returned created count should match liens actually created');
        System.assertEquals(0, result.rejectedCount, 'The sample CSV should validate cleanly once its Health Plans participate in the settlement');
    }

    @isTest
    static void testImportClaimants_missingSettlement() {
        Boolean exceptionThrown = false;
        try {
            ClaimantImportController.importClaimants(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assert(
            exceptionThrown,
            'Expected an exception when no settlement is provided (Settlement__c is a required field on Lien__c)'
        );
    }

    // NOTE: This test depends on the record-triggered Flow ("Lien Automation on Create")
    // built in Task W.2. It will fail if run before the Flow is built and activated —
    // that is expected on Tuesday (Task T.2) and not a sign of a broken controller.
    // Re-run this test after Wednesday's Flow work to confirm it passes.
    @isTest
    static void testImportClaimants_escalationPath() {
        Settlement__c settlement = createSettlement();

        Test.startTest();
        ClaimantImportController.importClaimants(settlement.Id);
        Test.stopTest();

        List<Lien__c> escalated = [
            SELECT Stage__c, Escalation_Reason__c
            FROM Lien__c
            WHERE Settlement__c = :settlement.Id
            AND Coverage_Result__c = 'Unable to Confirm'
            LIMIT 1
        ];

        System.assert(!escalated.isEmpty(), 'Expected at least one Unable to Confirm lien from the sample CSV');
        System.assertEquals(
            'Escalated',
            escalated[0].Stage__c,
            'Unable to Confirm liens should be routed to Escalated by the Flow'
        );
        System.assertNotEquals(null, escalated[0].Escalation_Reason__c, 'Escalation reason should be populated');
    }
}
