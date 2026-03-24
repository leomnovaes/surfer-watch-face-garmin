import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
class OpenMeteoService {

    private var _callback as Method;

    function initialize(callback as Method) {
        _callback = callback;
    }

    // =========================================================
    // fetchCurrent() — Shore mode: fetches current weather +
    // sunrise/sunset from Open-Meteo Forecast API.
    // No API key needed. Response ~670 bytes.
    // wind_speed_unit=ms ensures m/s (matches our internal format).
    // =========================================================
    function fetchCurrent(lat as Float, lon as Float) as Void {
        var url = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + lat.toString()
            + "&longitude=" + lon.toString()
            + "&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,precipitation_probability,is_day"
            + "&daily=sunrise,sunset"
            + "&timezone=auto"
            + "&forecast_days=1"
            + "&wind_speed_unit=ms";

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(url, null, options, method(:onCurrentResponse));
    }

    // Callback for Open-Meteo current weather response
    function onCurrentResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            _callback.invoke(null);
            return;
        }

        var current = data["current"];
        if (current == null || !(current instanceof Dictionary)) {
            _callback.invoke(null);
            return;
        }

        var weatherDict = {} as Dictionary<String, Application.PropertyValueType>;

        // Temperature (°C — Open-Meteo default)
        weatherDict["temp"] = current["temperature_2m"] as Application.PropertyValueType;

        // WMO weather code (stored as conditionId, mapper selected at render time)
        weatherDict["conditionId"] = current["weather_code"] as Application.PropertyValueType;

        // Wind (m/s — we requested wind_speed_unit=ms)
        weatherDict["windSpeed"] = current["wind_speed_10m"] as Application.PropertyValueType;
        weatherDict["windDeg"] = current["wind_direction_10m"] as Application.PropertyValueType;

        // Precipitation probability
        weatherDict["precipProbability"] = current["precipitation_probability"] as Application.PropertyValueType;

        // is_day (1=day, 0=night)
        weatherDict["isDay"] = current["is_day"] as Application.PropertyValueType;

        // Sunrise/sunset from daily
        var daily = data["daily"];
        if (daily != null && daily instanceof Dictionary) {
            var sunriseArr = daily["sunrise"] as Array or Null;
            var sunsetArr = daily["sunset"] as Array or Null;
            var utcOffset = data["utc_offset_seconds"] as Number or Null;
            if (utcOffset == null) { utcOffset = 0; }

            if (sunriseArr != null && sunriseArr.size() > 0 && sunriseArr[0] != null) {
                var srUnix = parseLocalISOToUnix(sunriseArr[0] as String, utcOffset);
                if (srUnix != null) {
                    weatherDict["sunrise"] = srUnix as Application.PropertyValueType;
                }
            }
            if (sunsetArr != null && sunsetArr.size() > 0 && sunsetArr[0] != null) {
                var ssUnix = parseLocalISOToUnix(sunsetArr[0] as String, utcOffset);
                if (ssUnix != null) {
                    weatherDict["sunset"] = ssUnix as Application.PropertyValueType;
                }
            }
        }

        // Write fetch metadata
        var now = Time.now().value();
        Application.Storage.setValue("owmFetchedAt", now);

        _callback.invoke(weatherDict);
    }

    // =========================================================
    // fetchSwell() — fetches swell forecast from Open-Meteo
    // Marine API. Free, no API key, flat array response (~1.2KB
    // for 24h). Returns dict with heights, periods, directions arrays.
    // =========================================================
    private var _swellCallback as Method or Null;

    function fetchSwell(lat as Float, lng as Float, callback as Method) as Void {
        _swellCallback = callback;

        var url = "https://marine-api.open-meteo.com/v1/marine"
            + "?latitude=" + lat.toString()
            + "&longitude=" + lng.toString()
            + "&hourly=swell_wave_height,swell_wave_period,swell_wave_direction,sea_surface_temperature"
            + "&forecast_days=1";

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(url, null, options, method(:onSwellResponse));
    }

    function onSwellResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            if (_swellCallback != null) { _swellCallback.invoke(null); }
            return;
        }

        var hourly = data["hourly"];
        if (hourly == null || !(hourly instanceof Dictionary)) {
            if (_swellCallback != null) { _swellCallback.invoke(null); }
            return;
        }

        var times = hourly["time"] as Array or Null;
        var heights = hourly["swell_wave_height"] as Array or Null;
        var periods = hourly["swell_wave_period"] as Array or Null;
        var dirs = hourly["swell_wave_direction"] as Array or Null;

        if (times == null || heights == null || periods == null || dirs == null || times.size() == 0) {
            if (_swellCallback != null) { _swellCallback.invoke(null); }
            return;
        }

        var result = {} as Dictionary<String, Application.PropertyValueType>;
        result["times"] = times as Application.PropertyValueType;
        result["heights"] = heights as Application.PropertyValueType;
        result["periods"] = periods as Application.PropertyValueType;
        result["directions"] = dirs as Application.PropertyValueType;

        // Sea surface temperature — hourly array, same pattern as swell
        var sst = hourly["sea_surface_temperature"] as Array or Null;
        if (sst != null) {
            result["seaSurfaceTemps"] = sst as Application.PropertyValueType;
        }

        if (_swellCallback != null) {
            _swellCallback.invoke(result);
        }
    }

    // =========================================================
    // fetchSurfWind() — Surf mode: fetches 24h hourly wind
    // forecast from Open-Meteo. Response ~986 bytes.
    // Returns dict with "speeds" and "directions" flat arrays.
    // =========================================================
    private var _surfWindCallback as Method or Null;

    function fetchSurfWind(lat as Float, lon as Float, callback as Method) as Void {
        _surfWindCallback = callback;

        var url = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + lat.toString()
            + "&longitude=" + lon.toString()
            + "&hourly=wind_speed_10m,wind_direction_10m"
            + "&daily=sunrise,sunset"
            + "&forecast_days=1"
            + "&timezone=auto"
            + "&wind_speed_unit=ms";

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(url, null, options, method(:onSurfWindResponse));
    }

    // Callback for Open-Meteo surf wind forecast response
    function onSurfWindResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            if (_surfWindCallback != null) { _surfWindCallback.invoke(null); }
            return;
        }

        var hourly = data["hourly"];
        if (hourly == null || !(hourly instanceof Dictionary)) {
            if (_surfWindCallback != null) { _surfWindCallback.invoke(null); }
            return;
        }

        var speeds = hourly["wind_speed_10m"] as Array or Null;
        var dirs = hourly["wind_direction_10m"] as Array or Null;

        if (speeds == null || dirs == null || speeds.size() == 0) {
            if (_surfWindCallback != null) { _surfWindCallback.invoke(null); }
            return;
        }

        var result = {} as Dictionary<String, Application.PropertyValueType>;
        result["speeds"] = speeds as Application.PropertyValueType;
        result["directions"] = dirs as Application.PropertyValueType;

        // Extract sunrise/sunset for surf spot
        var daily = data["daily"];
        if (daily != null && daily instanceof Dictionary) {
            var utcOffset = data["utc_offset_seconds"] as Number or Null;
            if (utcOffset == null) { utcOffset = 0; }
            var sunriseArr = daily["sunrise"] as Array or Null;
            var sunsetArr = daily["sunset"] as Array or Null;
            if (sunriseArr != null && sunriseArr.size() > 0 && sunriseArr[0] != null) {
                var srUnix = parseLocalISOToUnix(sunriseArr[0] as String, utcOffset);
                if (srUnix != null) { result["sunrise"] = srUnix as Application.PropertyValueType; }
            }
            if (sunsetArr != null && sunsetArr.size() > 0 && sunsetArr[0] != null) {
                var ssUnix = parseLocalISOToUnix(sunsetArr[0] as String, utcOffset);
                if (ssUnix != null) { result["sunset"] = ssUnix as Application.PropertyValueType; }
            }
        }

        if (_surfWindCallback != null) {
            _surfWindCallback.invoke(result);
        }
    }

    // =========================================================
    // parseLocalISOToUnix() — Converts Open-Meteo local time
    // ISO string (e.g. "2026-03-23T07:12") to Unix timestamp.
    // Open-Meteo returns local time when timezone=auto.
    // Gregorian.moment() interprets as UTC, so we subtract the
    // utc_offset_seconds to get the correct Unix time.
    // =========================================================
    private function parseLocalISOToUnix(isoStr as String, utcOffset as Number) as Number or Null {
        // Format: "YYYY-MM-DDTHH:MM" (16 chars minimum)
        if (isoStr.length() < 16) { return null; }

        var year = isoStr.substring(0, 4).toNumber();
        var month = isoStr.substring(5, 7).toNumber();
        var day = isoStr.substring(8, 10).toNumber();
        var hour = isoStr.substring(11, 13).toNumber();
        var min = isoStr.substring(14, 16).toNumber();

        if (year == null || month == null || day == null || hour == null || min == null) {
            return null;
        }

        // Gregorian.moment() treats input as UTC.
        // The input is local time, so subtract utcOffset to get UTC.
        var moment = Gregorian.moment({
            :year => year,
            :month => month,
            :day => day,
            :hour => hour,
            :minute => min,
            :second => 0
        });

        return moment.value() - utcOffset;
    }

}
