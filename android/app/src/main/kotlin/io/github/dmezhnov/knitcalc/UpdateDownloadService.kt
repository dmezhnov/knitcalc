package io.github.dmezhnov.knitcalc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
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
 * Latest notification strings pushed from Dart (see
 * `syncAndroidUpdateNotificationStrings`), so the download notification follows
 * the in-app language toggle rather than the device locale. Null until the app
 * sets them, in which case the service falls back to its bundled resources.
 */
object UpdateNotificationStrings {
    @Volatile
    var values: Map<String, String>? = null

    fun get(key: String): String? = values?.get(key)
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
        const val EXTRA_SIZE = "size"
        const val EXTRA_VERSION = "version"

        /** Live instance, so [MainActivity] can signal foreground/background
         *  directly (an in-process call avoids the Android 12+ ban on starting a
         *  service from the background, which a lifecycle Intent would hit). */
        @Volatile
        var instance: UpdateDownloadService? = null
            private set

        /** Path of a downloaded APK awaiting install. Set on completion; consumed
         *  by [MainActivity] (it launches the installer from its Activity, which a
         *  background service can't do). Survives the service stopping. */
        @Volatile
        var pendingInstallPath: String? = null

        /** Cache file an update of [version] downloads to. Shared with
         *  [MainActivity], which checks it to skip re-downloading a finished APK. */
        fun cachedApk(context: android.content.Context, version: String): java.io.File {
            val safe = version.replace(Regex("[^A-Za-z0-9._-]"), "_")
            return java.io.File(context.cacheDir, "$APK_PREFIX-$safe.apk")
        }

