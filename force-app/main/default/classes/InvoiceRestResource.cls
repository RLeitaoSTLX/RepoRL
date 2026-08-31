/**
 * Public REST API for Invoice__c records.
 *
 * Base URI: /services/apexrest/invoices/
 *   GET  /services/apexrest/invoices/{invoiceId}  -> fetch a single Invoice
 *   POST /services/apexrest/invoices/            -> create a single Invoice
 *
 * Design notes:
 * - Every response, success or failure, uses the same ApiResponse envelope so
 *   clients can parse one shape instead of branching on the HTTP status first.
 * - `global` is required by @RestResource; `with sharing` means record-level
 *   sharing rules apply to the caller, so this endpoint cannot be used to read
 *   Invoices the running user would not see in the UI.
 * - CRUD/FLS is enforced explicitly rather than relying on sharing alone:
 *   describe checks up front, WITH SECURITY_ENFORCED on read, and
 *   Security.stripInaccessible on create.
 * - Status__c values accepted here mirror the transitions in InvoiceService
 *   (Draft -> Submitted -> Approved). Creating an Invoice directly as
 *   'Approved' bypasses those transitions, which is why the Account__c
 *   requirement is validated here instead of being assumed upstream.
 *
 * @see InvoiceService for the status transition logic
 * @see InvoiceRestResourceTest for coverage
 */
@RestResource(urlMapping='/invoices/*')
global with sharing class InvoiceRestResource {
    /**
     * A single machine-readable error. `field` names the offending request
     * field (null for errors that are not field-specific) and `code` is a
     * stable identifier clients can switch on without parsing `message`.
     */
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

    /**
     * Uniform response envelope. On success `data` carries the payload and
     * `errors` is omitted from the JSON (null fields are dropped by
     * JSON.serialize); on failure `data` is null and `errors` is populated.
     */
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

    /**
     * Expected POST body. Field names are the JSON keys clients send.
     *
     * All four are optional: a body of `{}` creates an Invoice with Status__c
     * defaulted to 'Draft' and no Amount__c set. Note that `accountId` is typed
     * as Id, so a syntactically invalid Id string fails during JSON.deserialize
     * and surfaces as INVALID_JSON rather than reaching field validation.
     */
    global class CreateInvoiceRequest {
        public Decimal amount;
        public String status;
        public Id accountId;
        public String name;
    }

    /**
     * GET /services/apexrest/invoices/{invoiceId}
     *
     * Returns the Invoice as `data` on success. Status codes:
     *   200 found
     *   400 no Id in the URI (MISSING_ID) or not a well-formed Id (INVALID_ID)
     *   403 no object access (NO_ACCESS) or FLS blocked a selected field
     *   404 Id is valid but no row is visible to the caller (NOT_FOUND)
     *   500 anything else (SERVER_ERROR)
     *
     * Because sharing is enforced, a record the caller cannot see is
     * indistinguishable from one that does not exist — both return 404. That is
     * deliberate: it avoids leaking the existence of records via status codes.
     */
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

        // Cast before querying: an Id-shaped bind variable avoids handing
        // arbitrary caller input to SOQL and gives a clean 400 for junk input.
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
            // A single-row assignment throws QueryException for two very
            // different reasons: no rows, or WITH SECURITY_ENFORCED rejecting a
            // field. The message is the only thing separating them here.
            // NOTE: matching on 'List has no rows' is fragile — the platform
            // message text is not a contract. Selecting into a List and
            // checking isEmpty() would distinguish the cases structurally.
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

    /**
     * POST /services/apexrest/invoices/
     *
     * Creates one Invoice from a CreateInvoiceRequest body. On success returns
     * 201 with `{ id, status }` and a Location header pointing at the GET URI.
     *
     * Status codes:
     *   201 created
     *   400 missing body (MISSING_BODY), unparseable body (INVALID_JSON),
     *       or the insert was rejected by the platform (DML_ERROR)
     *   403 no create access on the object, or FLS blocked a supplied field
     *   422 the body parsed but failed business validation (see validateCreate)
     *   500 anything else (SERVER_ERROR)
     *
     * 400 vs 422 is the usual split: 400 means "I could not read this request",
     * 422 means "I read it and the values are not acceptable".
     */
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

        // Map only the fields the client actually supplied, so unset fields keep
        // whatever default the org has configured rather than being nulled out.
        Invoice__c inv = new Invoice__c();
        if (input != null) {
            if (input.amount != null) {
                inv.Amount__c = input.amount;
            }
            inv.Status__c = String.isBlank(input.status) ? 'Draft' : input.status;
            if (input.accountId != null) {
                inv.Account__c = input.accountId;
            }

            // Name is only set when the caller sent one AND the field is
            // writable — an Auto Number Name is not createable, and assigning
            // to it would throw at insert time.
            if (!String.isBlank(input.name) && Invoice__c.Name.getDescribe().isCreateable()) {
                inv.Name = input.name;
            }
        }

        // Enforce FLS for fields being set. If the user attempted to set fields they can't create, fail with 403.
        //
        // stripInaccessible normally *silently removes* fields the caller cannot
        // write. That silence is wrong for an API: the client would get a 201
        // and assume its Amount__c was saved. So we inspect getRemovedFields()
        // and reject the whole request instead, naming the offending fields.
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
            // allOrNone = false: validation rules, required fields and triggers
            // come back as a SaveResult we can translate into a 400, instead of
            // a DmlException that would land in the generic 500 handler.
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

    /**
     * Business validation for a create request. Collects *all* problems rather
     * than returning on the first, so a client fixes one round trip's worth of
     * mistakes at a time.
     *
     * Rules:
     * - Amount__c may be omitted or zero, but not negative.
     * - Status__c defaults to 'Draft' and must be one of the three known values.
     * - Approved invoices must name an Account, and that Id must actually be an
     *   Account (a valid Id of the wrong SObject type is rejected).
     *
     * @param input deserialized body; null-safe (a null input is valid and
     *              produces a Draft Invoice)
     * @return zero or more ErrorItems; empty means the request is acceptable
     */
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
        // Hardcoded rather than read from the picklist describe: it keeps this in
        // lockstep with InvoiceService's constants, at the cost of needing an
        // edit here if the picklist gains a value.
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

    /**
     * Single exit point for writing a response: sets the status, the JSON
     * content type and the serialized body together, so no code path can
     * accidentally return a body without a content type or vice versa.
     */
    private static void writeJson(RestResponse res, Integer statusCode, Object payload) {
        if (res == null) {
            return;
        }
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json; charset=UTF-8');
        res.responseBody = Blob.valueOf(JSON.serialize(payload));
    }

    /**
     * Pulls the last path segment out of the request URI, since urlMapping
     * '/invoices/*' captures the Id as part of the path rather than as a
     * parameter.
     *
     * Tolerates a query string and any number of trailing slashes, so all of
     * these yield the same Id:
     *   /services/apexrest/invoices/a01xx0000000001
     *   /services/apexrest/invoices/a01xx0000000001/
     *   /services/apexrest/invoices/a01xx0000000001?debug=1
     *
     * @return the last segment, or null if the URI carries no Id
     */
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

