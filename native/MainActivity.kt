package com.markys.markys_pdv_mobile

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "markys/license_clock").setMethodCallHandler { call, result ->
            if (call.method != "snapshot") result.notImplemented()
            else try {
                val boot = android.provider.Settings.Global.getInt(contentResolver, "boot_count", -1)
                if (boot < 0) result.error("CLOCK", "Inicialização não verificável", null)
                else result.success(mapOf("boot" to boot, "elapsed" to android.os.SystemClock.elapsedRealtime()))
            } catch (e: Exception) { result.error("CLOCK", "Relógio indisponível", null) }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "markys/printer").setMethodCallHandler { call, result ->
            if (call.method == "permission") {
                if (Build.VERSION.SDK_INT < 31 || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) result.success(true)
                else if (pending != null) result.error("BUSY", "Permissão em andamento", null)
                else { pending = result; requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), 91) }
            } else if (call.method == "devices" || call.method == "print") {
                worker.execute {
                    try {
                        val adapter = getSystemService(BluetoothManager::class.java).adapter ?: error("Bluetooth indisponível")
                        check(adapter.isEnabled) { "Ative o Bluetooth" }
                        if (call.method == "devices") {
                            val devices = adapter.bondedDevices.map { mapOf("name" to (it.name ?: it.address), "address" to it.address) }
                            runOnUiThread { result.success(devices) }
                        } else {
                            val address = call.argument<String>("address") ?: error("Selecione a impressora")
                            val bytes = call.argument<ByteArray>("bytes") ?: error("Dados inválidos")
                            val device = adapter.bondedDevices.firstOrNull { it.address == address } ?: error("Pareie a impressora nas configurações do Android")
                            device.createRfcommSocketToServiceRecord(UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")).use { socket ->
                                socket.connect()
                                socket.outputStream.write(bytes)
                                socket.outputStream.flush()
                            }
                            runOnUiThread { result.success(true) }
                        }
                    } catch (e: Exception) { runOnUiThread { result.error("BLUETOOTH", e.message ?: "Falha de conexão", null) } }
                }
            } else result.notImplemented()
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 91) { pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED); pending = null }
    }
}
