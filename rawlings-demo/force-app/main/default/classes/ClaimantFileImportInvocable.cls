public with sharing class ClaimantFileImportInvocable {

    public class Request {
        @InvocableVariable(required=true)
        public Id settlementId;
        @InvocableVariable(required=true)
        public Id contentDocumentId;
    }

    public class Response {
        @InvocableVariable
        public Integer rowsReceived;
        @InvocableVariable
        public Integer createdCount;
        @InvocableVariable
        public Integer updatedCount;
        @InvocableVariable
        public Integer rejectedCount;
        @InvocableVariable
        public Integer automatedCount;
        @InvocableVariable
        public Integer escalatedCount;
        @InvocableVariable
        public String rejectionFilename;
    }

    @InvocableMethod(label='Import Claimant File' description='Validates and imports an uploaded claimant CSV file, creating or updating Liens and producing a rejection file when data-quality issues are found.')
    public static List<Response> importFile(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            ContentVersion cv = [
                SELECT VersionData
                FROM ContentVersion
                WHERE ContentDocumentId = :req.contentDocumentId
                AND IsLatest = true
                LIMIT 1
            ];

            ClaimantImportResult result = ClaimantImportService.importFromCsv(req.settlementId, cv.VersionData);

            Response res = new Response();
            res.rowsReceived = result.rowsReceived;
            res.createdCount = result.createdCount;
            res.updatedCount = result.updatedCount;
            res.rejectedCount = result.rejectedCount;
            res.automatedCount = result.automatedCount;
            res.escalatedCount = result.escalatedCount;
            res.rejectionFilename = result.rejectionFilename;
            responses.add(res);
        }

        return responses;
    }
}
