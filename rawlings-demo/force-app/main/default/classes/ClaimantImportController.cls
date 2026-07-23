public with sharing class ClaimantImportController {

    @AuraEnabled
    public static Map<String, Integer> importClaimants(Id settlementId) {
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'SampleClaimants'
            LIMIT 1
        ];
        if (resources.isEmpty()) {
            AuraHandledException ex = new AuraHandledException('Sample file not found. Upload SampleClaimants static resource.');
            ex.setMessage('Sample file not found. Upload SampleClaimants static resource.');
            throw ex;
        }

        List<String> lines = resources[0].Body.toString().split('\n');
        List<List<String>> parsedRows = new List<List<String>>();
        Set<String> healthPlanNames = new Set<String>();

        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i].trim();
            if (String.isBlank(line)) {
                continue;
            }

            List<String> cols = parseCsvRow(line);
            if (cols.size() < 5) {
                continue;
            }

            parsedRows.add(cols);
            if (cols.size() > 2 && String.isNotBlank(cols[2])) {
                healthPlanNames.add(cols[2]);
            }
        }

        Map<String, Id> healthPlanIdByName = new Map<String, Id>();
        for (Account acc : [SELECT Id, Name FROM Account WHERE Name IN :healthPlanNames]) {
            healthPlanIdByName.put(acc.Name, acc.Id);
        }

        List<Lien__c> liensToInsert = new List<Lien__c>();
        for (List<String> cols : parsedRows) {
            Lien__c lien = new Lien__c();
            lien.Settlement__c = settlementId;
            lien.Claimant_Name__c = cols[0];
            lien.Claimant_ID__c = cols[1];
            lien.Health_Plan__c = healthPlanIdByName.get(cols[2]);
            lien.Health_Plan_Text__c = cols[2];
            lien.Injury_Category__c = cols[3];
            lien.Coverage_Result__c = cols[4];
            lien.Recoverable_Amount__c = (cols.size() > 5 && String.isNotBlank(cols[5]))
                ? Decimal.valueOf(cols[5])
                : null;
            lien.Stage__c = 'Intake';
            lien.Intake_Date__c = Date.today();
            lien.Response_Deadline__c = Date.today().addDays(90);
            liensToInsert.add(lien);
        }

        try {
            insert liensToInsert;
        } catch (DmlException e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }

        Map<String, Integer> counts = new Map<String, Integer>{
            'total' => liensToInsert.size(),
            'automated' => 0,
            'escalated' => 0
        };

        for (Lien__c lien : [
            SELECT Stage__c
            FROM Lien__c
            WHERE Id IN :liensToInsert
        ]) {
            if (lien.Stage__c == 'Escalated') {
                counts.put('escalated', counts.get('escalated') + 1);
            } else if (lien.Stage__c == 'Coverage Confirmed') {
                counts.put('automated', counts.get('automated') + 1);
            }
        }

        return counts;
    }

    private static List<String> parseCsvRow(String row) {
        List<String> result = new List<String>();
        Boolean inQuotes = false;
        String current = '';

        for (Integer i = 0; i < row.length(); i++) {
            String ch = row.substring(i, i + 1);
            if (ch == '"') {
                inQuotes = !inQuotes;
            } else if (ch == ',' && !inQuotes) {
                result.add(current);
                current = '';
            } else {
                current += ch;
            }
        }
        result.add(current);
        return result;
    }
}
