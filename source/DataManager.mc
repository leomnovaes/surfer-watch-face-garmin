import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

class DataManager {

    // --- Cached weather data (from OWM, received via onBackgroundData) ---
    var temperature as Float or Null;
    var weatherConditionId as Number or Null;
    var windSpeed as Float or Null;
    var windDeg as Number or Null;
    var sunrise as Number or Null;
    var sunset as Number or Null;
    var moonPhase as Float or Null;
    var owmFetchedAt as Number or Null;

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

    function initialize() {
        // Initialize sensor defaults
        battery = 0;
        notificationCount = 0;
        bluetoothConnected = false;

        // Load persisted data from Application.Storage
        loadTideData();
        loadWeatherData();
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
        Application.Storage.setValue("lastKnownLat", lastKnownLat);
        Application.Storage.setValue("lastKnownLng", lastKnownLng);
        Application.Storage.setValue("bluetoothConnected", bluetoothConnected);
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
    }

    // =========================================================
    // updateGarminWeather() — reads weather from Garmin built-in
    // Weather.getCurrentConditions(). Called from onUpdate() when
    // WeatherSource=0 (Garmin). No background HTTP needed.
    // =========================================================
    function updateGarminWeather() as Void {
        if (Weather has :getCurrentConditions) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null) {
                temperature = conditions.temperature != null ? conditions.temperature.toFloat() : null;
                weatherConditionId = conditions.condition;
                windSpeed = conditions.windSpeed != null ? conditions.windSpeed.toFloat() : null;
                windDeg = conditions.windBearing != null ? conditions.windBearing.toNumber() : null;
                owmFetchedAt = Time.now().value();
            }
        }
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
    // onWeatherData(data) — receives parsed OWM Dictionary from
    // onBackgroundData(). Keys: temp, conditionId, windSpeed,
    // windDeg, sunrise, sunset.
    // owmFetchedAt is read from Application.Storage (written by
    // WeatherService in the background process) — single source
    // of truth for refresh timing.
    // =========================================================
    function onWeatherData(data as Dictionary) as Void {
        temperature = data["temp"] as Float or Null;
        weatherConditionId = data["conditionId"] as Number or Null;
        windSpeed = data["windSpeed"] as Float or Null;
        windDeg = data["windDeg"] as Number or Null;
        sunrise = data["sunrise"] as Number or Null;
        sunset = data["sunset"] as Number or Null;
        // Read owmFetchedAt from Storage (written by WeatherService in background)
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
        // Clear expired flag since we have fresh data
        Application.Storage.setValue("tideDataExpired", false);
        persistTideData();
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

        var now = Time.now().value();
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
            Application.Storage.setValue("tideDataExpired", true);
            return;
        }

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
