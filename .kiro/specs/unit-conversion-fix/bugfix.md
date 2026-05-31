# Bugfix Requirements Document

## Introduction

The watch face displays unit suffixes (°F, ft) based on `distanceUnits` but fails to actually convert values from their stored metric format. The most visible symptom is shore temperature showing a Celsius value with an "F" suffix when the user's distance setting is imperial. Additionally, the code uses `distanceUnits` as a proxy for ALL unit decisions, but Garmin provides separate `DeviceSettings` fields: `temperatureUnits`, `elevationUnits`, and `distanceUnits`. This causes incorrect unit display for users with mixed settings (e.g., distance=miles but temperature=Celsius).

A secondary issue exists in the OWM fetch layer: the code conditionally passes `units=imperial` to the OWM API based on `distanceUnits`, meaning cached values may be in imperial units and the display layer cannot reliably know the unit of the stored value. The fix standardizes on always storing metric and converting at display time.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the device `distanceUnits` is set to UNIT_STATUTE and WeatherSource is Open-Meteo or Garmin THEN the system displays shore temperature in Celsius with an "F" suffix (no C→F conversion applied)

1.2 WHEN the device `distanceUnits` is set to UNIT_STATUTE and WeatherSource is OWM THEN the system fetches temperature in imperial from OWM (already Fahrenheit) and displays it correctly, but creates an inconsistency where stored values depend on the fetch-time unit setting

1.3 WHEN the device `temperatureUnits` is set to Fahrenheit but `distanceUnits` is set to UNIT_METRIC THEN the system displays temperature in Celsius with a "C" suffix (ignores user's temperature preference)

1.4 WHEN the device `elevationUnits` is set to feet but `distanceUnits` is set to UNIT_METRIC THEN the system displays tide height and swell height in meters (ignores user's elevation preference)

1.5 WHEN the device `distanceUnits` is set to UNIT_STATUTE and `elevationUnits` is set to meters THEN the system displays tide height and swell height in feet (ignores user's elevation preference)

1.6 WHEN OWM is the weather source and `distanceUnits` is UNIT_STATUTE THEN the system fetches wind in imperial (mph) from OWM and then back-converts it to m/s at display time using `/ 2.237`, introducing floating-point precision loss

1.7 WHEN OWM is the weather source and the user changes `distanceUnits` between fetches THEN the system may display wind incorrectly because the stored value's unit depends on the setting at fetch time, not at display time

### Expected Behavior (Correct)

2.1 WHEN the device `temperatureUnits` is set to Fahrenheit THEN the system SHALL convert the stored Celsius value to Fahrenheit (×1.8 + 32) and display with "°F" suffix

2.2 WHEN the device `temperatureUnits` is set to Celsius THEN the system SHALL display the stored Celsius value with "°C" suffix without conversion

2.3 WHEN the device `elevationUnits` is set to feet (UNIT_STATUTE) THEN the system SHALL convert stored meter values to feet (×3.281) for tide height and swell height display

2.4 WHEN the device `elevationUnits` is set to meters (UNIT_METRIC) THEN the system SHALL display tide height and swell height in meters without conversion

2.5 WHEN OWM is the weather source THEN the system SHALL always fetch with `units=metric` so that temperature is stored in Celsius and wind speed in m/s, regardless of device settings

2.6 WHEN wind speed is displayed THEN the system SHALL use the stored m/s value (consistent across all weather sources) and convert to the display unit using the `WindSpeedUnit` app setting (Auto mode falls back to `distanceUnits` for km/h vs mph selection)

2.7 WHEN OWM wind is displayed THEN the system SHALL NOT apply back-conversion from mph to m/s since the value is already stored in m/s after the fix

### Unchanged Behavior (Regression Prevention)

3.1 WHEN `WindSpeedUnit` app setting is 0 (Auto) and `distanceUnits` is UNIT_METRIC THEN the system SHALL CONTINUE TO display wind speed in km/h (m/s × 3.6)

3.2 WHEN `WindSpeedUnit` app setting is 0 (Auto) and `distanceUnits` is UNIT_STATUTE THEN the system SHALL CONTINUE TO display wind speed in mph (m/s × 2.237)

3.3 WHEN `WindSpeedUnit` app setting is 1 (km/h), 2 (knots), 3 (mph), or 4 (m/s) THEN the system SHALL CONTINUE TO convert from m/s using the existing conversion factors

3.4 WHEN Open-Meteo is the weather source THEN the system SHALL CONTINUE TO receive temperature in Celsius and wind in m/s (no fetch-layer change needed)

3.5 WHEN Garmin built-in is the weather source THEN the system SHALL CONTINUE TO receive temperature in Celsius and wind in m/s from the OS (no fetch-layer change needed)

3.6 WHEN surf mode water temperature is displayed (watch sensor or sea surface) THEN the system SHALL CONTINUE TO apply C→F conversion when showing Fahrenheit (this already works correctly, but should switch from `distanceUnits` to `temperatureUnits`)

3.7 WHEN the Storage version is bumped THEN the system SHALL CONTINUE TO clear all cached values on the next app startup, invalidating any previously-fetched imperial OWM data

3.8 WHEN tide height is zero (0.0m) THEN the system SHALL CONTINUE TO display "0.0m" or "0.0ft" without error

3.9 WHEN temperature is negative (e.g., -5°C) THEN the system SHALL correctly convert to Fahrenheit (23°F) and display with the sign
