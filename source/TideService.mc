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
    private var _backupApiKey as String or Null;
    private var _fetchLat as Float;
    private var _fetchLng as Float;

    function initialize(callback as Method) {
        _callback = callback;
        _backupApiKey = null;
        _fetchLat = 0.0f;
        _fetchLng = 0.0f;
    }

    // Set backup API key for retry on failure
    function setBackupKey(key as String or Null) as Void {
        _backupApiKey = key;
    }

    // Builds StormGlass URL with 48h window, sets Authorization header, makes async request
    function fetch(lat as Float, lng as Float, apiKey as String) as Void {
        _fetchLat = lat;
        _fetchLng = lng;
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
        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            // Try backup key if available
            if (_backupApiKey != null && !_backupApiKey.equals("")) {
                var backupKey = _backupApiKey;
                _backupApiKey = null; // Prevent infinite retry
                fetch(_fetchLat, _fetchLng, backupKey);
                return;
            }
            _callback.invoke(null);
            return;
        }

        // Check quota: meta.requestCount vs meta.dailyQuota
        var meta = data["meta"];
        if (meta != null && meta instanceof Dictionary) {
            var requestCount = meta["requestCount"];
            var dailyQuota = meta["dailyQuota"];
            if (requestCount != null && dailyQuota != null) {
                if (requestCount >= dailyQuota) {
                    Application.Storage.setValue("stormGlassQuotaExhausted", true);
                }
            }
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
    // fetchSwell() — fetches swell + wind data from StormGlass
    // /v2/weather/point endpoint. Uses a separate callback from
    // tide fetching. Returns closest hourly entry to now.
    // =========================================================
    function fetchSwell(lat as Float, lng as Float, apiKey as String, callback as Method) as Void {
        _fetchLat = lat;
        _fetchLng = lng;
        var now = Time.now();
        var todayInfo = Gregorian.info(now, Time.FORMAT_SHORT);
        var startMoment = Gregorian.moment({
            :year => todayInfo.year,
            :month => todayInfo.month,
            :day => todayInfo.day,
            :hour => 0,
            :minute => 0,
            :second => 0
        });
        var startUnix = startMoment.value();
        var endUnix = startUnix + 86400;

        var url = "https://api.stormglass.io/v2/weather/point"
            + "?lat=" + lat.toString()
            + "&lng=" + lng.toString()
            + "&params=swellHeight,swellPeriod,swellDirection,windSpeed,windDirection"
            + "&start=" + startUnix.toString()
            + "&end=" + endUnix.toString();

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => {
                "Authorization" => apiKey
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        // Store callback for swell response
        _swellCallback = callback;
        Communications.makeWebRequest(url, null, options, method(:onSwellResponse));
    }

    private var _swellCallback as Method or Null;

    function onSwellResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            // Try backup key if available
            if (_backupApiKey != null && !_backupApiKey.equals("") && _swellCallback != null) {
                var backupKey = _backupApiKey;
                _backupApiKey = null;
                fetchSwell(_fetchLat, _fetchLng, backupKey, _swellCallback);
                return;
            }
            if (_swellCallback != null) {
                _swellCallback.invoke(null);
            }
            return;
        }

        // Check quota
        var meta = data["meta"];
        if (meta != null && meta instanceof Dictionary) {
            var requestCount = meta["requestCount"];
            var dailyQuota = meta["dailyQuota"];
            if (requestCount != null && dailyQuota != null) {
                if (requestCount >= dailyQuota) {
                    Application.Storage.setValue("surf_stormGlassQuotaExhausted", true);
                }
            }
        }

        var hours = data["hours"];
        if (hours == null || !(hours instanceof Array) || hours.size() == 0) {
            if (_swellCallback != null) {
                _swellCallback.invoke(null);
            }
            return;
        }

        // Find hourly entry closest to now
        var now = Time.now().value();
        var bestEntry = null;
        var bestDiff = 999999999;

        for (var i = 0; i < hours.size(); i++) {
            var entry = hours[i];
            if (entry != null && entry instanceof Dictionary) {
                var timeStr = entry["time"];
                if (timeStr != null) {
                    var entryTime = parseISOToUnix(timeStr as String);
                    if (entryTime != null) {
                        var diff = (entryTime - now).abs();
                        if (diff < bestDiff) {
                            bestDiff = diff;
                            bestEntry = entry;
                        }
                    }
                }
            }
        }

        if (bestEntry == null) {
            if (_swellCallback != null) {
                _swellCallback.invoke(null);
            }
            return;
        }

        // Extract sg values
        var result = {} as Dictionary<String, Application.PropertyValueType>;
        var sh = bestEntry["swellHeight"];
        if (sh != null && sh instanceof Dictionary) {
            result["swellHeight"] = sh["sg"] as Application.PropertyValueType;
        }
        var sp = bestEntry["swellPeriod"];
        if (sp != null && sp instanceof Dictionary) {
            result["swellPeriod"] = sp["sg"] as Application.PropertyValueType;
        }
        var sd = bestEntry["swellDirection"];
        if (sd != null && sd instanceof Dictionary) {
            result["swellDirection"] = sd["sg"] as Application.PropertyValueType;
        }
        var ws = bestEntry["windSpeed"];
        if (ws != null && ws instanceof Dictionary) {
            result["windSpeed"] = ws["sg"] as Application.PropertyValueType;
        }
        var wd = bestEntry["windDirection"];
        if (wd != null && wd instanceof Dictionary) {
            result["windDeg"] = wd["sg"] as Application.PropertyValueType;
        }

        if (_swellCallback != null) {
            _swellCallback.invoke(result);
        }
    }

}
