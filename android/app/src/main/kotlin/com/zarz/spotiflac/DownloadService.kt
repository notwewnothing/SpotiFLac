package com.zarz.spotiflac

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Foreground service to keep downloads running when app is in background.
 * This prevents Android from killing the download process or throttling network.
 * 
 * Note: Android 15+ (API 35+) has a 6-hour timeout for dataSync foreground services.
 * The service will be stopped automatically after 6 hours of cumulative runtime in 24 hours.
 */
class DownloadService : Service() {
    
    companion object {
        private const val CHANNEL_ID = "download_channel"
        private const val NOTIFICATION_ID = 1001
        private const val WAKELOCK_TAG = "SpotiFLAC:DownloadWakeLock"
        
        const val ACTION_START = "com.zarz.spotiflac.action.START_DOWNLOAD"
        const val ACTION_STOP = "com.zarz.spotiflac.action.STOP_DOWNLOAD"
        const val ACTION_UPDATE_PROGRESS = "com.zarz.spotiflac.action.UPDATE_PROGRESS"
        
        const val EXTRA_TRACK_NAME = "track_name"
        const val EXTRA_ARTIST_NAME = "artist_name"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_TOTAL = "total"
        const val EXTRA_QUEUE_COUNT = "queue_count"
        
        private var isRunning = false
        
        fun isServiceRunning(): Boolean = isRunning
        
        fun start(context: Context, trackName: String = "", artistName: String = "", queueCount: Int = 0) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TRACK_NAME, trackName)
                putExtra(EXTRA_ARTIST_NAME, artistName)
                putExtra(EXTRA_QUEUE_COUNT, queueCount)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stop(context: Context) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
        
        fun updateProgress(context: Context, trackName: String, artistName: String, progress: Long, total: Long, queueCount: Int) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_UPDATE_PROGRESS
                putExtra(EXTRA_TRACK_NAME, trackName)
                putExtra(EXTRA_ARTIST_NAME, artistName)
                putExtra(EXTRA_PROGRESS, progress)
                putExtra(EXTRA_TOTAL, total)
                putExtra(EXTRA_QUEUE_COUNT, queueCount)
            }
            context.startService(intent)
        }
    }
    
    private var wakeLock: PowerManager.WakeLock? = null
    private var currentTrackName = ""
    private var currentArtistName = ""
    private var queueCount = 0
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                currentTrackName = intent.getStringExtra(EXTRA_TRACK_NAME) ?: ""
                currentArtistName = intent.getStringExtra(EXTRA_ARTIST_NAME) ?: ""
                queueCount = intent.getIntExtra(EXTRA_QUEUE_COUNT, 0)
                startForegroundService()
            }
            ACTION_STOP -> {
                stopForegroundService()
            }
            ACTION_UPDATE_PROGRESS -> {
                currentTrackName = intent.getStringExtra(EXTRA_TRACK_NAME) ?: currentTrackName
                currentArtistName = intent.getStringExtra(EXTRA_ARTIST_NAME) ?: currentArtistName
                val progress = intent.getLongExtra(EXTRA_PROGRESS, 0)
                val total = intent.getLongExtra(EXTRA_TOTAL, 0)
                queueCount = intent.getIntExtra(EXTRA_QUEUE_COUNT, queueCount)
                updateNotification(progress, total)
            }
        }
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    /**
     * Called when the foreground service timeout is reached (Android 15+, API 35+).
     * dataSync services have a 6-hour limit in a 24-hour period.
     * We must call stopSelf() within a few seconds to avoid a crash.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        android.util.Log.w("DownloadService", "Foreground service timeout reached (6 hours limit). Stopping service.")
        
        stopForegroundService()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Download Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows download progress"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
    
    private fun startForegroundService() {
        isRunning = true

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            WAKELOCK_TAG
        ).apply {
            acquire(60 * 60 * 1000L)
        }
        
        val notification = buildNotification(0, 0)
        startForeground(NOTIFICATION_ID, notification)
    }
    
    private fun stopForegroundService() {
        isRunning = false
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
    
    private fun updateNotification(progress: Long, total: Long) {
        if (!isRunning) return
        
        val notification = buildNotification(progress, total)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }
    
    private fun buildNotification(progress: Long, total: Long): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val title = if (queueCount > 1) {
            "Downloading $queueCount tracks"
        } else if (currentTrackName.isNotEmpty()) {
            currentTrackName
        } else {
            "Downloading..."
        }
        
        val text = if (currentArtistName.isNotEmpty() && queueCount <= 1) {
            currentArtistName
        } else if (total > 0) {
            val progressPercent = (progress * 100 / total).toInt()
            val progressMB = progress / (1024.0 * 1024.0)
            val totalMB = total / (1024.0 * 1024.0)
            String.format("%.1f / %.1f MB (%d%%)", progressMB, totalMB, progressPercent)
        } else {
            "Preparing download..."
        }
        
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        
        if (total > 0) {
            builder.setProgress(100, (progress * 100 / total).toInt(), false)
        } else {
            builder.setProgress(0, 0, true)
        }
        
        return builder.build()
    }
    
    override fun onDestroy() {
        isRunning = false
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        super.onDestroy()
    }
}
