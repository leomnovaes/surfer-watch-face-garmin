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

    // =========================================================
    // Application.Storage key reference (short keys save memory)
    // =========================================================
    // Flags (set by App, read/cleared by View):
    //   "sc"  = settingsChanged     "bge" = bgEventOccurred
    //   "wu"  = weatherUpdated      "su"  = swellUpdated
    //   "tu"  = tideUpdated
    // Background data (written by App/Delegate, read by DataManager):
    //   "bwd" = bgWeatherData       "bsd" = bgSwellData
    // Weather cache (persisted across restarts):
    //   "ct"  = cachedTemp          "cci" = cachedConditionId
    //   "cws" = cachedWindSpeed     "cwd" = cachedWindDeg
    //   "csr" = cachedSunrise       "css" = cachedSunset
    //   "ofa" = owmFetchedAt
    // Surf forecast arrays:
    //   "ssh" = surf_swellHeights   "ssp" = surf_swellPeriods
    //   "ssd" = surf_swellDirections "sst" = surf_seaSurfaceTemps
    //   "sws" = surf_windSpeeds     "swd" = surf_windDirections
    // Surf tide arrays:
    //   "sth" = surf_tideHeights    "stt" = surf_tideTimes
    //   "sty" = surf_tideTypes      "std" = surf_tideFetchedDay
    //   "stl" = surf_tideFetchLat   "stn" = surf_tideFetchLng
    //   "ste" = surf_tideDataExpired
    // Shore tide arrays:
    //   "th"  = tideHeights         "tt"  = tideTimes
    //   "tp"  = tideTypes           "tfd" = tideFetchedDay
    //   "tfl" = tideFetchLat        "tfn" = tideFetchLng
    //   "tde" = tideDataExpired
    // Tide metadata:
    //   "src" = sgLastResponseCode
    // Version:
    //   "av"  = appVersion
    // =========================================================

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

    // --- Cached tide data (flat arrays from StormGlass, via Application.Storage) ---
    var tideHeights as Array or Null;
    var tideTimes as Array or Null;
    var tideTypes as Array or Null;
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
    private var _seaSurfaceTempsCache as Array or Null;
    private var _windSpeedsCache as Array or Null;
    private var _windDirectionsCache as Array or Null;

    // --- Surf mode: sensor data ---
    var waterTemp as Float or Null;
    var seaSurfaceTemp as Float or Null;
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

    // --- Display-ready subscreen fields (set by updateSubscreenData/updateArcData) ---
    var subscreenIcon as String;
    var subscreenValue as String;
    var subscreenFont as Number;
    var arcValue as Number or Null;

    // --- Storage write tracking (avoid flash I/O every tick) ---
    private var _tideExpiredWritten as Boolean;

    function initialize() {
        // Initialize sensor defaults
        battery = 0;
        notificationCount = 0;
        bluetoothConnected = false;
        bottomToggleState = 0;
        _tideExpiredWritten = false;
        tideCurveMinH = 0.0;
        tideCurveMaxH = 1.0;
        tideCurveHRange = 1.0;
        // Subscreen defaults (shore mode: heart)
        subscreenIcon = "h";
        subscreenValue = "--";
        subscreenFont = 0;
        arcValue = null;

        // Load persisted data from Application.Storage
        loadTideData();
        loadWeatherData();
        extractTideCurveData();
    }

    // =========================================================
    // checkBackgroundFlags() — checks Storage flags set by
    // App.onBackgroundData() and processes any pending data.
    // Called from onUpdate() each tick — flags are only set on
    // background events (every 5 min), so most ticks do nothing.
    // =========================================================
    function checkBackgroundFlags() as Void {
        var bgEvent = Application.Storage.getValue("bge");
        if (bgEvent == null || bgEvent != true) { return; }

        // Clear the event flag first
        Application.Storage.setValue("bge", false);

        // Weather data
        var weatherUpdated = Application.Storage.getValue("wu");
        if (weatherUpdated != null && weatherUpdated == true) {
            var weatherData = Application.Storage.getValue("bwd");
            if (weatherData != null && weatherData instanceof Dictionary) {
                var surfMode = Application.Properties.getValue("SurfMode");
                if (surfMode != null && surfMode == 1) {
                    onSurfWindData(weatherData as Dictionary);
                } else {
                    onWeatherData(weatherData as Dictionary);
                }
            }
            Application.Storage.setValue("wu", false);
            Application.Storage.setValue("bwd", null);
        }

        // Swell data
        var swellUpdated = Application.Storage.getValue("su");
        if (swellUpdated != null && swellUpdated == true) {
            var swellData = Application.Storage.getValue("bsd");
            if (swellData != null && swellData instanceof Dictionary) {
                onSwellData(swellData as Dictionary);
            }
            Application.Storage.setValue("su", false);
            Application.Storage.setValue("bsd", null);
        }

        // Tide data (arrays already in Storage — just reload)
        var tideUpdated = Application.Storage.getValue("tu");
        if (tideUpdated != null && tideUpdated == true) {
            onTideData();
            Application.Storage.setValue("tu", false);
        }

        // Update GPS from OS cache (event-driven, not per-tick)
        updateGPS();
        // Refresh weather (sunrise/sunset + Garmin weather if applicable)
        refreshWeatherOnBackgroundEvent();
        // Recompute moon phase (changes daily, no need to run per tick)
        computeMoonPhase();
    }

    // =========================================================
    // updateSensorData() — called from onUpdate() each tick
    // Reads display-only sensors: HR, stress, battery, BT, notifications
    // GPS is read on background events only (see updateGPS)
    // =========================================================
    function updateSensorData() as Void {
        // Heart rate + Stress — only in shore mode (surf shows tide height + solar arc)
        var surfMode = Application.Properties.getValue("SurfMode");
        if (surfMode == null || surfMode == 0) {
            var activityInfo = Activity.getActivityInfo();
            if (activityInfo != null) {
                heartRate = activityInfo.currentHeartRate;
            } else {
                heartRate = null;
            }

            if (SensorHistory has :getStressHistory) {
                var stressIter = SensorHistory.getStressHistory({:period => 1});
                if (stressIter != null) {
                    var sample = stressIter.next();
                    if (sample != null && sample.data != null) {
                        var val = sample.data;
                        if (val >= 0 && val <= 100) {
                            stress = val.toNumber();
                        } else { stress = null; }
                    } else { stress = null; }
                } else { stress = null; }
            } else { stress = null; }
        }

        // Battery
        var stats = System.getSystemStats();
        battery = stats.battery.toNumber();

        // Notifications and Bluetooth
        var settings = System.getDeviceSettings();
        notificationCount = settings.notificationCount;
        bluetoothConnected = settings.phoneConnected;
    }

    // =========================================================
    // updateSubscreenAndArc() — sets display-ready subscreen + arc
    // fields. Called from onUpdate() AFTER sensor reads and tide
    // computation so values are current tick.
    // =========================================================
    function updateSubscreenAndArc() as Void {
        var surfMode = Application.Properties.getValue("SurfMode");
        if (surfMode != null && surfMode == 1) {
            if (nextTideType != null) {
                subscreenIcon = nextTideType.equals("high") ? "H" : "L";
                subscreenFont = 1;
            } else {
                subscreenIcon = "--";
                subscreenFont = -1;
            }
            if (interpTideHeight != null) {
                var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
                subscreenValue = isMetric ? interpTideHeight.format("%.1f") : (interpTideHeight * 3.281).format("%.1f");
            } else { subscreenValue = "--"; }
            var stats = System.getSystemStats();
            if (stats has :solarIntensity && stats.solarIntensity != null && stats.solarIntensity >= 0) {
                arcValue = stats.solarIntensity.toNumber();
            } else { arcValue = 0; }
        } else {
            subscreenIcon = "h";
            subscreenFont = 0;
            subscreenValue = (heartRate != null) ? heartRate.toString() : "--";
            arcValue = (stress != null) ? stress : 0;
        }
    }

    // =========================================================
    // updateGPS() — reads GPS position from OS cache.
    // Called on background events and init — NOT per tick.
    // Position.getInfo() is an in-memory read (no I/O).
    // Used by computeSunriseSunset() and checkCopyGPS().
    // =========================================================
    function updateGPS() as Void {
        var posInfo = Position.getInfo();
        if (posInfo != null && posInfo.accuracy != Position.QUALITY_NOT_AVAILABLE && posInfo.position != null) {
            var coords = posInfo.position.toDegrees();
            lastKnownLat = coords[0].toFloat();
            lastKnownLng = coords[1].toFloat();
        }
    }

    // =========================================================
    // refreshWeatherOnBackgroundEvent() — called on every
    // background event, settings change, and startup.
    //
    // For Garmin mode: computes sunrise/sunset locally (no API),
    //   reads built-in weather, flows through onWeatherData().
    // For Garmin + surf: computes surf sunrise/sunset locally.
    // For API modes (OWM/Open-Meteo): sunrise/sunset comes from
    //   the API response via onWeatherData/onSurfWindData — no
    //   local computation needed.
    // =========================================================
    function refreshWeatherOnBackgroundEvent() as Void {
        var surfMode = Application.Properties.getValue("SurfMode");
        var weatherSource = Application.Properties.getValue("WeatherSource");

        // Garmin mode: compute sunrise/sunset locally + read built-in weather
        if (weatherSource == null || weatherSource == 0) {
            if (surfMode != null && surfMode == 1) {
                computeSurfSunriseSunset();
            } else {
                computeSunriseSunset();
                // Shore + Garmin: build weather dict with computed sunrise/sunset
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
                weatherDict["sunrise"] = sunrise as Application.PropertyValueType;
                weatherDict["sunset"] = sunset as Application.PropertyValueType;
                Application.Storage.setValue("ofa", Time.now().value());
                onWeatherData(weatherDict);
            }
        }
        // API modes (OWM/Open-Meteo): sunrise/sunset delivered by API via
        // onWeatherData() or onSurfWindData() — no local computation.
    }

    // =========================================================
    // updateGarminWeather() — reads weather from Garmin built-in
    // Weather.getCurrentConditions(). Called from onUpdate() when
    // WeatherSource=0 (Garmin). This is an OS-cached memory read,
    // not flash I/O — safe to call every tick. Does NOT compute
    // sunrise/sunset (that's done in refreshWeatherOnBackgroundEvent).
    // =========================================================
    function updateGarminWeather() as Void {
        if (Weather has :getCurrentConditions) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null) {
                temperature = conditions.temperature != null ? conditions.temperature.toFloat() : null;
                weatherConditionId = conditions.condition;
                windSpeed = conditions.windSpeed != null ? conditions.windSpeed.toFloat() : null;
                windDeg = conditions.windBearing != null ? conditions.windBearing.toNumber() : null;
                precipProbability = conditions.precipitationChance != null ? conditions.precipitationChance.toNumber() : null;
                owmFetchedAt = Time.now().value();
            }
        }
    }

    // =========================================================
    // updatePerTickWeather() — called from onUpdate() each tick.
    // Handles per-tick weather reads that depend on weather source.
    // View calls this without knowing the source — DataManager
    // decides internally what to do.
    // =========================================================
    function updatePerTickWeather() as Void {
        var weatherSource = Application.Properties.getValue("WeatherSource");
        var surfMode = Application.Properties.getValue("SurfMode");
        if (weatherSource == null || weatherSource == 0) {
            // Garmin: read OS-cached weather each tick (shore only)
            if (surfMode == null || surfMode == 0) {
                updateGarminWeather();
            }
        }
        // Surf + Open-Meteo: advance hourly wind forecast
        if (surfMode != null && surfMode == 1) {
            if (weatherSource != null && weatherSource == 1) {
                updateSurfWindFromForecast();
            }
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
        Application.Storage.setValue("ct", null);
        Application.Storage.setValue("cci", null);
        Application.Storage.setValue("cws", null);
        Application.Storage.setValue("cwd", null);
        Application.Storage.setValue("csr", null);
        Application.Storage.setValue("css", null);
        Application.Storage.setValue("ofa", null);
        // Clear surf wind forecast arrays (source-dependent)
        Application.Storage.setValue("sws", null);
        Application.Storage.setValue("swd", null);
    }

    // =========================================================
    // computeSunriseSunset() — calculates sunrise/sunset from
    // lat/lon + current date using SunCalc algorithm (Julian date
    // with equation of time correction and atmospheric refraction).
    // Used when WeatherSource=0 (Garmin) since Weather.getSunrise()
    // requires CIQ 4.1 and we target 3.4.
    // =========================================================
    function computeSunriseSunset() as Void {
        if (lastKnownLat == null || lastKnownLng == null) {
            return;
        }
        var result = calcSunTimes(lastKnownLat.toDouble(), lastKnownLng.toDouble());
        if (result != null) {
            sunrise = result[0];
            sunset = result[1];
        } else {
            sunrise = null;
            sunset = null;
        }
    }

    // =========================================================
    // computeSurfSunriseSunset() — same algorithm but reads from
    // SurfSpotLat/SurfSpotLng settings instead of GPS.
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
        var result = calcSunTimes(lat.toDouble(), lng.toDouble());
        if (result != null) {
            surfSunrise = result[0];
            surfSunset = result[1];
        } else {
            surfSunrise = null;
            surfSunset = null;
        }
    }

    // =========================================================
    // calcSunTimes(lat, lng) — SunCalc algorithm (Julian date).
    // Returns [sunriseUnix, sunsetUnix] or null for polar regions.
    // Includes equation of time and -0.833° atmospheric refraction.
    // Adapted from haraldh/SunCalc (MIT license).
    // =========================================================
    private function calcSunTimes(lat as Double, lng as Double) as Array or Null {
        var RAD = Math.PI / 180.0;
        var PI2 = Math.PI * 2.0;
        var J1970 = 2440588;
        var J2000 = 2451545;
        var DAYS = 86400;

        var d = Time.now().value().toDouble() / DAYS - 0.5 + J1970 - J2000;
        var lngRad = lng * RAD;
        var latRad = lat * RAD;

        // Julian cycle
        var n = (d - 0.0009 + lngRad / PI2 + 0.5).toNumber().toFloat();
        var ds = 0.0009 - lngRad / PI2 + n - 1.1574e-5 * 68;

        // Mean anomaly and equation of center
        var M = 6.240059967 + 0.0172019715 * ds;
        var sinM = Math.sin(M);
        var C = (1.9148 * sinM + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M)) * RAD;

        // Ecliptic longitude and declination
        var L = M + C + 1.796593063 + Math.PI;
        var sin2L = Math.sin(2 * L);
        var dec = Math.asin(0.397783703 * Math.sin(L));

        // Solar noon (Julian)
        var Jnoon = J2000 + ds + 0.0053 * sinM - 0.0069 * sin2L;

        // Hour angle for sunrise/sunset (-0.833° = atmospheric refraction)
        var cosH = (Math.sin(-0.833 * RAD) - Math.sin(latRad) * Math.sin(dec))
                   / (Math.cos(latRad) * Math.cos(dec));

        if (cosH > 1.0 || cosH < -1.0) {
            return null; // polar region
        }

        var dsSet = 0.0009 + (Math.acos(cosH) - lngRad) / PI2 + n - 1.1574e-5 * 68;
        var Jset = J2000 + dsSet + 0.0053 * sinM - 0.0069 * sin2L;
        var Jrise = Jnoon - (Jset - Jnoon);

        // Convert Julian to Unix
        var srUnix = ((Jrise + 0.5 - J1970) * DAYS).toNumber();
        var ssUnix = ((Jset + 0.5 - J1970) * DAYS).toNumber();
        return [srUnix, ssUnix];
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
        // OWM doesn't return pop — fall back to Garmin built-in
        if (precipProbability == null && Weather has :getCurrentConditions) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null && conditions.precipitationChance != null) {
                precipProbability = conditions.precipitationChance.toNumber();
            }
        }
        isDay = data["isDay"] as Number or Null;
        // Read owmFetchedAt from Storage (written by WeatherService/OpenMeteoService in background)
        owmFetchedAt = Application.Storage.getValue("ofa") as Number or Null;
        persistWeatherData();
    }

    // =========================================================
    // onTideData() — called when foreground detects tideUpdated
    // flag from background. Reloads flat arrays from Storage.
    // =========================================================
    function onTideData() as Void {
        var surfMode = Application.Properties.getValue("SurfMode");
        if (surfMode != null && surfMode == 1) {
            tideHeights = Application.Storage.getValue("sth") as Array or Null;
            tideTimes = Application.Storage.getValue("stt") as Array or Null;
            tideTypes = Application.Storage.getValue("sty") as Array or Null;
        } else {
            tideHeights = Application.Storage.getValue("th") as Array or Null;
            tideTimes = Application.Storage.getValue("tt") as Array or Null;
            tideTypes = Application.Storage.getValue("tp") as Array or Null;
        }
        nextTideTime = null;
        _tideExpiredWritten = false;
        extractTideCurveData();
    }

    // =========================================================
    // markTideForRefresh() — sets tideDataExpired flag in Storage
    // to trigger a tide fetch on the next background event.
    // Uses _tideExpiredWritten to avoid repeated Storage writes.
    // =========================================================
    function markTideForRefresh() as Void {
        if (!_tideExpiredWritten) {
            var surfMode = Application.Properties.getValue("SurfMode");
            if (surfMode != null && surfMode == 1) {
                Application.Storage.setValue("ste", true);
            } else {
                Application.Storage.setValue("tde", true);
            }
            _tideExpiredWritten = true;
        }
    }

    // =========================================================
    // computeNextTide() — walks tideExtremes to find next event
    // after now, sets nextTideTime/nextTideType/nextTideHeight.
    // If all events are in the past, sets tideDataExpired=true
    // in Application.Storage to trigger background refresh.
    // =========================================================
    function computeNextTide() as Void {
        if (tideTimes == null || tideTimes.size() == 0) {
            nextTideTime = null;
            nextTideType = null;
            currentTideHeight = null;
            return;
        }

        var now = Time.now().value();
        if (nextTideTime != null && nextTideTime > now) {
            return;
        }
        var nextIdx = -1;

        for (var i = 0; i < tideTimes.size(); i++) {
            var entryTime = tideTimes[i] as Number;
            if (entryTime > now) {
                nextIdx = i;
                break;
            }
        }

        if (nextIdx == -1) {
            nextTideTime = null;
            nextTideType = null;
            currentTideHeight = null;
            markTideForRefresh();
            return;
        }

        _tideExpiredWritten = false;
        nextTideTime = tideTimes[nextIdx] as Number;
        nextTideType = (tideTypes[nextIdx] as Number) == 1 ? "high" : "low";
        if (tideHeights != null && nextIdx < tideHeights.size()) {
            currentTideHeight = (tideHeights[nextIdx] as Float).toFloat();
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
        if (tideTimes == null || tideHeights == null || tideTimes.size() < 2) {
            tideCurveTimes = null;
            tideCurveHeights = null;
            return;
        }
        var n = tideTimes.size();
        var times = new [n];
        var heights = new [n];
        var minH = 999.0;
        var maxH = -999.0;
        for (var i = 0; i < n; i++) {
            times[i] = (tideTimes[i] as Number).toFloat();
            heights[i] = (tideHeights[i] as Float).toFloat();
            var hf = heights[i];
            if (hf < minH) { minH = hf; }
            if (hf > maxH) { maxH = hf; }
        }
        if (maxH <= minH) { maxH = minH + 1.0; }
        var hRange = maxH - minH;
        tideCurveMinH = minH - hRange * 0.25;
        tideCurveMaxH = maxH + hRange * 0.1;
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
        if (tideTimes == null || tideHeights == null || tideTimes.size() < 2) {
            interpTideHeight = null;
            return;
        }

        var now = Time.now().value();
        var prevIdx = -1;
        var nextIdx2 = -1;

        for (var i = 0; i < tideTimes.size(); i++) {
            var entryTime = tideTimes[i] as Number;
            if (entryTime <= now) {
                prevIdx = i;
            } else if (nextIdx2 == -1) {
                nextIdx2 = i;
            }
        }

        if (prevIdx == -1 && nextIdx2 >= 0) {
            interpTideHeight = (tideHeights[nextIdx2] as Float).toFloat();
            return;
        }
        if (prevIdx >= 0 && nextIdx2 == -1) {
            interpTideHeight = (tideHeights[prevIdx] as Float).toFloat();
            return;
        }
        if (prevIdx == -1 || nextIdx2 == -1) {
            interpTideHeight = null;
            return;
        }

        var prevTime = (tideTimes[prevIdx] as Number).toFloat();
        var nextTime = (tideTimes[nextIdx2] as Number).toFloat();
        var prevHeight = (tideHeights[prevIdx] as Float).toFloat();
        var nextHeight = (tideHeights[nextIdx2] as Float).toFloat();

        var t = (now.toFloat() - prevTime) / (nextTime - prevTime);
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
        seaSurfaceTemp = data["seaSurfaceTemp"] as Float or Null;
        // Refresh cached forecast arrays from Storage (delegate just wrote them)
        _swellHeightsCache = Application.Storage.getValue("ssh") as Array or Null;
        _swellPeriodsCache = Application.Storage.getValue("ssp") as Array or Null;
        _swellDirectionsCache = Application.Storage.getValue("ssd") as Array or Null;
        _seaSurfaceTempsCache = Application.Storage.getValue("sst") as Array or Null;
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
        _windSpeedsCache = Application.Storage.getValue("sws") as Array or Null;
        _windDirectionsCache = Application.Storage.getValue("swd") as Array or Null;
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
        // Sea surface temperature advances with the same hourly index
        var surfTempSource = Application.Properties.getValue("SurfTempSource");
        if (surfTempSource != null && surfTempSource == 1) {
            seaSurfaceTemp = (_seaSurfaceTempsCache != null && idx < _seaSurfaceTempsCache.size() && _seaSurfaceTempsCache[idx] != null) ? (_seaSurfaceTempsCache[idx] as Float).toFloat() : null;
        }
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
        _swellHeightsCache = Application.Storage.getValue("ssh") as Array or Null;
        _swellPeriodsCache = Application.Storage.getValue("ssp") as Array or Null;
        _swellDirectionsCache = Application.Storage.getValue("ssd") as Array or Null;
        _seaSurfaceTempsCache = Application.Storage.getValue("sst") as Array or Null;
        _windSpeedsCache = Application.Storage.getValue("sws") as Array or Null;
        _windDirectionsCache = Application.Storage.getValue("swd") as Array or Null;
    }

    // =========================================================
    // loadSurfCache() — loads surf-mode data from surf_ prefixed
    // Application.Storage keys.
    // =========================================================
    function loadSurfCache() as Void {
        tideHeights = Application.Storage.getValue("sth") as Array or Null;
        tideTimes = Application.Storage.getValue("stt") as Array or Null;
        tideTypes = Application.Storage.getValue("sty") as Array or Null;
        tideFetchedDay = Application.Storage.getValue("std") as String or Null;
        nextTideTime = null;
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
        nextTideTime = null;
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

        // Solar intensity — from System.getSystemStats().solarIntensity
        // Returns 0-100 on solar devices, null on non-solar devices
        var stats2 = System.getSystemStats();
        if (stats2 has :solarIntensity && stats2.solarIntensity != null) {
            var val = stats2.solarIntensity;
            if (val >= 0) {
                solarIntensity = val.toNumber();
            } else {
                solarIntensity = null; // negative = not charging
            }
        } else {
            solarIntensity = null;
        }
    }

    // =========================================================
    // loadTideData() — restores tideExtremes and tideFetchedDay
    // from Application.Storage on startup
    // =========================================================
    function loadTideData() as Void {
        tideHeights = Application.Storage.getValue("th") as Array or Null;
        tideTimes = Application.Storage.getValue("tt") as Array or Null;
        tideTypes = Application.Storage.getValue("tp") as Array or Null;
        tideFetchedDay = Application.Storage.getValue("tfd") as String or Null;
    }

    // =========================================================
    // persistWeatherData() — saves weather fields to
    // Application.Storage so they survive restarts
    // =========================================================
    function persistWeatherData() as Void {
        Application.Storage.setValue("ct", temperature);
        Application.Storage.setValue("cci", weatherConditionId);
        Application.Storage.setValue("cws", windSpeed);
        Application.Storage.setValue("cwd", windDeg);
        Application.Storage.setValue("csr", sunrise);
        Application.Storage.setValue("css", sunset);
    }

    // =========================================================
    // loadWeatherData() — restores weather fields from
    // Application.Storage on startup
    // =========================================================
    function loadWeatherData() as Void {
        temperature = Application.Storage.getValue("ct") as Float or Null;
        weatherConditionId = Application.Storage.getValue("cci") as Number or Null;
        windSpeed = Application.Storage.getValue("cws") as Float or Null;
        windDeg = Application.Storage.getValue("cwd") as Number or Null;
        sunrise = Application.Storage.getValue("csr") as Number or Null;
        sunset = Application.Storage.getValue("css") as Number or Null;
        owmFetchedAt = Application.Storage.getValue("ofa") as Number or Null;
    }

}