        private const val CHANNEL_ID = "knitcalc_update"
        private const val NOTIFICATION_ID = 4711
        private const val APK_PREFIX = "knitcalc-update"
        private const val BUFFER = 64 * 1024
        private const val EMIT_INTERVAL_MS = 150L
    }

    private val main = Handler(Looper.getMainLooper())

    @Volatile private var paused = false
    @Volatile private var cancelled = false
    @Volatile private var received = 0L
    @Volatile private var total = -1L
    @Volatile private var worker: Thread? = null

    // A download is in progress (between start and done/cancel/error). Drives
    // whether backgrounding promotes the service to foreground with a notification.
    @Volatile private var downloading = false

    // The app is currently visible. The notification is shown only while this is
    // false — when the app is foreground the in-app progress dialog is enough.
    @Volatile private var appInForeground = true

    private val resumeLock = Object()
    private var lastEmitMs = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val url = intent.getStringExtra(EXTRA_URL)
                if (url == null) {
                    stopAll()
                } else if (worker == null) {
                    val size = intent.getLongExtra(EXTRA_SIZE, -1L)
                    val version = intent.getStringExtra(EXTRA_VERSION) ?: "latest"
                    downloading = true
                    startDownload(url, size, version)
                }
            }
            ACTION_PAUSE -> setPaused(true)
            ACTION_RESUME -> setPaused(false)
            ACTION_CANCEL -> doCancel()
        }
        return START_NOT_STICKY
    }

    /** Called by [MainActivity] when the app becomes visible: hide the
     *  notification (the in-app dialog takes over) but keep downloading. */
    fun onAppForeground() {
        appInForeground = true
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
    }

    /** Called by [MainActivity] when the app is backgrounded: while a download is
     *  in flight, promote to a foreground service so it keeps running and shows
     *  the progress notification. */
    fun onAppBackground() {
        appInForeground = false
        if (!downloading) return
        createChannel()
        val notification = buildNotification()
        // Called from MainActivity.onStop, within the grace period that still lets
        // a just-foregrounded app start a foreground service. Guard anyway: if the
        // system refuses (Android 12+ ForegroundServiceStartNotAllowedException),
        // the download just continues without the notification rather than crashing.
        try {
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
        } catch (_: Exception) {
            // Couldn't promote to foreground; leave it as a plain started service.
        }
    }

    private fun startDownload(urlStr: String, expectedSize: Long, version: String) {
        paused = false
        cancelled = false
        pendingInstallPath = null

        // Cache the APK under a per-version name and drop other versions' leftovers,
        // so a finished download for this version can be reused without re-fetching.
        val apk = apkFile(version)
        cleanupStaleApks(apk)

        val existing = if (apk.exists()) apk.length() else 0L
        when {
            // Already fully downloaded this version: skip straight to install.
            expectedSize > 0 && existing == expectedSize -> {
                received = expectedSize
                total = expectedSize
                downloading = false
                finishDownloaded(apk)
                return
            }
            // A partial file for this version: resume from where it stopped.
            expectedSize > 0 && existing in 1 until expectedSize -> received = existing
            // No usable partial (empty, or larger than expected → corrupt): restart.
            else -> {
                if (apk.exists()) apk.delete()
                received = 0L
            }
        }
        total = if (expectedSize > 0) expectedSize else -1L

        worker = thread(start = true) {
            try {
                downloadLoop(urlStr, apk)
                downloading = false
                when {
                    cancelled -> {
                        apk.delete()
                        UpdateProgressBridge.emit("cancelled", received, total)
                        stopAll()
                    }
                    else -> finishDownloaded(apk)
                }
            } catch (_: Exception) {
                downloading = false
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

    /** A complete APK is ready. Remember it for install and either let the
     *  foreground app install it (Dart's "done" handling) or, when backgrounded,
     *  show a tappable "downloaded" notification — a service can't start the
     *  installer Activity itself, but [MainActivity] does on the next foreground. */
    private fun finishDownloaded(apk: java.io.File) {
        pendingInstallPath = apk.absolutePath
        UpdateProgressBridge.emitDone(received, total, apk.absolutePath)
        if (appInForeground) {
            stopAll()
        } else {
            showInstallNotification(apk)
        }
    }

    private fun apkFile(version: String): java.io.File = cachedApk(this, version)

    /** Removes other cached update APKs (old versions, or the pre-versioned file)
     *  so the cache holds at most the one we're about to use. */
    private fun cleanupStaleApks(keep: java.io.File) {
        cacheDir.listFiles()?.forEach { f ->
            if (f.name.startsWith(APK_PREFIX) && f.name.endsWith(".apk") && f != keep) {
                f.delete()
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
        // Once a pause/cancel is requested, suppress the per-chunk "downloading"
        // event for any in-flight chunk: a stale "downloading" would otherwise be
        // mirrored back by the app as a resume and undo the pause.
        if (paused || cancelled) return
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
            localized("title", R.string.update_notification_title),
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    /** App-pushed string for [key] (in the in-app language) or the bundled
     *  resource [fallback] (device locale) if the app hasn't set one. */
    private fun localized(key: String, fallback: Int): String =
        UpdateNotificationStrings.get(key) ?: getString(fallback)

    private fun buildNotification(): Notification {
        val percent = if (total > 0) ((received * 100) / total).toInt() else 0
        val indeterminate = total <= 0

        val text = when {
            paused -> localized("paused", R.string.update_notification_paused)
            total > 0 -> {
                val unit = UpdateNotificationStrings.get("mbUnit")
                if (unit != null) {
                    "${mb(received)} / ${mb(total)} $unit · $percent%"
                } else {
                    getString(
                        R.string.update_notification_progress,
                        mb(received),
                        mb(total),
                        percent,
                    )
                }
            }
            else -> localized("preparing", R.string.update_notification_preparing)
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(localized("title", R.string.update_notification_title))
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, percent, indeterminate)
            .setContentIntent(openAppIntent())

        if (paused) {
            builder.addAction(
                0,
                localized("resume", R.string.update_action_resume),
                servicePendingIntent(ACTION_RESUME),
            )
        } else {
            builder.addAction(
                0,
                localized("pause", R.string.update_action_pause),
                servicePendingIntent(ACTION_PAUSE),
            )
        }
        builder.addAction(
            0,
            localized("cancel", R.string.update_action_cancel),
            servicePendingIntent(ACTION_CANCEL),
        )
        return builder.build()
    }

    private fun updateNotification() {
        // Only refresh the notification while it is shown (app backgrounded);
        // posting one while foreground would create the very notification we keep
        // hidden until the user leaves the app.
        if (appInForeground) return
        // Build and post on the main thread so all updates are serialized on one
        // looper and the notification is built from the *current* state at post
        // time. The worker thread and the action-handling main thread both refresh
        // the notification; if a worker-built "downloading" (Pause button) snapshot
        // were posted after a main-thread "paused" (Resume button) one, the shutter
        // would keep showing Pause while the download is actually paused. Deferring
        // the build to the main looper makes the last post win and read paused=true.
        main.post {
            if (appInForeground) return@post
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification())
        }
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
            .setContentTitle(localized("readyTitle", R.string.update_notification_ready_title))
            .setContentText(localized("readyText", R.string.update_notification_ready_text))
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

    /** PendingIntent that opens [MainActivity] with the APK path, so the tap is
     *  handled by the same deduped install path as the foreground/auto cases
     *  (a service can't start the installer Activity itself). */
    private fun installPendingIntent(file: java.io.File): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = "io.github.dmezhnov.knitcalc.action.INSTALL"
            putExtra(MainActivity.EXTRA_INSTALL_PATH, file.absolutePath)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
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
