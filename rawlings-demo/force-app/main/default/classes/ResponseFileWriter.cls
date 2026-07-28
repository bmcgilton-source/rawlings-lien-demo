public with sharing class ResponseFileWriter {

    public class GenerateResult {
        @AuraEnabled public String filename;
        @AuraEnabled public List<ResponseRow> rows;
    }

    public class ResponseRow {
        @AuraEnabled public String claimantId;
        @AuraEnabled public String claimantName;
        @AuraEnabled public String healthPlan;
        @AuraEnabled public Decimal recoverableAmount;
        @AuraEnabled public Date responseDeadline;
    }

    @AuraEnabled
    public static GenerateResult generateResponseFile(Id settlementId) {
        if (settlementId == null) {
            AuraHandledException ex = new AuraHandledException('No settlement specified.');
            ex.setMessage('No settlement specified.');
            throw ex;
        }

        List<Lien__c> liens = [
            SELECT Claimant_ID__c, Claimant_Name__c, Health_Plan__r.Name,
                   Recoverable_Amount__c, Stage__c, Response_Deadline__c
            FROM Lien__c
            WHERE Settlement__c = :settlementId
            AND Stage__c = 'Coverage Confirmed'
        ];

        if (liens.isEmpty()) {
            AuraHandledException ex = new AuraHandledException('No Coverage Confirmed liens found for this settlement.');
            ex.setMessage('No Coverage Confirmed liens found for this settlement.');
            throw ex;
        }

        String csv = 'Claimant_ID,Claimant_Name,Health_Plan,Recoverable_Amount,Stage,Response_Deadline\n';
        for (Lien__c lien : liens) {
            csv += String.join(new List<String>{
                lien.Claimant_ID__c,
                lien.Claimant_Name__c,
                lien.Health_Plan__r?.Name,
                lien.Recoverable_Amount__c == null ? '' : String.valueOf(lien.Recoverable_Amount__c),
                lien.Stage__c,
                lien.Response_Deadline__c == null ? '' : String.valueOf(lien.Response_Deadline__c)
            }, ',') + '\n';
        }

        String filename = 'response_' + Datetime.now().format('yyyyMMdd_HHmmss') + '.csv';

        ContentVersion cv = new ContentVersion();
        cv.Title = filename;
        cv.PathOnClient = filename;
        cv.VersionData = Blob.valueOf(csv);
        insert cv;

        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        ContentDocumentLink link = new ContentDocumentLink();
        link.ContentDocumentId = contentDocumentId;
        link.LinkedEntityId = settlementId;
        link.ShareType = 'V';
        link.Visibility = 'AllUsers';
        insert link;

        Set<Id> lienIds = new Map<Id, Lien__c>(liens).keySet();

        for (Lien__c lien : liens) {
            lien.Stage__c = 'Response Submitted';
        }
        update liens;

        List<Response__c> responses = [
            SELECT Status__c, Sent_Date__c
            FROM Response__c
            WHERE Lien__c IN :lienIds
        ];
        for (Response__c response : responses) {
            response.Status__c = 'Sent';
            response.Sent_Date__c = Date.today();
        }
        update responses;

        GenerateResult result = new GenerateResult();
        result.filename = filename;
        result.rows = new List<ResponseRow>();
        for (Lien__c lien : liens) {
            ResponseRow row = new ResponseRow();
            row.claimantId = lien.Claimant_ID__c;
            row.claimantName = lien.Claimant_Name__c;
            row.healthPlan = lien.Health_Plan__r?.Name;
            row.recoverableAmount = lien.Recoverable_Amount__c;
            row.responseDeadline = lien.Response_Deadline__c;
            result.rows.add(row);
        }

        return result;
    }
}
