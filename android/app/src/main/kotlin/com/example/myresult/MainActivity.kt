package com.example.myresult

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android: keep classic inset fitting so adjustResize + IME insets match Scaffold
        // (avoids bottom bar / keyboard overlap on many devices when edge-to-edge is default).
        WindowCompat.setDecorFitsSystemWindows(window, true)
        super.onCreate(savedInstanceState)
    }
}
