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
    private static const MID_RIGHT_TOP_Y = MID_Y-1;
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
    private var heartIconFont = null;

    // --- Clock font resources ---
    private var clockSaira40 = null;
    private var clockRajdhani40 = null;

    // --- Sleep state: true when watch is in low power mode (no wrist gesture) ---
    private var isSleeping = false;
    // --- Last wrist raise timestamp for double-gesture detection (surf mode) ---
    private var lastWristRaiseTime as Number = 0;

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
        heartIconFont = WatchUi.loadResource(Rez.Fonts.HeartIcon);
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
        if (dm == null) { return; }

        var surfMode = Application.Properties.getValue("SurfMode");

        if (surfMode != null && surfMode == 1) {
            // Surf mode
            dm.updateSensorData();
            dm.checkCopyGPS();
            dm.updateSurfSensors();
            dm.computeNextTide();
            dm.interpolateTideHeight();
            dm.computeMoonPhase();

            drawHrCircle_Surf(dc, dm);
            drawTopSection_Surf(dc, dm);
            drawDividers(dc);
            drawMiddleSection_Surf(dc, dm);
            if (dm.bottomToggleState == 0) {
                drawSwellSection(dc, dm);
            } else {
                drawTideCurve(dc, dm);
            }
        } else {
            // Shore mode
            dm.updateSensorData();
            dm.computeMoonPhase();
            dm.computeNextTide();

            var weatherSource = Application.Properties.getValue("WeatherSource");
            if (weatherSource == null || weatherSource == 0) {
                dm.updateGarminWeather();
                dm.computeSunriseSunset();
            }

            drawHrCircle(dc, dm);
            drawTopSection(dc, dm);
            drawDividers(dc);
            drawMiddleSection(dc, dm);
            drawDateRow(dc);
            drawWeatherWidget(dc, dm);
        }
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
                // Map 0.0-1.0 to 28 phases (chars '0' through 'K', ASCII 48-75)
                var idx = Math.round(dm.moonPhase * 28).toNumber() % 28;
                var charCode = 48 + idx;
                glyph = charCode.toChar().toString();
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
            var weatherSource = Application.Properties.getValue("WeatherSource");
            var glyph;
            if (weatherSource != null && weatherSource == 1) {
                glyph = owmToWeatherGlyph(dm.weatherConditionId, isNight);
            } else {
                glyph = garminToWeatherGlyph(dm.weatherConditionId, isNight);
            }
            drawTextAligned(dc, x, y, weatherIconsFont, glyph, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Maps OWM condition code to Erik Flowers Weather Icons glyph character
    // Day: A-V, Night: a-g. Full OWM mapping from erikflowers.github.io
    private function owmToWeatherGlyph(code as Number, isNight as Boolean) as String {
        // Clear
        if (code == 800) { return isNight ? "a" : "A"; }
        // Clouds
        if (code == 801 || code == 802) { return isNight ? "b" : "C"; }     // few/scattered → day-cloudy / night-cloudy
        if (code == 803) { return "D"; }                                      // broken clouds → cloudy (same day/night)
        if (code == 804) { return "D"; }                                      // overcast → cloudy (same day/night)
        // Thunderstorm (200-232)
        if (code >= 200 && code <= 202) { return isNight ? "e" : "F"; }      // thunderstorm with rain
        if (code >= 210 && code <= 221) { return isNight ? "e" : "F"; }      // thunderstorm
        if (code >= 230 && code <= 232) { return isNight ? "e" : "F"; }      // thunderstorm with drizzle
        // Drizzle (300-321)
        if (code == 300 || code == 301 || code == 321) { return isNight ? "d" : "G"; } // sprinkle
        if (code >= 302 && code <= 314) { return isNight ? "c" : "H"; }      // rain
        if (code == 500) { return isNight ? "d" : "G"; }                     // light rain → sprinkle
        // Rain (501-531)
        if (code >= 501 && code <= 504) { return isNight ? "c" : "H"; }      // rain
        if (code == 511) { return "K"; }                                      // freezing rain → rain-mix
        if (code >= 520 && code <= 522) { return isNight ? "d" : "I"; }      // showers
        if (code == 531) { return isNight ? "d" : "I"; }                      // ragged showers
        // Snow (600-622)
        if (code == 600 || code == 601 || code == 621 || code == 622) { return isNight ? "f" : "J"; } // snow
        if (code == 602) { return isNight ? "f" : "J"; }                      // heavy snow
        if (code >= 611 && code <= 612) { return "M"; }                       // sleet
        if (code >= 613 && code <= 620) { return "K"; }                       // rain-mix
        // Atmosphere (700-781)
        if (code == 701) { return "E"; }                                      // mist → fog
        if (code == 711) { return "N"; }                                      // smoke
        if (code == 721) { return "O"; }                                      // haze
        if (code == 731 || code == 761 || code == 762) { return "P"; }       // dust
        if (code == 741) { return "E"; }                                      // fog
        if (code == 771) { return "Q"; }                                      // squalls → cloudy-gusts
        if (code == 781) { return "R"; }                                      // tornado
        // Extreme
        if (code == 900) { return "R"; }                                      // tornado
        if (code == 901) { return "L"; }                                      // tropical storm
        if (code == 902) { return "S"; }                                      // hurricane
        if (code == 903) { return "T"; }                                      // cold
        if (code == 904) { return "U"; }                                      // hot
        if (code == 905) { return "V"; }                                      // windy
        return isNight ? "a" : "A"; // fallback: clear
    }

    // Maps Garmin Weather.CONDITION_* codes to weather icon glyphs
    // Garmin codes 0-53, mapped to same glyph set as OWM
    private function garminToWeatherGlyph(code as Number, isNight as Boolean) as String {
        // Clear/fair
        if (code == 0 || code == 40) { return isNight ? "a" : "A"; }
        // Partly cloudy/clear
        if (code == 1 || code == 22 || code == 23 || code == 52) { return isNight ? "b" : "B"; }
        // Mostly/fully cloudy
        if (code == 2 || code == 20) { return "D"; }
        // Rain
        if (code == 3 || code == 15) { return isNight ? "c" : "H"; }
        // Light rain
        if (code == 14 || code == 45) { return isNight ? "d" : "G"; }
        // Snow
        if (code == 4 || code == 17 || code == 43 || code == 46) { return isNight ? "f" : "J"; }
        // Light snow / flurries
        if (code == 16 || code == 48) { return isNight ? "f" : "J"; }
        // Windy
        if (code == 5) { return "V"; }
        // Thunderstorms
        if (code == 6 || code == 12 || code == 28) { return isNight ? "e" : "F"; }
        // Wintry mix / rain-snow
        if (code == 7 || code == 18 || code == 19 || code == 21 || code == 44 || code == 47 || code == 51) { return "K"; }
        // Fog
        if (code == 8) { return "E"; }
        // Hazy / haze
        if (code == 9 || code == 39) { return "O"; }
        // Hail / ice
        if (code == 10 || code == 34) { return "M"; }
        // Showers
        if (code == 11 || code == 24 || code == 25 || code == 26 || code == 27) { return isNight ? "d" : "I"; }
        // Unknown precipitation
        if (code == 13) { return isNight ? "c" : "H"; }
        // Mist
        if (code == 29) { return isNight ? "d" : "I"; }
        // Dust / sand / sandstorm
        if (code == 30 || code == 35 || code == 37) { return "P"; }
        // Drizzle
        if (code == 31) { return isNight ? "d" : "G"; }
        // Tornado
        if (code == 32) { return "R"; }
        // Smoke
        if (code == 33) { return "N"; }
        // Squall
        if (code == 36) { return "Q"; }
        // Volcanic ash
        if (code == 38) { return "P"; }
        // Hurricane / tropical storm
        if (code == 41) { return "S"; }
        if (code == 42) { return "L"; }
        // Freezing rain
        if (code == 49) { return "K"; }
        // Sleet
        if (code == 50) { return "M"; }
        return isNight ? "a" : "A"; // fallback: clear
    }

    private function drawIconWind(dc as Dc, x as Number, y as Number, dm as DataManager) as Void {
        if (dm.windDeg != null) {
            drawWindArrow(dc, x, y + WIND_ARROW_Y_OFFSET, dm.windDeg, WIND_ARROW_SIZE);
        }
    }

    // Draws a wind direction arrow (swallow-tail triangle) at center cx,cy
    // rotated to `degrees` (meteorological: 0=N, 90=E, 180=S, 270=W).
    // Arrow points in the direction wind blows FROM.
    // size = half-height of the arrow.
    private function drawWindArrow(dc as Dc, cx as Number, cy as Number, degrees as Number, size as Number) as Void {
        // Meteorological convention: degrees is where wind comes FROM
        // 0=N, 90=E, 180=S, 270=W (clockwise)
        // Screen: Y increases downward. Standard rotation is counter-clockwise.
        // Negate angle to convert clockwise meteorological to counter-clockwise math.
        var rad = -degrees * Math.PI / 180.0;
        var sinA = Math.sin(rad);
        var cosA = Math.cos(rad);

        // Arrow shape (pointing up = north, before rotation):
        //   tip:         (0, -size)
        //   left base:   (-size*0.6, size)
        //   tail notch:  (0, size*0.4)
        //   right base:  (size*0.6, size)
        var s = size.toFloat();
        var pts = [
            [0.0, -s],                          // tip
            [-s * WIND_ARROW_WIDTH, s],          // left base
            [0.0, s * WIND_ARROW_NOTCH],         // tail notch (swallow tail)
            [s * WIND_ARROW_WIDTH, s]            // right base
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

    // --- Layout constants — Wind Arrow (tweak these) ---
    private static const WIND_ARROW_SIZE =7;       // half-height in pixels (total height = size * 2)
    private static const WIND_ARROW_WIDTH = 0.8;    // half-width of base as fraction of size (1.0 = as wide as tall)
    private static const WIND_ARROW_NOTCH = 0.5;    // tail notch Y (1.0 = no tail/triangle, 0.0 = center, negative = deep tail)
    private static const WIND_ARROW_Y_OFFSET = 5;   // vertical offset from icon position

    // --- Layout constants — Tide Curve (tweak these) ---
    private static const TC_Y = 114;               // top Y of entire tide curve section (including labels)
    private static const TC_LABEL_HEIGHT = 16;      // vertical space reserved for labels above curve
    private static const TC_CURVE_HEIGHT = 36;      // height of the filled curve area in pixels
    private static const TC_LABEL_GAP = 2;          // gap between label text and curve edge
    private static const TC_LEFT_X = 14;            // left edge of curve
    private static const TC_RIGHT_X = 162;          // right edge of curve
    private static const TC_NOW_GAP_HALF = 2;       // half-width of the "now" gap in pixels
    private static const TC_TRI_WIDTH = 4;          // half-width of the "now" triangle
    private static const TC_TRI_HEIGHT = 5;         // height of the "now" triangle
    private static const TC_TRI_GAP = 3;            // gap between triangle tip and curve top
    private static const TC_HEIGHT_PAD = 0.1;       // padding fraction added to top of height range
    private static const TC_HEIGHT_PAD_BOTTOM = 0.25; // padding fraction added to bottom of height range (thicker base at low tide)

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
        if (heartIconFont != null) {
            dc.drawText(x, y, heartIconFont, "h", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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
        var arcStartAngle = 45;  // 2:30 o'clock
        var arcEndAngle = 135;   // 9:30 o'clock
        var totalArcDeg = 270;   // clockwise from 45° through bottom to 135°

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);

        // Outer and inner borders
        dc.drawArc(cx, cy, arcOuterR, Graphics.ARC_CLOCKWISE, arcStartAngle, arcEndAngle);
        dc.drawArc(cx, cy, arcInnerR, Graphics.ARC_CLOCKWISE, arcStartAngle, arcEndAngle);

        // End caps — from inner border to just past outer border
        var capInnerR = arcInnerR + 1;
        var capOuterR = arcOuterR + 1;
        var startRad = arcStartAngle * Math.PI / 180.0;
        var endRad = arcEndAngle * Math.PI / 180.0;
        dc.setPenWidth(2);
        dc.drawLine(
            cx + (capInnerR * Math.cos(startRad)).toNumber(), cy - (capInnerR * Math.sin(startRad)).toNumber(),
            cx + (capOuterR * Math.cos(startRad)).toNumber(), cy - (capOuterR * Math.sin(startRad)).toNumber());
        dc.drawLine(
            cx + (capInnerR * Math.cos(endRad)).toNumber(), cy - (capInnerR * Math.sin(endRad)).toNumber(),
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
        // Check if weather data is available
        var hasWeather = false;
        var weatherSource = Application.Properties.getValue("WeatherSource");
        if (weatherSource != null && weatherSource == 1) {
            // OWM mode: check staleness (>2h)
            if (dm.owmFetchedAt != null) {
                var age = Time.now().value() - dm.owmFetchedAt;
                if (age < 7200) {
                    hasWeather = true;
                }
            }
        } else {
            // Garmin mode: always fresh if data exists
            hasWeather = (dm.temperature != null);
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
            var windUnit = Application.Properties.getValue("WindSpeedUnit");
            var speed;
            var rawSpeed = dm.windSpeed;

            // OWM metric returns m/s, OWM imperial returns mph, Garmin returns m/s
            // Normalize to m/s first
            var speedMs = rawSpeed;
            if (weatherSource != null && weatherSource == 1) {
                // OWM mode
                var isImperial = System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE;
                if (isImperial) {
                    speedMs = rawSpeed / 2.237; // mph back to m/s
                }
            }

            if (windUnit == null || windUnit == 0) {
                // Auto: km/h for metric, mph for imperial
                var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
                if (isMetric) {
                    speed = speedMs * 3.6;
                } else {
                    speed = speedMs * 2.237;
                }
            } else if (windUnit == 1) {
                speed = speedMs * 3.6;       // km/h
            } else if (windUnit == 2) {
                speed = speedMs * 1.944;     // knots
            } else if (windUnit == 3) {
                speed = speedMs * 2.237;     // mph
            } else {
                speed = speedMs;             // m/s
            }
            windText = speed.format("%.1f");
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
    // Surf Mode rendering methods
    // =========================================================

    // Surf mode subscreen: tide height + solar arc + tide direction
    private function drawHrCircle_Surf(dc as Dc, dm as DataManager) as Void {
        // Filled white circle
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(HR_CENTER_X, HR_CENTER_Y, HR_RADIUS);

        // Solar intensity arc (reuses stress arc geometry)
        var solarVal = 0;
        if (dm.solarIntensity != null) {
            solarVal = dm.solarIntensity;
        }
        drawStressArc(dc, HR_CENTER_X, HR_CENTER_Y, HR_RADIUS, STRESS_ARC_WIDTH, solarVal);

        // Tide direction arrow (up=rising, down=falling) — uses tide icons from surfer-icons
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        if (dm.nextTideType != null && surferIconsFont != null) {
            var tideGlyph = dm.nextTideType.equals("high") ? "H" : "L";
            dc.drawText(HR_HEART_X, HR_HEART_Y, surferIconsFont, tideGlyph, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.drawText(HR_HEART_X, HR_HEART_Y, Graphics.FONT_XTINY, "--", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Tide height text
        var tideText = "--";
        if (dm.interpTideHeight != null) {
            var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
            if (isMetric) {
                tideText = dm.interpTideHeight.format("%.1f");
            } else {
                tideText = (dm.interpTideHeight * 3.281).format("%.1f");
            }
        }
        dc.drawText(HR_TEXT_X, HR_TEXT_Y, Graphics.FONT_XTINY, tideText, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    // Surf mode top section: battery, water temp, next tide
    private function drawTopSection_Surf(dc as Dc, dm as DataManager) as Void {
        // Row 1 — Battery (same as shore)
        drawBatteryWithPercent(dc, TOP_COL2_X, TOP_ROW1_Y, dm.battery, dm);

        // Row 2 — Water temperature (icon where notification icon was, text where count was)
        var tempText = "--";
        if (dm.waterTemp != null) {
            var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
            if (isMetric) {
                tempText = dm.waterTemp.toNumber().toString() + "°C";
            } else {
                tempText = (dm.waterTemp * 1.8 + 32).toNumber().toString() + "°F";
            }
        }
        // Text right-justified to same anchor as notification count
        drawTextAligned(dc, TOP_COL2_X - 6 - SPACER, TOP_ROW2_Y, Graphics.FONT_XTINY, tempText, Graphics.TEXT_JUSTIFY_RIGHT);
        // Thermometer icon where notification icon was
        if (surferIconsFont != null) {
            drawTextAligned(dc, TOP_COL2_X - 6, TOP_ROW2_Y, surferIconsFont, "T", Graphics.TEXT_JUSTIFY_LEFT);
        }

        // Row 3 — Tide (same as shore)
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

    // Surf mode middle section: wind, time, moon/ampm/seconds
    private function drawMiddleSection_Surf(dc as Dc, dm as DataManager) as Void {
        // Left column — Wind from OWM for surf spot (or Garmin fallback)
        if (dm.windDeg != null) {
            drawWindArrow(dc, MID_LEFT_X, MID_ICON_Y + WIND_ARROW_Y_OFFSET, dm.windDeg, WIND_ARROW_SIZE);
        }
        var windText = "--";
        if (dm.windSpeed != null) {
            var windUnit = Application.Properties.getValue("WindSpeedUnit");
            var speed;
            var speedMs = dm.windSpeed; // OWM metric=m/s, imperial=mph
            // Normalize to m/s for conversion
            var weatherSource = Application.Properties.getValue("WeatherSource");
            if (weatherSource != null && weatherSource == 1) {
                var isImperial = System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE;
                if (isImperial) {
                    speedMs = dm.windSpeed / 2.237;
                }
            }
            if (windUnit == null || windUnit == 0) {
                var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
                speed = isMetric ? speedMs * 3.6 : speedMs * 2.237;
            } else if (windUnit == 1) {
                speed = speedMs * 3.6;
            } else if (windUnit == 2) {
                speed = speedMs * 1.944;
            } else if (windUnit == 3) {
                speed = speedMs * 2.237;
            } else {
                speed = speedMs;
            }
            windText = speed.format("%.1f");
        }
        drawTextAligned(dc, MID_LEFT_X, MID_TEXT_Y, Graphics.FONT_XTINY, windText, Graphics.TEXT_JUSTIFY_CENTER);

        // Center — current time (same as shore)
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

        // Right column — moon, AM/PM, seconds (same as shore)
        var seconds = clockTime.sec.format("%02d");
        drawRightColumn(dc, ampm, seconds, dm);
    }

    // Surf mode bottom section — swell view
    private function drawSwellSection(dc as Dc, dm as DataManager) as Void {
        var swellY = 120;
        var swellTextY = swellY + 18;

        // Col 1: Swell height
        var htText = "--";
        if (dm.swellHeight != null) {
            var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
            if (isMetric) {
                htText = dm.swellHeight.format("%.1f") + "m";
            } else {
                htText = (dm.swellHeight * 3.281).format("%.1f") + "ft";
            }
        }
        // Col 1: Swell height — surfing icon
        if (surferIconsFont != null) {
            drawTextAligned(dc, WX_COL1_X, swellY, surferIconsFont, "S", Graphics.TEXT_JUSTIFY_CENTER);
        }
        drawTextAligned(dc, WX_COL1_X, swellTextY, Graphics.FONT_XTINY, htText, Graphics.TEXT_JUSTIFY_CENTER);

        // Col 2: Swell period
        var perText = "--";
        if (dm.swellPeriod != null) {
            perText = dm.swellPeriod.toNumber().toString() + "s";
        }
        // Col 2: Swell period — timer-sand icon
        if (surferIconsFont != null) {
            drawTextAligned(dc, WX_COL2_X, swellY + 4, surferIconsFont, "P", Graphics.TEXT_JUSTIFY_CENTER);
        }
        drawTextAligned(dc, WX_COL2_X, swellTextY + 4, Graphics.FONT_XTINY, perText, Graphics.TEXT_JUSTIFY_CENTER);

        // Col 3: Swell direction arrow
        if (dm.swellDirection != null) {
            drawWindArrow(dc, WX_COL3_X, swellY + WIND_ARROW_Y_OFFSET, dm.swellDirection, WIND_ARROW_SIZE);
        }
        var dirText = "--";
        if (dm.swellDirection != null) {
            dirText = degreesToCompass(dm.swellDirection);
        }
        drawTextAligned(dc, WX_COL3_X, swellTextY, Graphics.FONT_XTINY, dirText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Surf mode bottom section — tide curve view
    // Filled area under curve, gap at "now", triangle marker, tick marks + time labels at events
    private function drawTideCurve(dc as Dc, dm as DataManager) as Void {
        // Derived positions from constants
        var curveTopY = TC_Y + TC_LABEL_HEIGHT;
        var curveBottomY = curveTopY + TC_CURVE_HEIGHT;
        var leftX = TC_LEFT_X;
        var rightX = TC_RIGHT_X;
        var nowGapHalf = TC_NOW_GAP_HALF; // half-width of the "now" gap in pixels

        if (dm.tideExtremes == null || dm.tideExtremes.size() < 2) {
            drawTextAligned(dc, 88, curveTopY + TC_CURVE_HEIGHT / 2, Graphics.FONT_XTINY, "--", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Time range: local today (midnight to midnight)
        var now = Time.now();
        var startTime = Time.today().value().toFloat();
        var endTime = startTime + 86400.0;
        var nowVal = now.value().toFloat();
        var nowX = leftX + ((nowVal - startTime) / (endTime - startTime) * (rightX - leftX)).toNumber();

        // Find height range from all extremes
        var minH = 999.0;
        var maxH = -999.0;
        for (var i = 0; i < dm.tideExtremes.size(); i++) {
            var entry = dm.tideExtremes[i] as Dictionary;
            var h = entry["height"];
            if (h != null) {
                var hf = (h as Float).toFloat();
                if (hf < minH) { minH = hf; }
                if (hf > maxH) { maxH = hf; }
            }
        }
        if (maxH <= minH) { maxH = minH + 1.0; }
        var hRange = maxH - minH;
        minH -= hRange * TC_HEIGHT_PAD_BOTTOM;
        maxH += hRange * TC_HEIGHT_PAD;
        hRange = maxH - minH;

        // Helper: interpolate height at time t
        // (inline since Monkey C doesn't support closures)

        // Draw filled area under curve + curve line
        for (var x = leftX; x <= rightX; x++) {
            var t = startTime + (x - leftX).toFloat() / (rightX - leftX).toFloat() * (endTime - startTime);

            // Find surrounding events
            var prev = null;
            var next = null;
            for (var i = 0; i < dm.tideExtremes.size(); i++) {
                var entry = dm.tideExtremes[i] as Dictionary;
                var et = entry["time"] as Number;
                if (et != null) {
                    if (et.toFloat() <= t) { prev = entry; }
                    else if (next == null) { next = entry; }
                }
            }

            var height = null;
            if (prev != null && next != null) {
                var pt = (prev["time"] as Number).toFloat();
                var nt = (next["time"] as Number).toFloat();
                var ph = (prev["height"] as Float).toFloat();
                var nh = (next["height"] as Float).toFloat();
                var frac = (t - pt) / (nt - pt);
                height = ph + (nh - ph) * (1.0 - Math.cos(frac * Math.PI)) / 2.0;
            } else if (prev != null) {
                height = (prev["height"] as Float).toFloat();
            } else if (next != null) {
                height = (next["height"] as Float).toFloat();
            }

            if (height != null) {
                var py = curveBottomY - ((height - minH) / hRange * TC_CURVE_HEIGHT).toNumber();
                if (py < curveTopY) { py = curveTopY; }
                if (py > curveBottomY) { py = curveBottomY; }

                // Now marker: dithered checkerboard for "gray" effect, solid fill elsewhere
                var inNowGap = (x >= nowX - nowGapHalf && x <= nowX + nowGapHalf);
                if (inNowGap) {
                    for (var dy = py; dy < curveBottomY; dy++) {
                        if ((x + dy) % 2 == 0) {
                            dc.drawPoint(x, dy);
                        }
                    }
                } else if (py < curveBottomY) {
                    dc.drawLine(x, py, x, curveBottomY);
                }
            }
        }

        // Draw triangle marker at "now" position (above the curve)
        if (nowVal >= startTime && nowVal <= endTime) {
            // Interpolate height at now to find the curve Y
            var nowHeight = null;
            var prev2 = null;
            var next2 = null;
            for (var i = 0; i < dm.tideExtremes.size(); i++) {
                var entry = dm.tideExtremes[i] as Dictionary;
                var et = entry["time"] as Number;
                if (et != null) {
                    if (et.toFloat() <= nowVal) { prev2 = entry; }
                    else if (next2 == null) { next2 = entry; }
                }
            }
            var nowPy = curveBottomY;
            if (prev2 != null && next2 != null) {
                var pt = (prev2["time"] as Number).toFloat();
                var nt = (next2["time"] as Number).toFloat();
                var ph = (prev2["height"] as Float).toFloat();
                var nh = (next2["height"] as Float).toFloat();
                var frac = (nowVal - pt) / (nt - pt);
                nowHeight = ph + (nh - ph) * (1.0 - Math.cos(frac * Math.PI)) / 2.0;
                nowPy = curveBottomY - ((nowHeight - minH) / hRange * TC_CURVE_HEIGHT).toNumber();
            }
            var triBottom = nowPy - TC_TRI_GAP;
            var triTopPt = triBottom - TC_TRI_HEIGHT;
            dc.fillPolygon([[nowX, triBottom], [nowX - TC_TRI_WIDTH, triTopPt], [nowX + TC_TRI_WIDTH, triTopPt]]);
        }

        // Time labels at tide events (above curve, short format, aligned to nearest hour)
        for (var i = 0; i < dm.tideExtremes.size(); i++) {
            var entry = dm.tideExtremes[i] as Dictionary;
            var et = entry["time"] as Number;
            if (et != null) {
                var etf = et.toFloat();
                if (etf >= startTime && etf <= endTime) {
                    // Align label X with the event position
                    var ex = leftX + ((etf - startTime) / (endTime - startTime) * (rightX - leftX)).toNumber();

                    // Short format: round to nearest hour
                    var moment = new Time.Moment(et);
                    var info = Gregorian.info(moment, Time.FORMAT_SHORT);
                    var hr = info.hour;
                    // Round: if minutes >= 30, bump hour
                    if (info.min >= 30) { hr = (hr + 1) % 24; }
                    var is24 = System.getDeviceSettings().is24Hour;
                    var timeLabel;
                    if (is24) {
                        timeLabel = hr.toString();
                    } else {
                        var suffix = hr >= 12 ? "p" : "a";
                        hr = hr % 12;
                        if (hr == 0) { hr = 12; }
                        timeLabel = hr.toString() + suffix;
                    }

                    drawTextAligned(dc, ex, curveTopY - TC_LABEL_GAP - 13, Graphics.FONT_XTINY, timeLabel, Graphics.TEXT_JUSTIFY_CENTER);
                }
            }
        }
    }

    // Convert degrees to compass direction
    private function degreesToCompass(deg as Number) as String {
        var dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        var idx = Math.round(deg.toFloat() / 45.0).toNumber() % 8;
        return dirs[idx];
    }

    // =========================================================
    // onBackgroundData — NOT on the view, moved to App class
    // =========================================================

    // --- Lifecycle ---
    function onHide() as Void {
    }

    function onExitSleep() as Void {
        isSleeping = false;

        // Double wrist gesture detection for surf mode bottom toggle
        var surfMode = Application.Properties.getValue("SurfMode");
        if (surfMode != null && surfMode == 1) {
            var now = Time.now().value();
            var diff = now - lastWristRaiseTime;
            if (lastWristRaiseTime > 0 && diff < 10) {
                // Double raise detected — toggle bottom view
                var dm = (Application.getApp() as SurferWatchFaceApp).getDataManager();
                if (dm != null) {
                    dm.bottomToggleState = (dm.bottomToggleState == 0) ? 1 : 0;
                }
                lastWristRaiseTime = 0;
            } else {
                lastWristRaiseTime = now;
            }
        }

        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        isSleeping = true;
        WatchUi.requestUpdate();
    }

}


// BehaviorDelegate for button press handling (surf mode bottom toggle)
class SurferWatchFaceBehaviorDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        var surfMode = Application.Properties.getValue("SurfMode");
        if (surfMode != null && surfMode == 1) {
            var dm = (Application.getApp() as SurferWatchFaceApp).getDataManager();
            if (dm != null) {
                dm.bottomToggleState = (dm.bottomToggleState == 0) ? 1 : 0;
                WatchUi.requestUpdate();
            }
            return true;
        }
        return false;
    }
}
