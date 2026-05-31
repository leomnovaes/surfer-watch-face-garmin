import Toybox.Lang;
import Toybox.Test;

// ===== celsiusToFahrenheit tests =====

(:test)
function testCelsiusToFahrenheit_Zero(logger as Test.Logger) as Boolean {
    var result = UnitConverter.celsiusToFahrenheit(0.0);
    var expected = 32.0;
    return (result - expected).abs() < 0.01;
}

(:test)
function testCelsiusToFahrenheit_Boiling(logger as Test.Logger) as Boolean {
    var result = UnitConverter.celsiusToFahrenheit(100.0);
    var expected = 212.0;
    return (result - expected).abs() < 0.01;
}

(:test)
function testCelsiusToFahrenheit_Crossover(logger as Test.Logger) as Boolean {
    // -40 is the crossover point where C == F
    var result = UnitConverter.celsiusToFahrenheit(-40.0);
    var expected = -40.0;
    return (result - expected).abs() < 0.01;
}

(:test)
function testCelsiusToFahrenheit_RoomTemp(logger as Test.Logger) as Boolean {
    var result = UnitConverter.celsiusToFahrenheit(22.0);
    var expected = 71.6;
    return (result - expected).abs() < 0.01;
}

(:test)
function testCelsiusToFahrenheit_Negative(logger as Test.Logger) as Boolean {
    var result = UnitConverter.celsiusToFahrenheit(-5.0);
    var expected = 23.0;
    return (result - expected).abs() < 0.01;
}

// ===== metersToFeet tests =====

(:test)
function testMetersToFeet_Zero(logger as Test.Logger) as Boolean {
    var result = UnitConverter.metersToFeet(0.0);
    var expected = 0.0;
    return (result - expected).abs() < 0.01;
}

(:test)
function testMetersToFeet_OneMeter(logger as Test.Logger) as Boolean {
    var result = UnitConverter.metersToFeet(1.0);
    var expected = 3.281;
    return (result - expected).abs() < 0.01;
}

(:test)
function testMetersToFeet_TideHeight(logger as Test.Logger) as Boolean {
    var result = UnitConverter.metersToFeet(1.5);
    var expected = 4.9215;
    return (result - expected).abs() < 0.01;
}

(:test)
function testMetersToFeet_SmallValue(logger as Test.Logger) as Boolean {
    var result = UnitConverter.metersToFeet(0.3);
    var expected = 0.9843;
    return (result - expected).abs() < 0.01;
}

(:test)
function testMetersToFeet_VerySmall(logger as Test.Logger) as Boolean {
    // Edge: very small values
    var result = UnitConverter.metersToFeet(0.01);
    var expected = 0.03281;
    return (result - expected).abs() < 0.01;
}

// ===== msToKmh tests =====

(:test)
function testMsToKmh_Zero(logger as Test.Logger) as Boolean {
    var result = UnitConverter.msToKmh(0.0);
    var expected = 0.0;
    return (result - expected).abs() < 0.01;
}

(:test)
function testMsToKmh_One(logger as Test.Logger) as Boolean {
    var result = UnitConverter.msToKmh(1.0);
    var expected = 3.6;
    return (result - expected).abs() < 0.01;
}

(:test)
function testMsToKmh_Ten(logger as Test.Logger) as Boolean {
    var result = UnitConverter.msToKmh(10.0);
    var expected = 36.0;
    return (result - expected).abs() < 0.01;
}

// ===== msToMph tests =====

(:test)
function testMsToMph_Zero(logger as Test.Logger) as Boolean {
    var result = UnitConverter.msToMph(0.0);
    var expected = 0.0;
    return (result - expected).abs() < 0.01;
}

(:test)
function testMsToMph_One(logger as Test.Logger) as Boolean {
    var result = UnitConverter.msToMph(1.0);
    var expected = 2.237;
    return (result - expected).abs() < 0.01;
}

