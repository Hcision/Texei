/**
 * @Author: Hicham Hdidou
 * @Date: 30/05/2024
 * @Purpose: This test class validates the functionality of the WeatherComponentController class,
 * which provides weather information from the Geonames API based on geographic coordinates or city and country,
 * and sends weather reports via email to contacts or the current user.
 */
@isTest
public class WeatherCmpCTL_Test {

    @isTest
    static void testGetInfosFromApi() {
        Test.setMock(HttpCalloutMock.class, new GeonamesWeatherMock());

        Map<String, String> weatherData = WeatherComponentController.getInfosFromApi('36.81666666666667', '11.966666666666667');

        System.assertNotEquals(null, weatherData, 'Weather data should not be null');
        System.assertEquals('Pantelleria, IT', weatherData.get('location'), 'Location should be Pantelleria, IT');
    }

    @isTest
    static void testGetWeatherByCity() {
        Test.setMock(HttpCalloutMock.class, new GeonamesCityAndWeatherMock());

        Test.startTest();
        Map<String, String> weatherDataByCity = WeatherComponentController.getWeatherByCity('Pantelleria', 'IT');
        Test.stopTest();

        System.assertNotEquals(null, weatherDataByCity, 'Weather data by city should not be null');
        System.assertEquals('Pantelleria, IT', weatherDataByCity.get('location'), 'Location should be Pantelleria, IT');
    }

    @isTest
    static void testSendWeatherReport() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Contact testContact = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'test@example.com', AccountId = testAccount.Id);
        insert testContact;

        Map<String, String> weatherData = new Map<String, String>{
            'temperature' => '22',
            'humidity' => '73',
            'windSpeed' => '17',
            'weatherConditions' => 'n/a'
        };

        Test.startTest();
        Map<String, Object> result = WeatherComponentController.sendWeatherReport(testAccount.Id, weatherData);
        Test.stopTest();

        System.assertEquals('Success', result.get('status'), 'Email should be sent successfully');

        Account updatedAccount = [SELECT Id, Last_Report_Sent__c FROM Account WHERE Id = :testAccount.Id];
        System.assertNotEquals(null, updatedAccount.Last_Report_Sent__c, 'Last report sent date should be updated');

        Test.startTest();
        Map<String, Object> resultUser = WeatherComponentController.sendWeatherReport(null, weatherData);
        Test.stopTest();

        System.assertEquals('Success', resultUser.get('status'), 'Email should be sent successfully to current user');

        User currentUser = [SELECT Id, Last_Report_Sent__c FROM User WHERE Id = :UserInfo.getUserId()];
        System.assertNotEquals(null, currentUser.Last_Report_Sent__c, 'Last report sent date for user should be updated');
    }

    @isTest
    static void testSendWeatherReportLimitExceeded() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        Contact testContact = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'test@example.com', AccountId = testAccount.Id);
        insert testContact;

        Map<String, String> weatherData = new Map<String, String>{
            'temperature' => '22',
            'humidity' => '73',
            'windSpeed' => '17',
            'weatherConditions' => 'n/a'
        };

        // Simulate the email limit being exceeded by forcing an exception
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new EmailLimitExceededMock());
        Map<String, Object> result = WeatherComponentController.sendWeatherReport(testAccount.Id, weatherData);
        Test.stopTest();

        System.assertEquals('LimitExceeded', result.get('status'), 'Email limit should be exceeded');
    }

    private class GeonamesCityAndWeatherMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            if (req.getEndpoint().contains('searchJSON')) {
                res.setBody('{"totalResultsCount": 1, "geonames": [{"adminCode1": "15", "lng": "11.94611", "geonameId": 2523890, "toponymName": "Pantelleria", "countryId": "3175395", "fcl": "P", "population": 3455, "countryCode": "IT", "name": "Pantelleria", "fclName": "city, village,...", "adminCodes1": {"ISO3166_2": "82"}, "countryName": "Italy", "fcodeName": "seat of a third-order administrative division", "adminName1": "Sicily", "lat": "36.82836", "fcode": "PPLA3"}]}');
            } else if (req.getEndpoint().contains('findNearByWeatherJSON')) {
                res.setBody('{"weatherObservation": {"elevation": 191, "lng": 11.9666666666667, "observation": "LICG 310750Z 19017KT CAVOK 22/17 Q1012", "ICAO": "LICG", "clouds": "clouds and visibility OK", "dewPoint": "17", "cloudsCode": "CAVOK", "datetime": "2024-05-31 07:50:00", "countryCode": "IT", "temperature": "22", "humidity": 73, "stationName": "Pantelleria", "weatherCondition": "n/a", "windDirection": 190, "hectoPascAltimeter": 1012, "windSpeed": "17", "lat": 36.8166666666667}}');
            }
            return res;
        }
    }

    private class GeonamesWeatherMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"weatherObservation": {"elevation": 191, "lng": 11.9666666666667, "observation": "LICG 310750Z 19017KT CAVOK 22/17 Q1012", "ICAO": "LICG", "clouds": "clouds and visibility OK", "dewPoint": "17", "cloudsCode": "CAVOK", "datetime": "2024-05-31 07:50:00", "countryCode": "IT", "temperature": "22", "humidity": 73, "stationName": "Pantelleria", "weatherCondition": "n/a", "windDirection": 190, "hectoPascAltimeter": 1012, "windSpeed": "17", "lat": 36.8166666666667}}');
            return res;
        }
    }

    private class EmailLimitExceededMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new System.HandledException('The daily limit for the org would be exceeded by this request');
        }
    }
}