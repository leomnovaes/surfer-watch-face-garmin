import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

class DataManager {

    // --- Cached weather data (from OWM or Open-Meteo, received via onBackgroundData) ---
    var temperature as Float or Null;
    var weatherConditionId as Number or Null;
    var windSpeed as Float or Null;
    var windDeg as Number or Null;
    var sunrise as Number or Null;
    var sunset as Number or Null;
    var moonPhase as Float or Null;
    var owmFetchedAt as Number or Null;
    var precipProbability as Number or Null;
    var isDay as Number or Null;

    // --- Cached tide data (from StormGlass, received via onBackgroundData) ---
    var tideExtremes as Array or Null;
    var tideFetchedDay as String or Null;

    // --- Computed from tideExtremes on each onUpdate() ---
    var nextTideTime as Number or Null;
    var nextTideType as String or Null;
    var currentTideHeight as Float or Null;

    // --- Device/sensor data (updated each onUpdate()) ---
    var heartRate as Number or Null;
    var stress as Number or Null;
    var battery as Number;
    var notificationCount as Number;
    var bluetoothConnected as Boolean;
    var lastKnownLat as Float or Null;
    var lastKnownLng as Float or Null;

    // --- Surf mode: swell data (from Open-Meteo Marine API) ---
    var swellHeight as Float or Null;
    var swellPeriod as Float or Null;
    var swellDirection as Number or Null;
    var surfWindSpeed as Float or Null;
    var surfWindDeg as Number or Null;

    // --- Surf mode: sunrise/sunset (computed from surf spot coordinates) ---
    var surfSunrise as Number or Null;
    var surfSunset as Number or Null;

    // --- Surf mode: cached forecast arrays (loaded from Storage on data change, not every tick) ---
    private var _swellHeightsCache as Array or Null;
    private var _swellPeriodsCache as Array or Null;
    private var _swellDirectionsCache as Array or Null;
    private var _windSpeedsCache as Array or Null;
    private var _windDirectionsCache as Array or Null;

    // --- Surf mode: sensor data ---
    var waterTemp as Float or Null;
    var solarIntensity as Number or Null;

    // --- Surf mode: interpolated tide ---
    var interpTideHeight as Float or Null;

    // --- Surf mode: pre-extracted tide curve data (computed once on data change) ---
    var tideCurveTimes as Array or Null;
    var tideCurveHeights as Array or Null;
    var tideCurveMinH as Float;
    var tideCurveMaxH as Float;
    var tideCurveHRange as Float;

    // --- Surf mode: UI state ---
    var bottomToggleState as Number;

    // --- Storage write tracking (avoid flash I/O every tick) ---
    private var _prevStoredLat as Float or Null;
    private var _prevStoredLng as Float or Null;
    private var _prevStoredBt as Boolean;
    private var _tideExpiredWritten as Boolean;

    function initialize() {
        // Initialize sensor defaults
        battery = 0;
        notificationCount = 0;
        bluetoothConnected = false;
        bottomToggleState = 0;
        _prevStoredLat = null;
        _prevStoredLng = null;
        _prevStoredBt = false;
        _tideExpiredWritten = false;
        tideCurveMinH = 0.0;
        tideCurveMaxH = 1.0;
        tideCurveHRange = 1.0;

        // Load persisted data from Application.Storage
        loadTideData();
        loadWeatherData();
        extractTideCurveData();
    }

