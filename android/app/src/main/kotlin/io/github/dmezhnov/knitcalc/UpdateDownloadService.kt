package io.github.dmezhnov.knitcalc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.EventChannel
import java.io.IOException
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Bridges download progress from [UpdateDownloadService] to the Flutter
 * EventChannel wired up in [MainActivity]. The service runs in the same process,
 * so a static sink is enough; events are delivered on the main thread, where the
 * Flutter sink must be touched.
 */
object UpdateProgressBridge {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    var sink: EventChannel.EventSink? = null

    fun emit(state: String, received: Long, total: Long) {
        if (sink == null) return
        main.post {
            sink?.success(
                mapOf("state" to state, "received" to received, "total" to total),
            )
        }
    }

    /** Terminal "done" event carrying the downloaded APK path so the foreground
     *  app can launch the installer from its Activity context. */
    fun emitDone(received: Long, total: Long, path: String) {
        if (sink == null) return
        main.post {
            sink?.success(
                mapOf(
                    "state" to "done",
                    "received" to received,
                    "total" to total,
                    "path" to path,
                ),
            )
        }
    }
}

/**
 * Foreground service that downloads the update APK and hands it to the system
 * installer. It keeps running while the app is backgrounded and shows an ongoing
 * notification mirroring the in-app progress dialog: a progress bar, percentage,
 * megabytes and Pause/Resume + Cancel actions. Pause drops the connection but
 * keeps the partial file; resume continues with a `Range` request.
 */
class UpdateDownloadService : Service() {
    companion object {
        const val ACTION_START = "io.github.dmezhnov.knitcalc.action.START"
        const val ACTION_PAUSE = "io.github.dmezhnov.knitcalc.action.PAUSE"
        const val ACTION_RESUME = "io.github.dmezhnov.knitcalc.action.RESUME"
        const val ACTION_CANCEL = "io.github.dmezhnov.knitcalc.action.CANCEL"
        const val EXTRA_URL = "url"

        private const val CHANNEL_ID = "knitcalc_update"
        private const val NOTIFICATION_ID = 4711
        private const val APK_NAME = "knitcalc-update.apk"
        private const val BUFFER = 64 * 1024
        private const val EMIT_INTERVAL_MS = 150L
    }

    private val main = Handler(Looper.getMainLooper())

