import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
class SurferWatchFaceDelegate extends System.ServiceDelegate {

    private var _isSurfMode as Boolean;
    private var _lat as Float;
    private var _lng as Float;

    // What needs fetching this cycle
    private var _tideNeeded as Boolean;
    private var _swellNeeded as Boolean;
    private var _windNeeded as Boolean;

    // Accumulated results for Background.exit()
    private var _weatherResult as Dictionary or Null;
    private var _tideResult as Boolean;
    private var _swellResult as Dictionary or Null;

    function initialize() {
        ServiceDelegate.initialize();
        _isSurfMode = false;
        _lat = 0.0f;
        _lng = 0.0f;
        _tideNeeded = false;
        _swellNeeded = false;
        _windNeeded = false;
        _weatherResult = null;
        _tideResult = false;
        _swellResult = null;
    }

    // =========================================================
    // Utility
    // =========================================================

    function distanceBetween(lat1 as Float, lon1 as Float, lat2 as Float, lon2 as Float) as Float {
        var R = 6371000.0f;
        var dLat = (lat2 - lat1) * Math.PI / 180.0f;
        var dLon = (lon2 - lon1) * Math.PI / 180.0f;
        var a = Math.sin(dLat / 2.0f) * Math.sin(dLat / 2.0f) +
                Math.cos(lat1 * Math.PI / 180.0f) * Math.cos(lat2 * Math.PI / 180.0f) *
                Math.sin(dLon / 2.0f) * Math.sin(dLon / 2.0f);
        var c = 2.0f * Math.atan2(Math.sqrt(a), Math.sqrt(1.0f - a));
        return R * c;
    }

    private function todayUTC() as String {
        var now = Time.now();
        var today = Gregorian.info(now, Time.FORMAT_SHORT);
        return today.year.format("%04d") + "-" + today.month.format("%02d") + "-" + today.day.format("%02d");
    }

    private function getStormGlassApiKey() as String or Null {
        // Always try primary key first — TideService handles 402 retry with backup
        var apiKey = Application.Properties.getValue("StormGlassApiKey") as String or Null;
        if (apiKey != null && !apiKey.equals("")) { return apiKey; }
        // If no primary key, try backup as the only key
        var backupKey = Application.Properties.getValue("StormGlassBackupApiKey") as String or Null;
        if (backupKey != null && !backupKey.equals("")) { return backupKey; }
        return null;
    }

    // =========================================================
    // Refresh checks
    // =========================================================

    private function isTideRefreshNeeded(lat as Float, lng as Float) as Boolean {
        var tideFetchedDay = Application.Storage.getValue("tfd") as String or Null;
        var today = todayUTC();
        if (tideFetchedDay == null) { return true; }
        if (!tideFetchedDay.equals(today)) { return true; }
        // Even if fetch day matches, refresh if we have no actual data
        var tideData = Application.Storage.getValue("th");
        if (tideData == null) { return true; }
        var tideFetchLat = Application.Storage.getValue("tfl") as Float or Null;
        var tideFetchLng = Application.Storage.getValue("tfn") as Float or Null;
        if (tideFetchLat != null && tideFetchLng != null) {
            if (distanceBetween(lat, lng, tideFetchLat, tideFetchLng) > 50000.0f) { return true; }
        }
        var tideDataExpired = Application.Storage.getValue("tde");
        if (tideDataExpired != null && tideDataExpired == true) { return true; }
        return false;
    }

    private function isSurfTideRefreshNeeded(lat as Float, lng as Float) as Boolean {
        var tideFetchedDay = Application.Storage.getValue("std") as String or Null;
        var today = todayUTC();
        if (tideFetchedDay == null) { return true; }
        if (!tideFetchedDay.equals(today)) { return true; }
        var surfTideData = Application.Storage.getValue("sth");
        if (surfTideData == null) { return true; }
        var tideFetchLat = Application.Storage.getValue("stl") as Float or Null;
        var tideFetchLng = Application.Storage.getValue("stn") as Float or Null;
        if (tideFetchLat == null || tideFetchLng == null) { return true; }
        if (tideFetchLat != lat || tideFetchLng != lng) { return true; }
        var tideDataExpired = Application.Storage.getValue("ste");
        if (tideDataExpired != null && tideDataExpired == true) { return true; }
        return false;
    }