    // =========================================================
    // updateSensorData() — called from onUpdate() each tick
    // Reads HR, battery, notifications, BT status, GPS
    // Writes lat/lng/BT to Application.Storage for background
    // =========================================================
    function updateSensorData() as Void {
        // Heart rate
        var activityInfo = Activity.getActivityInfo();
        if (activityInfo != null) {
            heartRate = activityInfo.currentHeartRate;
        } else {
            heartRate = null;
        }

        // Stress (from SensorHistory, updates every ~3 min)
        if (SensorHistory has :getStressHistory) {
            var stressIter = SensorHistory.getStressHistory({:period => 1});
            if (stressIter != null) {
                var sample = stressIter.next();
                if (sample != null && sample.data != null) {
                    var val = sample.data;
                    if (val >= 0 && val <= 100) {
                        stress = val.toNumber();
                    } else {
                        stress = null;
                    }
                } else {
                    stress = null;
                }
            } else {
                stress = null;
            }
        } else {
            stress = null;
        }

        // Battery
        var stats = System.getSystemStats();
        battery = stats.battery.toNumber();

        // Notifications and Bluetooth
        var settings = System.getDeviceSettings();
        notificationCount = settings.notificationCount;
        bluetoothConnected = settings.phoneConnected;

        // GPS — try Position.getInfo(), fall back to HomeLat/HomeLng from settings
        var posInfo = Position.getInfo();
        if (posInfo != null && posInfo.accuracy != Position.QUALITY_NOT_AVAILABLE && posInfo.position != null) {
            var coords = posInfo.position.toDegrees();
            lastKnownLat = coords[0].toFloat();
            lastKnownLng = coords[1].toFloat();
        } else {
            // Fall back to HomeLat/HomeLng from app settings
            var homeLat = Application.Properties.getValue("HomeLat");
            var homeLng = Application.Properties.getValue("HomeLng");
            if (homeLat != null && homeLng != null) {
                var lat = homeLat.toFloat();
                var lng = homeLng.toFloat();
                // Treat 0.0 as "not configured"
                if (lat != 0.0 || lng != 0.0) {
                    lastKnownLat = lat;
                    lastKnownLng = lng;
                } else {
                    lastKnownLat = null;
                    lastKnownLng = null;
                }
            } else {
                lastKnownLat = null;
                lastKnownLng = null;
            }
        }

        // Write shared state to Application.Storage for background process
        // Only write when values actually change to avoid flash I/O every tick
        if (lastKnownLat != _prevStoredLat || lastKnownLng != _prevStoredLng) {
            Application.Storage.setValue("lastKnownLat", lastKnownLat);
            Application.Storage.setValue("lastKnownLng", lastKnownLng);
            _prevStoredLat = lastKnownLat;
            _prevStoredLng = lastKnownLng;
        }
        if (bluetoothConnected != _prevStoredBt) {
            Application.Storage.setValue("bluetoothConnected", bluetoothConnected);
            _prevStoredBt = bluetoothConnected;
        }
    }

    // =========================================================
    // refreshGarminWeatherData() — called when background event
    // completes or settings change. For Garmin mode, reads
    // Weather.getCurrentConditions() and computes sunrise/sunset,
    // then flows through onWeatherData() / onSurfWindData() —
    // same path as API sources. No special-casing.
    // =========================================================
    function refreshGarminWeatherData() as Void {
        var weatherSource = Application.Properties.getValue("WeatherSource");
        if (weatherSource != null && weatherSource != 0) { return; } // Not Garmin mode

        var surfMode = Application.Properties.getValue("SurfMode");
        if (surfMode != null && surfMode == 1) {
            // Surf mode + Garmin: compute surf sunrise/sunset, pass through onSurfWindData
            // (no wind available from Garmin for remote surf spot)
            computeSurfSunriseSunset();
        } else {
            // Shore mode + Garmin: build weather dict from built-in, pass through onWeatherData
            var weatherDict = {} as Dictionary<String, Application.PropertyValueType>;
            if (Weather has :getCurrentConditions) {
                var conditions = Weather.getCurrentConditions();
                if (conditions != null) {
                    weatherDict["temp"] = conditions.temperature != null ? conditions.temperature.toFloat() as Application.PropertyValueType : null;
                    weatherDict["conditionId"] = conditions.condition as Application.PropertyValueType;
                    weatherDict["windSpeed"] = conditions.windSpeed != null ? conditions.windSpeed.toFloat() as Application.PropertyValueType : null;
                    weatherDict["windDeg"] = conditions.windBearing != null ? conditions.windBearing.toNumber() as Application.PropertyValueType : null;
                }
            }
            // Compute sunrise/sunset from GPS and include in the same dict
            computeSunriseSunset();
            weatherDict["sunrise"] = sunrise as Application.PropertyValueType;
            weatherDict["sunset"] = sunset as Application.PropertyValueType;
            // Store fetch timestamp
            Application.Storage.setValue("owmFetchedAt", Time.now().value());
            // Flow through the same path as API weather data
            onWeatherData(weatherDict);
        }
    }

