import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;

(:background)
class WeatherService {

    private var _lat as Float;
    private var _lon as Float;
    private var _callback as Method;

    function initialize(callback as Method) {
        _lat = 0.0f;
        _lon = 0.0f;
        _callback = callback;
    }

    // Builds OWM 2.5 Current Weather URL, makes async request
    function fetch(lat as Float, lon as Float, apiKey as String, units as String) as Void {
        _lat = lat;
        _lon = lon;

        var url = "https://api.openweathermap.org/data/2.5/weather"
            + "?lat=" + lat.toString()
            + "&lon=" + lon.toString()
            + "&appid=" + apiKey
            + "&units=" + units;

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(url, null, options, method(:onOWMResponse));
    }

    // Callback for OWM 2.5 response
    function onOWMResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            _callback.invoke(null);
            return;
        }

        var weatherDict = {} as Dictionary<String, Application.PropertyValueType>;

        // Parse main fields
        var main = data["main"];
        if (main != null && main instanceof Dictionary) {
            weatherDict["temp"] = main["temp"] as Application.PropertyValueType;
        }

        // Parse weather condition
        var weatherArr = data["weather"];
        if (weatherArr != null && weatherArr instanceof Array && weatherArr.size() > 0) {
            var firstWeather = weatherArr[0];
            if (firstWeather != null && firstWeather instanceof Dictionary) {
                weatherDict["conditionId"] = firstWeather["id"] as Application.PropertyValueType;
            }
        }

        // Parse wind
        var wind = data["wind"];
        if (wind != null && wind instanceof Dictionary) {
            weatherDict["windSpeed"] = wind["speed"] as Application.PropertyValueType;
            weatherDict["windDeg"] = wind["deg"] as Application.PropertyValueType;
        }

        // Parse sunrise/sunset from sys
        var sys = data["sys"];
        if (sys != null && sys instanceof Dictionary) {
            weatherDict["sunrise"] = sys["sunrise"] as Application.PropertyValueType;
            weatherDict["sunset"] = sys["sunset"] as Application.PropertyValueType;
        }

        // Write fetch metadata to Application.Storage on success
        var now = Time.now().value();
        Application.Storage.setValue("ofa", now);
        Application.Storage.setValue("ofl", _lat);
        Application.Storage.setValue("ofo", _lon);

        _callback.invoke(weatherDict);
    }

}
