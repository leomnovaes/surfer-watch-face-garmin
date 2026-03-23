import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class SurferWatchFaceApp extends Application.AppBase {

    var dataManager as DataManager or Null;

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
        return [ new SurferWatchFaceView() ];
    }

    // New app settings have been received so trigger a UI update
    function onSettingsChanged() as Void {
        if (dataManager != null) {
            dataManager.clearWeatherData();
            var surfMode = Application.Properties.getValue("SurfMode");
            if (surfMode != null && surfMode == 1) {
                dataManager.loadSurfCache();
            } else {
                dataManager.loadShoreCache();
            }
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
                    dataManager.onWeatherData(weatherData as Dictionary);
                }
                var tideData = data["tides"];
                if (tideData != null && tideData instanceof Array) {
                    dataManager.onTideData(tideData as Array);
                }
                var swellData = data["swell"];
                if (swellData != null && swellData instanceof Dictionary) {
                    dataManager.onSwellData(swellData as Dictionary);
                }
            }
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