    // =========================================================
    // clearWeatherData() — resets all weather fields to null.
    // Called when weather source setting changes to prevent
    // stale data from one source being rendered by the other's
    // condition code mapper.
    // =========================================================
    function clearWeatherData() as Void {
        temperature = null;
        weatherConditionId = null;
        windSpeed = null;
        windDeg = null;
        sunrise = null;
        sunset = null;
        owmFetchedAt = null;
        precipProbability = null;
        isDay = null;
        // Also clear surf wind — source change affects surf mode wind too
        surfWindSpeed = null;
        surfWindDeg = null;
    }

    // =========================================================
    // clearPersistedWeatherData() — removes cached weather from
    // Application.Storage so loadWeatherData() doesn't restore
    // stale data from a different weather source.
    // Also clears surf wind forecast arrays.
    // =========================================================
    function clearPersistedWeatherData() as Void {
        Application.Storage.setValue("cachedTemp", null);
        Application.Storage.setValue("cachedConditionId", null);
        Application.Storage.setValue("cachedWindSpeed", null);
        Application.Storage.setValue("cachedWindDeg", null);
        Application.Storage.setValue("cachedSunrise", null);
        Application.Storage.setValue("cachedSunset", null);
        Application.Storage.setValue("owmFetchedAt", null);
        // Clear surf wind forecast arrays (source-dependent)
        Application.Storage.setValue("surf_windSpeeds", null);
        Application.Storage.setValue("surf_windDirections", null);
    }

    // =========================================================
    // computeSunriseSunset() — calculates sunrise/sunset from
    // lat/lon + current date using simplified solar position.
    // Used when WeatherSource=0 (Garmin) since Weather.getSunrise()
    // requires CIQ 4.1 and we target 3.4.
    // =========================================================
    function computeSunriseSunset() as Void {
        if (lastKnownLat == null || lastKnownLng == null) {
            return;
        }
        var lat = lastKnownLat;
        var lng = lastKnownLng;

        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);

        // Day of year
        var N = dayOfYear(info.year, info.month, info.day);

        // Solar declination (radians)
        var decl = -23.45 * Math.PI / 180.0 * Math.cos(2.0 * Math.PI / 365.0 * (N + 10));

        // Hour angle at sunrise/sunset
        var latRad = lat * Math.PI / 180.0;
        var cosH = -Math.tan(latRad) * Math.tan(decl);

        // Clamp for polar regions
        if (cosH < -1.0) {
            // Midnight sun — no sunset
            sunrise = null;
            sunset = null;
            return;
        }
        if (cosH > 1.0) {
            // Polar night — no sunrise
            sunrise = null;
            sunset = null;
            return;
        }

        var H = Math.acos(cosH) * 180.0 / Math.PI; // hour angle in degrees

        // Solar noon (hours UTC)
        var solarNoon = 12.0 - lng / 15.0;

        var sunriseHour = solarNoon - H / 15.0;
        var sunsetHour = solarNoon + H / 15.0;

        // Convert to unix timestamps for today
        var startOfDay = Gregorian.moment({
            :year => info.year,
            :month => info.month,
            :day => info.day,
            :hour => 0,
            :minute => 0,
            :second => 0
        });
        var dayStart = startOfDay.value();

