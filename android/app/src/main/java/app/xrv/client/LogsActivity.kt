package app.xrv.client

import android.content.ClipData
import android.content.ClipboardManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import app.xrv.client.databinding.ActivityLogsBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder

class LogsActivity : AppCompatActivity() {
    private lateinit var binding: ActivityLogsBinding
    private val handler = Handler(Looper.getMainLooper())
    private val refresh = object : Runnable {
        override fun run() {
            render()
            handler.postDelayed(this, 2_000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityLogsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { view, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        ViewCompat.requestApplyInsets(binding.root)

        binding.logsBackButton.setOnClickListener { finish() }
        binding.logsCopyButton.setOnClickListener { copyLogs() }
        binding.logsClearButton.setOnClickListener { confirmClear() }
        render()
    }

    private fun render() {
        val app = XrvLog.read()
        val native = if (NativeBridge.loadError == null) {
            runCatching { NativeBridge.logs() }.getOrNull().orEmpty()
        } else {
            "Native library unavailable: ${NativeBridge.loadError}"
        }
        val text = buildString {
            appendLine("=== ${getString(R.string.logs_section_app)} ===")
            appendLine(app.ifEmpty { getString(R.string.logs_empty) })
            appendLine()
            appendLine("=== ${getString(R.string.logs_section_native)} ===")
            appendLine(native.ifEmpty { getString(R.string.logs_empty) })
        }
        binding.logsText.text = text
        binding.logsScroll.post {
            binding.logsScroll.fullScroll(android.view.View.FOCUS_DOWN)
        }
    }

    private fun copyLogs() {
        val clipboard = getSystemService(ClipboardManager::class.java) ?: return
        clipboard.setPrimaryClip(
            ClipData.newPlainText(getString(R.string.app_name), binding.logsText.text)
        )
        Toast.makeText(this, getString(R.string.logs_copied), Toast.LENGTH_SHORT).show()
    }

    private fun confirmClear() {
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.logs_clear_confirm)
            .setPositiveButton(R.string.clear_confirm) { _, _ ->
                XrvLog.clear()
                if (NativeBridge.loadError == null) {
                    runCatching { NativeBridge.clearLogs() }
                }
                render()
                Toast.makeText(this, getString(R.string.logs_cleared), Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton(R.string.cancel, null)
            .show()
    }

    override fun onStart() {
        super.onStart()
        handler.removeCallbacks(refresh)
        handler.post(refresh)
    }

    override fun onStop() {
        handler.removeCallbacks(refresh)
        super.onStop()
    }
}
