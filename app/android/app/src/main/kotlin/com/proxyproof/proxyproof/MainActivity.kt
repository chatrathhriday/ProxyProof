package com.proxyproof.proxyproof

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity (not plain FlutterActivity) because BiometricPrompt needs one.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val keys = DeviceKeys(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "proxyproof/keys")
            .setMethodCallHandler { call, result -> keys.handle(call, result) }
    }
}
