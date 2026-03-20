import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.WatchUi;

class SurferWatchFaceView extends WatchUi.WatchFace {

    // --- Layout constants — Top Section ---
    private static const ROW_SPACING_TOP = 23;
    private static const TOP_COL1_X = 1;
    private static const TOP_COL2_X = 85;
    private static const TOP_ROW1_Y = 2;
    private static const TOP_ROW2_Y = TOP_ROW1_Y + ROW_SPACING_TOP;
    private static const TOP_ROW3_Y = TOP_ROW2_Y + ROW_SPACING_TOP;
    private static const SPACER = 4;

    // --- Layout constants — Heart Rate Circle ---
    // Sub-screen circle from simulator.json: x=113, y=1, 62x62
    // Center = (144, 31), radius = 31
    private static const HR_CENTER_X = 144;
    private static const HR_CENTER_Y = 31;
    private static const HR_RADIUS = 31;

    // --- Layout constants — Middle Section ---
    private static const MID_Y = 76;
    private static const MID_LEFT_X = 22;
    private static const MID_CENTER_X = 88;
    // Right column 2x2 grid
    private static const MID_RIGHT_LEFT_X = 132;
    private static const MID_RIGHT_RIGHT_X = 174;
    private static const MID_RIGHT_TOP_Y = MID_Y - 2;
    private static const MID_RIGHT_BOTTOM_Y = MID_Y + 18;
    private static const MID_ICON_Y = MID_Y;
    private static const MID_TEXT_Y = MID_Y + 18;

    // --- Layout constants — Dividers ---
    private static const DIV_TOP_Y = 68;
    private static const DIV_LEFT_X = 8;
    private static const DIV_RIGHT_X = 160;

    // --- Layout constants — Date Row ---
    private static const DATE_Y = 114;
    private static const DATE_TEXT_X = 88;

    // --- Layout constants — Weather Widget ---
    private static const WX_Y = 139;
    private static const WX_Y_EDGE = 130;
    private static const WX_TEXT_Y = WX_Y + 18;
    private static const WX_TEXT_Y_EDGE = WX_Y_EDGE + 18;
    private static const WX_COL1_X = 42;
    private static const WX_COL2_X = 88;
    private static const WX_COL3_X = 134;

    // --- Icon font resources (loaded in onLayout) ---
    private var crystalIconsFont = null;
    private var weatherIconsFont = null;
    private var moonIconsFont = null;
    private var seg34IconsFont = null;
    private var surferIconsFont = null;

    // --- Clock font resources ---
    private var clockSaira40 = null;
    private var clockRajdhani40 = null;

    // --- Sleep state: true when watch is in low power mode (no wrist gesture) ---
    private var isSleeping = false;

