package app.xrv.client

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class TunnelService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val profile = SecureProfileStore(this).load() ?: return START_NOT_STICKY
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("xrv", "XRV connection", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        startForeground(7, NotificationCompat.Builder(this, "xrv").setSmallIcon(android.R.drawable.stat_sys_upload).setContentTitle("XRV connected").setContentText("SOCKS5 at 127.0.0.1:${profile.socksPort}").build())
        Thread {
            // The engine never returns configuration or secrets in its error.
            val result = NativeBridge.start(profile.json())
            if (result.isNotEmpty()) stopSelf()
        }.start()
        return START_STICKY
    }
    override fun onDestroy() { NativeBridge.stop(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
}
