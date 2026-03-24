import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class SurferWatchFaceApp extends Application.AppBase {

    var dataManager as DataManager or Null;
    private var _lastWeatherSource as Number = -1;

    function initialize() {
        AppBase.initialize();
    }

    function getDataManager() as DataManager {
        return dataManager;
    }

    // Return the service delegate for background processing
    (:background)
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new SurferWatchFaceDelegate()];
    }

    // onStart() is called on application start up — runs in BOTH foreground and background
    function onStart(state as Dictionary?) as Void {
        // Register background temporal event
        // Try immediate trigger first; fall back to 5-min if system enforces minimum
        if (Background has :registerForTemporalEvent) {
            try {
                Background.registerForTemporalEvent(Time.now());
            } catch (e) {
                Background.registerForTemporalEvent(new Time.Duration(5 * 60));
            }
        }
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view — only called in foreground process
    function getInitialView() as [Views] or [Views, InputDelegates] {
        dataManager = new DataManager();
        var ws = Application.Properties.getValue("WeatherSource");
        _lastWeatherSource = (ws != null) ? ws : 0;
        // Load correct cache based on current mode
        var surfMode = Application.Properties.getValue("SurfMode");
        if (surfMode != null && surfMode == 1) {
            dataManager.loadSurfCache();
        }
        // Compute sunrise/sunset + Garmin weather if applicable
        dataManager.refreshWeatherOnBackgroundEvent();
        return [ new SurferWatchFaceView() ];
    }

    // New app settings have been received so trigger a UI update
    function onSettingsChanged() as Void {
        if (dataManager != null) {
            // Clear weather data only if WeatherSource changed — prevents
            // condition code mismatch between mappers (WMO vs OWM vs Garmin).
            var ws = Application.Properties.getValue("WeatherSource");
            var currentSource = (ws != null) ? ws : 0;
            if (currentSource != _lastWeatherSource) {
                dataManager.clearWeatherData();
                dataManager.clearPersistedWeatherData();
                _lastWeatherSource = currentSource;
            }

            var surfMode = Application.Properties.getValue("SurfMode");
            if (surfMode != null && surfMode == 1) {
                dataManager.loadSurfCache();
            } else {
                dataManager.loadShoreCache();
            }
            // Compute sunrise/sunset + Garmin weather if applicable
            dataManager.refreshWeatherOnBackgroundEvent();
        }
        // Try to trigger immediate background fetch for fresh data
        if (Background has :registerForTemporalEvent) {
            try {
                Background.registerForTemporalEvent(Time.now());
            } catch (e) {
                // 5-min minimum enforced
            }
        }
        WatchUi.requestUpdate();
    }

    // Called by the system after Background.exit() — routes data to DataManager
    function onBackgroundData(data) as Void {
        if (data instanceof Dictionary) {
            if (dataManager != null) {
                var weatherData = data["weather"];
                if (weatherData != null && weatherData instanceof Dictionary) {
                    var surfMode = Application.Properties.getValue("SurfMode");
                    if (surfMode != null && surfMode == 1) {
                        dataManager.onSurfWindData(weatherData as Dictionary);
                    } else {
                        dataManager.onWeatherData(weatherData as Dictionary);
                    }
                }
                var tideData = data["tideUpdated"];
                if (tideData != null) {
                    // Tide data written to Storage by delegate — reload it
                    var surfMode = Application.Properties.getValue("SurfMode");
                    if (surfMode != null && surfMode == 1) {
                        var tides = Application.Storage.getValue("surf_tideExtremes") as Array or Null;
                        if (tides != null) { dataManager.onTideData(tides); }
                    } else {
                        var tides = Application.Storage.getValue("tideExtremes") as Array or Null;
                        if (tides != null) { dataManager.onTideData(tides); }
                    }
                }
                var swellData = data["swell"];
                if (swellData != null && swellData instanceof Dictionary) {
                    dataManager.onSwellData(swellData as Dictionary);
                }
            }
        }
        // Compute sunrise/sunset + Garmin weather on every background cycle
        if (dataManager != null) {
            dataManager.refreshWeatherOnBackgroundEvent();
        }
        // Re-register for next background event in 5 minutes
        if (Background has :registerForTemporalEvent) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        }
        WatchUi.requestUpdate();
    }

}

function getApp() as SurferWatchFaceApp {
    return Application.getApp() as SurferWatchFaceApp;
}