    // =========================================================
    // onTemporalEvent — entry point
    // Shore mode: OWM weather → SG tide
    // Surf mode:  Open-Meteo swell → SG tide → OWM wind
    // =========================================================

    function onTemporalEvent() as Void {
        // Clear previous cycle's response code
        Application.Storage.setValue("src", 0);

        // Check BT directly from device settings (no Storage needed)
        var settings = System.getDeviceSettings();
        if (!settings.phoneConnected) {
            Background.exit(null);
            return;
        }

        var surfMode = Application.Properties.getValue("SurfMode");
        _isSurfMode = (surfMode != null && surfMode == 1);

        if (_isSurfMode) {
            var surfLat = Application.Properties.getValue("SurfSpotLat");
            var surfLng = Application.Properties.getValue("SurfSpotLng");
            if (surfLat == null || surfLng == null) { Background.exit(null); return; }
            _lat = surfLat.toFloat();
            _lng = surfLng.toFloat();
            if (_lat == 0.0 && _lng == 0.0) { Background.exit(null); return; }
        } else {
            // Read GPS directly from OS cache (no Storage relay needed)
            var posInfo = Position.getInfo();
            if (posInfo != null && posInfo.accuracy != Position.QUALITY_NOT_AVAILABLE && posInfo.position != null) {
                var coords = posInfo.position.toDegrees();
                _lat = coords[0].toFloat();
                _lng = coords[1].toFloat();
            } else {
                Background.exit(null);
                return;
            }
        }

        if (_isSurfMode) {
            _swellNeeded = true; // Open-Meteo is free, always fetch fresh swell
            _tideNeeded = isSurfTideRefreshNeeded(_lat, _lng);
            var weatherSource = Application.Properties.getValue("WeatherSource");
            if (weatherSource != null && weatherSource == 1) {
                // Open-Meteo: always fetch wind (free, no key)
                _windNeeded = true;
            } else if (weatherSource != null && weatherSource == 2) {
                // OWM: needs API key
                var owmKey = Application.Properties.getValue("OWMApiKey") as String or Null;
                _windNeeded = (owmKey != null && !owmKey.equals(""));
            } else {
                // Garmin: no wind for surf spot
                _windNeeded = false;
            }

            // Surf chain: swell → tide → wind
            if (_swellNeeded) {
                startSwellFetch();
            } else if (_tideNeeded) {
                startTideFetch();
            } else if (_windNeeded) {
                startWindFetch();
            } else {
                Background.exit(null);
            }
        } else {
            // Shore mode: weather → tide
            _tideNeeded = isTideRefreshNeeded(_lat, _lng);
            _swellNeeded = false;
            _windNeeded = false;

            var weatherNeeded = false;
            var weatherSource = Application.Properties.getValue("WeatherSource");
            if (weatherSource != null && weatherSource == 1) {
                weatherNeeded = true;
            } else if (weatherSource != null && weatherSource == 2) {
                var apiKey = Application.Properties.getValue("OWMApiKey") as String or Null;
                if (apiKey != null && !apiKey.equals("")) { weatherNeeded = true; }
            }

            if (weatherNeeded) {
                startShoreWeatherFetch();
            } else if (_tideNeeded) {
                startTideFetch();
            } else {
                Background.exit(null);
            }
        }
    }

    // =========================================================
    // Fetch starters
    // =========================================================

    private function startSwellFetch() as Void {
        var oms = new OpenMeteoService(method(:onShoreWeatherDone));
        oms.fetchSwell(_lat, _lng, method(:onSwellDone));
    }

    private function startTideFetch() as Void {
        var apiKey = getStormGlassApiKey();
        if (apiKey == null) { chainAfterTide(); return; }
        var ts = new TideService(method(:onTideComplete));
        ts.fetch(_lat, _lng, apiKey);
    }

