import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
class TideService {

    private var _callback as Method;

    function initialize(callback as Method) {
        _callback = callback;
    }

    // Builds StormGlass URL with 48h window, sets Authorization header, makes async request
    function fetch(lat as Float, lng as Float, apiKey as String) as Void {
        // Calculate 48h window: start of current day UTC to end of next day UTC
        var now = Time.now();
        var todayInfo = Gregorian.info(now, Time.FORMAT_SHORT);
        // Start of today UTC (midnight)
        var startMoment = Gregorian.moment({
            :year => todayInfo.year,
            :month => todayInfo.month,
            :day => todayInfo.day,
            :hour => 0,
            :minute => 0,
            :second => 0
        });
        var startUnix = startMoment.value();
        // End of tomorrow UTC (48h from start of today)
        var endUnix = startUnix + (48 * 3600);

        var url = "https://api.stormglass.io/v2/tide/extremes/point"
            + "?lat=" + lat.toString()
            + "&lng=" + lng.toString()
            + "&start=" + startUnix.toString()
            + "&end=" + endUnix.toString()
            + "&datum=MLLW";

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => {
                "Authorization" => apiKey
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(url, null, options, method(:onTideResponse));
    }

    // Callback for StormGlass response
    function onTideResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        System.println("TIDE: response code=" + responseCode);
        Application.Storage.setValue("sgLastResponseCode", responseCode);
        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            _callback.invoke(null);
            return;
        }

        // Check quota (informational only — backup key handles exhaustion)
        var meta = data["meta"];
        if (meta != null && meta instanceof Dictionary) {
            // Quota info available but not used for gating
        }

        // Parse response data array — minimal parsing for background memory
        var dataArray = data["data"];
        if (dataArray == null || !(dataArray instanceof Array)) {
            _callback.invoke(null);
            return;
        }

        var results = [] as Array;
        for (var i = 0; i < dataArray.size(); i++) {
            var entry = dataArray[i];
            if (entry != null && entry instanceof Dictionary) {
                var height = entry["height"];
                var timeStr = entry["time"];
                var type = entry["type"];

                if (timeStr != null && type != null) {
                    // Convert ISO time string to Unix timestamp
                    var unixTime = parseISOToUnix(timeStr as String);
                    if (unixTime != null) {
                        var item = {} as Dictionary<String, Application.PropertyValueType>;
                        item["height"] = height as Application.PropertyValueType;
                        item["time"] = unixTime as Application.PropertyValueType;
                        item["type"] = type as Application.PropertyValueType;
                        results.add(item);
                    }
                }
            }
        }

        if (results.size() == 0) {
            _callback.invoke(null);
            return;
        }

        _callback.invoke(results);
    }

    // Parse ISO 8601 time string (e.g. "2024-03-18T14:32:00+00:00") to Unix timestamp
    // StormGlass returns UTC times. Gregorian.moment() interprets as LOCAL time,
    // so we must compensate by adding the local timezone offset.
    private function parseISOToUnix(isoStr as String) as Number or Null {
        // Expected format: "YYYY-MM-DDTHH:MM:SS+00:00"
        // We need at least 19 chars for "YYYY-MM-DDTHH:MM:SS"
        if (isoStr.length() < 19) {
            return null;
        }

        var year = isoStr.substring(0, 4).toNumber();
        var month = isoStr.substring(5, 7).toNumber();
        var day = isoStr.substring(8, 10).toNumber();
        var hour = isoStr.substring(11, 13).toNumber();
        var min = isoStr.substring(14, 16).toNumber();
        var sec = isoStr.substring(17, 19).toNumber();

        if (year == null || month == null || day == null ||
            hour == null || min == null || sec == null) {
            return null;
        }

        // Gregorian.moment() interprets input as UTC (confirmed by Garmin forum testing).
        // StormGlass returns UTC times, so we can feed them directly.
        var moment = Gregorian.moment({
            :year => year,
            :month => month,
            :day => day,
            :hour => hour,
            :minute => min,
            :second => sec
        });

        return moment.value();
    }

    // =========================================================
    // fetchSwell() — fetches swell forecast from Open-Meteo
    // Marine API. Free, no API key, flat array response (~1.2KB
    // for 24h). Returns array of {time, height, period, direction}.
    // =========================================================
    function fetchSwell(lat as Float, lng as Float, callback as Method) as Void {
        var url = "https://marine-api.open-meteo.com/v1/marine"
            + "?latitude=" + lat.toString()
            + "&longitude=" + lng.toString()
            + "&hourly=swell_wave_height,swell_wave_period,swell_wave_direction"
            + "&forecast_days=1";

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        _swellCallback = callback;
        Communications.makeWebRequest(url, null, options, method(:onSwellResponse));
    }

    private var _swellCallback as Method or Null;

    function onSwellResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        System.println("SWELL: response code=" + responseCode);
        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            if (_swellCallback != null) {
                _swellCallback.invoke(null);
            }
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

        // Build flat array of hourly entries
        var results = [] as Array;
        for (var i = 0; i < times.size(); i++) {
            var entry = {} as Dictionary<String, Application.PropertyValueType>;
            entry["time"] = times[i] as Application.PropertyValueType;
            entry["swellHeight"] = (i < heights.size()) ? heights[i] as Application.PropertyValueType : null;
            entry["swellPeriod"] = (i < periods.size()) ? periods[i] as Application.PropertyValueType : null;
            entry["swellDirection"] = (i < dirs.size()) ? dirs[i] as Application.PropertyValueType : null;
            results.add(entry);
        }

        if (_swellCallback != null) {
            _swellCallback.invoke(results);
        }
    }

}
