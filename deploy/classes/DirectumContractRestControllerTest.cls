@isTest
public with sharing class DirectumContractRestControllerTest {

    private static Opportunity opportunity;

    static {
        insert CFUtilsTest.createCFSettingsForRussia(false);
        insert E2EFormRuDataTestFactory.createTransitContractTypeMapping(30, 1);
        E2EFormRuTestUtils.initCustomSettings();

        Account account = OrganizationRequisiteTestDataFactory.createAccount('1234567890', 'test', 123456789);
        insert account;

        opportunity = OrganizationRequisiteTestDataFactory.createOpportunity(account);
        opportunity.StageName = OrganizationRequisiteDataService.SENT_TO_EDMS_STAGE_NAME;
        insert opportunity;

        Id contactId = E2EFormRuTestUtils.insertContact(E2EFormRuTestUtils.createContact(account.Id)).Id;
        insert E2EFormRuTestUtils.createOpportunityContactRole(opportunity.Id, contactId);

        Credit_Factory_Report__c report = CFTestDataFactory.createCreditFactoryReport(account, opportunity);
        report.RU_Client_choice__c = true;
        insert report;
    }

    @isTest
    private static void testUpdateContractWrongOpportunityStage() {
        insert OrganizationRequisiteTestDataFactory.createStageMapping(
                OrganizationRequisiteDataService.DIRECTUM_STATUS_FOR_PROCESS_COUNTERPARTY);
        opportunity.StageName = 'Contract signed in EDMS';
        update opportunity;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/sf-ru-conrtact-proccessing/v1/contract-status';
        req.httpMethod = HttpUtils.METHOD.POST;
        req.requestBody = Blob.valueOf(JSON.serialize(DirectumDataTestFactory.generateTestContractRequestBody(
                opportunity.Id, OrganizationRequisiteDataService.DIRECTUM_STATUS_FOR_PROCESS_COUNTERPARTY)));
        RestContext.request = req;
        RestContext.response = res;

        DirectumContractRestController.updateContract();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Contract signed in EDMS', opportunity.StageName);
    }

    @isTest
    private static void testUpdateContractStatusProcessCounterparty() {
        insert OrganizationRequisiteTestDataFactory.createStageMapping(
                OrganizationRequisiteDataService.DIRECTUM_STATUS_FOR_PROCESS_COUNTERPARTY);
        DirectumContractStatusRequestBody testRequest = DirectumDataTestFactory.generateTestContractRequestBody(
                opportunity.Id,
                OrganizationRequisiteDataService.DIRECTUM_STATUS_FOR_PROCESS_COUNTERPARTY
        );
        testUpdateContractData(testRequest);
    }

    @isTest
    private static void testUpdateContractStatusDocumentsCreated() {
        insert OrganizationRequisiteTestDataFactory.createStageMapping(
                DirectumContractRestController.DIRECTUM_STATUS_DOCUMENTS_CREATED);
        DirectumContractStatusRequestBody testRequest = DirectumDataTestFactory.generateTestContractRequestBody(
                opportunity.Id,
                DirectumContractRestController.DIRECTUM_STATUS_DOCUMENTS_CREATED
        );
        testUpdateContractData(testRequest);
    }

    @isTest
    public static void updateContractErrorTest() {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/sf-ru-conrtact-proccessing/v1/contract-status';
        req.httpMethod = HttpUtils.METHOD.POST;
        req.requestBody = null;
        RestContext.request = req;
        RestContext.response = res;

        DirectumContractRestController.updateContract();

        System.assertEquals(500, RestContext.response.statusCode);
    }

    @IsTest
    private static void testUpdateContractWithoutCustomSettings_Negative() {
        DirectumContractStatusRequestBody testRequest = DirectumDataTestFactory.generateTestContractRequestBody(
                opportunity.Id,
                DirectumContractRestController.DIRECTUM_STATUS_DOCUMENTS_CREATED
        );
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/sf-ru-conrtact-proccessing/v1/contract-status';
        req.httpMethod = HttpUtils.METHOD.POST;
        req.requestBody = Blob.valueOf(JSON.serialize(testRequest));
        RestContext.request = req;
        RestContext.response = res;

        DirectumContractRestController.updateContract();

        ApexClass apexClass = ([
                SELECT Id
                FROM ApexClass
                WHERE Name = :CreateTransitCounterpartyQue.class.getName()
        ]).get(0);
        List<AsyncApexJob> job = ([
                SELECT Id
                FROM AsyncApexJob
                WHERE ApexClassId = :apexClass.Id
        ]);

        System.assert(job.size() == 0);
        System.assertEquals(500, RestContext.response.statusCode);
    }

    private static void testUpdateContractData(DirectumContractStatusRequestBody testRequest) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/sf-ru-conrtact-proccessing/v1/contract-status';
        req.httpMethod = HttpUtils.METHOD.POST;

        req.requestBody = Blob.valueof(JSON.serialize(testRequest));
        RestContext.request = req;
        RestContext.response = res;

        Map<String, HttpCalloutMock> mockMap = new Map<String, HttpCalloutMock>();
        mockMap.put(
                TransitTestDataFactory.createContURI,
                new SingleRequestMock(200, 'Complete', TransitTestDataFactory.createContResponseBody200, TransitTestDataFactory.responseHeaders)
        );
        mockMap.put(
                MZKTestDataFactory.getRequestNumberURI,
                new SingleRequestMock(200, 'Complete', MZKTestDataFactory.getRequestNumberResponseBody200, MZKTestDataFactory.responseHeaders)
        );

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new MultiRequestMock(mockMap));

        DirectumContractRestController.updateContract();

        ApexClass apexClass = ([
                SELECT Id
                FROM ApexClass
                WHERE Name = :CreateTransitCounterpartyQue.class.getName()
        ]).get(0);
        List<AsyncApexJob> job = ([
                SELECT Id
                FROM AsyncApexJob
                WHERE ApexClassId = :apexClass.Id
        ]);
        System.assert(job.size() == 1);

        Test.stopTest();

        String jsonStr = RestContext.response.responseBody.toString();
        DirectumResponseBody response = (DirectumResponseBody) JSON.deserialize(jsonStr, DirectumResponseBody.class);

        System.assertNotEquals(null, response);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Contract updated successfully', response.message);
    }
}