    private function startWindFetch() as Void {
        var weatherSource = Application.Properties.getValue("WeatherSource");
        if (weatherSource != null && weatherSource == 1) {
            // Open-Meteo: fetch 24h hourly wind forecast for surf spot
            var oms = new OpenMeteoService(method(:onWindDone));
            oms.fetchSurfWind(_lat, _lng, method(:onSurfWindForecastDone));
        } else {
            // OWM: fetch current wind
            var apiKey = Application.Properties.getValue("OWMApiKey") as String or Null;
            if (apiKey == null || apiKey.equals("")) { exitWithAllResults(); return; }
            var units = "metric";
            if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) { units = "imperial"; }
            var ws = new WeatherService(method(:onWindDone));
            ws.fetch(_lat, _lng, apiKey, units);
        }
    }

    // Shore mode: weather fetch (Open-Meteo or OWM), chains to tide
    private function startShoreWeatherFetch() as Void {
        var weatherSource = Application.Properties.getValue("WeatherSource");
        if (weatherSource != null && weatherSource == 1) {
            // Open-Meteo: no key needed
            var oms = new OpenMeteoService(method(:onShoreWeatherDone));
            oms.fetchCurrent(_lat, _lng);
        } else {
            // OWM
            var apiKey = Application.Properties.getValue("OWMApiKey") as String or Null;
            if (apiKey == null || apiKey.equals("")) {
                if (_tideNeeded) { startTideFetch(); } else { exitWithAllResults(); }
                return;
            }
            var units = "metric";
            if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) { units = "imperial"; }
            var ws = new WeatherService(method(:onShoreWeatherDone));
            ws.fetch(_lat, _lng, apiKey, units);
        }
    }

    // =========================================================
    // Callbacks — each writes to Storage, then chains to next
    // =========================================================

    // Swell done — receives dict of flat arrays from Open-Meteo
    function onSwellDone(swellData as Dictionary or Null) as Void {
        if (swellData != null) {
            // Store flat arrays directly — no conversion needed
            Application.Storage.setValue("ssh", swellData["heights"]);
            Application.Storage.setValue("ssp", swellData["periods"]);
            Application.Storage.setValue("ssd", swellData["directions"]);
            Application.Storage.setValue("sst", swellData["seaSurfaceTemps"]);

            // Extract current hour for immediate display
            var heights = swellData["heights"] as Array;
            var periods = swellData["periods"] as Array;
            var dirs = swellData["directions"] as Array;
            if (heights != null && heights.size() > 0) {
                var nowHour = Gregorian.info(Time.now(), Time.FORMAT_SHORT).hour;
                var idx = nowHour < heights.size() ? nowHour : heights.size() - 1;
                var current = {} as Dictionary<String, Application.PropertyValueType>;
                current["swellHeight"] = heights[idx] as Application.PropertyValueType;
                current["swellPeriod"] = (idx < periods.size()) ? periods[idx] as Application.PropertyValueType : null;
                current["swellDirection"] = (idx < dirs.size()) ? dirs[idx] as Application.PropertyValueType : null;
                // Sea surface temp for current hour
                var sst = swellData["seaSurfaceTemps"] as Array or Null;
                if (sst != null && idx < sst.size()) {
                    current["seaSurfaceTemp"] = sst[idx] as Application.PropertyValueType;
                }
                _swellResult = current;
            }
        }
        chainAfterSwell();
    }

    private function chainAfterSwell() as Void {
        if (_tideNeeded) {
            startTideFetch();
        } else if (_windNeeded) {
            startWindFetch();
        } else {
            exitWithAllResults();
        }
    }

    // Tide done → chain to wind (surf) or exit (shore)
    function onTideComplete(tideData as Dictionary or Null) as Void {
        if (tideData != null) {
            if (_isSurfMode) {
                Application.Storage.setValue("sth", tideData["heights"]);
                Application.Storage.setValue("stt", tideData["times"]);
                Application.Storage.setValue("sty", tideData["types"]);
                Application.Storage.setValue("std", todayUTC());
                Application.Storage.setValue("stl", _lat);
                Application.Storage.setValue("stn", _lng);
                Application.Storage.setValue("ste", false);
            } else {
                Application.Storage.setValue("th", tideData["heights"]);
                Application.Storage.setValue("tt", tideData["times"]);
                Application.Storage.setValue("tp", tideData["types"]);
                Application.Storage.setValue("tfd", todayUTC());
                Application.Storage.setValue("tfl", _lat);
                Application.Storage.setValue("tfn", _lng);
                Application.Storage.setValue("tde", false);
            }
            _tideResult = true;
        }
        var lastCode = Application.Storage.getValue("src") as Number or Null;
        if (lastCode != null && lastCode == -403) {
            exitWithAllResults();
            return;
        }
        chainAfterTide();
    }

    private function chainAfterTide() as Void {
        if (_isSurfMode && _windNeeded) {
            startWindFetch();
        } else {
            exitWithAllResults();
        }
    }

    // Wind/weather done → exit (surf mode OWM, last in chain)
    function onWindDone(weatherData as Dictionary or Null) as Void {
        if (weatherData != null) {
            // In surf mode, extract wind + sunrise/sunset — don't pollute shore weather fields
            var windResult = {} as Dictionary<String, Application.PropertyValueType>;
            windResult["windSpeed"] = weatherData["windSpeed"] as Application.PropertyValueType;
            windResult["windDeg"] = weatherData["windDeg"] as Application.PropertyValueType;
            // OWM response includes sunrise/sunset — pass them for surf spot
            if (weatherData["sunrise"] != null) { windResult["surfSunrise"] = weatherData["sunrise"] as Application.PropertyValueType; }
            if (weatherData["sunset"] != null) { windResult["surfSunset"] = weatherData["sunset"] as Application.PropertyValueType; }
            _weatherResult = windResult;
        }
        exitWithAllResults();
    }

    // Surf wind forecast done (Open-Meteo hourly) → stores arrays, extracts current hour, exits
    function onSurfWindForecastDone(windData as Dictionary or Null) as Void {
        if (windData != null) {
            // Store 24h forecast arrays for offline advancement
            Application.Storage.setValue("sws", windData["speeds"]);
            Application.Storage.setValue("swd", windData["directions"]);

            // Extract current hour for immediate display
            var speeds = windData["speeds"] as Array;
            var dirs = windData["directions"] as Array;
            if (speeds != null && speeds.size() > 0) {
                var nowHour = Gregorian.info(Time.now(), Time.FORMAT_SHORT).hour;
                var idx = nowHour < speeds.size() ? nowHour : speeds.size() - 1;
                var windResult = {} as Dictionary<String, Application.PropertyValueType>;
                windResult["windSpeed"] = speeds[idx] as Application.PropertyValueType;
                windResult["windDeg"] = (idx < dirs.size()) ? dirs[idx] as Application.PropertyValueType : null;
                // Include sunrise/sunset for surf spot if available
                if (windData["sunrise"] != null) { windResult["surfSunrise"] = windData["sunrise"] as Application.PropertyValueType; }
                if (windData["sunset"] != null) { windResult["surfSunset"] = windData["sunset"] as Application.PropertyValueType; }
                _weatherResult = windResult;
            }
        }
        exitWithAllResults();
    }

    // Shore weather done → chain to tide
    function onShoreWeatherDone(weatherData as Dictionary or Null) as Void {
        _weatherResult = weatherData;
        if (_tideNeeded) {
            startTideFetch();
        } else {
            exitWithAllResults();
        }
    }

    // =========================================================
    // Exit with all accumulated results
    // =========================================================

    private function exitWithAllResults() as Void {
        var result = {} as Dictionary<String, Application.PropertyValueType>;
        if (_weatherResult != null) {
            result["weather"] = _weatherResult as Application.PropertyValueType;
        }
        if (_tideResult) {
            // Tide data already written to Storage — just signal foreground to reload
            result["tu"] = true as Application.PropertyValueType;
        }
        if (_swellResult != null) {
            result["swell"] = _swellResult as Application.PropertyValueType;
        }
        if (result.size() > 0) {
            Background.exit(result);
        } else {
            Background.exit(null);
        }
    }

}
