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

    private var _isSurfMode as Boolean;
    private var _lat as Float;
    private var _lng as Float;

    // What needs fetching this cycle
    private var _tideNeeded as Boolean;
    private var _swellNeeded as Boolean;
    private var _windNeeded as Boolean;

    // Accumulated results for Background.exit()
    private var _weatherResult as Dictionary or Null;
    private var _tideResult as Array or Null;
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
        _tideResult = null;
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
        var apiKey = Application.Properties.getValue("StormGlassApiKey") as String or Null;
        if (apiKey != null && !apiKey.equals("")) { return apiKey; }
        var backupKey = Application.Properties.getValue("StormGlassBackupApiKey") as String or Null;
        if (backupKey != null && !backupKey.equals("")) { return backupKey; }
        return null;
    }

    private function getStormGlassBackupKey() as String or Null {
        var backupKey = Application.Properties.getValue("StormGlassBackupApiKey") as String or Null;
        if (backupKey != null && !backupKey.equals("")) { return backupKey; }
        return null;
    }

    // =========================================================
    // Refresh checks
    // =========================================================

    private function isTideRefreshNeeded(lat as Float, lng as Float) as Boolean {
        var tideFetchedDay = Application.Storage.getValue("tideFetchedDay") as String or Null;
        var today = todayUTC();
        if (tideFetchedDay == null) { return true; }
        if (!tideFetchedDay.equals(today)) { return true; }
        var tideFetchLat = Application.Storage.getValue("tideFetchLat") as Float or Null;
        var tideFetchLng = Application.Storage.getValue("tideFetchLng") as Float or Null;
        if (tideFetchLat != null && tideFetchLng != null) {
            if (distanceBetween(lat, lng, tideFetchLat, tideFetchLng) > 50000.0f) { return true; }
        }
        var tideDataExpired = Application.Storage.getValue("tideDataExpired");
        if (tideDataExpired != null && tideDataExpired == true) { return true; }
        return false;
    }

    private function isSurfTideRefreshNeeded(lat as Float, lng as Float) as Boolean {
        var tideFetchedDay = Application.Storage.getValue("surf_tideFetchedDay") as String or Null;
        var today = todayUTC();
        if (tideFetchedDay == null) { return true; }
        if (!tideFetchedDay.equals(today)) { return true; }
        var tideFetchLat = Application.Storage.getValue("surf_tideFetchLat") as Float or Null;
        var tideFetchLng = Application.Storage.getValue("surf_tideFetchLng") as Float or Null;
        if (tideFetchLat == null || tideFetchLng == null) { return true; }
        if (tideFetchLat != lat || tideFetchLng != lng) { return true; }
        var tideDataExpired = Application.Storage.getValue("surf_tideDataExpired");
        if (tideDataExpired != null && tideDataExpired == true) { return true; }
        return false;
    }

    private function isSwellRefreshNeeded() as Boolean {        var swellFetchedDay = Application.Storage.getValue("surf_swellFetchedDay") as String or Null;
        var today = todayUTC();
        if (swellFetchedDay == null) { return true; }
        if (!swellFetchedDay.equals(today)) { return true; }
        var cachedHeight = Application.Storage.getValue("surf_swellHeight");
        if (cachedHeight == null) { return true; }
        var swellFetchLat = Application.Storage.getValue("surf_swellFetchLat") as Float or Null;
        var swellFetchLng = Application.Storage.getValue("surf_swellFetchLng") as Float or Null;
        if (swellFetchLat == null || swellFetchLng == null) { return true; }
        if (swellFetchLat != _lat || swellFetchLng != _lng) { return true; }
        return false;
    }

    // =========================================================
    // onTemporalEvent — entry point
    // Shore mode: OWM weather → SG tide
    // Surf mode:  SG swell → SG tide → OWM wind
    // =========================================================

    function onTemporalEvent() as Void {
        var btConnected = Application.Storage.getValue("bluetoothConnected");
        if (btConnected == null || btConnected == false) {
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
            var lat = Application.Storage.getValue("lastKnownLat") as Float or Null;
            var lng = Application.Storage.getValue("lastKnownLng") as Float or Null;
            if (lat == null || lng == null) { Background.exit(null); return; }
            _lat = lat;
            _lng = lng;
        }

        if (_isSurfMode) {
            _swellNeeded = isSwellRefreshNeeded();
            _tideNeeded = isSurfTideRefreshNeeded(_lat, _lng);
            var owmKey = Application.Properties.getValue("OWMApiKey") as String or Null;
            _windNeeded = (owmKey != null && !owmKey.equals(""));
            System.println("SURF: swellNeeded=" + _swellNeeded + " tideNeeded=" + _tideNeeded + " windNeeded=" + _windNeeded);

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
            // Shore mode: OWM weather → tide
            _tideNeeded = isTideRefreshNeeded(_lat, _lng);
            _swellNeeded = false;
            _windNeeded = false;

            var owmNeeded = false;
            var weatherSource = Application.Properties.getValue("WeatherSource");
            if (weatherSource != null && weatherSource == 1) {
                var apiKey = Application.Properties.getValue("OWMApiKey") as String or Null;
                if (apiKey != null && !apiKey.equals("")) { owmNeeded = true; }
            }

            if (owmNeeded) {
                startWindFetch(); // reuse same OWM fetch for shore weather
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
        var apiKey = getStormGlassApiKey();
        System.println("SWELL: startSwellFetch key=" + (apiKey != null ? "set" : "null"));
        if (apiKey == null) { chainAfterSwell(); return; }
        var ts = new TideService(method(:onTideComplete));
        ts.fetchSwell(_lat, _lng, apiKey, method(:onSwellDone));
    }

    private function startTideFetch() as Void {
        var apiKey = getStormGlassApiKey();
        System.println("TIDE: startTideFetch key=" + (apiKey != null ? "set" : "null"));
        if (apiKey == null) { chainAfterTide(); return; }
        var ts = new TideService(method(:onTideComplete));
        ts.fetch(_lat, _lng, apiKey);
    }

    private function startWindFetch() as Void {
        var apiKey = Application.Properties.getValue("OWMApiKey") as String or Null;
        System.println("WIND: startWindFetch key=" + (apiKey != null ? "set" : "null"));
        if (apiKey == null || apiKey.equals("")) { exitWithAllResults(); return; }
        var units = "metric";
        if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) { units = "imperial"; }
        var ws = new WeatherService(method(:onWindDone));
        ws.fetch(_lat, _lng, apiKey, units);
    }

    // =========================================================
    // Callbacks — each writes to Storage, then chains to next
    // =========================================================

    // Swell done → chain to tide → wind
    function onSwellDone(swellData as Dictionary or Null) as Void {
        System.println("SWELL: done data=" + (swellData != null ? "received" : "null"));
        if (swellData != null) {
            _swellResult = swellData;
            var prefix = "surf_";
            Application.Storage.setValue(prefix + "swellFetchedDay", todayUTC());
            Application.Storage.setValue(prefix + "swellFetchLat", _lat);
            Application.Storage.setValue(prefix + "swellFetchLng", _lng);
        }
        // Check if we got -403 (out of memory) — stop chaining, exit now
        var lastCode = Application.Storage.getValue("sgLastResponseCode") as Number or Null;
        if (lastCode != null && lastCode == -403) {
            System.println("SWELL: -403 memory exhausted, exiting cycle");
            exitWithAllResults();
            return;
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
    function onTideComplete(tideData as Array or Null) as Void {
        System.println("TIDE: done data=" + (tideData != null ? "received" : "null"));
        if (tideData != null) {
            _tideResult = tideData;
            var prefix = _isSurfMode ? "surf_" : "";
            Application.Storage.setValue(prefix + "tideFetchedDay", todayUTC());
            Application.Storage.setValue(prefix + "tideFetchLat", _lat);
            Application.Storage.setValue(prefix + "tideFetchLng", _lng);
            Application.Storage.setValue(prefix + "tideDataExpired", false);
            if (_isSurfMode) {
                Application.Storage.setValue("surf_tideExtremes", tideData);
            }
        }
        var lastCode = Application.Storage.getValue("sgLastResponseCode") as Number or Null;
        if (lastCode != null && lastCode == -403) {
            System.println("TIDE: -403 memory exhausted, exiting cycle");
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

    // Wind/weather done → exit
    function onWindDone(weatherData as Dictionary or Null) as Void {
        System.println("WIND: done data=" + (weatherData != null ? "received" : "null"));
        _weatherResult = weatherData;
        exitWithAllResults();
    }

    // =========================================================
    // Exit with all accumulated results
    // =========================================================

    private function exitWithAllResults() as Void {
        var result = {} as Dictionary<String, Application.PropertyValueType>;
        if (_weatherResult != null) {
            result["weather"] = _weatherResult as Application.PropertyValueType;
        }
        if (_tideResult != null) {
            result["tides"] = _tideResult as Application.PropertyValueType;
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
