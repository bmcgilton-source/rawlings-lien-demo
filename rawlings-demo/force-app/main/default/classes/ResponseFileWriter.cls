public with sharing class ResponseFileWriter {

    @AuraEnabled
    public static void generateResponseFile(Id settlementId) {
        if (settlementId == null) {
            AuraHandledException ex = new AuraHandledException('No settlement specified.');
            ex.setMessage('No settlement specified.');
            throw ex;
        }
        writeFileAsync(String.valueOf(settlementId));
    }

    // @Future(callout=true) is used for demo simplicity so the LWC gets an
    // immediate success response while the callout completes in the background.
    // Production would replace this with a Platform Event or Queueable job with
    // proper error handling, retry logic, and job tracking.
    @Future(callout=true)
    private static void writeFileAsync(String settlementId) {
        List<Lien__c> liens = [
            SELECT Claimant_ID__c, Claimant_Name__c, Health_Plan__r.Name,
                   Recoverable_Amount__c, Stage__c, Response_Deadline__c
            FROM Lien__c
            WHERE Settlement__c = :settlementId
            AND Stage__c = 'Coverage Confirmed'
        ];

        if (liens.isEmpty()) {
            return;
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

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:LocalSFTPDemo');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/csv');
        req.setHeader('X-Filename', filename);
        req.setBody(csv);

        HttpResponse res = new Http().send(req);
        System.debug('ResponseFileWriter callout status: ' + res.getStatusCode());
    }
}