    // --- Crystal Icons glyph characters (from Crystal Face) ---
    private static const IC_NOTIFICATIONS = "5";
    private static const IC_SUNRISE = ">";
    private static const IC_SUNSET = "?";

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        crystalIconsFont = WatchUi.loadResource(Rez.Fonts.CrystalIcons);
        weatherIconsFont = WatchUi.loadResource(Rez.Fonts.WeatherIcons);
        moonIconsFont = WatchUi.loadResource(Rez.Fonts.MoonIcons);
        seg34IconsFont = WatchUi.loadResource(Rez.Fonts.Seg34Icons);
        surferIconsFont = WatchUi.loadResource(Rez.Fonts.SurferIcons);
        clockSaira40 = WatchUi.loadResource(Rez.Fonts.ClockSaira40);
        clockRajdhani40 = WatchUi.loadResource(Rez.Fonts.ClockRajdhani40);
    }

    function onShow() as Void {
    }

    // --- onUpdate: draws everything in order per design §2.5 ---
    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var dm = (Application.getApp() as SurferWatchFaceApp).getDataManager();
        if (dm != null) {
            dm.updateSensorData();
            dm.computeMoonPhase();
            dm.computeNextTide();
        }

        drawHrCircle(dc, dm);
        drawTopSection(dc, dm);
        drawDividers(dc);
        drawMiddleSection(dc, dm);
        drawDateRow(dc);
        drawWeatherWidget(dc, dm);
    }

    // =========================================================
    // Drawing helper — compensates for font top padding so that
    // the Y coordinate = top pixel of visible text. Since icons
    // will also be rendered via drawText with an icon font, both
    // text and icons share the same padding behavior and align
    // naturally at the same Y.
    // =========================================================
    private function drawTextAligned(dc as Dc, x as Number, y as Number, font, text as String, justify as Number) as Void {
        var fontHeight = dc.getFontHeight(font);
        var ascent = Graphics.getFontAscent(font);
        var topPadding = fontHeight - ascent;
        dc.drawText(x, y - topPadding, font, text, justify);
    }

    // Formats a Unix timestamp to "H:MM" or "HH:MM" respecting 12/24hr setting
    private function formatUnixTime(unixTime as Number) as String {
        var moment = new Time.Moment(unixTime);
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        var hours = info.hour;
        var is24Hour = System.getDeviceSettings().is24Hour;
        if (!is24Hour) {
            var suffix = hours >= 12 ? "p" : "a";
            hours = hours % 12;
            if (hours == 0) { hours = 12; }
            return hours.toString() + ":" + info.min.format("%02d") + suffix;
        }
        return hours.toString() + ":" + info.min.format("%02d");
    }

    // =========================================================
    // Icon drawing methods — each renders a single icon glyph.
    // Currently uses text placeholders; will be swapped to icon
    // font glyphs in Task 27. All go through drawTextAligned so
    // they share the same coordinate system as text.
    // =========================================================
    private function drawIconBattery(dc as Dc, x as Number, y as Number, dm as DataManager) as Void {
        var pct = dm.battery;

        // Battery body: 18x10 rectangle
        var bx = x;
        var by = y + 2; // vertically center with text
        var bw = 18;
        var bh = 10;
        dc.drawRectangle(bx, by, bw, bh);
        // Battery tip (positive terminal): 2x4 nub on right
        dc.fillRectangle(bx + bw, by + 3, 2, 4);
        // Fill bar inside (1px inset)
        var fillW = ((bw - 2) * pct / 100);
        if (fillW > 0) {
            dc.fillRectangle(bx + 1, by + 1, fillW, bh - 2);
        }
    }

    private function drawIconNotification(dc as Dc, x as Number, y as Number) as Void {
        if (crystalIconsFont != null) {
            drawTextAligned(dc, x, y, crystalIconsFont, IC_NOTIFICATIONS, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    private function drawIconTide(dc as Dc, x as Number, y as Number, isHigh as Boolean) as Void {
        if (surferIconsFont != null) {
            var glyph = isHigh ? "H" : "L";
            drawTextAligned(dc, x, y, surferIconsFont, glyph, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    private function drawIconSun(dc as Dc, x as Number, y as Number, isSunrise as Boolean) as Void {
        var glyph = isSunrise ? IC_SUNRISE : IC_SUNSET;
        drawTextAligned(dc, x, y, Graphics.FONT_XTINY, glyph, Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function drawIconBluetooth(dc as Dc, x as Number, y as Number) as Void {
        if (seg34IconsFont != null) {
            drawTextAligned(dc, x, y, seg34IconsFont, "L", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawIconMoon(dc as Dc, x as Number, y as Number, dm as DataManager) as Void {
        if (moonIconsFont != null) {
            var glyph = "0";
            if (dm.moonPhase != null) {
                var idx = (dm.moonPhase * 8).toNumber() % 8;
                glyph = idx.toString();
            }
            drawTextAligned(dc, x, y, moonIconsFont, glyph, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    private function drawIconWeather(dc as Dc, x as Number, y as Number, dm as DataManager) as Void {
        if (weatherIconsFont != null && dm.weatherConditionId != null) {
            var isNight = false;
            if (dm.sunrise != null && dm.sunset != null) {
                var now = Time.now().value();
                isNight = (now < dm.sunrise || now >= dm.sunset);
            }
            var glyph = owmToWeatherGlyph(dm.weatherConditionId, isNight);
            drawTextAligned(dc, x, y, weatherIconsFont, glyph, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Maps OWM condition code to Crystal Face Weather Icons glyph character
    // Day icons: A-I, Night icons: a-h
    private function owmToWeatherGlyph(code as Number, isNight as Boolean) as String {
        if (code == 800) { return isNight ? "f" : "H"; }                    // clear
        if (code >= 801 && code <= 803) { return isNight ? "h" : "A"; }     // cloudy
        if (code == 804) { return "I"; }                                     // overcast (same day/night)
        if (code >= 200 && code <= 232) { return isNight ? "e" : "C"; }     // thunderstorm
        if (code >= 300 && code <= 321) { return isNight ? "c" : "E"; }     // showers
        if (code >= 500 && code <= 531) { return isNight ? "b" : "D"; }     // rain
        if (code >= 600 && code <= 622) { return isNight ? "d" : "F"; }     // snow
        if (code >= 700 && code <= 781) { return isNight ? "h" : "G"; }     // fog/haze
        if (code == 900 || code == 781) { return "g"; }                      // tornado (same day/night)
        return isNight ? "f" : "H"; // fallback: clear
    }

    private function drawIconWind(dc as Dc, x as Number, y as Number, dm as DataManager) as Void {
        if (dm.windDeg != null) {
            drawWindArrow(dc, x, y + 7, dm.windDeg, 7);
        }
    }

    // Draws a wind direction arrow (swallow-tail triangle) at center cx,cy
    // rotated to `degrees` (meteorological: 0=N, 90=E, 180=S, 270=W).
    // Arrow points in the direction wind blows FROM.
    // size = half-height of the arrow.
    private function drawWindArrow(dc as Dc, cx as Number, cy as Number, degrees as Number, size as Number) as Void {
        var rad = degrees * Math.PI / 180.0;
        var sinA = Math.sin(rad);
        var cosA = Math.cos(rad);

        // Arrow shape (pointing up = north, before rotation):
        //   tip:         (0, -size)
        //   left base:   (-size*0.6, size)
        //   tail notch:  (0, size*0.4)
        //   right base:  (size*0.6, size)
        var s = size.toFloat();
        var pts = [
            [0.0, -s],              // tip
            [-s * 0.6, s],          // left base
            [0.0, s * 0.4],         // tail notch (swallow tail)
            [s * 0.6, s]            // right base
        ];

        // Rotate each point and translate to cx,cy
        var poly = new [4];
        for (var i = 0; i < 4; i++) {
            var px = (pts[i] as Array)[0] as Float;
            var py = (pts[i] as Array)[1] as Float;
            var rx = px * cosA - py * sinA;
            var ry = px * sinA + py * cosA;
            poly[i] = [cx + rx.toNumber(), cy + ry.toNumber()];
        }

        dc.fillPolygon(poly);
    }

    private function drawIconUmbrella(dc as Dc, x as Number, y as Number) as Void {
        if (surferIconsFont != null) {
            drawTextAligned(dc, x, y, surferIconsFont, "U", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawIconHeart(dc as Dc, x as Number, y as Number) as Void {
        if (seg34IconsFont != null) {
            drawTextAligned(dc, x, y, seg34IconsFont, "h", Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // =========================================================
    // Composite component methods — each renders a reusable UI
    // unit (text + icon) that can be placed anywhere via x, y.
    //
    // Anchoring rule:
    //   text-first (text left, icon right): x = anchor point
    //     between text and icon. Text is RIGHT-justified to x,
    //     icon is LEFT-justified from x + SPACER.
    //   icon-first (icon left, text right): x = left edge.
    //     Icon is LEFT-justified from x, text is LEFT-justified
    //     from x + iconWidth + SPACER.
    // =========================================================

    // Text left, icon right — x is the anchor between them
    private function drawBatteryWithPercent(dc as Dc, x as Number, y as Number, percent as Number, dm as DataManager) as Void {
        drawTextAligned(dc, x - SPACER, y, Graphics.FONT_XTINY, percent.toString() + "%", Graphics.TEXT_JUSTIFY_RIGHT);
        drawIconBattery(dc, x, y, dm);
    }

    // Text left, icon right — x is the anchor between them
    private function drawNotificationWithCount(dc as Dc, x as Number, y as Number, count as Number) as Void {
        drawTextAligned(dc, x - SPACER, y, Graphics.FONT_XTINY, count.toString(), Graphics.TEXT_JUSTIFY_RIGHT);
        drawIconNotification(dc, x, y-4);
    }

    // Icon left, text right — x is the left edge
    private function drawTideInfo(dc as Dc, x as Number, y as Number, isHigh as Boolean, time as String, height as String) as Void {
        drawIconTide(dc, x, y, isHigh);
        var iconWidth = surferIconsFont != null ? dc.getTextWidthInPixels("H", surferIconsFont) : 15;
        drawTextAligned(dc, x + iconWidth + SPACER-5, y, Graphics.FONT_XTINY, time, Graphics.TEXT_JUSTIFY_LEFT);
        drawTextAligned(dc, x + 105, y, Graphics.FONT_XTINY, height, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // Icon centered above text — x is the center of the column
    private function drawSunInfo(dc as Dc, centerX as Number, iconY as Number, textY as Number, isSunrise as Boolean, time as String) as Void {
        // Icon centered on column — use Crystal Icons font
        var glyph = isSunrise ? IC_SUNRISE : IC_SUNSET;
        var font = crystalIconsFont != null ? crystalIconsFont : Graphics.FONT_XTINY;
        drawTextAligned(dc, centerX, iconY, font, glyph, Graphics.TEXT_JUSTIFY_CENTER);
        // Time centered below
        drawTextAligned(dc, centerX, textY, Graphics.FONT_XTINY, time, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Right column 2x2 grid:
    //   top-left: moon icon    top-right: illumination %
    //   bottom-left: AM/PM     bottom-right: seconds (hidden by default)
    private function drawRightColumn(dc as Dc, ampm as String, seconds as String, dm as DataManager) as Void {
        drawIconMoon(dc, MID_RIGHT_LEFT_X+2, MID_RIGHT_TOP_Y, dm);
        // Bottom-left: AM/PM
        drawTextAligned(dc, MID_RIGHT_LEFT_X, MID_RIGHT_BOTTOM_Y, Graphics.FONT_XTINY, ampm, Graphics.TEXT_JUSTIFY_LEFT);
        // Bottom-right: seconds (only when awake — wrist gesture active)
        if (!isSleeping) {
            drawTextAligned(dc, MID_RIGHT_RIGHT_X, MID_RIGHT_BOTTOM_Y, Graphics.FONT_XTINY, seconds, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    // Icon centered above text — for weather widget columns
    private function drawWeatherCol(dc as Dc, centerX as Number, iconY as Number, textY as Number, icon as String, value as String) as Void {
        drawTextAligned(dc, centerX, iconY, Graphics.FONT_XTINY, icon, Graphics.TEXT_JUSTIFY_CENTER);
        drawTextAligned(dc, centerX, textY, Graphics.FONT_XTINY, value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // --- Layout constants — HR Circle content positions (tweak these) ---
    private static const HR_HEART_X = 144;
    private static const HR_HEART_Y = 14;
    private static const HR_TEXT_X = 144;
    private static const HR_TEXT_Y = 34;
    private static const STRESS_ARC_WIDTH = 6;

    // =========================================================
    // Section renderers — called from onUpdate()
    // =========================================================
    private function drawHrCircle(dc as Dc, dm as DataManager) as Void {

        // Filled white circle
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(HR_CENTER_X, HR_CENTER_Y, HR_RADIUS);

        // Stress arc
        var stressVal = 0;
        if (dm.stress != null) {
            stressVal = dm.stress;
        }
        drawStressArc(dc, HR_CENTER_X, HR_CENTER_Y, HR_RADIUS, STRESS_ARC_WIDTH, stressVal);

        // Heart icon
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        drawHrHeart(dc, HR_HEART_X, HR_HEART_Y);

        // Heart rate text
        var hrText = "--";
        if (dm.heartRate != null) {
            hrText = dm.heartRate.toString();
        }
        drawHrText(dc, HR_TEXT_X, HR_TEXT_Y, hrText);

        // Restore white for subsequent drawing
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    // Draws the heart icon at (x, y) — black, centered
    private function drawHrHeart(dc as Dc, x as Number, y as Number) as Void {
        if (seg34IconsFont != null) {
            dc.drawText(x, y, seg34IconsFont, "h", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Draws the heart rate number at (x, y) — black, centered
    private function drawHrText(dc as Dc, x as Number, y as Number, text as String) as Void {
        dc.drawText(x, y, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Draws the stress arc gauge around a circle
    // cx, cy = circle center; radius = circle radius; barWidth = arc thickness; stressPercent = 0-100
    private function drawStressArc(dc as Dc, cx as Number, cy as Number, radius as Number, barWidth as Number, stressPercent as Number) as Void {
        var arcOuterR = radius;
        var arcInnerR = arcOuterR - barWidth;
        var arcMidR = arcOuterR - (barWidth / 2);
        var arcStartAngle = 60;  // 2 o'clock
        var arcEndAngle = 120;   // 10 o'clock
        var totalArcDeg = 300;   // clockwise from 60° through bottom to 120°

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);

        // Outer and inner borders
        dc.drawArc(cx, cy, arcOuterR, Graphics.ARC_CLOCKWISE, arcStartAngle, arcEndAngle);
        dc.drawArc(cx, cy, arcInnerR, Graphics.ARC_CLOCKWISE, arcStartAngle, arcEndAngle);

        // End caps — extend 1px past outer to close gap
        var capOuterR = arcOuterR + 1;
        var startRad = arcStartAngle * Math.PI / 180.0;
        var endRad = arcEndAngle * Math.PI / 180.0;
        dc.drawLine(
            cx + (arcInnerR * Math.cos(startRad)).toNumber(), cy - (arcInnerR * Math.sin(startRad)).toNumber(),
            cx + (capOuterR * Math.cos(startRad)).toNumber(), cy - (capOuterR * Math.sin(startRad)).toNumber());
        dc.drawLine(
            cx + (arcInnerR * Math.cos(endRad)).toNumber(), cy - (arcInnerR * Math.sin(endRad)).toNumber(),
            cx + (capOuterR * Math.cos(endRad)).toNumber(), cy - (capOuterR * Math.sin(endRad)).toNumber());

        // Fill: black portion proportional to stress %
        if (stressPercent > 0) {
            var blackDegrees = (totalArcDeg * stressPercent / 100);
            var fillEnd = arcStartAngle - blackDegrees;
            dc.setPenWidth(barWidth);
            dc.drawArc(cx, cy, arcMidR, Graphics.ARC_CLOCKWISE, arcStartAngle, fillEnd);
        }
        dc.setPenWidth(1);
    }

    private function drawTopSection(dc as Dc, dm as DataManager) as Void {
        // Row 1 — Battery (live)
        var batteryPercent = dm.battery;
        drawBatteryWithPercent(dc, TOP_COL2_X, TOP_ROW1_Y, batteryPercent, dm);

        // Row 2 — Bluetooth + Notifications (live)
        if (dm.bluetoothConnected) {
            drawIconBluetooth(dc, TOP_COL1_X+20, TOP_ROW2_Y-2);
        }
        var notifCount = dm.notificationCount;
        drawNotificationWithCount(dc, TOP_COL2_X-6, TOP_ROW2_Y, notifCount);

        // Row 3 — Tide (live)
        var tideIsHigh = true;
        var tideTimeStr = "--";
        var tideHeightStr = "--";
        if (dm.nextTideTime != null && dm.nextTideType != null) {
            tideIsHigh = dm.nextTideType.equals("high");
            tideTimeStr = formatUnixTime(dm.nextTideTime);
        }
        if (dm.currentTideHeight != null) {
            var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
            if (isMetric) {
                tideHeightStr = dm.currentTideHeight.format("%.1f") + "m";
            } else {
                tideHeightStr = (dm.currentTideHeight * 3.281).format("%.1f") + "ft";
            }
        }
        drawTideInfo(dc, TOP_COL1_X, TOP_ROW3_Y, tideIsHigh, tideTimeStr, tideHeightStr);
    }

    private function drawDividers(dc as Dc) as Void {
        dc.drawLine(DIV_LEFT_X, DIV_TOP_Y, DIV_RIGHT_X, DIV_TOP_Y);
    }

    private function drawMiddleSection(dc as Dc, dm as DataManager) as Void {
        // Left column — sunrise/sunset (live from OWM)
        var sunTime = "--";
        var isSunrise = true;
        if (dm.sunrise != null && dm.sunset != null) {
            var now = Time.now().value();
            if (now < dm.sunrise) {
                // Before sunrise — next event is sunrise
                isSunrise = true;
                sunTime = formatUnixTime(dm.sunrise);
            } else if (now < dm.sunset) {
                // After sunrise, before sunset — next event is sunset
                isSunrise = false;
                sunTime = formatUnixTime(dm.sunset);
            } else {
                // After sunset — next event is tomorrow's sunrise (show today's as placeholder)
                isSunrise = true;
                sunTime = formatUnixTime(dm.sunrise);
            }
        }
        drawSunInfo(dc, MID_LEFT_X, MID_ICON_Y-4, MID_TEXT_Y, isSunrise, sunTime);

        // Center — current time
        var clockTime = System.getClockTime();
        var hours = clockTime.hour;
        var is24Hour = System.getDeviceSettings().is24Hour;
        var ampm = "";
        if (!is24Hour) {
            ampm = hours >= 12 ? "pm" : "am";
            hours = hours % 12;
            if (hours == 0) { hours = 12; }
        }
        var timeString = hours.toString() + ":" + clockTime.min.format("%02d");
        var clockFont = clockSaira40;
        var fontSetting = Application.Properties.getValue("ClockFont");
        if (fontSetting != null && fontSetting == 1) {
            clockFont = clockRajdhani40;
        }
        dc.drawText(MID_CENTER_X, MID_Y + 14, clockFont, timeString, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Right column — 2x2 grid: moon, AM/PM, seconds
        var seconds = clockTime.sec.format("%02d");
        drawRightColumn(dc, ampm, seconds, dm);
    }

    private function drawDateRow(dc as Dc) as Void {
        // Live date: "Wed Mar 18"
        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_MEDIUM);
        var dateString = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.month.toUpper(), info.day]);
        drawTextAligned(dc, DATE_TEXT_X, DATE_Y, Graphics.FONT_XTINY, dateString, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawWeatherWidget(dc as Dc, dm as DataManager) as Void {
        // Check if weather data is available and not stale (>2h)
        var hasWeather = false;
        if (dm.owmFetchedAt != null) {
            var age = Time.now().value() - dm.owmFetchedAt;
            if (age < 7200) { // 2 hours
                hasWeather = true;
            }
        }

        // Col 1: weather icon + temperature
        var tempText = "--";
        if (hasWeather && dm.temperature != null) {
            var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
            var suffix = isMetric ? "C" : "F";
            tempText = dm.temperature.toNumber().toString() + "°" + suffix;
        }
        drawIconWeather(dc, WX_COL1_X, WX_Y_EDGE, dm);
        drawTextAligned(dc, WX_COL1_X, WX_TEXT_Y_EDGE, Graphics.FONT_XTINY, tempText, Graphics.TEXT_JUSTIFY_CENTER);

        // Col 2: wind icon + speed
        var windText = "--";
        if (hasWeather && dm.windSpeed != null) {
            var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
            var speed;
            var unit;
            if (isMetric) {
                // OWM metric returns m/s, convert to km/h
                speed = (dm.windSpeed * 3.6).toNumber();
                unit = "kph";
            } else {
                // OWM imperial returns mph directly
                speed = dm.windSpeed.toNumber();
                unit = "mph";
            }
            windText = speed.toString() + unit;
        }
        drawIconWind(dc, WX_COL2_X, WX_Y, dm);
        drawTextAligned(dc, WX_COL2_X, WX_TEXT_Y, Graphics.FONT_XTINY, windText, Graphics.TEXT_JUSTIFY_CENTER);

        // Col 3: umbrella icon + precipitation % (from Garmin built-in current weather)
        var precipText = "--";
        if (Weather has :getCurrentConditions) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null && conditions.precipitationChance != null) {
                precipText = conditions.precipitationChance.toString() + "%";
            }
        }
        drawIconUmbrella(dc, WX_COL3_X, WX_Y_EDGE);
        drawTextAligned(dc, WX_COL3_X, WX_TEXT_Y_EDGE, Graphics.FONT_XTINY, precipText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // =========================================================
    // onBackgroundData — NOT on the view, moved to App class
    // =========================================================

    // --- Lifecycle ---
    function onHide() as Void {
    }

    function onExitSleep() as Void {
        isSleeping = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        isSleeping = true;
        WatchUi.requestUpdate();
    }

}
