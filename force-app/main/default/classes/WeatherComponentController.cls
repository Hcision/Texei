/**
 * @Author: Hicham Hdidou
 * @Date: 30/05/2024
 * @Purpose: This class provides weather information from the Geonames API based on geographic coordinates or city and country,
 * and sends weather reports via email to contacts or the current user.
 */
public with sharing class WeatherComponentController {

    /**
     * Retrieves weather information based on latitude and longitude from the Geonames API.
     * @param latitude Latitude of the location.
     * @param longitude Longitude of the location.
     * @return Map of weather factors.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getInfosFromApi(String latitude, String longitude) {
        Map<String, String> weatherFactorsMap = new Map<String, String>();
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        String username = 'hichamtexei';
        request.setEndpoint('http://api.geonames.org/findNearByWeatherJSON?lat=' + latitude + '&lng=' + longitude + '&username=' + username);
        request.setMethod('GET');
        HttpResponse response = http.send(request);

        if (response.getStatusCode() == 200) {
            Map<String, Object> deserializedMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            Map<String, Object> weatherObservation = (Map<String, Object>) deserializedMap.get('weatherObservation');
            if (weatherObservation != null) {
                weatherFactorsMap.put('location', String.valueOf(weatherObservation.get('stationName')) + ', ' + String.valueOf(weatherObservation.get('countryCode')));
                weatherFactorsMap.put('temperature', String.valueOf(weatherObservation.get('temperature')));
                weatherFactorsMap.put('weatherConditions', String.valueOf(weatherObservation.get('weatherCondition')));
                weatherFactorsMap.put('humidity', String.valueOf(weatherObservation.get('humidity')));
                weatherFactorsMap.put('windSpeed', String.valueOf(weatherObservation.get('windSpeed')));
                weatherFactorsMap.put('clouds', String.valueOf(weatherObservation.get('cloudsCode')));
            }
        } else {
            throw new AuraHandledException('Failed to retrieve weather information. Status code: ' + response.getStatusCode());
        }
        return weatherFactorsMap;
    }

    /**
     * Retrieves weather information based on city and country by first obtaining coordinates and then calling getInfosFromApi.
     * @param city City name.
     * @param country Country code.
     * @return Map of weather factors.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getWeatherByCity(String city, String country) {
        Map<String, String> weatherFactorsMap = new Map<String, String>();
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        String username = 'hichamtexei';
        request.setEndpoint('http://api.geonames.org/searchJSON?q=' + city + '&country=' + country + '&username=' + username);
        request.setMethod('GET');
        HttpResponse response = http.send(request);

        if (response.getStatusCode() == 200) {
            Map<String, Object> deserializedMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> geonames = (List<Object>) deserializedMap.get('geonames');
            if (!geonames.isEmpty()) {
                Map<String, Object> location = (Map<String, Object>) geonames[0];
                String latitude = String.valueOf(location.get('lat'));
                String longitude = String.valueOf(location.get('lng'));
                return getInfosFromApi(latitude, longitude);
            }
        } else {
            throw new AuraHandledException('Failed to retrieve location information. Status code: ' + response.getStatusCode());
        }
        return weatherFactorsMap;
    }

    /**
     * Sends a weather report via email to contacts related to a given account or to the current user.
     * @param recordId Account record Id.
     * @param weatherData Map containing weather data.
     * @return Status message indicating success or error.
     */
    @AuraEnabled
    public static Map<String, Object> sendWeatherReport(Id recordId, Map<String, String> weatherData) {
        System.debug('sendWeatherReport called with recordId: ' + recordId);
        System.debug('Weather Data: ' + weatherData);
    
        Map<String, Object> resultMap = new Map<String, Object>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        String userEmail = UserInfo.getUserEmail();
        List<String> emailAddresses = new List<String>();
    
        if (recordId != null) {
            List<Contact> contacts = [
                SELECT Email 
                FROM Contact 
                WHERE AccountId = :recordId AND Email != NULL
                LIMIT 1000
            ];
    
            for (Contact contact : contacts) {
                emailAddresses.add(contact.Email);
            }
        } else {
            emailAddresses.add(userEmail);
        }
    
        System.debug('Email Addresses: ' + emailAddresses);
    
        if (emailAddresses.isEmpty()) {
            throw new AuraHandledException('No email addresses found to send the weather report.');
        }
    
        String emailBody = 'Weather Report\n\n' +
                           'Temperature: ' + weatherData.get('temperature') + '\n' +
                           'Humidity: ' + weatherData.get('humidity') + '\n' +
                           'Wind Speed: ' + weatherData.get('windSpeed') + '\n' +
                           'Weather Conditions: ' + weatherData.get('weatherConditions');
    
        for (String emailAddress : emailAddresses) {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { emailAddress });
            mail.setSubject('Weather Report');
            mail.setPlainTextBody(emailBody);
            emails.add(mail);
        }
    
        try {
            Integer emailsToSend = emails.size();
            
            // Check org limits
            Map<String, System.OrgLimit> limitsMap = OrgLimits.getMap();
            System.OrgLimit singleEmailLimit = limitsMap.get('SingleEmail');
            Integer currentUsage = singleEmailLimit.getValue();
            Integer maxLimit = singleEmailLimit.getLimit();
            Integer remainingCapacity = maxLimit - currentUsage;
    
            if (emailsToSend > remainingCapacity) {
                resultMap.put('status', 'LimitExceeded');
                resultMap.put('remainingCapacity', remainingCapacity);
                return resultMap;
            }
    
            Messaging.reserveSingleEmailCapacity(emailsToSend);
    
            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails);
            }
    
            // Update the Last sent field on the Account or User
            if (recordId != null) {
                Account account = [SELECT Id, Last_Report_Sent__c FROM Account WHERE Id = :recordId LIMIT 1];
                account.Last_Report_Sent__c = System.now();
                update account;
            } else {
                User currentUser = [SELECT Id, Last_Report_Sent__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
                currentUser.Last_Report_Sent__c = System.now();
                update currentUser;
            }
    
            resultMap.put('status', 'Success');
            resultMap.put('remainingCapacity', remainingCapacity - emailsToSend);
            return resultMap;
        } catch (System.HandledException e) {
            if (e.getMessage().contains('The daily limit for the org would be exceeded by this request')) {
                resultMap.put('status', 'LimitExceeded');
            } else {
                resultMap.put('status', 'Error: ' + e.getMessage());
            }
        } catch (Exception e) {
            System.debug('Error sending email: ' + e.getMessage());
            resultMap.put('status', 'Error: ' + e.getMessage());
        }
        return resultMap;
    }            
}
