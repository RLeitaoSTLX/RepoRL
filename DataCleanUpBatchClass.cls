/**
 * NOTE: This file was transcribed from `DataCleanUpBatchClass.png`.
 * The screenshot’s original class name appears as `GEN_DataCleanUpBatchClass`;
 * per request, this transcription uses `DataCleanUpBatchClass`.
 *
 * Name:        GEN_DataCleanUpBatchClass.cls
 * Description: Batch class to delete sObject records for clean up purpose
 *
 * Date     Version Author               Summary of Changes
 * Nov 2016 1.0     Swapnil Mane         Initial Release || PROJ-1619672_BREQ-012
 * Oct 2018 1.1     Pankaj Patkar        PROJ-1834243_BREQ-053 - Delete reports not run for last 1 year
 * Apr 2019 1.2     Pallavi Shewale      SR-00361738 Added Static Variable isGEN_DataCleanUpBatchClassRunning
 * Sep 2019 2.0     Harshad Bharsakle    PROJ-1943021_BREQ-0017 (sandbox/production + single object recurring mode)
 * Dec 2019 2.2     Saumya Bajpai        PROJ-1944918_BREQ-017 (Additional_Where_Clause_3__c)
 * Mar 2020 2.3     Divya Mahajan        PROJ-2047175_BREQ-043 (Customer Site handling)
 * Dec 2020 2.4     Patil, Giriraj       PROJ-2055772_US-114 (GDPR Individual)
 * Apr 2021 2.5     Patil, Giriraj       PROJ-2159317_US-095 (GDPR Legal Entity)
 * Nov 2021 2.6     Amit Bhosale         PROJ-1620010_US-618 (Optimization)
 * Feb 2023 3.0     Shivam Vishwakarma   US-ID_0007416 (ATA criteria)
 * Mar 2023 3.1     Shivam Vishwakarma   US-ID_0007466 (Orphan records + groups)
 * Oct 2023 3.2     Sri Sai              US-ID_0011270 (Dynamic base URL)
 * Mar 2024 4.0     Shilpa               US-ID_0013864 (Indentation/beautification)
 */
