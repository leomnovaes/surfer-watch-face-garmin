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
    private var _lat as Float;
    private var _lng as Float;
    private var _triedBackup as Boolean;

    function initialize(callback as Method) {
        _callback = callback;
        _lat = 0.0f;
        _lng = 0.0f;
        _triedBackup = false;
    }

    // Builds StormGlass URL with 72h window from local midnight, sets Authorization header
    function fetch(lat as Float, lng as Float, apiKey as String) as Void {
        _lat = lat;
        _lng = lng;
        // 72h window from local midnight today — covers today + tomorrow + day after
        // Time.today() returns start of today in local time as a Moment
        var startUnix = Time.today().value();
        var endUnix = startUnix + (72 * 3600);

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
        System.println("TIDE: onTideResponse code=" + responseCode.toString());
        Application.Storage.setValue("sgLastResponseCode", responseCode);

        // On 402 (quota exhausted), immediately retry with backup key if available
        if (responseCode == 402 && !_triedBackup) {
            var backupKey = Application.Properties.getValue("StormGlassBackupApiKey") as String or Null;
            if (backupKey != null && !backupKey.equals("")) {
                _triedBackup = true;
                fetch(_lat, _lng, backupKey);
                return;
            }
        }

        if (responseCode != 200 || data == null || !(data instanceof Dictionary)) {
            _callback.invoke(null);
            return;
        }

        // Parse response data array — minimal parsing for background memory
        var dataArray = data["data"];
        if (dataArray == null || !(dataArray instanceof Array)) {
            _callback.invoke(null);
            return;
        }

        // Parse into flat arrays — much less memory than array of Dictionaries
        var heights = [] as Array;
        var times = [] as Array;
        var types = [] as Array;
        for (var i = 0; i < dataArray.size(); i++) {
            var entry = dataArray[i];
            if (entry != null && entry instanceof Dictionary) {
                var height = entry["height"];
                var timeStr = entry["time"];
                var type = entry["type"];

                if (timeStr != null && type != null) {
                    var unixTime = parseISOToUnix(timeStr as String);
                    if (unixTime != null) {
                        heights.add(height);
                        times.add(unixTime);
                        types.add(type.equals("high") ? 1 : 0);
                    }
                }
            }
        }

        if (heights.size() == 0) {
            _callback.invoke(null);
            return;
        }

        // Return as dict of flat arrays
        var result = {} as Dictionary<String, Application.PropertyValueType>;
        result["heights"] = heights as Application.PropertyValueType;
        result["times"] = times as Application.PropertyValueType;
        result["types"] = types as Application.PropertyValueType;
        _callback.invoke(result);
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

}