        sunrise = dayStart + (sunriseHour * 3600).toNumber();
        sunset = dayStart + (sunsetHour * 3600).toNumber();
    }

    // Helper: day of year (1-366)
    private function dayOfYear(year as Number, month as Number, day as Number) as Number {
        var daysInMonth = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) {
            daysInMonth[2] = 29;
        }
        var doy = 0;
        for (var m = 1; m < month; m++) {
            doy += daysInMonth[m];
        }
        return doy + day;
    }

    // =========================================================
    // computeSurfSunriseSunset() — calculates sunrise/sunset from
    // surf spot coordinates + current date. Uses the same solar
    // position algorithm as computeSunriseSunset() but reads from
    // SurfSpotLat/SurfSpotLng settings instead of GPS.
    // Stores in separate surfSunrise/surfSunset fields.
    // =========================================================
    function computeSurfSunriseSunset() as Void {
        var surfLatStr = Application.Properties.getValue("SurfSpotLat");
        var surfLngStr = Application.Properties.getValue("SurfSpotLng");
        if (surfLatStr == null || surfLngStr == null) {
            surfSunrise = null;
            surfSunset = null;
            return;
        }
        var lat = surfLatStr.toFloat();
        var lng = surfLngStr.toFloat();
        if (lat == 0.0 && lng == 0.0) {
            surfSunrise = null;
            surfSunset = null;
            return;
        }

        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var N = dayOfYear(info.year, info.month, info.day);
        var decl = -23.45 * Math.PI / 180.0 * Math.cos(2.0 * Math.PI / 365.0 * (N + 10));
        var latRad = lat * Math.PI / 180.0;
        var cosH = -Math.tan(latRad) * Math.tan(decl);

        if (cosH < -1.0 || cosH > 1.0) {
            surfSunrise = null;
            surfSunset = null;
            return;
        }

        var H = Math.acos(cosH) * 180.0 / Math.PI;
        var solarNoon = 12.0 - lng / 15.0;
        var sunriseHour = solarNoon - H / 15.0;
        var sunsetHour = solarNoon + H / 15.0;

        var startOfDay = Gregorian.moment({
            :year => info.year, :month => info.month, :day => info.day,
            :hour => 0, :minute => 0, :second => 0
        });
        var dayStart = startOfDay.value();

        surfSunrise = dayStart + (sunriseHour * 3600).toNumber();
        surfSunset = dayStart + (sunsetHour * 3600).toNumber();
    }

    // =========================================================
    // onWeatherData(data) — receives parsed weather Dictionary from
    // onBackgroundData(). Works for both OWM and Open-Meteo.
    // OWM keys: temp, conditionId, windSpeed, windDeg, sunrise, sunset
    // Open-Meteo adds: precipProbability, isDay
    // owmFetchedAt is read from Application.Storage (written by
    // WeatherService/OpenMeteoService in the background process).
    // =========================================================
    function onWeatherData(data as Dictionary) as Void {
        temperature = data["temp"] as Float or Null;
        weatherConditionId = data["conditionId"] as Number or Null;
        windSpeed = data["windSpeed"] as Float or Null;
        windDeg = data["windDeg"] as Number or Null;
        sunrise = data["sunrise"] as Number or Null;
        sunset = data["sunset"] as Number or Null;
        precipProbability = data["precipProbability"] as Number or Null;
        isDay = data["isDay"] as Number or Null;
        // Read owmFetchedAt from Storage (written by WeatherService/OpenMeteoService in background)
        owmFetchedAt = Application.Storage.getValue("owmFetchedAt") as Number or Null;
        persistWeatherData();
    }

    // =========================================================
    // onTideData(data) — receives parsed tide Array from
    // onBackgroundData(). Each element is a Dictionary with
    // String keys: "height", "time", "type"
    // =========================================================
    function onTideData(data as Array) as Void {
        tideExtremes = data;
        nextTideTime = null; // Force recomputation with new data
        _tideExpiredWritten = false;
        // Persist to the correct prefixed key based on current mode
        var surfMode = Application.Properties.getValue("SurfMode");
        if (surfMode != null && surfMode == 1) {
            // Surf mode: delegate already wrote to surf_tideExtremes in onTideComplete,
            // but we also clear the surf expired flag
            Application.Storage.setValue("surf_tideDataExpired", false);
        } else {
            // Shore mode: persist to unprefixed keys
            Application.Storage.setValue("tideDataExpired", false);
            persistTideData();
        }
        extractTideCurveData();
    }

    // =========================================================
    // computeNextTide() — walks tideExtremes to find next event
    // after now, sets nextTideTime/nextTideType/nextTideHeight.
    // If all events are in the past, sets tideDataExpired=true
    // in Application.Storage to trigger background refresh.
    // =========================================================
    function computeNextTide() as Void {
        if (tideExtremes == null || tideExtremes.size() == 0) {
            nextTideTime = null;
            nextTideType = null;
            currentTideHeight = null;
            return;
        }

        // Early exit: if we already have a next tide and it's still in the future, skip recomputation
        var now = Time.now().value();
        if (nextTideTime != null && nextTideTime > now) {
            return;
        }
        var nextIdx = -1;

        // Walk array to find first event where time > now
        for (var i = 0; i < tideExtremes.size(); i++) {
            var entry = tideExtremes[i] as Dictionary;
            var entryTime = entry["time"] as Number;
            if (entryTime != null && entryTime > now) {
                nextIdx = i;
                break;
            }
        }

        // If no future events found — all in past, mark expired
        if (nextIdx == -1) {
            nextTideTime = null;
            nextTideType = null;
            currentTideHeight = null;
            if (!_tideExpiredWritten) {
                Application.Storage.setValue("tideDataExpired", true);
                _tideExpiredWritten = true;
            }
            return;
        }

        _tideExpiredWritten = false;

        // Set next tide info — time, type, and predicted height of that event
        var nextEntry = tideExtremes[nextIdx] as Dictionary;
        nextTideTime = nextEntry["time"] as Number;
        nextTideType = nextEntry["type"] as String;
        var nextHeight = nextEntry["height"];
        if (nextHeight != null) {
            currentTideHeight = (nextHeight as Float).toFloat();
        } else {
            currentTideHeight = null;
        }
    }

    // =========================================================
    // computeMoonPhase() — calculates moon phase from current
    // date using synodic period. Returns 0.0–1.0 matching OWM
    // convention: 0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter
    // =========================================================
    function computeMoonPhase() as Void {
        // Known new moon: Jan 6, 2000 18:14 UTC = Unix 947182440
        var knownNewMoon = 947182440;
        var synodicPeriod = 29.53058867;
        var now = Time.now().value();
        var daysSinceNew = (now - knownNewMoon).toFloat() / 86400.0f;
        var cycles = daysSinceNew / synodicPeriod;
        // Phase as 0.0–1.0
        moonPhase = (cycles - cycles.toNumber().toFloat());
        if (moonPhase < 0.0f) { moonPhase = moonPhase + 1.0f; }
    }

    // =========================================================
    // extractTideCurveData() — pre-extracts event times and
    // heights from tideExtremes into flat arrays + computes
    // height range. Called once when tide data changes, not
    // on every render. drawTideCurve() reads these cached arrays.
    // =========================================================
    function extractTideCurveData() as Void {
        if (tideExtremes == null || tideExtremes.size() < 2) {
            tideCurveTimes = null;
            tideCurveHeights = null;
            return;
        }
        var n = tideExtremes.size();
        var times = new [n];
        var heights = new [n];
        var minH = 999.0;
        var maxH = -999.0;
        for (var i = 0; i < n; i++) {
            var entry = tideExtremes[i] as Dictionary;
            var et = entry["time"];
            var eh = entry["height"];
            times[i] = (et != null) ? (et as Number).toFloat() : 0.0;
            heights[i] = (eh != null) ? (eh as Float).toFloat() : 0.0;
            var hf = heights[i];
            if (eh != null) {
                if (hf < minH) { minH = hf; }
                if (hf > maxH) { maxH = hf; }
            }
        }
        if (maxH <= minH) { maxH = minH + 1.0; }
        var hRange = maxH - minH;
        tideCurveMinH = minH - hRange * 0.25;  // TC_HEIGHT_PAD_BOTTOM
        tideCurveMaxH = maxH + hRange * 0.1;   // TC_HEIGHT_PAD
        tideCurveHRange = tideCurveMaxH - tideCurveMinH;
        tideCurveTimes = times;
        tideCurveHeights = heights;
    }

    // =========================================================
    // interpolateTideHeight() — cosine interpolation between
    // surrounding tide extremes for current tide height.
    // Called from onUpdate() when SurfMode=1.
    // =========================================================
    function interpolateTideHeight() as Void {
        if (tideExtremes == null || tideExtremes.size() < 2) {
            interpTideHeight = null;
            return;
        }

        var now = Time.now().value();
        var prevEvent = null;
        var nextEvent = null;

        for (var i = 0; i < tideExtremes.size(); i++) {
            var entry = tideExtremes[i] as Dictionary;
            var entryTime = entry["time"] as Number;
            if (entryTime != null) {
                if (entryTime <= now) {
                    prevEvent = entry;
                } else if (nextEvent == null) {
                    nextEvent = entry;
                }
            }
        }

        if (prevEvent == null && nextEvent != null) {
            interpTideHeight = (nextEvent["height"] as Float).toFloat();
            return;
        }
        if (prevEvent != null && nextEvent == null) {
            interpTideHeight = (prevEvent["height"] as Float).toFloat();
            return;
        }
        if (prevEvent == null || nextEvent == null) {
            interpTideHeight = null;
            return;
        }

        var prevTime = (prevEvent["time"] as Number).toFloat();
        var nextTime = (nextEvent["time"] as Number).toFloat();
        var prevHeight = (prevEvent["height"] as Float).toFloat();
        var nextHeight = (nextEvent["height"] as Float).toFloat();

        var t = (now.toFloat() - prevTime) / (nextTime - prevTime);
        // Cosine interpolation for smooth tide curve
        interpTideHeight = prevHeight + (nextHeight - prevHeight) * (1.0 - Math.cos(t * Math.PI)) / 2.0;
    }

    // =========================================================
    // onSwellData(data) — receives current swell entry (Dictionary)
    // from onBackgroundData(). The full forecast array is stored
    // separately in Application.Storage by the delegate.
    // =========================================================
    function onSwellData(data as Dictionary) as Void {
        swellHeight = data["swellHeight"] as Float or Null;
        swellPeriod = data["swellPeriod"] as Float or Null;
        swellDirection = data["swellDirection"] as Number or Null;
        // Refresh cached forecast arrays from Storage (delegate just wrote them)
        _swellHeightsCache = Application.Storage.getValue("surf_swellHeights") as Array or Null;
        _swellPeriodsCache = Application.Storage.getValue("surf_swellPeriods") as Array or Null;
        _swellDirectionsCache = Application.Storage.getValue("surf_swellDirections") as Array or Null;
    }

    // onSurfWindData(data) — receives OWM wind for surf spot.
    // Stored separately from shore wind fields.
    function onSurfWindData(data as Dictionary) as Void {
        surfWindSpeed = data["windSpeed"] as Float or Null;
        surfWindDeg = data["windDeg"] as Number or Null;
        // Extract surf sunrise/sunset if available (from Open-Meteo or OWM)
        if (data["surfSunrise"] != null) { surfSunrise = data["surfSunrise"] as Number; }
        if (data["surfSunset"] != null) { surfSunset = data["surfSunset"] as Number; }
        // Refresh cached wind forecast arrays from Storage (delegate may have written them)
        _windSpeedsCache = Application.Storage.getValue("surf_windSpeeds") as Array or Null;
        _windDirectionsCache = Application.Storage.getValue("surf_windDirections") as Array or Null;
    }

    // updateSwellFromForecast() — picks the current hour's entry
    // from the cached swell forecast arrays. Called from onUpdate()
    // so the display advances through the forecast over time.
    // Arrays are cached in memory — loaded from Storage only on data change.
    function updateSwellFromForecast() as Void {
        if (_swellHeightsCache == null || _swellHeightsCache.size() == 0) { return; }

        var nowHour = Gregorian.info(Time.now(), Time.FORMAT_SHORT).hour;
        var idx = nowHour < _swellHeightsCache.size() ? nowHour : _swellHeightsCache.size() - 1;

        swellHeight = _swellHeightsCache[idx] != null ? (_swellHeightsCache[idx] as Float).toFloat() : null;
        swellPeriod = (_swellPeriodsCache != null && idx < _swellPeriodsCache.size() && _swellPeriodsCache[idx] != null) ? (_swellPeriodsCache[idx] as Float).toFloat() : null;
        swellDirection = (_swellDirectionsCache != null && idx < _swellDirectionsCache.size() && _swellDirectionsCache[idx] != null) ? (_swellDirectionsCache[idx] as Number).toNumber() : null;
    }

    // updateSurfWindFromForecast() — picks the current hour's wind
    // from cached Open-Meteo hourly forecast arrays. Called from
    // onUpdate() when SurfMode=1 and WeatherSource=1 (Open-Meteo).
    function updateSurfWindFromForecast() as Void {
        if (_windSpeedsCache == null || _windSpeedsCache.size() == 0) { return; }

        var nowHour = Gregorian.info(Time.now(), Time.FORMAT_SHORT).hour;
        var idx = nowHour < _windSpeedsCache.size() ? nowHour : _windSpeedsCache.size() - 1;

        surfWindSpeed = _windSpeedsCache[idx] != null ? (_windSpeedsCache[idx] as Float).toFloat() : null;
        surfWindDeg = (_windDirectionsCache != null && idx < _windDirectionsCache.size() && _windDirectionsCache[idx] != null) ? (_windDirectionsCache[idx] as Number).toNumber() : null;
    }

    // loadForecastCaches() — loads swell and wind forecast arrays
    // from Application.Storage into memory. Called on data change
    // (onSwellData, onSurfWindData) and mode switch (loadSurfCache).
    function loadForecastCaches() as Void {
        _swellHeightsCache = Application.Storage.getValue("surf_swellHeights") as Array or Null;
        _swellPeriodsCache = Application.Storage.getValue("surf_swellPeriods") as Array or Null;
        _swellDirectionsCache = Application.Storage.getValue("surf_swellDirections") as Array or Null;
        _windSpeedsCache = Application.Storage.getValue("surf_windSpeeds") as Array or Null;
        _windDirectionsCache = Application.Storage.getValue("surf_windDirections") as Array or Null;
    }

    // =========================================================
    // loadSurfCache() — loads surf-mode data from surf_ prefixed
    // Application.Storage keys.
    // =========================================================
    function loadSurfCache() as Void {
        tideExtremes = Application.Storage.getValue("surf_tideExtremes") as Array or Null;
        tideFetchedDay = Application.Storage.getValue("surf_tideFetchedDay") as String or Null;
        nextTideTime = null; // Force recomputation from new tide data
        extractTideCurveData();
        loadForecastCaches();
    }

    // =========================================================
    // loadShoreCache() — loads shore-mode data from unprefixed
    // Application.Storage keys.
    // =========================================================
    function loadShoreCache() as Void {
        loadTideData();
        loadWeatherData();
        nextTideTime = null; // Force recomputation from new tide data
        extractTideCurveData();
    }

    // =========================================================
    // checkCopyGPS() — one-shot GPS copy to surf spot settings.
    // When CopyGPSToSurfSpot is true and GPS is available,
    // copies coordinates and resets the flag.
    // =========================================================
    function checkCopyGPS() as Void {
        var copyGPS = Application.Properties.getValue("CopyGPSToSurfSpot");
        if (copyGPS == null || copyGPS != true) {
            return;
        }
        if (lastKnownLat == null || lastKnownLng == null) {
            return;
        }
        Application.Properties.setValue("SurfSpotLat", lastKnownLat.toString());
        Application.Properties.setValue("SurfSpotLng", lastKnownLng.toString());
        Application.Properties.setValue("CopyGPSToSurfSpot", false);
    }

    // =========================================================
    // updateSurfSensors() — reads water temp and solar intensity
    // from SensorHistory. Called from onUpdate() when SurfMode=1.
    // =========================================================
    function updateSurfSensors() as Void {
        // Water temperature
        if (SensorHistory has :getTemperatureHistory) {
            var tempIter = SensorHistory.getTemperatureHistory({:period => 1});
            if (tempIter != null) {
                var sample = tempIter.next();
                if (sample != null && sample.data != null) {
                    waterTemp = sample.data.toFloat();
                } else {
                    waterTemp = null;
                }
            } else {
                waterTemp = null;
            }
        } else {
            waterTemp = null;
        }

        // Solar intensity
        if (SensorHistory has :getSolarIntensityHistory) {
            var solarIter = SensorHistory.getSolarIntensityHistory({:period => 1});
            if (solarIter != null) {
                var sample = solarIter.next();
                if (sample != null && sample.data != null) {
                    var val = sample.data;
                    if (val >= 0 && val <= 100) {
                        solarIntensity = val.toNumber();
                    } else {
                        solarIntensity = null;
                    }
                } else {
                    solarIntensity = null;
                }
            } else {
                solarIntensity = null;
            }
        } else {
            solarIntensity = null;
        }
    }

    // =========================================================
    // persistTideData() — saves tideExtremes and tideFetchedDay
    // to Application.Storage
    // =========================================================
    function persistTideData() as Void {
        Application.Storage.setValue("tideExtremes", tideExtremes);
        // Store today's date as the fetch day
        var now = Time.now();
        var today = Gregorian.info(now, Time.FORMAT_SHORT);
        tideFetchedDay = today.year.format("%04d") + "-" +
                         today.month.format("%02d") + "-" +
                         today.day.format("%02d");
        Application.Storage.setValue("tideFetchedDay", tideFetchedDay);
    }

    // =========================================================
    // loadTideData() — restores tideExtremes and tideFetchedDay
    // from Application.Storage on startup
    // =========================================================
    function loadTideData() as Void {
        tideExtremes = Application.Storage.getValue("tideExtremes") as Array or Null;
        tideFetchedDay = Application.Storage.getValue("tideFetchedDay") as String or Null;
    }

    // =========================================================
    // persistWeatherData() — saves weather fields to
    // Application.Storage so they survive restarts
    // =========================================================
    function persistWeatherData() as Void {
        Application.Storage.setValue("cachedTemp", temperature);
        Application.Storage.setValue("cachedConditionId", weatherConditionId);
        Application.Storage.setValue("cachedWindSpeed", windSpeed);
        Application.Storage.setValue("cachedWindDeg", windDeg);
        Application.Storage.setValue("cachedSunrise", sunrise);
        Application.Storage.setValue("cachedSunset", sunset);
    }

    // =========================================================
    // loadWeatherData() — restores weather fields from
    // Application.Storage on startup
    // =========================================================
    function loadWeatherData() as Void {
        temperature = Application.Storage.getValue("cachedTemp") as Float or Null;
        weatherConditionId = Application.Storage.getValue("cachedConditionId") as Number or Null;
        windSpeed = Application.Storage.getValue("cachedWindSpeed") as Float or Null;
        windDeg = Application.Storage.getValue("cachedWindDeg") as Number or Null;
        sunrise = Application.Storage.getValue("cachedSunrise") as Number or Null;
        sunset = Application.Storage.getValue("cachedSunset") as Number or Null;
        owmFetchedAt = Application.Storage.getValue("owmFetchedAt") as Number or Null;
    }

}
