import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
class SurferWatchFaceDelegate extends System.ServiceDelegate {

    // Holds weather result while waiting for tide fetch to complete
    private var _weatherResult as Dictionary or Null;
    // Track whether tide fetch is needed this cycle
    private var _tideNeeded as Boolean;
    // Current position for this cycle
    private var _lat as Float;
    private var _lng as Float;

    function initialize() {
        ServiceDelegate.initialize();
        _weatherResult = null;
        _tideNeeded = false;
        _lat = 0.0f;
        _lng = 0.0f;
    }

    // Haversine distance in meters between two lat/lon pairs
    function distanceBetween(lat1 as Float, lon1 as Float, lat2 as Float, lon2 as Float) as Float {
        var R = 6371000.0f; // Earth radius in meters
        var dLat = (lat2 - lat1) * Math.PI / 180.0f;
        var dLon = (lon2 - lon1) * Math.PI / 180.0f;
        var a = Math.sin(dLat / 2.0f) * Math.sin(dLat / 2.0f) +
                Math.cos(lat1 * Math.PI / 180.0f) * Math.cos(lat2 * Math.PI / 180.0f) *
                Math.sin(dLon / 2.0f) * Math.sin(dLon / 2.0f);
        var c = 2.0f * Math.atan2(Math.sqrt(a), Math.sqrt(1.0f - a));
        return R * c;
    }

    // Returns today's date as "YYYY-MM-DD" in UTC
    private function todayUTC() as String {
        var now = Time.now();
        var today = Gregorian.info(now, Time.FORMAT_SHORT);
        return today.year.format("%04d") + "-" +
               today.month.format("%02d") + "-" +
               today.day.format("%02d");
    }

    // Determine if StormGlass tide refresh is needed (design §4.2)
    private function isTideRefreshNeeded(lat as Float, lng as Float) as Boolean {
        var tideFetchedDay = Application.Storage.getValue("tideFetchedDay") as String or Null;
        var today = todayUTC();

        // Guard: skip if quota exhausted
        var quotaExhausted = Application.Storage.getValue("stormGlassQuotaExhausted");
        if (quotaExhausted != null && quotaExhausted == true) {
            // Check if it's a new day — clear quota flag if so
            if (tideFetchedDay != null && !tideFetchedDay.equals(today)) {
                // New day — clear the exhausted flag
                Application.Storage.setValue("stormGlassQuotaExhausted", false);
            } else {
                return false;
            }
        }

        // Condition 1: never fetched
        if (tideFetchedDay == null) {
            return true;
        }

        // Condition 2: new calendar day
        if (!tideFetchedDay.equals(today)) {
            return true;
        }

        // Condition 3: moved >50km since last fetch
        var tideFetchLat = Application.Storage.getValue("tideFetchLat") as Float or Null;
        var tideFetchLng = Application.Storage.getValue("tideFetchLng") as Float or Null;
        if (tideFetchLat != null && tideFetchLng != null) {
            if (distanceBetween(lat, lng, tideFetchLat, tideFetchLng) > 50000.0f) {
                return true;
            }
        }

        // Condition 4: tide data expired (all events in past)
        var tideDataExpired = Application.Storage.getValue("tideDataExpired");
        if (tideDataExpired != null && tideDataExpired == true) {
            return true;
        }

        return false;
    }

    function onTemporalEvent() as Void {
        // Guard: skip if no phone connection
        var btConnected = Application.Storage.getValue("bluetoothConnected");
        if (btConnected == null || btConnected == false) {
            Background.exit(null);
            return;
        }

        // Read current position from Storage (written by main process)
        var lat = Application.Storage.getValue("lastKnownLat") as Float or Null;
        var lng = Application.Storage.getValue("lastKnownLng") as Float or Null;

        // Guard: skip if no location available
        if (lat == null || lng == null) {
            Background.exit(null);
            return;
        }

        _lat = lat;
        _lng = lng;

        // Check weather source setting — only fetch OWM if WeatherSource=1
        var weatherSource = Application.Properties.getValue("WeatherSource");
        var owmNeeded = false;
        if (weatherSource != null && weatherSource == 1) {
            var apiKey = Application.Properties.getValue("OWMApiKey") as String or Null;
            if (apiKey != null && !apiKey.equals("")) {
                owmNeeded = true;
            }
        }

        // Check if tide refresh is needed (design §4.2)
        _tideNeeded = isTideRefreshNeeded(lat, lng);

        if (owmNeeded) {
            var apiKey = Application.Properties.getValue("OWMApiKey") as String;

            var units = "metric";
            if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
                units = "imperial";
            }

            var weatherService = new WeatherService(method(:onWeatherComplete));
            weatherService.fetch(lat, lng, apiKey, units);
        } else if (_tideNeeded) {
            // Only tide needed
            startTideFetch();
        } else {
            // Nothing needed
            Background.exit(null);
        }
    }

    // Called when WeatherService completes — chains into tide fetch if needed
    function onWeatherComplete(weatherData as Dictionary or Null) as Void {
        _weatherResult = weatherData;

        if (_tideNeeded) {
            startTideFetch();
        } else {
            exitWithResults();
        }
    }

    // Called when TideService completes — exits with both results
    function onTideComplete(tideData as Array or Null) as Void {
        if (tideData != null) {
            // Write tide fetch metadata to Application.Storage
            var today = todayUTC();
            Application.Storage.setValue("tideFetchedDay", today);
            Application.Storage.setValue("tideFetchLat", _lat);
            Application.Storage.setValue("tideFetchLng", _lng);
            // Clear expired flag since we have fresh data
            Application.Storage.setValue("tideDataExpired", false);
        }

        // Package and exit with both weather and tide results
        var result = {} as Dictionary<String, Application.PropertyValueType>;
        if (_weatherResult != null) {
            result["weather"] = _weatherResult as Application.PropertyValueType;
        }
        if (tideData != null) {
            result["tides"] = tideData as Application.PropertyValueType;
        }

        if (result.size() > 0) {
            Background.exit(result);
        } else {
            Background.exit(null);
        }
    }

    // Start a tide fetch using StormGlass API
    private function startTideFetch() as Void {
        var apiKey = Application.Properties.getValue("StormGlassApiKey") as String or Null;
        if (apiKey == null || apiKey.equals("")) {
            // No StormGlass key — exit with whatever we have
            exitWithResults();
            return;
        }

        var tideService = new TideService(method(:onTideComplete));
        tideService.fetch(_lat, _lng, apiKey);
    }

    // Exit with whatever results we have (weather only, or nothing)
    private function exitWithResults() as Void {
        if (_weatherResult != null) {
            var result = {} as Dictionary<String, Application.PropertyValueType>;
            result["weather"] = _weatherResult as Application.PropertyValueType;
            Background.exit(result);
        } else {
            Background.exit(null);
        }
    }

}
