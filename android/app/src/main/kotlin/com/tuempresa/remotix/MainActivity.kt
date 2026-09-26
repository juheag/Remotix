package com.tuempresa.remotix

import android.content.Context
import android.hardware.ConsumerIrManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "remotix/infrared"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val irManager = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasIrEmitter" -> result.success(irManager?.hasIrEmitter() == true)
                "transmit" -> {
                    val frequency = call.argument<Int>("frequency")
                    @Suppress("UNCHECKED_CAST")
                    val pattern = (call.argument<List<Int>>("pattern"))?.toIntArray()
                    when {
                        irManager == null || !irManager.hasIrEmitter() ->
                            result.error("NO_IR_EMITTER", "Este dispositivo no tiene emisor infrarrojo.", null)
                        frequency == null || pattern == null ->
                            result.error("INVALID_ARGS", "Frecuencia o patrón inválido.", null)
                        else -> {
                            irManager.transmit(frequency, pattern)
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
