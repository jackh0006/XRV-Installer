package app.xrv.client

import android.app.Notification
import android.app.Service
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.ServiceCompat

/** Centralises the foreground-service type so no service hits a 6-hour
 *  dataSync limit on Android 14+. VPN/proxy work is declared as specialUse. */
object Foreground {
    private fun type(): Int = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        else -> 0
    }

    fun start(service: Service, id: Int, notification: Notification) {
        val type = type()
        if (type != 0) {
            ServiceCompat.startForeground(service, id, notification, type)
        } else {
            service.startForeground(id, notification)
        }
    }

    fun stop(service: Service) {
        ServiceCompat.stopForeground(service, ServiceCompat.STOP_FOREGROUND_REMOVE)
    }
}
