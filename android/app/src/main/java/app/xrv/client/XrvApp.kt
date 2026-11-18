package app.xrv.client

import android.app.Application

class XrvApp : Application() {
    override fun onCreate() {
        super.onCreate()
        XrvLog.init(this)
        XrvLog.add("app", "XRV ${BuildConfig.VERSION_NAME} started")
        val existing = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            XrvLog.addSync(
                "crash",
                "${thread.name}: ${throwable.javaClass.simpleName}: ${throwable.message}\n" +
                    throwable.stackTraceToString().take(4000)
            )
            existing?.uncaughtException(thread, throwable)
        }
    }
}
