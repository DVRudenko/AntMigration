@RestResource(UrlMapping='/sf-ru-contract-processing/v1/contract-status')
global with sharing class DirectumContractRestController {
    public static final String LOGGER_NAME = 'DirectumContractRestController';
    public static final String FATAL_SUBJECT = 'DirectumContractRestController updateContract method exception';
    public static final String ERROR_SUBJECT = 'DirectumContractRestController updateContract error';
    public static final String CONTRACT_UPDATE_SUCCESS = 'Contract updated successfully';
    public static final String WRONG_STAGE_FOR_UPDATE = 'Wrong stage for contract update. OpportunityId = ';
    public static final String NO_ID_FOUND = 'No opportunities found by ID = ';

    @TestVisible
    private static final String DIRECTUM_STATUS_DOCUMENTS_CREATED = 'DocumentsCreated';

    private static Logger logger = new Logger(LOGGER_NAME);

    @HttpPost
    global static void updateContract() {
        RestResponse response = RestContext.response;
        DirectumResponseBody responseBody = new DirectumResponseBody();
        String directumContracStatusAgreed = Directum_contract_stage_mapping__c.getValues(
                OrganizationRequisiteDataService.DIRECTUM_STATUS_FOR_PROCESS_COUNTERPARTY
        )?.Contract_status__c;
        String directumContractStatusDocumentsCreated = Directum_contract_stage_mapping__c.getValues(
                DIRECTUM_STATUS_DOCUMENTS_CREATED
        )?.Contract_status__c;

        try {
            String jsonStr = RestContext.request.requestBody.toString();
            logger.info(RestContext.request.httpMethod + ' request from ' + RestContext.request.remoteAddress, jsonStr);
            DirectumContractStatusRequestBody requestBody = DirectumContractStatusRequestBody.parse(jsonStr);
            Id opportunityId = requestBody?.externalId;
            if (requestBody != null && opportunityId != null) {
                if (isOpportunityValidStage (opportunityId)) {
                    OrganizationRequisiteDataService.updateContractData(requestBody);

                    if (requestBody.contractStage.equals(directumContracStatusAgreed)
                            || requestBody.contractStage.equals(directumContractStatusDocumentsCreated)) {
                        CreateTransitCounterpartyQue createTransitCounterpartyQue = new CreateTransitCounterpartyQue(opportunityId);
                        System.enqueueJob(createTransitCounterpartyQue);
                    }
                    responseBody.message = CONTRACT_UPDATE_SUCCESS;
                } else {
                    responseBody.message = WRONG_STAGE_FOR_UPDATE + opportunityId;
                    logger.error(ERROR_SUBJECT, responseBody.message);
                }
                response.statusCode = 200;
            }
        } catch (Exception e) {
            response.statusCode = 500;
            responseBody.message = e.getTypeName() + ': ' + e.getMessage();
            logger.fatal(FATAL_SUBJECT, responseBody.message);
        } finally {
            response.responseBody = Blob.valueOf(JSON.serializePretty(responseBody, true));
            logger.saveLogs();
        }
    }

    private static Boolean isOpportunityValidStage(Id opportunityId) {
        try {
            Opportunity opportunity = OrganizationRequisiteDataService.getOpportunityById(opportunityId);
            return opportunity.StageName == OrganizationRequisiteDataService.SENT_TO_EDMS_STAGE_NAME;
        } catch (Exception e) {
            throw new GlobalException(NO_ID_FOUND + opportunityId);
        }
    }
}