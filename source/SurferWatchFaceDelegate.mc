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
    // Track whether swell fetch is needed this cycle (surf mode only)
    private var _swellNeeded as Boolean;
    // Track surf mode for this cycle
    private var _isSurfMode as Boolean;
    // Current position for this cycle
    private var _lat as Float;
    private var _lng as Float;
    // Swell result holder
    private var _swellResult as Dictionary or Null;

    function initialize() {
        ServiceDelegate.initialize();
        _weatherResult = null;
        _tideNeeded = false;
        _swellNeeded = false;
        _isSurfMode = false;
        _lat = 0.0f;
        _lng = 0.0f;
        _swellResult = null;
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

    // Determine if StormGlass swell refresh is needed (surf mode only)
    private function isSwellRefreshNeeded() as Boolean {
        var swellFetchedDay = Application.Storage.getValue("surf_swellFetchedDay") as String or Null;
        var today = todayUTC();

        // Never fetched
        if (swellFetchedDay == null) { return true; }
        // New calendar day
        if (!swellFetchedDay.equals(today)) { return true; }

        // No actual swell data cached (fetch day was written but data wasn't)
        var cachedHeight = Application.Storage.getValue("surf_swellHeight");
        if (cachedHeight == null) { return true; }

        // Settings location changed
        var swellFetchLat = Application.Storage.getValue("surf_swellFetchLat") as Float or Null;
        var swellFetchLng = Application.Storage.getValue("surf_swellFetchLng") as Float or Null;
        if (swellFetchLat == null || swellFetchLng == null) { return true; }
        if (swellFetchLat != _lat || swellFetchLng != _lng) { return true; }

        return false;
    }

    // Determine if surf-mode tide refresh is needed (uses surf_ prefixed keys)
    private function isSurfTideRefreshNeeded(lat as Float, lng as Float) as Boolean {
        var tideFetchedDay = Application.Storage.getValue("surf_tideFetchedDay") as String or Null;
        var today = todayUTC();

        // Never fetched
        if (tideFetchedDay == null) { return true; }
        // New calendar day
        if (!tideFetchedDay.equals(today)) { return true; }

        // Settings location changed (any change, no distance threshold)
        var tideFetchLat = Application.Storage.getValue("surf_tideFetchLat") as Float or Null;
        var tideFetchLng = Application.Storage.getValue("surf_tideFetchLng") as Float or Null;
        if (tideFetchLat == null || tideFetchLng == null) { return true; }
        if (tideFetchLat != lat || tideFetchLng != lng) { return true; }

        // Tide data expired
        var tideDataExpired = Application.Storage.getValue("surf_tideDataExpired");
        if (tideDataExpired != null && tideDataExpired == true) { return true; }

        return false;
    }

    function onTemporalEvent() as Void {
        // Guard: skip if no phone connection
        var btConnected = Application.Storage.getValue("bluetoothConnected");
        if (btConnected == null || btConnected == false) {
            Background.exit(null);
            return;
        }

        // Determine mode and coordinates
        var surfMode = Application.Properties.getValue("SurfMode");
        _isSurfMode = (surfMode != null && surfMode == 1);

        if (_isSurfMode) {
            // Surf mode: use surf spot coordinates
            var surfLat = Application.Properties.getValue("SurfSpotLat");
            var surfLng = Application.Properties.getValue("SurfSpotLng");
            if (surfLat == null || surfLng == null) {
                Background.exit(null);
                return;
            }
            var lat = surfLat.toFloat();
            var lng = surfLng.toFloat();
            if (lat == 0.0 && lng == 0.0) {
                Background.exit(null);
                return;
            }
            _lat = lat;
            _lng = lng;
        } else {
            // Shore mode: use current GPS
            var lat = Application.Storage.getValue("lastKnownLat") as Float or Null;
            var lng = Application.Storage.getValue("lastKnownLng") as Float or Null;
            if (lat == null || lng == null) {
                Background.exit(null);
                return;
            }
            _lat = lat;
            _lng = lng;
        }

        // Check what needs fetching
        var owmNeeded = false;
        if (!_isSurfMode) {
            var weatherSource = Application.Properties.getValue("WeatherSource");
            if (weatherSource != null && weatherSource == 1) {
                var apiKey = Application.Properties.getValue("OWMApiKey") as String or Null;
                if (apiKey != null && !apiKey.equals("")) {
                    owmNeeded = true;
                }
            }
        }

        if (_isSurfMode) {
            _tideNeeded = isSurfTideRefreshNeeded(_lat, _lng);
            _swellNeeded = isSwellRefreshNeeded();
            System.println("SURF: tideNeeded=" + _tideNeeded + " swellNeeded=" + _swellNeeded + " lat=" + _lat + " lng=" + _lng);
        } else {
            _tideNeeded = isTideRefreshNeeded(_lat, _lng);
            _swellNeeded = false;
        }

        if (owmNeeded) {
            var apiKey = Application.Properties.getValue("OWMApiKey") as String;
            var units = "metric";
            if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
                units = "imperial";
            }
            var weatherService = new WeatherService(method(:onWeatherComplete));
            weatherService.fetch(_lat, _lng, apiKey, units);
        } else if (_tideNeeded) {
            startTideFetch();
        } else if (_swellNeeded) {
            startSwellFetch();
        } else {
            Background.exit(null);
        }
    }

    // Called when WeatherService completes — chains into tide fetch if needed
    function onWeatherComplete(weatherData as Dictionary or Null) as Void {
        _weatherResult = weatherData;

        if (_tideNeeded) {
            startTideFetch();
        } else if (_swellNeeded) {
            startSwellFetch();
        } else {
            exitWithResults();
        }
    }

    // Called when TideService completes — chains into swell if needed, then exits
    function onTideComplete(tideData as Array or Null) as Void {
        if (tideData != null) {
            var today = todayUTC();
            var prefix = _isSurfMode ? "surf_" : "";
            Application.Storage.setValue(prefix + "tideFetchedDay", today);
            Application.Storage.setValue(prefix + "tideFetchLat", _lat);
            Application.Storage.setValue(prefix + "tideFetchLng", _lng);
            Application.Storage.setValue(prefix + "tideDataExpired", false);
            Application.Storage.setValue("sgPrimaryFailed", false);
            if (_isSurfMode) {
                Application.Storage.setValue("surf_tideExtremes", tideData);
            }
        } else {
            // Primary key failed — mark it so next cycle uses backup
            Application.Storage.setValue("sgPrimaryFailed", true);
            System.println("TIDE: primary key failed, marked for backup next cycle");
        }

        if (_swellNeeded) {
            startSwellFetch();
        } else {
            // Package and exit
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
    }

    // Called when swell fetch completes — exits with all results
    function onSwellComplete(swellData as Dictionary or Null) as Void {
        _swellResult = swellData;
        System.println("SWELL: onSwellComplete data=" + (swellData != null ? "received" : "null"));

        if (swellData == null) {
            // Primary key failed — mark it so next cycle uses backup
            Application.Storage.setValue("sgPrimaryFailed", true);
            System.println("SWELL: primary key failed, marked for backup next cycle");
        }

        // Only mark as fetched when we got real data
        if (swellData != null) {
            var prefix = _isSurfMode ? "surf_" : "";
            Application.Storage.setValue(prefix + "swellFetchedDay", todayUTC());
            Application.Storage.setValue(prefix + "swellFetchLat", _lat);
            Application.Storage.setValue(prefix + "swellFetchLng", _lng);
            Application.Storage.setValue("sgPrimaryFailed", false);
        }

        var result = {} as Dictionary<String, Application.PropertyValueType>;
        if (_weatherResult != null) {
            result["weather"] = _weatherResult as Application.PropertyValueType;
        }
        // Include tide data if it was fetched this cycle (stored in surf_ keys)
        if (_isSurfMode) {
            var surfTides = Application.Storage.getValue("surf_tideExtremes");
            if (surfTides != null) {
                result["tides"] = surfTides as Application.PropertyValueType;
            }
        }
        if (swellData != null) {
            result["swell"] = swellData as Application.PropertyValueType;
        }
        if (result.size() > 0) {
            Background.exit(result);
        } else {
            Background.exit(null);
        }
    }

    // Get the active StormGlass API key
    // If primary failed last time (stored flag), try backup first
    private function getStormGlassApiKey() as String or Null {
        var primaryFailed = Application.Storage.getValue("sgPrimaryFailed");
        var apiKey = Application.Properties.getValue("StormGlassApiKey") as String or Null;
        var backupKey = Application.Properties.getValue("StormGlassBackupApiKey") as String or Null;

        if (primaryFailed != null && primaryFailed == true) {
            // Try backup first
            if (backupKey != null && !backupKey.equals("")) {
                return backupKey;
            }
        }
        if (apiKey != null && !apiKey.equals("")) {
            return apiKey;
        }
        if (backupKey != null && !backupKey.equals("")) {
            return backupKey;
        }
        return null;
    }

    // Start a swell fetch using StormGlass weather endpoint
    private function startSwellFetch() as Void {
        var apiKey = getStormGlassApiKey();
        System.println("SWELL: startSwellFetch apiKey=" + (apiKey != null ? "set" : "null"));
        if (apiKey == null) {
            exitWithResults();
            return;
        }

        var tideService = new TideService(method(:onTideComplete));
        tideService.fetchSwell(_lat, _lng, apiKey, method(:onSwellComplete));
    }

    // Start a tide fetch using StormGlass API
    private function startTideFetch() as Void {
        var apiKey = getStormGlassApiKey();
        if (apiKey == null) {
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
