public with sharing class ClaimantImportService {

    public class ClaimantFileException extends Exception {}

    private class RowContext {
        Integer rowNumber;
        String originalLine;
        List<String> cols;
        String claimantName;
        String claimantId;
        String claimantIdUpper;
        Id healthPlanAccountId;
        String healthPlanText;
        String injuryCategory;
        String coverageResult;
        Decimal recoverableAmount;
        Id existingLienId;
    }

    private static final List<String> EXPECTED_HEADER = new List<String>{
        'Claimant_Name', 'Claimant_ID', 'Health_Plan', 'Injury_Category', 'Coverage_Result', 'Recoverable_Amount'
    };
    private static final List<String> ALLOWED_COVERAGE_RESULTS = new List<String>{ 'Confirmed', 'Unable to Confirm' };
    private static final Integer MAX_FILE_SIZE_BYTES = 1024 * 1024;
    private static final Integer MAX_ROW_COUNT = 2000;

    private static final String MSG_EMPTY_FILE = 'The uploaded claimant file is empty.';
    private static final String MSG_HEADER_MISMATCH = 'The claimant file columns do not match the expected data contract.';
    private static final String MSG_NO_DATA_ROWS = 'The claimant file contains no claimant rows.';
    private static final String MSG_FILE_TOO_LARGE = 'The claimant file exceeds the demo size limit.';
    private static final String MSG_TOO_MANY_ROWS = 'The claimant file exceeds the demo row limit.';

    public static ClaimantImportResult importFromCsv(Id settlementId, Blob csvBody) {
        validateSettlementAccess(settlementId);

        if (csvBody == null || csvBody.size() == 0) {
            throw new ClaimantFileException(MSG_EMPTY_FILE);
        }
        if (csvBody.size() > MAX_FILE_SIZE_BYTES) {
            throw new ClaimantFileException(MSG_FILE_TOO_LARGE);
        }

        String raw = csvBody.toString();
        if (raw.startsWith('﻿')) {
            raw = raw.substring(1);
        }
        raw = raw.replace('\r\n', '\n').replace('\r', '\n');

        if (String.isBlank(raw)) {
            throw new ClaimantFileException(MSG_EMPTY_FILE);
        }

        List<String> lines = raw.split('\n', -1);
        List<String> headerCols = parseCsvRow(lines[0].trim());
        for (Integer h = 0; h < headerCols.size(); h++) {
            headerCols[h] = headerCols[h].trim();
        }
        if (!headerCols.equals(EXPECTED_HEADER)) {
            throw new ClaimantFileException(MSG_HEADER_MISMATCH);
        }

        List<RowContext> rowContexts = new List<RowContext>();
        for (Integer i = 1; i < lines.size(); i++) {
            String line = lines[i];
            if (String.isBlank(line)) {
                continue;
            }
            RowContext ctx = new RowContext();
            ctx.rowNumber = i + 1;
            ctx.originalLine = line;
            ctx.cols = parseCsvRow(line);
            rowContexts.add(ctx);
        }

        if (rowContexts.isEmpty()) {
            throw new ClaimantFileException(MSG_NO_DATA_ROWS);
        }
        if (rowContexts.size() > MAX_ROW_COUNT) {
            throw new ClaimantFileException(MSG_TOO_MANY_ROWS);
        }

        Set<String> healthPlanNamesRaw = new Set<String>();
        for (RowContext ctx : rowContexts) {
            if (ctx.cols.size() >= 3 && String.isNotBlank(ctx.cols[2])) {
                healthPlanNamesRaw.add(ctx.cols[2].trim());
            }
        }

        Map<String, Id> healthPlanIdByLowerName = new Map<String, Id>();
        if (!healthPlanNamesRaw.isEmpty()) {
            for (Account acc : [SELECT Id, Name FROM Account WHERE Name IN :healthPlanNamesRaw]) {
                healthPlanIdByLowerName.put(acc.Name.trim().toLowerCase(), acc.Id);
            }
        }

        Set<Id> candidateAccountIds = new Set<Id>(healthPlanIdByLowerName.values());
        Set<Id> participatingAccountIds = new Set<Id>();
        if (!candidateAccountIds.isEmpty()) {
            for (Settlement_Health_Plan__c shp : [
                SELECT Health_Plan__c
                FROM Settlement_Health_Plan__c
                WHERE Settlement__c = :settlementId
                AND Health_Plan__c IN :candidateAccountIds
            ]) {
                participatingAccountIds.add(shp.Health_Plan__c);
            }
        }

        List<ClaimantRowError> rejections = new List<ClaimantRowError>();
        List<RowContext> validRows = new List<RowContext>();
        Set<String> seenClaimantIdsUpper = new Set<String>();

        for (RowContext ctx : rowContexts) {
            ClaimantRowError err = validateAndPrepareRow(ctx, healthPlanIdByLowerName, participatingAccountIds, seenClaimantIdsUpper);
            if (err != null) {
                rejections.add(err);
            } else {
                validRows.add(ctx);
            }
        }

        Set<String> validClaimantIdsUpper = new Set<String>();
        for (RowContext ctx : validRows) {
            validClaimantIdsUpper.add(ctx.claimantIdUpper);
        }

        Map<String, List<Lien__c>> existingByClaimantIdUpper = new Map<String, List<Lien__c>>();
        if (!validClaimantIdsUpper.isEmpty()) {
            for (Lien__c existing : [
                SELECT Id, Claimant_ID__c
                FROM Lien__c
                WHERE Settlement__c = :settlementId
                AND Claimant_ID__c IN :validClaimantIdsUpper
            ]) {
                String key = existing.Claimant_ID__c.trim().toUpperCase();
                if (!existingByClaimantIdUpper.containsKey(key)) {
                    existingByClaimantIdUpper.put(key, new List<Lien__c>());
                }
                existingByClaimantIdUpper.get(key).add(existing);
            }
        }

        List<RowContext> createRows = new List<RowContext>();
        List<RowContext> updateRows = new List<RowContext>();
        for (RowContext ctx : validRows) {
            List<Lien__c> matches = existingByClaimantIdUpper.get(ctx.claimantIdUpper);
            if (matches == null || matches.isEmpty()) {
                createRows.add(ctx);
            } else if (matches.size() == 1) {
                ctx.existingLienId = matches[0].Id;
                updateRows.add(ctx);
            } else {
                rejections.add(buildError(ctx, 'AMBIGUOUS_EXISTING_LIEN', 'More than one existing Lien matches this Settlement and Claimant ID.'));
            }
        }

        List<Lien__c> newLiens = new List<Lien__c>();
        for (RowContext ctx : createRows) {
            Lien__c lien = new Lien__c();
            lien.Settlement__c = settlementId;
            lien.Claimant_Name__c = ctx.claimantName;
            lien.Claimant_ID__c = ctx.claimantId;
            lien.Health_Plan__c = ctx.healthPlanAccountId;
            lien.Health_Plan_Text__c = ctx.healthPlanText;
            lien.Injury_Category__c = ctx.injuryCategory;
            lien.Coverage_Result__c = ctx.coverageResult;
            lien.Recoverable_Amount__c = ctx.recoverableAmount;
            lien.Stage__c = 'Intake';
            lien.Intake_Date__c = Date.today();
            lien.Response_Deadline__c = Date.today().addDays(90);
            newLiens.add(lien);
        }

        List<Lien__c> updateLiens = new List<Lien__c>();
        for (RowContext ctx : updateRows) {
            Lien__c lien = new Lien__c(Id = ctx.existingLienId);
            lien.Claimant_Name__c = ctx.claimantName;
            lien.Health_Plan__c = ctx.healthPlanAccountId;
            lien.Health_Plan_Text__c = ctx.healthPlanText;
            lien.Injury_Category__c = ctx.injuryCategory;
            lien.Coverage_Result__c = ctx.coverageResult;
            lien.Recoverable_Amount__c = ctx.recoverableAmount;
            updateLiens.add(lien);
        }

        Integer createdCount = 0;
        List<Id> createdLienIds = new List<Id>();
        if (!newLiens.isEmpty()) {
            List<Database.SaveResult> insertResults = Database.insert(newLiens, false);
            for (Integer i = 0; i < insertResults.size(); i++) {
                Database.SaveResult sr = insertResults[i];
                if (sr.isSuccess()) {
                    createdCount++;
                    createdLienIds.add(sr.getId());
                } else {
                    rejections.add(buildError(createRows[i], 'LIEN_CREATE_FAILED', sanitizeDmlMessage(sr.getErrors())));
                }
            }
        }

        Integer updatedCount = 0;
        if (!updateLiens.isEmpty()) {
            List<Database.SaveResult> updateResults = Database.update(updateLiens, false);
            for (Integer i = 0; i < updateResults.size(); i++) {
                Database.SaveResult sr = updateResults[i];
                if (sr.isSuccess()) {
                    updatedCount++;
                } else {
                    rejections.add(buildError(updateRows[i], 'LIEN_UPDATE_FAILED', sanitizeDmlMessage(sr.getErrors())));
                }
            }
        }

        Integer automatedCount = 0;
        Integer escalatedCount = 0;
        if (!createdLienIds.isEmpty()) {
            for (Lien__c created : [SELECT Stage__c FROM Lien__c WHERE Id IN :createdLienIds]) {
                if (created.Stage__c == 'Coverage Confirmed') {
                    automatedCount++;
                } else if (created.Stage__c == 'Escalated') {
                    escalatedCount++;
                }
            }
        }

        ClaimantImportResult result = new ClaimantImportResult();
        result.rowsReceived = rowContexts.size();
        result.createdCount = createdCount;
        result.updatedCount = updatedCount;
        result.rejectedCount = rejections.size();
        result.automatedCount = automatedCount;
        result.escalatedCount = escalatedCount;
        result.rowErrors = rejections;

        if (!rejections.isEmpty()) {
            attachRejectionFile(settlementId, rejections, result);
        }

        return result;
    }

    private static void validateSettlementAccess(Id settlementId) {
        if (settlementId == null) {
            throw new ClaimantFileException('The claimant file could not be imported because no settlement was specified.');
        }
        List<Settlement__c> settlements = [SELECT Id FROM Settlement__c WHERE Id = :settlementId LIMIT 1];
        if (settlements.isEmpty()) {
            throw new ClaimantFileException('The claimant file could not be imported because the settlement could not be found or you do not have access to it.');
        }
    }

    private static ClaimantRowError validateAndPrepareRow(
        RowContext ctx,
        Map<String, Id> healthPlanIdByLowerName,
        Set<Id> participatingAccountIds,
        Set<String> seenClaimantIdsUpper
    ) {
        if (ctx.cols.size() != 6) {
            return buildError(ctx, 'COLUMN_COUNT', 'Row does not contain the expected six columns.');
        }

        String claimantName = ctx.cols[0].trim();
        String claimantId = ctx.cols[1].trim();
        String healthPlanRaw = ctx.cols[2].trim();
        String injuryCategory = ctx.cols[3].trim();
        String coverageRaw = ctx.cols[4].trim();
        String amountRaw = ctx.cols[5].trim();

        ctx.claimantName = claimantName;
        ctx.claimantId = claimantId;

        if (String.isBlank(claimantName)) {
            return buildError(ctx, 'MISSING_CLAIMANT_NAME', 'Claimant Name is required.');
        }
        if (String.isBlank(claimantId)) {
            return buildError(ctx, 'MISSING_CLAIMANT_ID', 'Claimant ID is required.');
        }
        if (claimantId.length() > 20) {
            return buildError(ctx, 'CLAIMANT_ID_TOO_LONG', 'Claimant ID exceeds the supported length.');
        }
        if (String.isBlank(healthPlanRaw)) {
            return buildError(ctx, 'MISSING_HEALTH_PLAN', 'Health Plan is required.');
        }

        Id healthPlanId = healthPlanIdByLowerName.get(healthPlanRaw.toLowerCase());
        if (healthPlanId == null) {
            return buildError(ctx, 'UNKNOWN_HEALTH_PLAN', 'Health Plan does not match an Account in Salesforce.');
        }
        if (!participatingAccountIds.contains(healthPlanId)) {
            return buildError(ctx, 'NONPARTICIPATING_HEALTH_PLAN', 'Health Plan is not configured for this settlement.');
        }
        if (String.isBlank(injuryCategory)) {
            return buildError(ctx, 'MISSING_INJURY_CATEGORY', 'Injury Category is required.');
        }

        String normalizedCoverage = normalizeCoverageResult(coverageRaw);
        if (normalizedCoverage == null) {
            return buildError(ctx, 'INVALID_COVERAGE_RESULT', 'Coverage Result must be Confirmed or Unable to Confirm.');
        }

        Boolean amountBlank = String.isBlank(amountRaw);
        if (normalizedCoverage == 'Confirmed' && amountBlank) {
            return buildError(ctx, 'MISSING_RECOVERABLE_AMOUNT', 'Recoverable Amount is required when coverage is Confirmed.');
        }

        Decimal parsedAmount = null;
        if (!amountBlank) {
            try {
                parsedAmount = Decimal.valueOf(amountRaw);
            } catch (Exception ex) {
                return buildError(ctx, 'INVALID_RECOVERABLE_AMOUNT', 'Recoverable Amount must be numeric.');
            }
            if (parsedAmount < 0) {
                return buildError(ctx, 'NEGATIVE_RECOVERABLE_AMOUNT', 'Recoverable Amount cannot be negative.');
            }
            if (normalizedCoverage == 'Confirmed' && parsedAmount <= 0) {
                return buildError(ctx, 'NONPOSITIVE_CONFIRMED_AMOUNT', 'Confirmed coverage requires a Recoverable Amount greater than zero.');
            }
        }

        String claimantIdUpper = claimantId.toUpperCase();
        if (seenClaimantIdsUpper.contains(claimantIdUpper)) {
            return buildError(ctx, 'DUPLICATE_IN_FILE', 'Claimant ID appears more than once in this file.');
        }
        seenClaimantIdsUpper.add(claimantIdUpper);

        ctx.claimantIdUpper = claimantIdUpper;
        ctx.healthPlanAccountId = healthPlanId;
        ctx.healthPlanText = healthPlanRaw;
        ctx.injuryCategory = injuryCategory;
        ctx.coverageResult = normalizedCoverage;
        ctx.recoverableAmount = parsedAmount;
        return null;
    }

    private static String normalizeCoverageResult(String raw) {
        for (String allowed : ALLOWED_COVERAGE_RESULTS) {
            if (allowed.equalsIgnoreCase(raw)) {
                return allowed;
            }
        }
        return null;
    }

    private static ClaimantRowError buildError(RowContext ctx, String code, String reason) {
        ClaimantRowError err = new ClaimantRowError();
        err.rowNumber = ctx.rowNumber;
        err.claimantId = ctx.claimantId;
        err.claimantName = ctx.claimantName;
        err.rejectionCode = code;
        err.rejectionReason = reason;
        err.originalRow = ctx.originalLine;
        return err;
    }

    private static String sanitizeDmlMessage(List<Database.Error> errors) {
        String msg = (errors != null && !errors.isEmpty()) ? errors[0].getMessage() : 'The record could not be saved.';
        return msg.replaceAll('[a-zA-Z0-9]{15,18}', '[hidden]');
    }

    private static void attachRejectionFile(Id settlementId, List<ClaimantRowError> rejections, ClaimantImportResult result) {
        String timestamp = Datetime.now().formatGmt('yyyyMMdd-HHmmss');
        String filename = 'Claimant_Import_Rejections_' + timestamp + '.csv';

        List<String> lines = new List<String>();
        lines.add(String.join(new List<String>{
            csvField('Row_Number'), csvField('Claimant_ID'), csvField('Claimant_Name'),
            csvField('Rejection_Code'), csvField('Rejection_Reason')
        }, ','));
        for (ClaimantRowError err : rejections) {
            lines.add(String.join(new List<String>{
                csvField(String.valueOf(err.rowNumber)),
                csvField(err.claimantId),
                csvField(err.claimantName),
                csvField(err.rejectionCode),
                csvField(err.rejectionReason)
            }, ','));
        }
        String csvContent = String.join(lines, '\n') + '\n';

        ContentVersion cv = new ContentVersion();
        cv.Title = filename.removeEnd('.csv');
        cv.PathOnClient = filename;
        cv.VersionData = Blob.valueOf(csvContent);
        insert cv;

        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        ContentDocumentLink link = new ContentDocumentLink();
        link.ContentDocumentId = contentDocumentId;
        link.LinkedEntityId = settlementId;
        link.ShareType = 'V';
        link.Visibility = 'AllUsers';
        insert link;

        result.rejectionFilename = filename;
        result.rejectionContentDocumentId = contentDocumentId;
    }

    private static String csvField(String value) {
        String safeValue = value == null ? '' : value;
        return '"' + safeValue.replace('"', '""') + '"';
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
