import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getInfosFromApi from '@salesforce/apex/WeatherComponentController.getInfosFromApi';
import getWeatherByCity from '@salesforce/apex/WeatherComponentController.getWeatherByCity';
import sendWeatherReportApex from '@salesforce/apex/WeatherComponentController.sendWeatherReport';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ACCOUNT_LATITUDE_FIELD from '@salesforce/schema/Account.BillingLatitude';
import ACCOUNT_LONGITUDE_FIELD from '@salesforce/schema/Account.BillingLongitude';
import ACCOUNT_CITY_FIELD from '@salesforce/schema/Account.BillingCity';
import ACCOUNT_COUNTRY_FIELD from '@salesforce/schema/Account.BillingCountry';
import ACCOUNT_LAST_REPORT_SENT_FIELD from '@salesforce/schema/Account.Last_Report_Sent__c';
import USER_LAST_REPORT_SENT_FIELD from '@salesforce/schema/User.Last_Report_Sent__c';

const ACCOUNT_FIELDS = [
    ACCOUNT_LATITUDE_FIELD,
    ACCOUNT_LONGITUDE_FIELD,
    ACCOUNT_CITY_FIELD,
    ACCOUNT_COUNTRY_FIELD,
    ACCOUNT_LAST_REPORT_SENT_FIELD
];

const USER_FIELDS = [
    USER_LAST_REPORT_SENT_FIELD
];

const cloudIconMap = {

    //This are just are samples of the png links only CAVOK is reel.
    'n/a': 'https://example.com/icons/na.png',
    'SKC': 'https://example.com/icons/clear_sky.png',
    'CLR': 'https://example.com/icons/clear_sky.png',
    'FEW': 'https://example.com/icons/few_clouds.png',
    'SCT': 'https://example.com/icons/scattered_clouds.png',
    'BKN': 'https://example.com/icons/broken_clouds.png',
    'OVC': 'https://example.com/icons/overcast.png',
    'CAVOK': 'https://cdn-icons-png.freepik.com/512/1163/1163661.png?ga=GA1.1.1584079416.1716860712',
    'NCD': 'https://example.com/icons/no_clouds_detected.png',
    'NSC': 'https://example.com/icons/nil_significant_cloud.png',
    'VV': 'https://example.com/icons/vertical_visibility.png'
};

export default class WeatherComponent extends LightningElement {
    @api recordId;
    @track weatherData = {};
    @track error;

    @track latitude;
    @track longitude;
    @track city;
    @track country;
    @track isAccountPage = false;
    @track isSending = false;
    @track lastReportSent;

    // Fetch account fields if recordId is available
    @wire(getRecord, { recordId: '$recordId', fields: ACCOUNT_FIELDS })
    wiredAccountRecord({ error, data }) {
        if (data) {
            console.log('Account data:', data);
            this.latitude = getFieldValue(data, ACCOUNT_LATITUDE_FIELD);
            this.longitude = getFieldValue(data, ACCOUNT_LONGITUDE_FIELD);
            this.city = getFieldValue(data, ACCOUNT_CITY_FIELD);
            this.country = getFieldValue(data, ACCOUNT_COUNTRY_FIELD);
            this.lastReportSent = getFieldValue(data, ACCOUNT_LAST_REPORT_SENT_FIELD);
            this.isAccountPage = true;
            this.getWeatherData();
        } else if (error) {
            console.error('Error fetching account data:', error);
            this.error = error.body.message;
        }
    }

    // Fetch user fields if no recordId is available (i.e., on Home page)
    @wire(getRecord, { recordId: '$userId', fields: USER_FIELDS })
    wiredUserRecord({ error, data }) {
        if (!this.recordId && data) {
            console.log('User data:', data);
            this.lastReportSent = getFieldValue(data, USER_LAST_REPORT_SENT_FIELD);
        } else if (error) {
            console.error('Error fetching user data:', error);
            this.error = error.body.message;
        }
    }

    connectedCallback() {
        if (!this.recordId) {
            this.getUserLocation();
        }
    }

    getUserLocation() {
        if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition((position) => {
                this.latitude = position.coords.latitude;
                this.longitude = position.coords.longitude;
                this.isAccountPage = false;
                this.getWeatherDataByCoordinates();
            });
        } else {
            this.error = 'Geolocation is not supported by this browser.';
        }
    }

    getWeatherData() {
        if (this.latitude && this.longitude) {
            this.getWeatherDataByCoordinates();
        } else if (this.city && this.country) {
            this.getWeatherDataByCity(this.city, this.country);
        } else {
            this.error = 'Location information is not available.';
        }
    }

    getWeatherDataByCoordinates() {
        getInfosFromApi({ latitude: this.latitude.toString(), longitude: this.longitude.toString() })
            .then(result => {
                console.log('Weather data:', result);
                if (result && result.temperature && result.weatherConditions && result.humidity && result.windSpeed && result.clouds) {
                    this.weatherData = {
                        ...result,
                        cloudIcon: cloudIconMap[result.clouds] || cloudIconMap['n/a']
                    };
                    this.error = undefined;
                } else {
                    console.error('Unexpected result structure:', result);
                    this.error = 'Unexpected result structure';
                    this.weatherData = undefined;
                }
            })
            .catch(error => {
                console.error('Error fetching weather data:', error);
                this.error = error.body ? error.body.message : 'Unknown error';
                this.weatherData = undefined;
            });
    }

    getWeatherDataByCity(city, country) {
        getWeatherByCity({ city: city, country: country })
            .then(result => {
                console.log('Weather data:', result);
                if (result && result.temperature && result.weatherConditions && result.humidity && result.windSpeed && result.clouds) {
                    this.weatherData = {
                        ...result,
                        cloudIcon: cloudIconMap[result.clouds] || cloudIconMap['n/a']
                    };
                    this.error = undefined;
                } else {
                    console.error('Unexpected result structure:', result);
                    this.error = 'Unexpected result structure';
                    this.weatherData = undefined;
                }
            })
            .catch(error => {
                console.error('Error fetching weather data:', error);
                this.error = error.body ? error.body.message : 'Unknown error';
                this.weatherData = undefined;
            });
    }

    async sendWeatherReport() {
        try {
            this.isSending = true;
            let response;
            if (this.isAccountPage) {
                response = await sendWeatherReportApex({ recordId: this.recordId, weatherData: this.weatherData });
            } else {
                response = await sendWeatherReportApex({ weatherData: this.weatherData });
            }
            console.log('Email send response:', response);
            if (response !== 'Success') {
                this.showToast('Error', response, 'error');
            } else {
                this.showToast('Success', 'Weather report sent successfully', 'success');
            }
        } catch (error) {
            console.error('Error sending weather report:', error);
            this.showToast('Error', error.body ? error.body.message : 'Unknown error', 'error');
        } finally {
            this.isSending = false;
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    get windSpeed() {
        return this.weatherData.windSpeed || 'N/A';
    }

    get temperature() {
        return this.weatherData.temperature || 'N/A';
    }

    get humidity() {
        return this.weatherData.humidity || 'N/A';
    }

    get weatherConditions() {
        return this.weatherData.weatherConditions || 'N/A';
    }

    get cloudIcon() {
        return this.weatherData.cloudIcon || '';
    }

    get lastReportSentFormatted() {
        return this.lastReportSent ? new Date(this.lastReportSent).toLocaleString() : 'N/A';
    }
}
