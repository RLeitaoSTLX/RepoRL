@isTest
public class InvoiceServiceTest {
    @isTest
    static void submitInvoices_happyPath_updatesStatusAndReturnsSuccess() {
        Invoice__c inv = InvoiceTestFactory.createInvoice('Draft', false);

        Test.startTest();
        InvoiceService.Result res = InvoiceService.submitInvoices(new Set<Id>{ inv.Id });
        Test.stopTest();

        System.assertNotEquals(null, res, 'Result não pode ser null');
        System.assertEquals(false, res.hasErrors(), 'Não deveria haver erros');
        System.assertEquals(1, res.successIds.size(), 'Deveria retornar 1 successId');
        System.assert(res.successIds.contains(inv.Id), 'successIds deveria conter o Id do invoice');
        System.assertEquals(0, res.errorById.size(), 'errorById deveria estar vazio');

        Invoice__c reloaded = [SELECT Id, Status__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals('Submitted', reloaded.Status__c, 'Status__c deveria ter sido atualizado para Submitted');
    }

    @isTest
    static void approveInvoices_happyPath_updatesStatusAndReturnsSuccess() {
        Account a = InvoiceTestFactory.createAccount();
        Invoice__c inv = InvoiceTestFactory.createInvoices(1, 'Submitted', a.Id)[0];

        Test.startTest();
        InvoiceService.Result res = InvoiceService.approveInvoices(new Set<Id>{ inv.Id });
        Test.stopTest();

        System.assertNotEquals(null, res, 'Result não pode ser null');
        System.assertEquals(false, res.hasErrors(), 'Não deveria haver erros');
        System.assertEquals(1, res.successIds.size(), 'Deveria retornar 1 successId');
        System.assert(res.successIds.contains(inv.Id), 'successIds deveria conter o Id do invoice');
        System.assertEquals(0, res.errorById.size(), 'errorById deveria estar vazio');

        Invoice__c reloaded = [SELECT Id, Status__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals('Approved', reloaded.Status__c, 'Status__c deveria ter sido atualizado para Approved');
    }

    @isTest
    static void approveInvoices_validationError_returnsSaveResultError() {
        // When becoming Approved, trigger requires Account__c.
        Invoice__c inv = InvoiceTestFactory.createInvoice('Submitted', false);

        Test.startTest();
        InvoiceService.Result res = InvoiceService.approveInvoices(new Set<Id>{ inv.Id });
        Test.stopTest();

        System.assertNotEquals(null, res, 'Result não pode ser null');
        System.assertEquals(0, res.successIds.size(), 'Não deveria haver sucesso quando validação falha');
        System.assertEquals(true, res.hasErrors(), 'Deveria haver erro de validação');
        System.assertEquals(1, res.errorById.size(), 'Deveria haver 1 erro');
        System.assertNotEquals(
            null,
            res.errorById.get(inv.Id),
            'Mensagem de erro de validação deveria existir'
        );
        System.assert(
            res.errorById.get(inv.Id).contains('Account__c'),
            'Mensagem de erro deveria mencionar Account__c'
        );

        Invoice__c reloaded = [SELECT Id, Status__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals('Submitted', reloaded.Status__c, 'Status__c não deveria ter sido alterado quando update falha');
    }

    @isTest
    static void submitInvoices_nullOrEmpty_returnsEmptyResultAndDoesNothing() {
        InvoiceService.Result resNull = InvoiceService.submitInvoices(null);
        System.assertNotEquals(null, resNull, 'Result não pode ser null quando input é null');
        System.assertEquals(0, resNull.successIds.size(), 'successIds deveria estar vazio');
        System.assertEquals(0, resNull.errorById.size(), 'errorById deveria estar vazio');

        InvoiceService.Result resEmpty = InvoiceService.submitInvoices(new Set<Id>());
        System.assertNotEquals(null, resEmpty, 'Result não pode ser null quando input é vazio');
        System.assertEquals(0, resEmpty.successIds.size(), 'successIds deveria estar vazio');
        System.assertEquals(0, resEmpty.errorById.size(), 'errorById deveria estar vazio');

        InvoiceService.Result resOnlyNull = InvoiceService.submitInvoices(new Set<Id>{ null });
        System.assertNotEquals(null, resOnlyNull, 'Result não pode ser null quando input contém apenas null');
        System.assertEquals(0, resOnlyNull.successIds.size(), 'successIds deveria estar vazio');
        System.assertEquals(0, resOnlyNull.errorById.size(), 'errorById deveria estar vazio');
    }

    @isTest
    static void submitInvoices_invalidTransition_returnsErrorAndDoesNotUpdate() {
        Invoice__c inv = InvoiceTestFactory.createInvoice('Submitted', false);

        Test.startTest();
        InvoiceService.Result res = InvoiceService.submitInvoices(new Set<Id>{ inv.Id });
        Test.stopTest();

        System.assertNotEquals(null, res, 'Result não pode ser null');
        System.assertEquals(0, res.successIds.size(), 'Nenhum registro deveria ter sucesso');
        System.assertEquals(true, res.hasErrors(), 'Deveria haver erros');
        System.assertEquals(1, res.errorById.size(), 'Deveria haver 1 erro');
        System.assertEquals(
            'Invoice não encontrado, sem acesso, ou com status inválido para transição.',
            res.errorById.get(inv.Id),
            'Mensagem de erro deveria indicar status inválido para transição'
        );

        Invoice__c reloaded = [SELECT Id, Status__c FROM Invoice__c WHERE Id = :inv.Id];
        System.assertEquals('Submitted', reloaded.Status__c, 'Status__c não deveria ter sido alterado');
    }

    @isTest
    static void submitInvoices_mixedEligibleAndIneligible_partialSuccess() {
        Invoice__c eligible = InvoiceTestFactory.createInvoice('Draft', false);
        Invoice__c ineligible = InvoiceTestFactory.createInvoice('Approved', true);

        Test.startTest();
        InvoiceService.Result res = InvoiceService.submitInvoices(new Set<Id>{ eligible.Id, ineligible.Id, null });
        Test.stopTest();

        System.assertNotEquals(null, res, 'Result não pode ser null');
        System.assertEquals(1, res.successIds.size(), 'Apenas 1 registro deveria ter sucesso');
        System.assert(res.successIds.contains(eligible.Id), 'Registro elegível deveria estar em successIds');
        System.assertEquals(true, res.hasErrors(), 'Deveria haver erro para o registro inelegível');
        System.assertEquals(1, res.errorById.size(), 'Deveria haver 1 erro (null é ignorado)');
        System.assertEquals(
            'Invoice não encontrado, sem acesso, ou com status inválido para transição.',
            res.errorById.get(ineligible.Id),
            'Registro inelegível deveria retornar mensagem de transição inválida'
        );

        Map<Id, Invoice__c> reloaded = new Map<Id, Invoice__c>([
            SELECT Id, Status__c
            FROM Invoice__c
            WHERE Id IN :new Set<Id>{ eligible.Id, ineligible.Id }
        ]);
        System.assertEquals('Submitted', reloaded.get(eligible.Id).Status__c, 'Elegível deveria virar Submitted');
        System.assertEquals('Approved', reloaded.get(ineligible.Id).Status__c, 'Inelegível deveria permanecer Approved');
    }

    @isTest
    static void submitInvoices_bulkOver200_updatesAllAndReturnsSuccessForAll() {
        Integer total = 250;
        List<Invoice__c> invoices = InvoiceTestFactory.createInvoices(total, 'Draft', null);
        Set<Id> ids = new Set<Id>();
        for (Invoice__c inv : invoices) {
            ids.add(inv.Id);
        }
        System.assertEquals(total, ids.size(), 'Deveria ter ' + total + ' ids distintos');

        Test.startTest();
        InvoiceService.Result res = InvoiceService.submitInvoices(ids);
        Test.stopTest();

        System.assertNotEquals(null, res, 'Result não pode ser null');
        System.assertEquals(false, res.hasErrors(), 'Não deveria haver erros no bulk');
        System.assertEquals(total, res.successIds.size(), 'Deveria ter sucesso para todos os registros');
        System.assertEquals(0, res.errorById.size(), 'errorById deveria estar vazio no bulk');

        Integer submittedCount = [
            SELECT COUNT()
            FROM Invoice__c
            WHERE Id IN :ids
            AND Status__c = 'Submitted'
        ];
        System.assertEquals(total, submittedCount, 'Todos deveriam estar com Status__c = Submitted');
    }
}

