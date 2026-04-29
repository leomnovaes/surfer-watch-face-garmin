import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class SurferWatchFaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
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

    // Return the initial view — only called in foreground process.
    // DataManager is created and initialized by the View in onLayout().
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new SurferWatchFaceView() ];
    }

    // New app settings have been received — set Storage flag for View to handle.
    // All DataManager interactions happen in View's onUpdate() to keep App clean
    // of foreground class references (Crystal Face pattern).
    function onSettingsChanged() as Void {
        Application.Storage.setValue("settingsChanged", true);
        if (Background has :registerForTemporalEvent) {
            try {
                Background.registerForTemporalEvent(Time.now());
            } catch (e) {
            }
        }
        WatchUi.requestUpdate();
    }

    // Called by the system after Background.exit() — writes to Storage only.
    // View reads from Storage on next onUpdate() via DataManager.checkBackgroundFlags().
    // This follows the Crystal Face pattern: App never references foreground classes.
    function onBackgroundData(data) as Void {
        if (data instanceof Dictionary) {
            var weatherData = data["weather"];
            if (weatherData != null) {
                Application.Storage.setValue("bgWeatherData", weatherData);
                Application.Storage.setValue("weatherUpdated", true);
            }
            var tideData = data["tideUpdated"];
            if (tideData != null) {
                // Tide arrays already written to Storage by delegate — just set flag
                Application.Storage.setValue("tideUpdated", true);
            }
            var swellData = data["swell"];
            if (swellData != null) {
                Application.Storage.setValue("bgSwellData", swellData);
                Application.Storage.setValue("swellUpdated", true);
            }
        }
        // Set flag for View to refresh weather (sunrise/sunset + Garmin weather)
        Application.Storage.setValue("bgEventOccurred", true);
        // Re-register for next background event in 5 minutes
        if (Background has :registerForTemporalEvent) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        }
        WatchUi.requestUpdate();
    }

}
