import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
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

    // Builds OWM One Call 3.0 URL, makes async request
    function fetch(lat as Float, lon as Float, apiKey as String, units as String) as Void {
        _lat = lat;
        _lon = lon;

        var url = "https://api.openweathermap.org/data/3.0/onecall"
            + "?lat=" + lat.toString()
            + "&lon=" + lon.toString()
            + "&appid=" + apiKey
            + "&units=" + units
            + "&exclude=minutely,hourly,daily,alerts";

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(url, null, options, method(:onOWMResponse));
    }

    // Callback for OWM response
    function onOWMResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            _callback.invoke(null);
            return;
        }

        var weatherDict = {} as Dictionary<String, Application.PropertyValueType>;

        // Parse current weather fields
        var current = data["current"];
        if (current != null && current instanceof Dictionary) {
            weatherDict["temp"] = current["temp"] as Application.PropertyValueType;
            weatherDict["windSpeed"] = current["wind_speed"] as Application.PropertyValueType;
            weatherDict["windDeg"] = current["wind_deg"] as Application.PropertyValueType;
            weatherDict["sunrise"] = current["sunrise"] as Application.PropertyValueType;
            weatherDict["sunset"] = current["sunset"] as Application.PropertyValueType;

            // current.weather[0].id
            var weatherArr = current["weather"];
            if (weatherArr != null && weatherArr instanceof Array && weatherArr.size() > 0) {
                var firstWeather = weatherArr[0];
                if (firstWeather != null && firstWeather instanceof Dictionary) {
                    weatherDict["conditionId"] = firstWeather["id"] as Application.PropertyValueType;
                }
            }
        }

        // Write fetch metadata to Application.Storage on success
        var now = Time.now().value();
        Application.Storage.setValue("owmFetchedAt", now);
        Application.Storage.setValue("owmFetchLat", _lat);
        Application.Storage.setValue("owmFetchLon", _lon);

        _callback.invoke(weatherDict);
    }

}
