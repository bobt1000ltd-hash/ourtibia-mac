package com.otclient

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.content.ContextCompat
import android.view.ViewGroup
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.github.otclient.databinding.ActivityMainBinding
import com.google.androidgamesdk.GameActivity

class MainActivity : GameActivity() {

    private lateinit var androidManager: AndroidManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val binding = ActivityMainBinding.inflate(layoutInflater)
        findViewById<ViewGroup>(contentViewId).addView(binding.root)

        androidManager = AndroidManager(
            context = this,
            editText = binding.editText,
            previewContainer = binding.keyboardPreviewContainer,
            previewText = binding.inputPreviewText,
            pasteButton = binding.pasteButton,
            copyButton = binding.copyButton,
        ).apply {
            nativeInit()
            nativeSetAudioEnabled(true)
        }

        // Track keyboard visibility and height for toolbar positioning
        var lastImeVisible = false
        var lastImeBottom = 0
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { _, insets ->
            val imeInsets = insets.getInsets(WindowInsetsCompat.Type.ime())
            val imeVisible = imeInsets.bottom > 0
            if (imeVisible != lastImeVisible || imeInsets.bottom != lastImeBottom) {
                lastImeVisible = imeVisible
                lastImeBottom = imeInsets.bottom
                androidManager.onImeVisibilityChanged(imeVisible, imeInsets.bottom)
            }
            insets
        }

        hideSystemBars()

        // OurTibia (16.10.2026): keep the connection alive in the background
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            try { requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 71) } catch (_: Exception) { }
        }
        KeepAliveService.start(this)
    }

    override fun onResume() {
        super.onResume()
        KeepAliveService.start(this)
        androidManager.nativeSetAudioEnabled(true)
    }

    override fun onPause() {
        androidManager.nativeSetAudioEnabled(false)
        super.onPause()
    }

    override fun onDestroy() {
        if (isFinishing) KeepAliveService.stop(this)
        androidManager.nativeSetAudioEnabled(false)
        super.onDestroy()
    }

    private fun hideSystemBars() {
        val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        windowInsetsController.hide(WindowInsetsCompat.Type.systemBars())
    }

    companion object {
        init {
            System.loadLibrary("otclient")
        }
    }
}
