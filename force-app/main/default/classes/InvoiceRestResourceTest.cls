@IsTest
private class InvoiceRestResourceTest {
    private static Invoice__c makeInvoice(String status, Decimal amount, Id accountId) {
        Invoice__c inv = new Invoice__c();
        if (Invoice__c.Name.getDescribe().isCreateable()) {
            inv.Name = 'Test Invoice';
        }
        inv.Status__c = String.isBlank(status) ? 'Draft' : status;
        inv.Amount__c = amount;
        if (accountId != null) {
            inv.Account__c = accountId;
        }
        insert inv;
        return inv;
    }

    @IsTest
    static void getById_returns200() {
        Invoice__c inv = makeInvoice('Draft', 10, null);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/invoices/' + inv.Id;
        req.httpMethod = 'GET';
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        InvoiceRestResource.doGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertNotEquals(null, RestContext.response.responseBody);
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('"success":true'));
        System.assert(body.contains((String)inv.Id));
    }

    @IsTest
    static void getById_notFound_returns404() {
        Invoice__c inv = makeInvoice('Draft', 1, null);
        Id fakeId = inv.Id;
        delete inv;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/invoices/' + fakeId;
        req.httpMethod = 'GET';
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        InvoiceRestResource.doGet();
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode);
    }

    @IsTest
    static void postCreate_returns201() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/invoices';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"amount":12.34,"status":"Draft"}');
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        InvoiceRestResource.doPost();
        Test.stopTest();

        System.assertEquals(201, RestContext.response.statusCode);
        System.assertNotEquals(null, RestContext.response.responseBody);
        System.assert(RestContext.response.responseBody.toString().contains('"success":true'));
    }

    @IsTest
    static void postCreate_negativeAmount_returns422() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/invoices';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"amount":-1,"status":"Draft"}');
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        InvoiceRestResource.doPost();
        Test.stopTest();

        System.assertEquals(422, RestContext.response.statusCode);
    }
}

