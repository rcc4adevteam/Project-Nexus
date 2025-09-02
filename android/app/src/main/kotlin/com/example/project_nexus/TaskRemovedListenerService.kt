package com.example.project_nexus

import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import id.flutter.flutter_background_service.BackgroundService

class TaskRemovedListenerService : Service() {

    override fun onBind(intent: Intent): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent) {
        Log.d("TaskRemovedListener", "TASK REMOVED, RESTARTING FLUTTER SERVICE!")
        
        // This code restarts your flutter_background_service
        val intent = Intent(this, BackgroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }
}