    @Volatile private var paused = false
    @Volatile private var cancelled = false
    @Volatile private var received = 0L
    @Volatile private var total = -1L
    @Volatile private var worker: Thread? = null
    private val resumeLock = Object()
    private var lastEmitMs = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val url = intent.getStringExtra(EXTRA_URL)
                if (url == null) {
                    stopAll()
                } else {
                    startForegroundNow()
                    if (worker == null) startDownload(url)
                }
            }
            ACTION_PAUSE -> setPaused(true)
            ACTION_RESUME -> setPaused(false)
            ACTION_CANCEL -> doCancel()
        }
        return START_NOT_STICKY
    }

    private fun startForegroundNow() {
        createChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startDownload(urlStr: String) {
        paused = false
        cancelled = false
        received = 0L
        total = -1L

        val apk = java.io.File(cacheDir, APK_NAME)
        if (apk.exists()) apk.delete()

        worker = thread(start = true) {
            try {
                downloadLoop(urlStr, apk)
                when {
                    cancelled -> {
                        apk.delete()
                        UpdateProgressBridge.emit("cancelled", received, total)
                        stopAll()
                    }
                    else -> {
                        // The foreground app installs via its Activity (see Dart's
                        // "done" handling); for the backgrounded case a tappable
                        // "downloaded" notification launches the installer, since a
                        // service can't start an Activity in the background.
                        UpdateProgressBridge.emitDone(received, total, apk.absolutePath)
                        showInstallNotification(apk)
                    }
                }
            } catch (_: Exception) {
                apk.delete()
                UpdateProgressBridge.emit(
                    if (cancelled) "cancelled" else "error",
                    received,
                    total,
                )
                stopAll()
            }
        }
    }

    /**
     * Downloads in passes: one HTTP connection per pass. A pause ends the current
     * pass (connection closed, partial file kept) and the next pass resumes with a
     * `Range` request from [received]. The normal case runs the loop once.
     */
    private fun downloadLoop(urlStr: String, apk: java.io.File) {
        while (true) {
            if (cancelled) return

            val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                setRequestProperty("User-Agent", "knitcalc-updater")
                connectTimeout = 30_000
                readTimeout = 30_000
                if (received > 0) setRequestProperty("Range", "bytes=$received-")
            }

            try {
                conn.connect()
                val code = conn.responseCode
                val resuming = received > 0

                if (resuming && code != HttpURLConnection.HTTP_PARTIAL) {
                    // Server ignored the range: restart the whole download.
                    received = 0L
                    apk.delete()
                } else if (!resuming && code != HttpURLConnection.HTTP_OK) {
                    throw IOException("HTTP $code")
                }

                val len = conn.contentLengthLong
                total = if (len >= 0) received + len else -1L

                val out = RandomAccessFile(apk, "rw").apply { seek(received) }
                val input = conn.inputStream
                val buf = ByteArray(BUFFER)
                var pausedOut = false

                try {
                    UpdateProgressBridge.emit("downloading", received, total)
                    updateNotification()
                    while (true) {
                        if (cancelled) return
                        if (paused) {
                            UpdateProgressBridge.emit("paused", received, total)
                            updateNotification()
                            synchronized(resumeLock) {
                                while (paused && !cancelled) resumeLock.wait()
                            }
                            if (cancelled) return
                            // Re-issue the request (Range) from the current offset.
                            pausedOut = true
                            break
                        }
                        val n = input.read(buf)
                        if (n == -1) return // finished
                        out.write(buf, 0, n)
                        received += n
                        emitThrottled()
                    }
                } finally {
                    try {
                        input.close()
                    } catch (_: Exception) {}
                    try {
                        out.close()
                    } catch (_: Exception) {}
                }

                if (!pausedOut) return
            } finally {
                conn.disconnect()
            }
        }
    }

    private fun emitThrottled() {
        val now = System.currentTimeMillis()
        if (now - lastEmitMs < EMIT_INTERVAL_MS) return
        lastEmitMs = now
        UpdateProgressBridge.emit("downloading", received, total)
        updateNotification()
    }

    private fun setPaused(value: Boolean) {
        if (paused == value) return
        paused = value
        if (!value) {
            synchronized(resumeLock) { resumeLock.notifyAll() }
        }
        UpdateProgressBridge.emit(if (value) "paused" else "downloading", received, total)
        updateNotification()
    }

    private fun doCancel() {
        cancelled = true
        synchronized(resumeLock) { resumeLock.notifyAll() }
        if (worker == null) {
            UpdateProgressBridge.emit("cancelled", received, total)
            stopAll()
        }
    }

    // --- Notification ---------------------------------------------------------

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.update_notification_title),
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val percent = if (total > 0) ((received * 100) / total).toInt() else 0
        val indeterminate = total <= 0

        val text = when {
            paused -> getString(R.string.update_notification_paused)
            total > 0 -> getString(
                R.string.update_notification_progress,
                mb(received),
                mb(total),
                percent,
            )
            else -> getString(R.string.update_notification_preparing)
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(getString(R.string.update_notification_title))
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, percent, indeterminate)
            .setContentIntent(openAppIntent())

        if (paused) {
            builder.addAction(
                0,
                getString(R.string.update_action_resume),
                servicePendingIntent(ACTION_RESUME),
            )
        } else {
            builder.addAction(
                0,
                getString(R.string.update_action_pause),
                servicePendingIntent(ACTION_PAUSE),
            )
        }
        builder.addAction(
            0,
            getString(R.string.update_action_cancel),
            servicePendingIntent(ACTION_CANCEL),
        )
        return builder.build()
    }

    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun mb(bytes: Long): String = String.format("%.1f", bytes / 1_048_576.0)

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun servicePendingIntent(action: String): PendingIntent {
        val intent = Intent(this, UpdateDownloadService::class.java).setAction(action)
        return PendingIntent.getService(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // --- Install + teardown ---------------------------------------------------

    /** Replaces the progress notification with a finished one whose tap opens the
     *  installer. A service can't start an Activity in the background, so the
     *  user's tap (BAL-exempt) is what launches the install when backgrounded; the
     *  foreground app launches it immediately from its Activity (Dart side). The
     *  notification is detached so it outlives the stopping service. */
    private fun showInstallNotification(file: java.io.File) {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(getString(R.string.update_notification_ready_title))
            .setContentText(getString(R.string.update_notification_ready_text))
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(installPendingIntent(file))
            .build()

        main.post {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, notification)
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
            stopSelf()
        }
    }

    /** Activity PendingIntent that launches the system package installer for the
     *  downloaded APK. */
    private fun installPendingIntent(file: java.io.File): PendingIntent {
        val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return PendingIntent.getActivity(
            this,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun stopAll() {
        main.post {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }
}
