import Toybox.Lang;
import Toybox.System;

module UnitConverter {

    function celsiusToFahrenheit(c as Float) as Float {
        return c * 1.8 + 32;
    }

    function metersToFeet(m as Float) as Float {
        return m * 3.281;
    }

    function msToKmh(ms as Float) as Float {
        return ms * 3.6;
    }

    function msToMph(ms as Float) as Float {
        return ms * 2.237;
    }

    function msToKnots(ms as Float) as Float {
        return ms * 1.944;
    }

    function isTemperatureImperial() as Boolean {
        return System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE;
    }

    function isElevationImperial() as Boolean {
        return System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE;
    }

}