(:test)
function testMsToMph_Ten(logger as Test.Logger) as Boolean {
    var result = UnitConverter.msToMph(10.0);
    var expected = 22.37;
    return (result - expected).abs() < 0.01;
}

// ===== msToKnots tests =====

(:test)
function testMsToKnots_Zero(logger as Test.Logger) as Boolean {
    var result = UnitConverter.msToKnots(0.0);
    var expected = 0.0;
    return (result - expected).abs() < 0.01;
}

(:test)
function testMsToKnots_One(logger as Test.Logger) as Boolean {
    var result = UnitConverter.msToKnots(1.0);
    var expected = 1.944;
    return (result - expected).abs() < 0.01;
}

(:test)
function testMsToKnots_Ten(logger as Test.Logger) as Boolean {
    var result = UnitConverter.msToKnots(10.0);
    var expected = 19.44;
    return (result - expected).abs() < 0.01;
}

// ===== Preservation: Wind speed conversion properties =====

(:test)
function testWindPreservation_KmhFormula(logger as Test.Logger) as Boolean {
    // msToKmh must equal input * 3.6 for all inputs
    var inputs = [0.0, 1.0, 5.0, 10.0, 25.0, 50.0];
    for (var i = 0; i < inputs.size(); i++) {
        var result = UnitConverter.msToKmh(inputs[i]);
        var expected = inputs[i] * 3.6;
        if ((result - expected).abs() >= 0.01) { return false; }
    }
    return true;
}

(:test)
function testWindPreservation_MphFormula(logger as Test.Logger) as Boolean {
    var inputs = [0.0, 1.0, 5.0, 10.0, 25.0, 50.0];
    for (var i = 0; i < inputs.size(); i++) {
        var result = UnitConverter.msToMph(inputs[i]);
        var expected = inputs[i] * 2.237;
        if ((result - expected).abs() >= 0.01) { return false; }
    }
    return true;
}

(:test)
function testWindPreservation_KnotsFormula(logger as Test.Logger) as Boolean {
    var inputs = [0.0, 1.0, 5.0, 10.0, 25.0, 50.0];
    for (var i = 0; i < inputs.size(); i++) {
        var result = UnitConverter.msToKnots(inputs[i]);
        var expected = inputs[i] * 1.944;
        if ((result - expected).abs() >= 0.01) { return false; }
    }
    return true;
}

(:test)
function testPreservation_TempOrdering(logger as Test.Logger) as Boolean {
    // Temperature conversion preserves ordering: if a > b then F(a) > F(b)
    var values = [-40.0, -10.0, 0.0, 10.0, 22.0, 37.0, 50.0];
    for (var i = 1; i < values.size(); i++) {
        var prev = UnitConverter.celsiusToFahrenheit(values[i-1]);
        var curr = UnitConverter.celsiusToFahrenheit(values[i]);
        if (curr <= prev) { return false; }
    }
    return true;
}

(:test)
function testPreservation_ElevationOrdering(logger as Test.Logger) as Boolean {
    // Meters-to-feet preserves ordering: if a > b then ft(a) > ft(b)
    var values = [0.0, 0.3, 0.5, 1.0, 1.5, 3.0, 10.0];
    for (var i = 1; i < values.size(); i++) {
        var prev = UnitConverter.metersToFeet(values[i-1]);
        var curr = UnitConverter.metersToFeet(values[i]);
        if (curr <= prev) { return false; }
    }
    return true;
}

(:test)
function testPreservation_WindOrdering(logger as Test.Logger) as Boolean {
    // All wind conversions preserve ordering
    var values = [0.0, 1.0, 5.0, 10.0, 25.0, 50.0];
    for (var i = 1; i < values.size(); i++) {
        if (UnitConverter.msToKmh(values[i]) <= UnitConverter.msToKmh(values[i-1])) { return false; }
        if (UnitConverter.msToMph(values[i]) <= UnitConverter.msToMph(values[i-1])) { return false; }
        if (UnitConverter.msToKnots(values[i]) <= UnitConverter.msToKnots(values[i-1])) { return false; }
    }
    return true;
}