// prettier-ignore
global class DataCleanUpBatchClass implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {
    String query;

    // PROJ-1943021_BREQ-0017 - Introduced variables.
    Integer sequence;
    Boolean isSandbox;
    Boolean isListEmpty;
    Boolean isRecurringObject;
    Integer dataCleanUpConfigName;
    Integer defaultBatchSize = 1;

    CSL_DataCleanUpConfig__c dataCleanUpCS = new CSL_DataCleanUpConfig__c();

    // SR-00361738 - static variable to prevent future method invocation.
    global static Boolean isDataCleanUpBatchClassRunning { get; set; }

    String apiVersion;
    String sessionId;
    Integer count = 0;
    Integer initialBatchSize = 0;
    List<sObject> sobjList;

    // US-ID_0007466 - Batch group support.
    Integer batchGroupNumber;

    /**
     * Get session id to connect REST (PROJ-1834243_BREQ-053).
     */
    public String getSessionId() {
        HttpCalloutMock mock = null;
        // prettier-ignore
        HND_Integration_ConfigurationHandler integrationConfigurationhandler =
            (HND_Integration_ConfigurationHandler) HND_HandlerFactory.getHandlerInstance(Integration_Configuration__c.SObjectType);
        // prettier-ignore
        List<Integration_Configuration__c> integrationConfigurationList =
            integrationConfigurationhandler.getIntegrationConfigurationByName(
                new Set<String>{ GEN_Constants.PDM_METADATASERVICE_AUTHENTICATION }
            );

        CSH_PDM_Batch_Details__c PDMBatchDetails = CSH_PDM_Batch_Details__c.getOrgDefaults();

        // US-ID_0011270 Start - dynamic base URL
        String sfdcBaseURL = URL.getSalesforceBaseUri().toExternalForm();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(sfdcBaseURL + '/services/oauth2/token');
        // US-ID_0011270 End

        req.setMethod(GEN_Constants.POST_METHOD);
        req.setTimeout((Integer) PDMBatchDetails.Timeout_Period__c);
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        // prettier-ignore
        req.setBody(
            'grant_type=password'
            + '&client_id=' + PDMBatchDetails.Consumer_Key__c
            + '&client_secret=' + PDMBatchDetails.Consumer_Secret__c
            + '&username=' + integrationConfigurationList[0].Username__c
            + '&password=' + integrationConfigurationList[0].Password__c
        );

        Http http = new Http();
        HttpResponse response;
        if (Test.isRunningTest()) {
            response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody('{"access_token":"access_token"}');
        } else {
            response = http.send(req);
        }

        // PROJ-1620010_US-618 - optimized error handling.
        String sid = null;
        if (response != null && response.getStatusCode() == 200) {
            Map<String, Object> mapBody = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            sid = (String) mapBody.get('access_token');
            return sid;
        }

        // prettier-ignore
        Application_Log__c logEntry = new Application_Log__c(
            Application__c = 'Datacleanup Batch job Exception',
            Message__c     = 'Status = Failed. Check Cleanup batch report deletion authentication error'
        );
        insert logEntry;
        return null;
    }

    /**
     * Get latest API version (PROJ-1834243_BREQ-053).
     */
    public String getLatestAPEXAPIVersion() {
        AggregateResult ar = [SELECT Max(ApiVersion) version FROM ApexClass];
        return String.valueOf(ar.get('version'));
    }

    /**
     * Constructor (PROJ-1943021_BREQ-0017 - changed parameters).
     */
    // prettier-ignore
    public DataCleanUpBatchClass(
        String dataCleanUpConfigItemName,
        Integer dataCleanUpConfigItemNumber,
        Boolean isSingleObjectRunningMode,
        Integer dataCleanUpBatchGroupNumber
    ) {
        try {
            apiVersion = getLatestAPEXAPIVersion();

            isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;

            // Resolve config number by object API name (if provided).
            if (String.isNotBlank(dataCleanUpConfigItemName)) {
                for (CSL_DataCleanUpConfig__c csItem : CSL_DataCleanUpConfig__c.getAll().values()) {
                    if (
                        csItem.Object_API_Name__c == dataCleanUpConfigItemName &&
                        ((isSandbox && csItem.Execute_On_Sandbox__c) || (!isSandbox && csItem.Execute_On_Production__c))
                    ) {
                        dataCleanUpConfigItemNumber = Integer.valueOf(csItem.Name);
                        break;
                    }
                }
            }

            // Default batch size from custom setting.
            List<CS_INT_CleanUp_Batch_Config__c> defaults = CS_INT_CleanUp_Batch_Config__c.getAll().values();
            if (!defaults.isEmpty()) {
                if (dataCleanUpConfigItemNumber == 18 || dataCleanUpConfigItemNumber == 19) {
                    defaultBatchSize = Integer.valueOf(defaults[0].Default_Batch_Size_Report__c);
                } else {
                    defaultBatchSize = Integer.valueOf(defaults[0].Default_Batch_Size__c);
                }
            }

            dataCleanUpConfigName = dataCleanUpConfigItemNumber;
            sequence = dataCleanUpConfigItemNumber;
            isRecurringObject = isSingleObjectRunningMode;

            // US-ID_0007466 - group number only if valid; otherwise null means "all".
            batchGroupNumber = (dataCleanUpBatchGroupNumber != null && dataCleanUpBatchGroupNumber > 0)
                ? dataCleanUpBatchGroupNumber
                : null;

            CSL_DataCleanUpConfig__c configSingleItem =
                CSL_DataCleanUpConfig__c.getValues(String.valueOf(dataCleanUpConfigItemNumber));

            if (configSingleItem == null) {
                query = null;
                dataCleanUpCS = null;
                return;
            }

            if ((isSandbox && configSingleItem.Execute_On_Sandbox__c) || (!isSandbox && configSingleItem.Execute_On_Production__c)) {
                dataCleanUpCS = configSingleItem;
                String initQuery;
                String finalQuery = '';

                if (configSingleItem.IsActive__c) {
                    // Org Id match (or blank).
                    if (
                        configSingleItem.SFDC_Org_ID__c == null ||
                        configSingleItem.SFDC_Org_ID__c == '' ||
                        configSingleItem.SFDC_Org_ID__c == UserInfo.getOrganizationId()
                    ) {
                        if (configSingleItem.Object_API_Name__c != null) {
                            if (String.isNotBlank(configSingleItem.Start_Query__c)) {
                                initQuery = configSingleItem.Start_Query__c + ' ' + configSingleItem.Object_API_Name__c + ' where ';
                            } else {
                                initQuery = 'select Id from ' + configSingleItem.Object_API_Name__c + ' where ';
                            }

                            // Market
                            if (configSingleItem.Market_Field_API_Name__c != null && configSingleItem.Market_Value__c != null) {
                                finalQuery += configSingleItem.Market_Field_API_Name__c + ' = \'' + String.valueOf(configSingleItem.Market_Value__c) + '\' AND ';
                            }

                            // CreatedBy
                            if (configSingleItem.CreatedByID__c != null) {
                                finalQuery += 'CreatedById = \'' + String.valueOf(configSingleItem.CreatedByID__c) + '\' AND ';
                            }
                            if (configSingleItem.CreatedByProfileName__c != null) {
                                Profile pc = [SELECT Id FROM Profile WHERE Name = :configSingleItem.CreatedByProfileName__c LIMIT 1];
                                finalQuery += 'CreatedBy.ProfileId = \'' + pc.Id + '\' AND ';
                            }

                            // Date field filters
                            if (
                                configSingleItem.Date_Field_API_Name__c != null &&
                                configSingleItem.Date_Field_Function__c != null &&
                                (
                                    configSingleItem.Use_Today_s_Date__c ||
                                    configSingleItem.Offset_from_todays_date__c != null ||
                                    configSingleItem.Date_Field_Value__c != null
                                )
                            ) {
                                if (configSingleItem.Use_Today_s_Date__c && configSingleItem.Offset_from_todays_date__c == null && configSingleItem.Date_Field_Value__c == null) {
                                    finalQuery += configSingleItem.Date_Field_API_Name__c + configSingleItem.Date_Field_Function__c + ' ' + String.valueOf(System.today()) + ' AND ';
                                } else if (!configSingleItem.Use_Today_s_Date__c && configSingleItem.Offset_from_todays_date__c != null && configSingleItem.Date_Field_Value__c == null) {
                                    Integer n = Integer.valueOf(configSingleItem.Offset_from_todays_date__c).round(System.RoundingMode.FLOOR);
                                    finalQuery += configSingleItem.Date_Field_API_Name__c + configSingleItem.Date_Field_Function__c + 'LAST_N_DAYS:' + String.valueOf(n) + ' AND ';
                                } else if (!configSingleItem.Use_Today_s_Date__c && configSingleItem.Date_Field_Value__c != null) {
                                    Datetime myDT = configSingleItem.Date_Field_Value__c;
                                    String myDate = myDT.format('yyyy-MM-dd\'T\'HH:mm:ss.SSSXXX');
                                    finalQuery += configSingleItem.Date_Field_API_Name__c + configSingleItem.Date_Field_Function__c + myDate + ' AND ';
                                }
                            }

                            // LastModifiedBy
                            if (configSingleItem.LastModifiedById__c != null) {
                                finalQuery += 'LastModifiedById = \'' + String.valueOf(configSingleItem.LastModifiedById__c) + '\' AND ';
                            }
                            if (configSingleItem.LastModifiedByProfileName__c != null) {
                                Profile pl = [SELECT Id FROM Profile WHERE Name = :configSingleItem.LastModifiedByProfileName__c LIMIT 1];
                                finalQuery += 'LastModifiedBy.ProfileId = \'' + pl.Id + '\' AND ';
                            }

                            // Record Type
                            if (configSingleItem.RecordTypeDeveloperName__c != null) {
                                finalQuery += 'RecordType.DeveloperName = \'' + String.valueOf(configSingleItem.RecordTypeDeveloperName__c) + '\' AND ';
                            }

                            // CreatedDate between
                            if (configSingleItem.Start_Date__c != null) {
                                String myStartDate = configSingleItem.Start_Date__c.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                                finalQuery += 'CreatedDate > ' + myStartDate + ' AND ';
                            }
                            if (configSingleItem.End_Date__c != null) {
                                String myEndDate = configSingleItem.End_Date__c.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                                finalQuery += 'CreatedDate < ' + myEndDate + ' AND ';
                            }

                            // Additional clauses (1..3)
                            if (configSingleItem.Additional_Where_Clause_1__c != null) {
                                finalQuery += String.valueOf(configSingleItem.Additional_Where_Clause_1__c) + ' AND ';
                            }
                            if (configSingleItem.Additional_Where_Clause_2__c != null) {
                                finalQuery += String.valueOf(configSingleItem.Additional_Where_Clause_2__c) + ' AND ';
                            }
                            if (configSingleItem.Additional_Where_Clause_3__c != null) {
                                finalQuery += String.valueOf(configSingleItem.Additional_Where_Clause_3__c) + ' AND ';
                            }

                            finalQuery = finalQuery.removeEnd(' AND ');
                            query = initQuery + finalQuery;
                        }
                    }
                }
            }

            // Fallback: nothing to run.
            if (query == null && configSingleItem != null && configSingleItem.Object_API_Name__c != null) {
                query = 'select Id from ' + configSingleItem.Object_API_Name__c + ' limit 0';
                dataCleanUpCS = null;
            }
        } catch (Exception e) {
            // prettier-ignore
            Application_Log__c logEntry = new Application_Log__c(
                Application__c = 'Datacleanup Batch job Exception',
                Message__c     = 'Status = Failed. Please check whether SFDC_Org_ID__c, IsActive__c and query formation is correct or not. Actual exception: ' + String.valueOf(e)
            );
            insert logEntry;
            throw e;
        }
    }

    // PROJ-1620010_US-618 - optimized error logging.
    private static void checkErrorsInResult(Database.DeleteResult[] resultList) {
        ApplicationLog.createAppLogForFailedRecordsInAppGuidance(
            resultList,
            'Gen_DataCleanUpBatch',
            'Gen_DataCleanUpBatch'
        );
    }

    // Start Method
    global Database.QueryLocator start(Database.BatchableContext bc) {
        isListEmpty = true;
        System.debug('>>>>>> query ' + query);
        return Database.getQueryLocator(query);
    }

    // Execute Logic
    global void execute(Database.BatchableContext bc, List<sObject> scope) {
        List<String> responseList = new List<String>();
        if (scope != null && !scope.isEmpty()) {
            count++;
            isDataCleanUpBatchClassRunning = true;

            // Capture initial batch size for re-trigger.
            List<sObject> listOfObjectToDelete = new List<sObject>();
            if (initialBatchSize == 0 && isRecurringObject) {
                initialBatchSize = scope.size();
            } else if (isRecurringObject) {
                initialBatchSize = defaultBatchSize;
            }

            isListEmpty = false;

            // Report / Dashboard deletion via REST.
            if (scope.getSObjectType() == Schema.Report.getSObjectType() || scope.getSObjectType() == Schema.Dashboard.getSObjectType()) {
                sessionId = getSessionId();
                if (sessionId != null && sessionId != '') {
                    Http http = new Http();
                    HttpRequest request = new HttpRequest();

                    String strBaseURL = System.URL.getSalesforceBaseURL().toExternalForm().toLowerCase();
                    String strObjectType = scope.getSObjectType().getDescribe().getLabelPlural().toLowerCase();

                    for (sObject tmpSobject : scope) {
                        request.setEndpoint(strBaseURL + '/services/data/v' + apiVersion + '/analytics/' + strObjectType + '/' + String.valueOf(tmpSobject.Id));
                        request.setMethod('DELETE');
                        request.setHeader('Authorization', 'Bearer ' + sessionId);
                        request.setHeader('Content-Type', 'application/json');

                        HttpResponse response = http.send(request);
                        Integer status = response.getStatusCode();
                        if (status != 200 && status != 204) {
                            String messageContent = response.getBody() + ' Object Name:-->' + strObjectType + ' RecordID:-->' + String.valueOf(tmpSobject.Id);
                            responseList.add(messageContent);
                        }
                    }

                    if (!responseList.isEmpty()) {
                        List<Application_Log__c> logEntries = new List<Application_Log__c>();
                        for (String errorResponse : responseList) {
                            // prettier-ignore
                            Application_Log__c errorReportLog = new Application_Log__c(
                                Application__c = 'Gen_DataCleanUpBatch_Report',
                                Module__c      = 'Gen_DataCleanUpBatch',
                                Message__c     = errorResponse
                            );
                            logEntries.add(errorReportLog);
                        }
                        insert logEntries;
                    }

                    // If REST is used, stop recurring mode.
                    isRecurringObject = false;
                }
            } else {
                // Customer Site special handling (PROJ-2047175_BREQ-043)
                if (scope.getSObjectType() == Schema.Customer_Site__c.getSObjectType()) {
                    List<Customer_Site__c> csList = (List<Customer_Site__c>) scope;
                    for (Customer_Site__c csObject : csList) {
                        if (csObject.Reason_for_Failure__c != null) {
                            listOfObjectToDelete.add(csObject);
                        }
                    }
                    Database.DeleteResult[] drList = Database.delete(listOfObjectToDelete, false);
                    checkErrorsInResult(drList);
                }
                // GDPR Individual handling (PROJ-2055772_US-114)
                else if (scope.getSObjectType() == Schema.Individual.getSObjectType()) {
                    List<Individual> individualList = (List<Individual>) scope;
                    for (Individual record : individualList) {
                        listOfObjectToDelete.add(record);
                    }
                    Database.DeleteResult[] drList = Database.delete(listOfObjectToDelete, false);
                    checkErrorsInResult(drList);
                }
                else {
                    Database.DeleteResult[] drList = Database.delete(scope, false);
                    checkErrorsInResult(drList);
                }
            }
        }
    }

    global void finish(Database.BatchableContext bc) {
        AsyncApexJob apexJobs = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
        ];

        // NOTE: external dependency kept as-is from screenshot.
        List<AsyncApexJob> apexJobStatusCheck = GEN_Utilities.checkBatchIsRunning('DataCleanUpBatchClass');

        // prettier-ignore
        Application_Log__c logEntry = new Application_Log__c(
            Application__c = 'Datacleanup Batch job',
            Message__c     = 'Status = ' + apexJobs.Status
                + ' NumberOfErrors = ' + apexJobs.NumberOfErrors
                + ' JobItemsProcessed = ' + apexJobs.JobItemsProcessed
                + ' TotalJobItems = ' + apexJobs.TotalJobItems
        );
        insert logEntry;

        if (dataCleanUpCS != null) {
            if (apexJobs.Status == GEN_Constants.ASYNC_JOBSTATUS_COMPLETED) {
                dataCleanUpCS.Status__c = GEN_Constants.DATA_CLEANUP_SUCCESS;
                dataCleanUpCS.RecordExecutionTimeStamp__c = Datetime.now();
            } else {
                dataCleanUpCS.Status__c = GEN_Constants.DATA_CLEANUP_FAILED;
                dataCleanUpCS.RecordExecutionTimeStamp__c = Datetime.now();
            }
            update dataCleanUpCS;
        }

        // PROJ-1943021_BREQ-0017 - Re-trigger logic.
        if (initialBatchSize == 0) initialBatchSize = defaultBatchSize;

        if (dataCleanUpConfigName != null && isRecurringObject) {
            if (count == 0) isListEmpty = false;
            if (GEN_Utilities.getNumberOfBatchesRunning() < 5 && isListEmpty && !Test.isRunningTest()) {
                if (apexJobStatusCheck == null || apexJobStatusCheck.isEmpty()) {
                    // US-ID_0007466 - pass null group when recurring same object.
                    DataCleanUpBatchClass nextBatch = new DataCleanUpBatchClass('', dataCleanUpConfigName, true, null);
                    Database.executeBatch(nextBatch, initialBatchSize);
                }
            }
        } else {
            // Move to next sequence.
            if (batchGroupNumber != null) {
                do {
                    sequence = sequence + 1;
                } while (
                    CSL_DataCleanUpConfig__c.getInstance(String.valueOf(sequence)) != null &&
                    CSL_DataCleanUpConfig__c.getInstance(String.valueOf(sequence)).Batch_Group_Number__c != batchGroupNumber &&
                    sequence <= CSL_DataCleanUpConfig__c.getAll().size()
                );
            } else {
                sequence = sequence + 1;
            }

            if (sequence <= CSL_DataCleanUpConfig__c.getAll().size()) {
                if (GEN_Utilities.getNumberOfBatchesRunning() < 5) {
                    if (apexJobStatusCheck == null || apexJobStatusCheck.isEmpty()) {
                        CSL_DataCleanUpConfig__c seqRecord = CSL_DataCleanUpConfig__c.getInstance(String.valueOf(sequence));

                        DataCleanUpBatchClass nextBatch = new DataCleanUpBatchClass('', sequence, false, batchGroupNumber);

                        if (sequence == 18 || sequence == 19) {
                            initialBatchSize = 90;
                        } else if (seqRecord != null && seqRecord.Custom_Batch_Size__c != null && seqRecord.Custom_Batch_Size__c > 0) {
                            initialBatchSize = Integer.valueOf(seqRecord.Custom_Batch_Size__c);
                        } else {
                            initialBatchSize = nextBatch.defaultBatchSize;
                        }

                        if (!Test.isRunningTest()) {
                            Database.executeBatch(nextBatch, initialBatchSize);
                        }
                    }
                }
            }
        }
    }
}

