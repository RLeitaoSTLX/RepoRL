@RestResource(urlMapping='/invoices/*')
global with sharing class InvoiceRestResource {
    global class ErrorItem {
        public String message;
        public String field;
        public String code;
        public ErrorItem(String message) {
            this.message = message;
        }
        public ErrorItem(String message, String field, String code) {
            this.message = message;
            this.field = field;
            this.code = code;
        }
    }

    global class ApiResponse {
        public Boolean success;
        public Object data;
        public List<ErrorItem> errors;
        public ApiResponse(Boolean success, Object data) {
            this.success = success;
            this.data = data;
        }
        public ApiResponse(Boolean success, Object data, List<ErrorItem> errors) {
            this.success = success;
            this.data = data;
            this.errors = errors;
        }
    }

    global class CreateInvoiceRequest {
        public Decimal amount;
        public String status;
        public Id accountId;
        public String name;
    }

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String idStr = extractIdFromUri(req != null ? req.requestURI : null);
        if (String.isBlank(idStr)) {
            writeJson(res, 400, new ApiResponse(false, null, new List<ErrorItem>{
                new ErrorItem('Informe o Id na URL. Ex: /services/apexrest/invoices/{id}', 'id', 'MISSING_ID')
            }));
            return;
        }

        Id invoiceId;
        try {
            invoiceId = (Id)idStr;
        } catch (Exception e) {
            writeJson(res, 400, new ApiResponse(false, null, new List<ErrorItem>{
                new ErrorItem('Id inválido.', 'id', 'INVALID_ID')
            }));
            return;
        }

        if (!Invoice__c.SObjectType.getDescribe().isAccessible()) {
            writeJson(res, 403, new ApiResponse(false, null, new List<ErrorItem>{
                new ErrorItem('Sem permissão de leitura em Invoice__c.', null, 'NO_ACCESS')
            }));
            return;
        }

        try {
            Invoice__c inv = [
                SELECT Id, Name, Status__c, Amount__c, Account__c, CreatedDate, LastModifiedDate
                FROM Invoice__c
                WHERE Id = :invoiceId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            writeJson(res, 200, new ApiResponse(true, inv));
        } catch (QueryException qe) {
            if (String.valueOf(qe.getMessage()).contains('List has no rows')) {
                writeJson(res, 404, new ApiResponse(false, null, new List<ErrorItem>{
                    new ErrorItem('Invoice não encontrado.', 'id', 'NOT_FOUND')
                }));
                return;
            }

            // Includes FLS/CRUD enforcement failures via WITH SECURITY_ENFORCED
            writeJson(res, 403, new ApiResponse(false, null, new List<ErrorItem>{
                new ErrorItem('Sem permissão para acessar os campos do Invoice.', null, 'NO_ACCESS')
            }));
        } catch (Exception e) {
            writeJson(res, 500, new ApiResponse(false, null, new List<ErrorItem>{
                new ErrorItem('Erro inesperado ao buscar Invoice.', null, 'SERVER_ERROR')
            }));
        }
    }

    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (!Invoice__c.SObjectType.getDescribe().isCreateable()) {
            writeJson(res, 403, new ApiResponse(false, null, new List<ErrorItem>{
                new ErrorItem('Sem permissão para criar Invoice__c.', null, 'NO_ACCESS')
            }));
            return;
        }

        String rawBody = (req != null && req.requestBody != null) ? req.requestBody.toString() : null;
        if (String.isBlank(rawBody)) {
            writeJson(res, 400, new ApiResponse(false, null, new List<ErrorItem>{
                new ErrorItem('Body JSON é obrigatório.', null, 'MISSING_BODY')
            }));
            return;
        }

        CreateInvoiceRequest input;
        try {
            input = (CreateInvoiceRequest)JSON.deserialize(rawBody, CreateInvoiceRequest.class);
        } catch (Exception e) {
            writeJson(res, 400, new ApiResponse(false, null, new List<ErrorItem>{
                new ErrorItem('JSON inválido.', null, 'INVALID_JSON')
            }));
            return;
        }

        List<ErrorItem> validationErrors = validateCreate(input);
        if (!validationErrors.isEmpty()) {
            writeJson(res, 422, new ApiResponse(false, null, validationErrors));
            return;
        }

        Invoice__c inv = new Invoice__c();
        if (input != null) {
            if (input.amount != null) {
                inv.Amount__c = input.amount;
            }
            inv.Status__c = String.isBlank(input.status) ? 'Draft' : input.status;
            if (input.accountId != null) {
                inv.Account__c = input.accountId;
            }

            if (!String.isBlank(input.name) && Invoice__c.Name.getDescribe().isCreateable()) {
                inv.Name = input.name;
            }
        }

        // Enforce FLS for fields being set. If the user attempted to set fields they can't create, fail with 403.
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<SObject>{ inv });
        List<String> removedFieldNames = new List<String>();
        if (decision != null) {
            List<SObjectField> removed = decision.getRemovedFields();
            if (removed != null && !removed.isEmpty()) {
                for (SObjectField f : removed) {
                    removedFieldNames.add(String.valueOf(f));
                }
            }
        }
        if (!removedFieldNames.isEmpty()) {
            writeJson(res, 403, new ApiResponse(false, null, new List<ErrorItem>{
                new ErrorItem('Sem permissão para definir alguns campos no Invoice.', String.join(removedFieldNames, ','), 'NO_FIELD_ACCESS')
            }));
            return;
        }

        try {
            Database.SaveResult sr = Database.insert(inv, false);
            if (!sr.isSuccess()) {
                String msg = (sr.getErrors() != null && !sr.getErrors().isEmpty())
                    ? sr.getErrors()[0].getMessage()
                    : 'Falha ao criar Invoice.';
                writeJson(res, 400, new ApiResponse(false, null, new List<ErrorItem>{
                    new ErrorItem(msg, null, 'DML_ERROR')
                }));
                return;
            }

            Map<String, Object> payload = new Map<String, Object>{
                'id' => sr.getId(),
                'status' => inv.Status__c
            };
            res.addHeader('Location', '/services/apexrest/invoices/' + String.valueOf(sr.getId()));
            writeJson(res, 201, new ApiResponse(true, payload));
        } catch (Exception e) {
            writeJson(res, 500, new ApiResponse(false, null, new List<ErrorItem>{
                new ErrorItem('Erro inesperado ao criar Invoice.', null, 'SERVER_ERROR')
            }));
        }
    }

    private static List<ErrorItem> validateCreate(CreateInvoiceRequest input) {
        List<ErrorItem> errors = new List<ErrorItem>();

        Decimal amount = input == null ? null : input.amount;
        if (amount != null && amount < 0) {
            errors.add(new ErrorItem('Amount__c não pode ser negativo.', 'amount', 'INVALID_AMOUNT'));
        }

        String status = input == null ? null : input.status;
        if (String.isBlank(status)) {
            status = 'Draft';
        }

        // Keep status values aligned with InvoiceService transitions + trigger rule.
        Set<String> allowed = new Set<String>{ 'Draft', 'Submitted', 'Approved' };
        if (!allowed.contains(status)) {
            errors.add(new ErrorItem('Status inválido. Use Draft, Submitted ou Approved.', 'status', 'INVALID_STATUS'));
        }

        if (status == 'Approved') {
            Id accountId = input == null ? null : input.accountId;
            if (accountId == null) {
                errors.add(new ErrorItem('Account__c é obrigatório quando Status__c for Approved.', 'accountId', 'MISSING_ACCOUNT'));
            } else {
                try {
                    if (accountId.getSObjectType() != Account.SObjectType) {
                        errors.add(new ErrorItem('accountId deve ser um Id de Account.', 'accountId', 'INVALID_ACCOUNT_ID'));
                    }
                } catch (Exception e) {
                    errors.add(new ErrorItem('accountId inválido.', 'accountId', 'INVALID_ACCOUNT_ID'));
                }
            }
        }

        return errors;
    }

    private static void writeJson(RestResponse res, Integer statusCode, Object payload) {
        if (res == null) {
            return;
        }
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json; charset=UTF-8');
        res.responseBody = Blob.valueOf(JSON.serialize(payload));
    }

    private static String extractIdFromUri(String uri) {
        if (String.isBlank(uri)) {
            return null;
        }
        // Handles /services/apexrest/invoices/{id} and trailing slashes.
        String cleaned = uri;
        Integer q = cleaned.indexOf('?');
        if (q >= 0) {
            cleaned = cleaned.substring(0, q);
        }
        while (cleaned.endsWith('/')) {
            cleaned = cleaned.substring(0, cleaned.length() - 1);
        }
        Integer lastSlash = cleaned.lastIndexOf('/');
        if (lastSlash < 0 || lastSlash == cleaned.length() - 1) {
            return null;
        }
        return cleaned.substring(lastSlash + 1);
    }
}

